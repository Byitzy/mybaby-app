import CoreData
import SwiftUI

/// Today's one-time "Who's using this iPhone?" card, so night-shift wake-ups and cry alerts buzz the
/// right parent. Each phone answers for itself; the answer stays on this iPhone (`NightPlan.alarmOwner`).
///
/// It's shown once both parents have names and nobody has picked on this iPhone yet (in Settings ›
/// Parents, Night shifts or here), on a phone that joined the partner's log, or on the phone that
/// set up the log while it's still on the old "both of us" default. Picking or dismissing it hides it
/// for good. View-only family see it too: it's a setting for this phone, not a change to the log.
struct DeviceOwnerPromptSection: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage(SettingsKey.deviceOwnerChosen) private var ownerChosen = false
    @ObservedObject var baby: Baby

    var body: some View {
        let plan = NightPlan(data: nightPlanData)
        if shouldAsk(plan) {
            Section {
                card(plan)
            }
        }
    }

    private func shouldAsk(_ plan: NightPlan) -> Bool {
        guard !ownerChosen, plan.hasBothNames else { return false }
        return PersistenceController.shared.isJoined(baby) || plan.alarmOwner == .both
    }

    private func card(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "iphone")
                    .font(.title3)
                    .foregroundStyle(Palette.nightShift)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Who's using this iPhone?")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Night-shift wake-ups and cry alerts will only buzz them. You can change it anytime in Settings › Parents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    ownerChosen = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(Spacing.xs)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
                .accessibilityHint("Doesn't ask again. You can choose in Settings › Parents.")
            }
            // Side by side, or one under the other when they don't fit (long names, large text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { buttons(plan) }
                VStack(alignment: .leading, spacing: Spacing.s) { buttons(plan) }
            }
            .controlSize(.small)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func buttons(_ plan: NightPlan) -> some View {
        ForEach(Parent.allCases) { parent in
            let name = plan.name(of: parent)
            Button(name) {
                ParentSettings.setOwner(AlarmOwner(parent), context: context)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(name)'s iPhone")
            .accessibilityHint("Only buzzes \(name) for night-shift wake-ups and cry alerts")
        }
        Button("Both of us") {
            ParentSettings.setOwner(.both, context: context)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Shared iPhone, both of us")
        .accessibilityHint("Buzzes whoever is on duty")
    }
}
