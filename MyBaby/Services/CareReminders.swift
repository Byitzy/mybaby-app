import CoreData
import Foundation
import UserNotifications

/// Reminders for the milk stash and medicine dose timing. Like the feeding reminder, they're
/// worked out again from the log whenever it changes, here or on the partner's phone.
enum CareReminders {
    private static var center: UNUserNotificationCenter { .current() }
    private static let medicinePrefix = "medicine-next-"
    private static let milkPrefix = "milk-stash-"
    /// Caps that keep the app within iOS's 64 pending notifications (see `NotificationManager`).
    static let maxMedicineReminders = 10
    static let maxMilkReminders = 10

    /// Both kinds of reminder. Call when the log changes on the other phone.
    @MainActor
    static func refresh(context: NSManagedObjectContext) {
        refreshMedicine(context: context)
        refreshMilkStash(context: context)
    }

    // MARK: Medicine

    /// One notification per medicine that has "Notify me" on, at the time its next dose is allowed.
    @MainActor
    static func refreshMedicine(context: NSManagedObjectContext) {
        context.saveIfChanged()
        let schedules = ((try? context.fetch(MedicineSchedule.fetchAll())) ?? []).filter(\.notifiesWhenAllowed)
        let babies = (try? context.count(for: Baby.fetchAll())) ?? 0
        var keep: Set<String> = []

        var due: [(schedule: MedicineSchedule, baby: Baby, id: String, next: Date)] = []
        for schedule in schedules {
            guard let baby = schedule.baby, let id = schedule.uuid?.uuidString else { continue }
            let key = MedicineSchedule.key(for: schedule.name)
            let doses = ((try? context.fetch(baby.entries(Activity.all(.medication)))) ?? [])
                .filter { MedicineSchedule.key(for: $0.medicationName) == key }
                .map(\.startDate)
            guard let next = MedicineTiming.nextAllowed(rule: schedule.rule, doseDates: doses) else { continue }
            due.append((schedule: schedule, baby: baby, id: id, next: next))
        }

        // The soonest ones only, within iOS's limit of 64 pending notifications.
        for (schedule, baby, id, next) in due.sorted(by: { $0.next < $1.next }).prefix(maxMedicineReminders) {
            let content = UNMutableNotificationContent()
            content.title = babies > 1
                ? "💊 \(schedule.name) for \(baby.displayName)"
                : "💊 \(schedule.name)"
            content.body = "The dose timing you entered allows the next dose now. Only give it if it's still needed, as your pediatrician directed."
            content.sound = .default

            let identifier = medicinePrefix + id
            add(identifier: identifier, content: content, at: next)
            keep.insert(identifier)
        }
        removePending(prefix: medicinePrefix, except: keep)
    }

    // MARK: Milk stash

    /// The morning (8 AM) a bag in the fridge or freezer reaches its use-by date, one notification
    /// per day. Room-temperature milk only keeps for hours, so it isn't included.
    @MainActor
    static func refreshMilkStash(context: NSManagedObjectContext) {
        let defaults = UserDefaults.shared
        let enabled = defaults.bool(forKey: SettingsKey.milkStashReminder)
        let unit = VolumeUnit(rawValue: defaults.string(forKey: SettingsKey.volumeUnit) ?? "") ?? .ml
        let bags = enabled ? ((try? context.fetch(MilkBag.inStash())) ?? []) : []
        let calendar = Calendar.current
        let now = Date.now

        var byFireDate: [Date: [MilkBag]] = [:]
        for bag in bags where bag.storage != .room || bag.isThawed {
            let useBy = bag.useBy
            guard var fire = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: useBy) else { continue }
            if fire >= useBy { fire = useBy.addingTimeInterval(-2 * 3600) }
            guard fire > now else { continue }
            byFireDate[fire, default: []].append(bag)
        }

        var keep: Set<String> = []
        // Only the next few, leaving room for the others in iOS's limit of 64 pending notifications.
        for fire in byFireDate.keys.sorted().prefix(maxMilkReminders) {
            let due = byFireDate[fire] ?? []
            let total = due.compactMap(\.amountML).reduce(0, +)
            let content = UNMutableNotificationContent()
            content.title = "🫙 Milk to use today"
            let bagsText = Format.plural(due.count, "bag")
            content.body = total > 0
                ? "\(bagsText) of milk (\(unit.format(ml: total))) in the stash reach their use-by date today."
                : "\(bagsText) of milk in the stash reach their use-by date today."
            if due.count == 1 {
                content.body = content.body.replacingOccurrences(of: "reach their", with: "reaches its")
            }
            content.sound = .default

            let identifier = milkPrefix + "\(Int(fire.timeIntervalSince1970))"
            add(identifier: identifier, content: content, at: fire)
            keep.insert(identifier)
        }
        removePending(prefix: milkPrefix, except: keep)
    }

    // MARK: Helpers

    private static func removePending(prefix: String, except keep: Set<String>) {
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) && !keep.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    private static func add(identifier: String, content: UNNotificationContent, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task {
            guard await NotificationManager.requestAuthorization() else { return }
            try? await center.add(request)
        }
    }
}
