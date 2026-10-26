import CoreData
import Foundation
import UserNotifications

/// After a vaccine is marked given, what to look out for and when (see `VaccineGuide.watchWindows`):
/// - **Today's card** (`VaccineFollowUpSection`): one card for each visit with a shot inside one of
///   its windows. The shots given on the same day are one visit, so the 2-month shots are one card.
///   Only shots marked given, dated today or earlier, ever count: never one that's only due.
/// - **The optional reminder** (Settings › *After vaccines*, off by default): a notification at 9 AM
///   on the day a later window starts (MMR and MMRV on day 6, BCG at 2 weeks). Only the next one is
///   pending (see the budget at the top of `NotificationManager`); shots for twins on the same day
///   share it. It's worked out again with the other care reminders (`CareReminders.refresh`), and on
///   every save and when the app opens (`WidgetSnapshotWriter`), so the next one follows on its own.
///   Tapping it opens Today.
///
/// Dismissing a card is remembered on this iPhone, per vaccine and window, so it comes back when the
/// next window starts (MMR's later days), and not before.
enum VaccineFollowUp {
    static let identifierPrefix = "vaccine-watch-"
    private static let babyKey = "babyID"
    /// The hour the reminder comes at: 9 AM, local time.
    static let reminderHour = 9
    /// Far enough back for the longest window (BCG, 12 weeks).
    static let lookBackDays = 90

    /// A shot, in the window it's in today.
    struct Shot: Identifiable {
        let vaccine: Vaccine
        let entry: VaccineGuide.Entry?
        let window: VaccineGuide.WatchWindow

        var id: NSManagedObjectID { vaccine.objectID }

        /// What's remembered when its card is dismissed: the vaccine and the window.
        var dismissKey: String { VaccineFollowUp.dismissKey(vaccine: vaccine, window: window) }

        /// "MMR", for a title. The guide's short name, or the name it was saved with.
        var shortName: String {
            if let entry, let short = VaccineGuide.watchShortName(for: entry) { return short }
            if let entry { return entry.name }
            return vaccine.name.isEmpty ? String(localized: "Vaccine") : vaccine.name
        }
    }

    /// One visit's shots that are inside a window today.
    struct Card: Identifiable {
        /// The day of the visit, at its start.
        let day: Date
        /// Whole days since the visit: 0 on the day.
        let daysSince: Int
        let shots: [Shot]

        var id: Date { day }

        var dismissKeys: [String] { shots.map(\.dismissKey) }

        /// Each vaccine's notes once, in the order they were given.
        var entries: [VaccineGuide.Entry] {
            var seen: Set<String> = []
            return shots.compactMap(\.entry).filter { seen.insert($0.id).inserted }
        }

        /// "After Tuesday's shots" in the first days, then "MMR was 9 days ago". Whole sentences, so
        /// each language has its own word order.
        var title: String {
            let one = shots.count == 1
            switch daysSince {
            case 0:
                return one
                    ? String(localized: "After today's shot", comment: "Vaccine follow-up card on Today: one vaccine given today")
                    : String(localized: "After today's shots", comment: "Vaccine follow-up card on Today: several vaccines given today")
            case 1:
                return one
                    ? String(localized: "After yesterday's shot", comment: "Vaccine follow-up card on Today: one vaccine given yesterday")
                    : String(localized: "After yesterday's shots", comment: "Vaccine follow-up card on Today: several vaccines given yesterday")
            case 2:
                let weekday = day.formatted(.dateTime.weekday(.wide))
                return one
                    ? String(localized: "After \(weekday)'s shot", comment: "Vaccine follow-up card on Today: one vaccine given 2 days ago; the day of the week, like Tuesday")
                    : String(localized: "After \(weekday)'s shots", comment: "Vaccine follow-up card on Today: several vaccines given 2 days ago; the day of the week, like Tuesday")
            default:
                return VaccineFollowUp.capitalizingFirstLetter(laterTitle)
            }
        }

        /// "MMR and the chickenpox vaccine were 9 days ago", past the first days.
        private var laterTitle: String {
            var seen: Set<String> = []
            let names = shots.map(\.shortName).filter { seen.insert($0).inserted }
            let list = names.formatted(.list(type: .and))
            if daysSince >= 14 {
                let weeks = daysSince / 7
                return names.count == 1
                    ? String(localized: "\(list) was \(weeks) weeks ago", comment: "Vaccine follow-up card on Today; a short vaccine name like BCG, then a number of weeks (2 or more)")
                    : String(localized: "\(list) were \(weeks) weeks ago", comment: "Vaccine follow-up card on Today; short vaccine names like “MMR and the chickenpox vaccine”, then a number of weeks (2 or more)")
            }
            return names.count == 1
                ? String(localized: "\(list) was \(daysSince) days ago", comment: "Vaccine follow-up card on Today; a short vaccine name like MMR, then a number of days (3 or more)")
                : String(localized: "\(list) were \(daysSince) days ago", comment: "Vaccine follow-up card on Today; short vaccine names like “MMR and the chickenpox vaccine”, then a number of days (3 or more)")
        }

        /// Two or three short lines. With several vaccines, the signs to call about (`isKey`) are
        /// always kept, then each vaccine's own lines before the ones for any vaccine; what's normal
        /// comes first and the signs to call about last. The rest is a tap away.
        var lines: [VaccineGuide.WatchLine] {
            var windows: [VaccineGuide.WatchWindow] = []
            for window in shots.map(\.window).sorted(by: { !$0.isGeneral && $1.isGeneral }) where !windows.contains(window) {
                windows.append(window)
            }
            var all: [VaccineGuide.WatchLine] = []
            for line in windows.flatMap(\.lines) where !all.contains(line) {
                all.append(line)
            }
            var chosen = all.filter(\.isKey)
            for line in all where !line.isKey && chosen.count < 3 {
                chosen.append(line)
            }
            return all.filter { !$0.isKey && chosen.contains($0) } + all.filter(\.isKey)
        }
    }

    // MARK: Today's cards

    /// The cards for `vaccines` (one baby's) today, the latest visit first. Leaves out shots that
    /// aren't marked given or are dated later than today, and cards whose shots were all dismissed.
    static func cards(
        for vaccines: [Vaccine],
        now: Date,
        dismissed: Set<String>,
        calendar: Calendar = .current
    ) -> [Card] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: [Shot]] = [:]
        for vaccine in vaccines where vaccine.isGiven {
            let day = calendar.startOfDay(for: vaccine.date)
            guard let days = calendar.dateComponents([.day], from: day, to: today).day, days >= 0 else { continue }
            let match = Self.entry(for: vaccine)
            // The windows of one vaccine don't overlap; the later one wins if they ever do.
            guard let window = VaccineGuide.watchWindows(for: match).last(where: { $0.days.contains(days) }) else { continue }
            byDay[day, default: []].append(Shot(vaccine: vaccine, entry: match, window: window))
        }
        return byDay.compactMap { element -> Card? in
            let (day, shots) = element
            guard shots.contains(where: { !dismissed.contains($0.dismissKey) }),
                  let days = calendar.dateComponents([.day], from: day, to: today).day
            else { return nil }
            return Card(day: day, daysSince: days, shots: shots)
        }
        .sorted { $0.day > $1.day }
    }

    /// `text` with its first letter capitalized the way the iPhone's language does it, for a title that
    /// starts with a short name like "the chickenpox vaccine".
    static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: .current) + text.dropFirst()
    }

    /// The guide's notes for a vaccine: by the name it was saved with, then by the product.
    static func entry(for vaccine: Vaccine) -> VaccineGuide.Entry? {
        VaccineGuide.entry(matching: vaccine.name) ?? VaccineGuide.entry(matching: vaccine.product)
    }

    static func dismissKey(vaccine: Vaccine, window: VaccineGuide.WatchWindow) -> String {
        let id = vaccine.uuid?.uuidString ?? vaccine.objectID.uriRepresentation().absoluteString
        return "\(id):\(window.id)"
    }

    // MARK: The reminder

    /// Replaces the pending reminder with one for the next later window to start, across every baby,
    /// or none when the setting is off.
    @MainActor
    static func refresh(context: NSManagedObjectContext, now: Date = .now, calendar: Calendar = .current) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.vaccineFollowUpReminder) else {
            removePending(except: nil)
            return
        }
        // While the stores are being reopened they look empty.
        guard CloudStatus.shared.reloadingMessage == nil else { return }

        let request = Vaccine.fetchAll()
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -lookBackDays, to: today) ?? today
        // Given today or earlier: never one that's only due, or dated later.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        request.predicate = NSPredicate(format: "isGiven == YES AND date >= %@ AND date < %@", since as NSDate, tomorrow as NSDate)
        let vaccines = (try? context.fetch(request)) ?? []

        var upcoming: [(fire: Date, vaccine: Vaccine, body: String)] = []
        for vaccine in vaccines {
            guard let match = Self.entry(for: vaccine) else { continue }
            let day = calendar.startOfDay(for: vaccine.date)
            for window in VaccineGuide.watchWindows(for: match) {
                guard let reminder = window.reminder,
                      let start = calendar.date(byAdding: .day, value: window.days.lowerBound, to: day),
                      let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: start),
                      fire > now
                else { continue }
                let name = VaccineGuide.watchShortName(for: match) ?? match.name
                upcoming.append((fire: fire, vaccine: vaccine, body: VaccineGuide.reminderBody(reminder, name: name, day: window.days.lowerBound)))
            }
        }
        guard let next = upcoming.map({ $0.fire }).min() else {
            removePending(except: nil)
            return
        }
        let due = upcoming.filter { $0.fire == next }

        var bodies: [String] = []
        for body in due.map({ $0.body }) where !bodies.contains(body) {
            bodies.append(body)
        }
        var babies: [Baby] = []
        for baby in due.compactMap({ $0.vaccine.baby }) where !babies.contains(baby) {
            babies.append(baby)
        }
        let babyCount = (try? context.count(for: Baby.fetchAll())) ?? 0

        let content = UNMutableNotificationContent()
        if babyCount > 1, !babies.isEmpty {
            let names = babies.map(\.displayName).formatted(.list(type: .and))
            content.title = String(localized: "💉 \(names): what to look out for", comment: "Notification title after a vaccine, with twins or siblings; the babies' names")
        } else {
            content.title = String(localized: "💉 What to look out for", comment: "Notification title after a vaccine")
        }
        content.body = bodies.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = identifierPrefix
        if babies.count == 1, let id = babies.first?.uuid?.uuidString {
            content.userInfo = [babyKey: id]
        }

        let identifier = identifierPrefix + "\(Int(next.timeIntervalSince1970))"
        removePending(except: identifier)
        // A calendar date, so it comes at 9 AM wherever the iPhone is that day.
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        let notification = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        Task {
            guard await NotificationManager.requestAuthorization() else { return }
            try? await UNUserNotificationCenter.current().add(notification)
        }
    }

    private static func removePending(except keep: String?) {
        let center = UNUserNotificationCenter.current()
        let prefix = identifierPrefix
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) && $0 != keep }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    /// Opens Today, on the baby it was about, when the reminder is tapped. Called by the app's
    /// notification delegate.
    static func handle(_ response: UNNotificationResponse) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(identifierPrefix),
              response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }
        let babyID = request.content.userInfo[babyKey] as? String
        await MainActor.run {
            if let babyID {
                UserDefaults.shared.set(babyID, forKey: SettingsKey.selectedBaby)
            }
            CryAlertTaps.shared.openToday = true
        }
    }
}

extension SettingsKey {
    // In `UserDefaults.standard`, so each phone chooses:
    /// Whether the "what to look out for" reminder comes when a later window after a vaccine starts.
    static let vaccineFollowUpReminder = "vaccineFollowUpReminder"
    /// The vaccine follow-up cards dismissed on Today, as "vaccine:window" keys, one per line.
    static let dismissedVaccineFollowUps = "dismissedVaccineFollowUps"
}
