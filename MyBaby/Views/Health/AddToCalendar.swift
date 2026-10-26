import EventKit
import EventKitUI
import SwiftUI

/// The system's new-event sheet, filled in from a `CalendarEventDraft`. On iOS 17 it runs outside the app
/// when MyBaby has no calendar access, so it needs no permission: the parent sees exactly what's added,
/// picks the calendar and taps Add, or cancels.
///
/// An added event is remembered on this iPhone (`CalendarSync.rememberAddedEvent`), so Delete all data
/// can remove it along with everything else.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let draft: CalendarEventDraft
    /// Called when the sheet is done; `true` if the event was added.
    let onDone: (_ saved: Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = CalendarSync.shared.store
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.location = draft.location
        // The same text, with the coordinates of a place picked from the search: Calendar then shows
        // the map and can offer a travel-time alert.
        if let structured = CalendarSync.structuredLocation(title: draft.location, coordinate: draft.coordinate) {
            event.structuredLocation = structured
        }
        if let offset = draft.alarmOffset {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }
        // With full access the sheet runs in the app and needs a calendar to start with.
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            event.calendar = store.defaultCalendarForNewEvents
        }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(draft: draft, onDone: onDone)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let draft: CalendarEventDraft
        let onDone: (Bool) -> Void

        init(draft: CalendarEventDraft, onDone: @escaping (Bool) -> Void) {
            self.draft = draft
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            let saved = action == .saved
            if saved {
                let event = controller.event
                let draft = self.draft
                // The sheet reports back on the main thread.
                MainActor.assumeIsolated {
                    CalendarSync.shared.rememberAddedEvent(event, draft: draft)
                }
            }
            onDone(saved)
        }
    }
}

extension View {
    /// Shows the new-event sheet while `draft` is set. `onAdded` runs if the parent added the event.
    func addToCalendarSheet(_ draft: Binding<CalendarEventDraft?>, onAdded: @escaping () -> Void = {}) -> some View {
        sheet(item: draft) { value in
            CalendarEventEditor(draft: value) { saved in
                draft.wrappedValue = nil
                if saved { onAdded() }
            }
            .ignoresSafeArea()
        }
    }
}

/// "Add to Calendar" in the appointment editor. While "Keep appointments in my calendar" is on, it says
/// the appointment is kept there instead, so the same event isn't added twice.
struct AddToCalendarSection: View {
    @ObservedObject private var calendarSync = CalendarSync.shared
    /// Built when tapped, from what's in the editor now (it may not be saved yet).
    let makeDraft: () -> CalendarEventDraft
    /// Whether MyBaby sends its own reminder for this appointment.
    let hasReminder: Bool

    @State private var draft: CalendarEventDraft?
    @State private var added = false

    init(makeDraft: @escaping () -> CalendarEventDraft, hasReminder: Bool) {
        self.makeDraft = makeDraft
        self.hasReminder = hasReminder
    }

    var body: some View {
        Section {
            if calendarSync.isEnabled {
                Label("Kept in your calendar", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    draft = makeDraft()
                } label: {
                    Label(added ? "Added to Calendar" : "Add to Calendar", systemImage: added ? "checkmark.circle" : "calendar.badge.plus")
                }
                .accessibilityHint("Opens a calendar event to check before you add it")
            }
        } footer: {
            Text(footer)
        }
        .addToCalendarSheet($draft) { added = true }
    }

    private var footer: String {
        let privacy = " " + AddToCalendarSection.privacyNote
        if calendarSync.isEnabled {
            return String(localized: "Saving changes here updates the event in your calendar.") + privacy
        }
        let alert = hasReminder
            ? String(localized: "The event has a calendar alert an hour before, on top of MyBaby's reminder. You can change it before adding.")
            : String(localized: "The event has a calendar alert an hour before. You can change it before adding.")
        return alert + privacy
    }

    /// The one line shown by the button and the setting.
    static let privacyNote = String(localized: "Calendar events are stored by your calendar's provider (such as iCloud, Google or Outlook), outside MyBaby's end-to-end encryption. Notes and questions aren't copied.")
}
