import SwiftUI

/// The app's tabs, so the selected one can be remembered (see `RootView`).
enum AppTab: String {
    case today, history, reports, health, more
}

/// The screens the More tab pushes, so its navigation can be remembered.
enum MoreRoute: Hashable, Codable {
    case babies
    /// A baby's profile, by the baby's `uuid`.
    case babyProfile(UUID)
    case nightShifts
    case cryAlerts
    case milkStash
    case milestones
    /// The diary: entries, week and month summaries, and letters for later.
    case diary
    case momCare
    case settings
    case privacy

    /// The baby a profile route opens, if it's one.
    var babyID: UUID? {
        if case .babyProfile(let id) = self { return id }
        return nil
    }
}

/// Where the parent is in the More tab.
///
/// Turning iCloud on or off takes every screen down and builds them again (see
/// `PersistenceController.takeDownContent`). The navigation stacks would start over with them, so a
/// parent who flipped the switch in More › Settings would land back at the top of More. The path is
/// kept here instead, outside the screens, so it comes back after the rebuild. Only in memory: a
/// fresh launch starts at the top of More.
@MainActor
final class NavigationMemory: ObservableObject {
    static let shared = NavigationMemory()

    @Published var morePath: [MoreRoute] = []

    /// Drops the profiles of babies that are gone (removed, merged into another, or a shared log
    /// that was left), so the parent goes back to where the profile was opened from.
    func dropProfiles(exceptFor babyIDs: Set<UUID>) {
        let kept = morePath.filter { route in
            guard let id = route.babyID else { return true }
            return babyIDs.contains(id)
        }
        if kept != morePath { morePath = kept }
    }

    /// Back to the top of More, e.g. when onboarding starts a new log.
    func reset() {
        if !morePath.isEmpty { morePath = [] }
    }
}

/// Opens a baby's profile inside the More tab, so it's remembered when iCloud is switched on or
/// off. A baby without an id yet opens the same way, just without being remembered.
struct BabyProfileLink<Label: View>: View {
    @ObservedObject var baby: Baby
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let id = baby.uuid {
            NavigationLink(value: MoreRoute.babyProfile(id), label: label)
        } else {
            NavigationLink(destination: { BabyProfileView(baby: baby) }, label: label)
        }
    }
}
