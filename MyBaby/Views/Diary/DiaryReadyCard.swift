import SwiftUI

/// Today's small card the day a week or month summary is ready: "Mavie is 3 months old today 🎉 · See
/// her month and write something for her." Tapping it opens the summary in the diary.
///
/// It stays for a few days (see `DiaryPeriod.justFinished`) unless it's dismissed, and only for periods
/// the app was in use for. Dismissing is remembered on this iPhone, per baby and period.
struct DiaryReadyCard: View {
    @ObservedObject var baby: Baby
    let now: Date
    @AppStorage(SettingsKey.dismissedDiaryCards) private var dismissed = ""

    var body: some View {
        if let period = readyPeriod {
            Section {
                NavigationLink {
                    DiaryView(baby: baby, opening: period)
                } label: {
                    card(period)
                }
                .swipeActions {
                    Button("Dismiss") { dismiss(period) }
                        .tint(Palette.inactive)
                }
                .accessibilityAction(named: "Dismiss") { dismiss(period) }
            }
        }
    }

    /// The summary that's just become ready, unless it was dismissed.
    private var readyPeriod: DiaryPeriod? {
        guard let birthDate = baby.birthDate,
              let period = DiaryPeriod.justFinished(birthDate: birthDate, now: now),
              // A baby added to the app at 5 months has no log for the months before.
              period.end > baby.createdAt,
              !dismissedKeys.contains(key(for: period))
        else { return nil }
        return period
    }

    private func card(_ period: DiaryPeriod) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            EmojiBadge(emoji: period.kind == .month ? "🎉" : "📖", tint: Palette.diary, size: 40)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title(period))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("See \(baby.possessivePronoun) \(period.noun) and write something for \(baby.objectPronoun).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title(period, emoji: false)). See \(baby.possessivePronoun) \(period.noun) and write something for \(baby.objectPronoun).")
            Spacer(minLength: 0)
            Button {
                dismiss(period)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(Spacing.xs)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.vertical, Spacing.xxs)
    }

    /// "Mavie is 3 months old today 🎉", or "Mavie turned 6 weeks on Tue, Oct 21" a day or two later.
    private func title(_ period: DiaryPeriod, emoji: Bool = true) -> String {
        let party = emoji && period.kind == .month ? " 🎉" : ""
        if Calendar.current.isDate(period.end, inSameDayAs: now) {
            return "\(baby.displayName) is \(period.ageReached) old today\(party)"
        }
        let day = period.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(baby.displayName) turned \(period.ageReached) on \(day)\(party)"
    }

    private var dismissedKeys: Set<String> {
        Set(dismissed.split(separator: "\n").map(String.init))
    }

    private func key(for period: DiaryPeriod) -> String {
        "\(baby.uuid?.uuidString ?? baby.displayName):\(period.id.key)"
    }

    private func dismiss(_ period: DiaryPeriod) {
        // Only the latest few are needed: older periods are past their few days anyway.
        var keys = dismissed.split(separator: "\n").map(String.init)
        keys.append(key(for: period))
        dismissed = keys.suffix(40).joined(separator: "\n")
    }
}
