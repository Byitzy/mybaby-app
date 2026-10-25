import SwiftUI

/// The five mood faces. Tapping the chosen face again clears it.
struct MoodPicker: View {
    @Binding var selection: Mood?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var faceSize: CGFloat = 30

    var body: some View {
        // In a row, or a column at the largest text sizes so the words aren't squeezed.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.xs))
        layout {
            ForEach(Mood.allCases) { mood in
                let isSelected = selection == mood
                Button {
                    selection = isSelected ? nil : mood
                } label: {
                    VStack(spacing: Spacing.xs) {
                        Text(mood.emoji)
                            .font(.system(size: min(faceSize, 44)))
                            .accessibilityHidden(true)
                        Text(mood.title)
                            .font(.caption2.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s)
                    .background(isSelected ? Palette.momCare.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.choice))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.choice)
                            .strokeBorder(isSelected ? Palette.momCare : Color.clear, lineWidth: 2)
                    )
                }
                // Each face is its own tap target inside the list row.
                .buttonStyle(.plain)
                .accessibilityLabel(mood.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How are you feeling?")
    }
}

/// Hours of sleep in half hours, or "Not set".
struct SleepStepper: View {
    let title: String
    @Binding var hours: Double?

    var body: some View {
        Stepper {
            LabeledContent(title, value: hours.map { Format.hours($0 * 3600) } ?? "Not set")
        } onIncrement: {
            hours = min(24, (hours ?? 5.5) + 0.5)
        } onDecrement: {
            hours = max(0, (hours ?? 6.5) - 0.5)
        }
    }
}

/// Pain from 0 (none) to 10 (worst), or not set.
struct PainPicker: View {
    @Binding var level: Int?

    var body: some View {
        Picker("Pain", selection: $level) {
            Text("Not set").tag(Int?.none)
            ForEach(0...10, id: \.self) { value in
                Text(Self.title(value)).tag(Int?.some(value))
            }
        }
    }

    static func title(_ value: Int) -> String {
        switch value {
        case 0: return "0 · None"
        case 10: return "10 · Worst"
        default: return "\(value)"
        }
    }
}

/// Bleeding after the birth, or not set. Heavy bleeding shows a gentle warning with its source.
struct BleedingPicker: View {
    @Binding var bleeding: Bleeding?

    var body: some View {
        Picker("Bleeding", selection: $bleeding) {
            Text("Not set").tag(Bleeding?.none)
            ForEach(Bleeding.allCases) { option in
                Text(option.shortTitle).tag(Bleeding?.some(option))
            }
        }
    }
}

/// Shown under the bleeding picker when "Heavy" is chosen.
struct HeavyBleedingNote: View {
    var body: some View {
        NoticeLabel("If you gave birth, heavy bleeding is one of the CDC's urgent warning signs. If you're worried, call your doctor or midwife now, or your local emergency number.")
    }
}

/// One care entry in a list: what it was, the details, and when.
struct CareEntryRow: View {
    @ObservedObject var entry: CareEntry
    var showsDate = true

    var body: some View {
        // Deleted entries can redraw once more before the list drops them.
        if entry.isDeleted || entry.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: entry.mood?.emoji ?? entry.kind.emoji, tint: Palette.momCare)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(entry.title)
                        .font(.body.weight(.medium))
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.subheadline.monospacedDigit())
                    if showsDate {
                        Text(entry.date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, Spacing.xxs)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }
}

/// The promise at the top of every Parent care screen.
struct MomPrivacyNote: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Only you can see this. It isn't shared with your partner.")
                    .font(.subheadline.weight(.semibold))
                Text("It stays on this iPhone, or in your own iCloud if sync is on, and is never part of the baby's log, exports or reports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.fill")
                .foregroundStyle(Palette.momCare)
        }
        .accessibilityElement(children: .combine)
    }
}
