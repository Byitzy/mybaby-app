import EventKit
import SwiftUI
import UIKit

/// Settings › Calendar: "Keep appointments in my calendar" (`CalendarSync`), set on each phone.
struct CalendarSyncSection: View {
    @ObservedObject private var calendarSync = CalendarSync.shared

    /// True while waiting for the calendar permission prompt.
    @State private var isTurningOn = false
    @State private var confirmingTurnOff = false
    @State private var showingAccessAlert = false

    init() {}

    var body: some View {
        Section {
            Toggle(isOn: toggleBinding) {
                Label("Keep appointments in my calendar", systemImage: "calendar")
            }
            .disabled(isTurningOn)

            if calendarSync.isEnabled {
                if calendarSync.hasFullAccess {
                    Picker("Calendar", selection: $calendarSync.calendarID) {
                        Text(defaultTitle).tag(String?.none)
                        ForEach(calendarSync.calendars, id: \.calendarIdentifier) { calendar in
                            Text(title(for: calendar)).tag(String?.some(calendar.calendarIdentifier))
                        }
                    }
                    if let notice = calendarSync.calendarNotice {
                        NoticeLabel(notice, systemImage: "info.circle.fill", tint: Palette.appointment)
                            .font(.subheadline)
                    }
                } else {
                    accessProblem
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text(footer)
        }
        .onAppear { calendarSync.refreshAccess() }
        .confirmationDialog("Turn off calendar sync?", isPresented: $confirmingTurnOff, titleVisibility: .visible) {
            Button("Keep the events") { calendarSync.disable(removingEvents: false) }
            Button("Remove the events", role: .destructive) { calendarSync.disable(removingEvents: true) }
        } message: {
            Text("Keep the appointments MyBaby added to your calendar, or remove them?")
        }
        .alert(accessAlertTitle, isPresented: $showingAccessAlert) {
            if calendarSync.access != .restricted {
                Button("Open Settings", action: openSettings)
                Button("Not now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(accessAlertMessage)
        }
    }

    // MARK: Turning it on and off

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { calendarSync.isEnabled || isTurningOn },
            set: { isOn in
                if isOn {
                    isTurningOn = true
                    Task {
                        let enabled = await calendarSync.enable()
                        isTurningOn = false
                        if !enabled { showingAccessAlert = true }
                    }
                } else if calendarSync.hasFullAccess && calendarSync.hasAddedEvents {
                    confirmingTurnOff = true
                } else {
                    calendarSync.disable(removingEvents: false)
                }
            }
        )
    }

    /// Calendar access was turned off after sync was turned on.
    @ViewBuilder
    private var accessProblem: some View {
        NoticeLabel("MyBaby can't reach your calendar right now, so appointments aren't being added or updated.")
            .font(.subheadline)
        if calendarSync.access == .notDetermined {
            Button("Allow calendar access") {
                Task {
                    if !(await calendarSync.enable()) { showingAccessAlert = true }
                }
            }
        } else if calendarSync.access != .restricted {
            Button("Open Settings", action: openSettings)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var accessAlertTitle: String {
        calendarSync.access == .restricted
            ? String(localized: "Calendar access is restricted")
            : String(localized: "Calendar access is off")
    }

    private var accessAlertMessage: String {
        if calendarSync.access == .restricted {
            return String(localized: "This iPhone doesn't allow calendar access, for example because of Screen Time or a work profile. You can still add an appointment with Add to Calendar when you open it.")
        }
        return String(localized: "To keep appointments in your calendar, MyBaby needs full access so it can update and remove the events it adds. Turn on Full Access in Settings › MyBaby › Calendars. You can still add an appointment with Add to Calendar without it.")
    }

    // MARK: Text

    private var defaultTitle: String {
        if let name = calendarSync.defaultCalendarTitle { return String(localized: "Default (\(name))", comment: "The default calendar, with its name") }
        return String(localized: "Default calendar")
    }

    /// "Family · iCloud", so calendars with the same name in two accounts can be told apart.
    private func title(for calendar: EKCalendar) -> String {
        let source = calendar.source?.title ?? ""
        return source.isEmpty ? calendar.title : "\(calendar.title) · \(source)"
    }

    private var footer: String {
        var text = String(localized: "Adds upcoming appointments to your calendar on this iPhone and keeps them up to date when they change or are deleted. Events have no alerts, since MyBaby already sends the reminder you choose on each appointment.")
        text += " " + AddToCalendarSection.privacyNote
        text += " " + String(localized: "If you and your partner share a family calendar, turn this on only on one phone.")
        return text
    }
}
