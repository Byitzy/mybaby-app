import CoreData
import Foundation

/// Keeps the night schedule the same on both parents' phones by storing it on the shared baby.
///
/// The plan is read from `UserDefaults.shared` everywhere in the app, so this only copies the schedule
/// between the current baby's record (synced through iCloud) and this phone's saved plan.
@MainActor
enum SharedPlanSync {
    /// Call after this phone's plan changes.
    static func push(_ plan: NightPlan, context: NSManagedObjectContext) {
        guard let baby = Baby.current(in: context), let data = try? JSONEncoder().encode(plan) else { return }
        // View-only family can follow the schedule, but not change it for everyone.
        guard PersistenceController.shared.canEdit(baby) else { return }
        if let existing = baby.nightPlanData, NightPlan(data: existing).adoptingSchedule(from: plan) == NightPlan(data: existing) {
            return
        }
        baby.nightPlanData = data
        context.saveIfChanged()
    }

    /// Call when iCloud brings in changes and when the app opens. Returns true if the schedule changed.
    @discardableResult
    static func pull(context: NSManagedObjectContext) -> Bool {
        guard let baby = Baby.current(in: context) else { return false }
        let local = NightPlan.load()

        guard let data = baby.nightPlanData else {
            // A plan set up before the baby was shared: publish it so the partner gets it too.
            if local.isEnabled { push(local, context: context) }
            return false
        }

        let merged = local.adoptingSchedule(from: NightPlan(data: data))
        guard merged != local else { return false }
        merged.save()
        return true
    }
}
