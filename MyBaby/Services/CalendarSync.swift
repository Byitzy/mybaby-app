import CoreData
import CoreLocation
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
    /// Where a place picked from the search is, so Calendar shows a map and can offer travel time.
    var coordinate: CLLocationCoordinate2D?
    /// Seconds before the start (negative), or `nil` for no alert.
    var alarmOffset: TimeInterval?

    /// From the editor's fields, which may not be saved yet.
    init(
        title: String, date: Date, provider: String, location: String, babyName: String?,
        address: String = "", coordinate: CLLocationCoordinate2D? = nil
    ) {
        self.title = CalendarSync.eventTitle(title, babyName: babyName)
        self.start = date
        self.end = date.addingTimeInterval(CalendarSync.defaultDuration)
        self.location = CalendarSync.eventLocation(provider: provider, location: location, address: address)
        self.coordinate = coordinate
        // Shown in the sheet, so the parent can change or remove it before saving.
        self.alarmOffset = -3600
    }

    init(appointment: Appointment) {
        self.init(
            title: appointment.title,
            date: appointment.date,
            provider: appointment.provider,
            location: appointment.location,
            babyName: appointment.baby?.displayName,
            address: appointment.placeAddress,
            coordinate: appointment.place?.coordinate
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
/// - Edits update the event; a deleted or cancelled appointment removes it, and restoring a cancelled
///   one adds it back. Only the title, time and place are kept in step; an alert or notes the parent
///   adds in Calendar stay. A place picked from the search also gets its coordinates
///   (`structuredLocation`), so Calendar shows the map and can offer travel time.
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

    /// The app's one event store, also used by "Add to Calendar". Made the first time it's needed:
    /// opening one connects to the calendar database, and calendar sync is off unless it's turned
    /// on, so most launches never need it.
    private(set) lazy var store = EKEventStore()

    /// New events last an hour; Appointment has no duration.
    nonisolated static let defaultDuration: TimeInterval = 3600
    /// Appointments that started up to this long ago are still kept in step.
    private static let recentWindow: TimeInterval = 24 * 3600
    private static let eventNote = String(localized: "Added by MyBaby. Changes to the appointment in MyBaby update this event.", comment: "The notes of a calendar event MyBaby adds")

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

    /// The parent said no to calendar access (or it isn't allowed on this iPhone), so iOS won't ask
    /// again: it can only be turned on in the Settings app.
    var isAccessOff: Bool { access == .denied || access == .restricted }

    /// The default calendar's name, for "Default (Home)".
    var defaultCalendarTitle: String? {
        hasFullAccess ? store.defaultCalendarForNewEvents?.title : nil
    }

    /// Whether events added by sync are still remembered, so turning it off has something to remove.
    var hasAddedEvents: Bool { !loadLinks().isEmpty }

    /// Whether "Add to Calendar" added events on this iPhone that Delete all data can remove.
    var hasEventsAddedOneAtATime: Bool { !loadSingles().isEmpty }

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
        guard await requestFullAccess() else { return false }
        calendarNotice = nil
        isEnabled = true
        syncNow()
        return true
    }

    /// Asks for full calendar access when it hasn't been decided yet, or is write-only, and says whether
    /// MyBaby has it. Write-only can't find, update or remove events, so iOS offers the upgrade. Once
    /// the parent has said no, iOS doesn't ask again; it can only be turned on in the Settings app.
    func requestFullAccess() async -> Bool {
        if access == .notDetermined || access == .writeOnly {
            _ = try? await store.requestFullAccessToEvents()
            store.refreshSourcesIfNecessary()
        }
        refreshAccess()
        return hasFullAccess
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
            if appointment.isCancelled {
                // Its event goes, as if it were deleted; restoring it adds one again (or adopts the
                // one still in the calendar, if it couldn't be removed).
                if let link = links[key] {
                    let event = store.event(withIdentifier: link.eventID)
                        ?? match(title: link.title, start: link.start, in: calendar, excluding: [])
                    if let event {
                        try? store.remove(event, span: .thisEvent, commit: true)
                    }
                }
                links[key] = nil
                continue
            }
            guard appointment.date >= cutoff else {
                // In the past: the event stays in the calendar as it is.
                links[key] = nil
                continue
            }
            let title = Self.eventTitle(appointment.title, babyName: appointment.baby?.displayName)
            let start = appointment.date
            let location = Self.eventLocation(
                provider: appointment.provider, location: appointment.location, address: appointment.placeAddress
            )
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
            Self.setPlace(of: event, to: location, coordinate: appointment.place?.coordinate)
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
            calendarNotice = String(localized: "The calendar you picked isn't available anymore, so appointments now go to your default calendar.")
            refreshCalendars()
        }
        return store.defaultCalendarForNewEvents
    }

    /// An event in `calendar` (any calendar when `nil`) with this title starting within a minute of `start`.
    private func match(title: String, start: Date, in calendar: EKCalendar?, excluding claimed: Set<String>) -> EKEvent? {
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-60),
            end: start.addingTimeInterval(60),
            calendars: calendar.map { [$0] }
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

    /// "Mavie: 2-month checkup". In this iPhone's language, so a phone set to another language gives
    /// the same appointment a different title and won't adopt the other phone's event.
    nonisolated static func eventTitle(_ title: String, babyName: String?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let what = trimmed.isEmpty ? String(localized: "Appointment", comment: "Calendar event title for an appointment without a title") : trimmed
        guard let babyName, !babyName.isEmpty else { return what }
        return String(localized: "\(babyName): \(what)", comment: "Calendar event title: the baby's name, then the appointment, e.g. Mavie: 2-month checkup")
    }

    /// "Dr. Lee, Maple Street Pediatrics, 12 Main Street", or `nil` when none is set. The address is
    /// only there for a place picked from the search.
    nonisolated static func eventLocation(provider: String, location: String, address: String = "") -> String? {
        let place = Appointment.placeLine(name: location, address: address)
        let parts = [provider, place]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The location text with the place's coordinates, for Calendar's map and travel time. `nil`
    /// for a typed-in place, which only has the text.
    nonisolated static func structuredLocation(title: String?, coordinate: CLLocationCoordinate2D?) -> EKStructuredLocation? {
        guard let title, !title.isEmpty, let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let structured = EKStructuredLocation(title: title)
        structured.geoLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return structured
    }

    /// Keeps the event's place in step: the text in `location`, as before, plus the coordinates when
    /// the place was picked from the search. Only changes what differs, so an unchanged event isn't saved.
    private static func setPlace(of event: EKEvent, to location: String?, coordinate: CLLocationCoordinate2D?) {
        let textChanged = (event.location ?? "") != (location ?? "")
        let structured = structuredLocation(title: location, coordinate: coordinate)
        if textChanged {
            // A place that's now typed in loses the old one's map.
            if structured == nil, event.structuredLocation?.geoLocation != nil {
                event.structuredLocation = nil
            }
            event.location = location
        }
        guard let structured, let wanted = structured.geoLocation?.coordinate else { return }
        let current = event.structuredLocation
        let currentCoordinate = current?.geoLocation?.coordinate
        let samePlace = current?.title == structured.title
            && currentCoordinate.map { abs($0.latitude - wanted.latitude) < 0.00001 && abs($0.longitude - wanted.longitude) < 0.00001 } == true
        if textChanged || !samePlace {
            event.structuredLocation = structured
        }
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

    // MARK: Events added one at a time

    /// An event "Add to Calendar" added on this iPhone, remembered so Delete all data can remove it too.
    ///
    /// Its identifier is only known when MyBaby has full calendar access, because only then does the
    /// sheet run inside the app. Without access (the usual case: iOS 17 runs the sheet outside the app,
    /// and the event never comes back), it's found again by the title and start it was offered with.
    /// Kept per device next to `CalendarEvents.json`, never in the shared log, like the sync links.
    struct AddedEvent: Codable, Equatable {
        var eventID: String?
        var title: String
        var start: Date

        /// "Mavie: 2-month checkup, Oct 2, 2026 at 9:30 AM", for saying which events stayed.
        var spokenName: String {
            "\(title), \(start.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    /// What removing the "Add to Calendar" events did, for Delete all data's summary.
    struct AddedEventsRemoval {
        var removed = 0
        /// Remembered, but not in the calendar any more: deleted already, or moved or renamed there.
        var notFound: [AddedEvent] = []
        /// Still in the calendar, because MyBaby wasn't allowed to open it or the calendar refused.
        var stayed: [AddedEvent] = []
    }

    /// The most events remembered; the oldest are forgotten first. Years of checkups fit easily.
    private static let addedEventsLimit = 500

    /// Remembers an event the parent just added with "Add to Calendar". `event` is the sheet's event:
    /// with full access it's the saved one, with its identifier and anything the parent changed;
    /// otherwise it still holds what the sheet was opened with.
    func rememberAddedEvent(_ event: EKEvent?, draft: CalendarEventDraft) {
        let identifier: String? = event?.eventIdentifier
        let eventID = (identifier?.isEmpty ?? true) ? nil : identifier
        let title: String? = event?.title
        let start: Date? = event?.startDate
        let added = AddedEvent(eventID: eventID, title: title ?? draft.title, start: start ?? draft.start)

        var singles = loadSingles()
        singles.removeAll { $0 == added || (eventID != nil && $0.eventID == eventID) }
        singles.append(added)
        if singles.count > Self.addedEventsLimit {
            singles.removeFirst(singles.count - Self.addedEventsLimit)
        }
        saveSingles(singles)
    }

    /// Removes every event "Add to Calendar" added on this iPhone, then forgets them all. Needs full
    /// calendar access, asked for beforehand with `requestFullAccess()`; without it nothing is removed
    /// and every event is listed in `stayed`.
    ///
    /// Run before `disable(removingEvents:)`, which removes the events Keep appointments in my calendar
    /// kept in step: an event it adopted from an earlier "Add to Calendar" is removed by either.
    func removeEventsAddedOneAtATime() -> AddedEventsRemoval {
        var result = AddedEventsRemoval()
        let singles = loadSingles()
        guard !singles.isEmpty else { return result }
        refreshAccess()
        guard hasFullAccess else {
            result.stayed = singles
            saveSingles([])
            return result
        }

        let synced = Array(loadLinks().values)
        var removedIDs = Set<String>()
        for single in singles {
            var found = single.eventID.flatMap { store.event(withIdentifier: $0) }
            if found == nil {
                // Its identifier can change, e.g. after the calendar syncs, and is unknown without access.
                found = match(title: single.title, start: single.start, in: nil, excluding: removedIDs)
            }
            guard let event = found else {
                let isSynced = synced.contains { $0.title == single.title && abs($0.start.timeIntervalSince(single.start)) < 60 }
                if isSynced {
                    // Adopted by Keep appointments in my calendar, which removes it next.
                    result.removed += 1
                } else {
                    result.notFound.append(single)
                }
                continue
            }
            let eventID: String? = event.eventIdentifier
            do {
                // The whole series, in case the parent made it repeat in the sheet.
                try store.remove(event, span: .futureEvents, commit: true)
                if let eventID { removedIDs.insert(eventID) }
                result.removed += 1
            } catch {
                print("MyBaby: couldn't remove a calendar event: \(error)")
                result.stayed.append(single)
            }
        }
        saveSingles([])
        return result
    }

    private static var singlesURL: URL {
        URL.applicationSupportDirectory.appending(path: "CalendarAddedEvents.json")
    }

    private func loadSingles() -> [AddedEvent] {
        guard let data = try? Data(contentsOf: Self.singlesURL),
              let singles = try? JSONDecoder().decode([AddedEvent].self, from: data)
        else { return [] }
        return singles
    }

    private func saveSingles(_ singles: [AddedEvent]) {
        let url = Self.singlesURL
        if singles.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(singles).write(to: url, options: .atomic)
        } catch {
            print("MyBaby: couldn't save the list of events added to the calendar: \(error)")
        }
    }
}
