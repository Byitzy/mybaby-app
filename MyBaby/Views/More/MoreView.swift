import CoreData
import SwiftUI

/// Everything beyond the daily log: the babies, the night features and Settings.
///
/// Its navigation is kept in `NavigationMemory`, so a parent who turns iCloud on or off in Settings
/// is still in Settings when the screens come back.
struct MoreView: View {
    @ObservedObject var baby: Baby
    @ObservedObject private var navigation = NavigationMemory.shared
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>

    var body: some View {
        NavigationStack(path: $navigation.morePath) {
            List {
                Section {
                    NavigationLink(value: MoreRoute.babies) {
                        MoreRow(title: "Babies", systemImage: "figure.and.child.holdinghands", tint: Palette.baby) {
                            Text(babies.count > 1 ? "\(baby.displayName) · \(babies.count) babies" : baby.displayName)
                        }
                    }
                }

                Section {
                    featureRows
                }

                Section {
                    NavigationLink(value: MoreRoute.settings) {
                        MoreRow(title: "Settings", systemImage: "gearshape", tint: Palette.settings)
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: MoreRoute.self) { route in
                destination(for: route)
            }
        }
        .onAppear {
            dropMissingBabies()
            // Two copies of the same baby may have come from iCloud (see `DuplicateBabies`).
            DuplicateBabies.shared.check()
        }
        .onChange(of: babies.count) { dropMissingBabies() }
    }

    /// One row per feature. A new feature adds its row here, with a case in `MoreRoute`.
    @ViewBuilder
    private var featureRows: some View {
        NavigationLink(value: MoreRoute.nightShifts) {
            MoreRow(title: "Night shifts", systemImage: "moon.stars", tint: Palette.nightShift) {
                Text(nightPlan.isEnabled ? nightPlan.mode.title : "Off")
            }
        }
        NavigationLink(value: MoreRoute.cryAlerts) {
            MoreRow(title: "Cry alerts", systemImage: "ear", tint: Palette.cryAlerts) {
                Text(CryMonitor.shared.isListening ? "Listening" : "Off")
            }
        }
        NavigationLink(value: MoreRoute.milkStash) {
            MoreRow(title: "Milk stash", systemImage: "refrigerator", tint: Palette.milkStash)
        }
        NavigationLink(value: MoreRoute.milestones) {
            MoreRow(title: "Milestones", systemImage: "star.circle", tint: Palette.milestone)
        }
        NavigationLink(value: MoreRoute.diary) {
            MoreRow(title: "Diary", systemImage: "book.closed", tint: Palette.diary)
        }
        NavigationLink(value: MoreRoute.momCare) {
            MoreRow(title: CareTitle.title(plan: NightPlan(data: nightPlanData)), systemImage: "heart.circle", tint: Palette.momCare)
        }
    }

    /// The screen for each route, for the current baby where it shows a baby's log.
    @ViewBuilder
    private func destination(for route: MoreRoute) -> some View {
        switch route {
        case .babies:
            BabiesView()
        case .babyProfile(let id):
            // A baby that's gone is dropped from the path (see `dropMissingBabies`).
            if let profile = babies.first(where: { $0.uuid == id }) {
                BabyProfileView(baby: profile)
            }
        case .nightShifts:
            NightPlanView()
        case .cryAlerts:
            CryMonitorView()
        case .milkStash:
            // Rebuilt for each baby, so it shows that baby's stash.
            MilkStashView(baby: baby)
                .id(baby.objectID)
        case .milestones:
            // Rebuilt for each baby, so the timeline is that baby's.
            MilestonesView(baby: baby)
                .id(baby.objectID)
        case .diary:
            // Rebuilt for each baby, so it's that baby's diary.
            DiaryView(baby: baby)
                .id(baby.objectID)
        case .momCare:
            PrivateContentLock(title: "This page is private") { MomCareView() }
        case .settings:
            // Rebuilt for each baby, so its counts and export are that baby's.
            SettingsView(baby: baby)
                .id(baby.objectID)
        case .privacy:
            PrivacyView()
        }
    }

    /// A remembered profile of a baby who was removed or merged into another goes away, so the
    /// parent is back where they opened it from.
    private func dropMissingBabies() {
        navigation.dropProfiles(exceptFor: Set(babies.compactMap(\.uuid)))
    }

    private var nightPlan: NightPlan { NightPlan(data: nightPlanData) }
}

/// A row in More: an icon, a title and an optional value on the right.
private struct MoreRow<Detail: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let detail: Detail

    init(title: String, systemImage: String, tint: Color, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.detail = detail()
    }

    var body: some View {
        LabeledContent {
            detail
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
        }
    }
}

extension MoreRow where Detail == EmptyView {
    init(title: String, systemImage: String, tint: Color) {
        self.init(title: title, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}
