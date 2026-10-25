import CoreData
import EventKit
import Foundation
import UIKit

extension SettingsKey {
    // In `UserDefaults.standard`, so each phone has its own:
    /// "Keep appointments in my calendar" (`CalendarSync`). Off by default.
    static let calendarSyncEnabled = "calendarSyncEnabled"
    /// The `calendarIdentifier` appointments go to. Not set means the default calendar.
    static let calendarSyncCalendarID = "calendarSyncCalendarID"
}

/// What a new calendar event for an appointment starts with. Used by "Add to Calendar"
/// (`CalendarEventEditor`) and, for the title and place, by `CalendarSync`.
///
/// The appointment's notes and questions are never copied: they can hold medical details, and the
/// event is stored by the calendar's provider, outside MyBaby's end-to-end encrypted log.
struct CalendarEventDraft: Identifiable {
    let id = UUID()
    var title: String
    var start: Date
    var end: Date
    var location: String?
    /// Seconds before the start (negative), or `nil` for no alert.
    var alarmOffset: TimeInterval?

    /// From the editor's fields, which may not be saved yet.
    init(title: String, date: Date, provider: String, location: String, babyName: String?) {
        self.title = CalendarSync.eventTitle(title, babyName: babyName)
        self.start = date
        self.end = date.addingTimeInterval(CalendarSync.defaultDuration)
        self.location = CalendarSync.eventLocation(provider: provider, location: location)
        // Shown in the sheet, so the parent can change or remove it before saving.
        self.alarmOffset = -3600
    }

    init(appointment: Appointment) {
        self.init(
            title: appointment.title,
            date: appointment.date,
            provider: appointment.provider,
            location: appointment.location,
            babyName: appointment.baby?.displayName
        )
    }
}

/// "Keep appointments in my calendar": copies upcoming appointments into a calendar the parent picks,
/// and keeps the events up to date. Off by default, and set on each phone.
///
/// - Turning it on asks for full calendar access, because MyBaby has to find, update and remove the
///   events it added. "Add to Calendar" for a single appointment needs no access at all (iOS 17 shows
///   that sheet outside the app), so it's the default way.
/// - Covers every baby on this iPhone, for appointments from 24 hours ago on. Older ones are left in the
///   calendar as they are and forgotten.
/// - Edits update the event; a deleted appointment removes it. Only the title, time and place are
///   kept in step; an alert or notes the parent adds in Calendar stay.
/// - Events get no alerts: MyBaby already sends the reminder chosen on each appointment.
/// - Which event belongs to which appointment is kept per device in a small JSON file in Application
///   Support, keyed by the appointment's `uuid`, never in Core Data: the log is shared, the calendar isn't.
/// - Before adding an event it looks for one with the same title at the same time in that calendar, and
///   adopts it. That covers the partner's phone doing the same into a shared family calendar, an earlier
///   "Add to Calendar", and a reinstall.
///
/// Started once at launch (`MyBabyApp.init`). It syncs again when the app opens, after any save that
/// touches an appointment or a baby (from any screen), and when changes arrive from the partner's phone.
@MainActor
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()

    /// The app's one event store, also used by "Add to Calendar".
    let store = EKEventStore()

    /// New events last an hour; Appointment has no duration.
    nonisolated static let defaultDuration: TimeInterval = 3600
    /// Appointments that started up to this long ago are still kept in step.
    private static let recentWindow: TimeInterval = 24 * 3600
    private static let eventNote = "Added by MyBaby. Changes to the appointment in MyBaby update this event."

    @Published private(set) var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: SettingsKey.calendarSyncEnabled) }
    }
    /// The calendar picked in Settings; `nil` is the default calendar.
    @Published var calendarID: String? {
        didSet {
            guard calendarID != oldValue else { return }
            defaults.set(calendarID, forKey: SettingsKey.calendarSyncCalendarID)
            if calendarID != nil { calendarNotice = nil }
            scheduleSync()
        }
    }
    @Published private(set) var access: EKAuthorizationStatus
    /// Calendars MyBaby can add events to, for the picker.
    @Published private(set) var calendars: [EKCalendar] = []
    /// Set when the picked calendar went away and appointments moved to the default calendar.
    @Published private(set) var calendarNotice: String?

    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    private init() {
        isEnabled = defaults.bool(forKey: SettingsKey.calendarSyncEnabled)
        calendarID = defaults.string(forKey: SettingsKey.calendarSyncCalendarID)
        access = EKEventStore.authorizationStatus(for: .event)
    }

    var hasFullAccess: Bool { access == .fullAccess }

    /// The default calendar's name, for "Default (Home)".
    var defaultCalendarTitle: String? {
        hasFullAccess ? store.defaultCalendarForNewEvents?.title : nil
    }

    /// Whether events added by sync are still remembered, so turning it off has something to remove.
    var hasAddedEvents: Bool { !loadLinks().isEmpty }

    // MARK: Starting

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if Self.touchesAppointments(notification) { self?.scheduleSync() }
            }
        })
        // The partner's changes, or a restore, arriving from iCloud.
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccess()
                self?.scheduleSync()
            }
        })
        scheduleSync()
    }

    /// Re-reads calendar access, which can change in the Settings app.
    func refreshAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != access { access = status }
        if hasFullAccess { refreshCalendars() }
    }

    func refreshCalendars() {
        guard hasFullAccess else {
            calendars = []
            return
        }
        calendars = store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Turning it on and off

    /// Asks for full calendar access if needed, then turns sync on. Returns false when access
    /// isn't given; `access` then says why.
    func enable() async -> Bool {
        if access == .notDetermined || access == .writeOnly {
            // Write-only can't find or update the events, so ask for full access (iOS offers the upgrade).
            _ = try? await store.requestFullAccessToEvents()
            store.refreshSourcesIfNecessary()
        }
        refreshAccess()
        guard hasFullAccess else { return false }
        calendarNotice = nil
        isEnabled = true
        syncNow()
        return true
    }

    /// Turns sync off. With `removingEvents`, deletes the events it added (or adopted) from the calendar.
    func disable(removingEvents: Bool) {
        pending?.cancel()
        pending = nil
        isEnabled = false
        calendarNotice = nil
        if removingEvents, hasFullAccess {
            for link in loadLinks().values {
                if let event = store.event(withIdentifier: link.eventID) {
                    try? store.remove(event, span: .thisEvent, commit: true)
                }
            }
        }
        // Kept events are found again by title and time if it's turned back on.
        saveLinks([:])
    }

    // MARK: Syncing

    /// Syncs shortly, so a burst of saves or an iCloud import syncs once.
    func scheduleSync() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// Brings the calendar in line with the log right away.
    func syncNow() {
        pending?.cancel()
        pending = nil
        guard isEnabled, hasFullAccess,
              // While the stores are being reopened they look empty.
              CloudStatus.shared.reloadingMessage == nil
        else { return }

        let context = PersistenceController.shared.viewContext
        guard let babies = try? context.fetch(Baby.fetchAll()), !babies.isEmpty,
              let appointments = try? context.fetch(Appointment.fetchAll()),
              let calendar = targetCalendar()
        else { return }

        let original = loadLinks()
        var links = original
        var byKey: [String: Appointment] = [:]
        for appointment in appointments {
            byKey[Self.key(for: appointment)] = appointment
        }

        // Deleted appointments: remove their events. Not while a log is still downloading, when
        // appointments can be missing for a moment.
        if CloudStatus.shared.awaitingImport == nil {
            for (key, link) in links where byKey[key] == nil {
                if let event = store.event(withIdentifier: link.eventID) {
                    try? store.remove(event, span: .thisEvent, commit: true)
                }
                links[key] = nil
            }
        }

        var claimed = Set(links.values.map(\.eventID))
        let cutoff = Date.now.addingTimeInterval(-Self.recentWindow)
        for appointment in appointments {
            let key = Self.key(for: appointment)
            guard appointment.date >= cutoff else {
                // In the past: the event stays in the calendar as it is.
                links[key] = nil
                continue
            }
            let title = Self.eventTitle(appointment.title, babyName: appointment.baby?.displayName)
            let start = appointment.date
            let location = Self.eventLocation(provider: appointment.provider, location: appointment.location)
            let previous = links[key]

            var existing = previous.flatMap { store.event(withIdentifier: $0.eventID) }
            if existing == nil, let previous {
                // Its identifier can change, e.g. after the calendar syncs; look where it was.
                existing = match(title: previous.title, start: previous.start, in: calendar, excluding: claimed)
            }
            if existing == nil {
                existing = match(title: title, start: start, in: calendar, excluding: claimed)
            }

            let event: EKEvent
            let duration: TimeInterval
            if let existing {
                event = existing
                duration = Self.duration(of: existing)
            } else {
                event = EKEvent(eventStore: store)
                event.notes = Self.eventNote
                duration = Self.defaultDuration
            }

            if event.title != title { event.title = title }
            let currentStart: Date? = event.startDate
            if currentStart.map({ abs($0.timeIntervalSince(start)) >= 1 }) ?? true {
                event.startDate = start
                event.endDate = start.addingTimeInterval(duration)
            }
            if (event.location ?? "") != (location ?? "") { event.location = location }
            if event.calendar?.calendarIdentifier != calendar.calendarIdentifier { event.calendar = calendar }

            if event.hasChanges {
                do {
                    try store.save(event, span: .thisEvent, commit: true)
                } catch {
                    print("MyBaby: couldn't save a calendar event: \(error)")
                    continue
                }
            }
            if let eventID = event.eventIdentifier {
                links[key] = Link(eventID: eventID, title: title, start: start)
                claimed.insert(eventID)
            }
        }

        if links != original { saveLinks(links) }
    }

    /// The picked calendar, or the default one if it was deleted or became read-only.
    private func targetCalendar() -> EKCalendar? {
        if let calendarID {
            if let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications {
                return calendar
            }
            self.calendarID = nil
            calendarNotice = "The calendar you picked isn't available anymore, so appointments now go to your default calendar."
            refreshCalendars()
        }
        return store.defaultCalendarForNewEvents
    }

    /// An event in `calendar` with this title starting within a minute of `start`.
    private func match(title: String, start: Date, in calendar: EKCalendar, excluding claimed: Set<String>) -> EKEvent? {
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-60),
            end: start.addingTimeInterval(60),
            calendars: [calendar]
        )
        return store.events(matching: predicate).first { event in
            let eventStart: Date? = event.startDate
            guard event.title == title,
                  let eventStart, abs(eventStart.timeIntervalSince(start)) < 60
            else { return false }
            guard let eventID = event.eventIdentifier else { return true }
            return !claimed.contains(eventID)
        }
    }

    private static func duration(of event: EKEvent) -> TimeInterval {
        let start: Date? = event.startDate
        let end: Date? = event.endDate
        guard let start, let end, end > start else { return defaultDuration }
        return end.timeIntervalSince(start)
    }

    /// Whether a save inserted, changed or deleted an appointment, or a baby (whose name is in the titles).
    private static func touchesAppointments(_ notification: Notification) -> Bool {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is Appointment || $0 is Baby }
        }
    }

    // MARK: Titles

    /// "Mavie: 2-month checkup".
    nonisolated static func eventTitle(_ title: String, babyName: String?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let what = trimmed.isEmpty ? "Appointment" : trimmed
        guard let babyName, !babyName.isEmpty else { return what }
        return "\(babyName): \(what)"
    }

    /// "Dr. Lee, 12 Main Street", or `nil` when neither is set.
    nonisolated static func eventLocation(provider: String, location: String) -> String? {
        let parts = [provider, location]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Which event is which appointment

    /// One appointment's event on this device, with the title and start it was last given, so it can
    /// be found again if its identifier changes.
    private struct Link: Codable, Equatable {
        var eventID: String
        var title: String
        var start: Date
    }

    /// The appointment's `uuid`. Older appointments without one use their object ID's URI, which stays the
    /// same once saved (only unsaved objects have temporary IDs, and sync only sees saved ones).
    private static func key(for appointment: Appointment) -> String {
        appointment.uuid?.uuidString ?? appointment.objectID.uriRepresentation().absoluteString
    }

    private static var linksURL: URL {
        URL.applicationSupportDirectory.appending(path: "CalendarEvents.json")
    }

    private func loadLinks() -> [String: Link] {
        guard let data = try? Data(contentsOf: Self.linksURL),
              let links = try? JSONDecoder().decode([String: Link].self, from: data)
        else { return [:] }
        return links
    }

    private func saveLinks(_ links: [String: Link]) {
        let url = Self.linksURL
        if links.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(links).write(to: url, options: .atomic)
        } catch {
            print("MyBaby: couldn't save the calendar links: \(error)")
        }
    }
}
