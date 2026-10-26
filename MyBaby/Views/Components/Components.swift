import SwiftUI
import UIKit

/// Which activity editor sheet to show: a new entry of `kind`, or an existing `activity`.
struct EditorTarget: Identifiable {
    let id = UUID()
    let kind: ActivityKind
    var activity: Activity?

    static func new(_ kind: ActivityKind) -> EditorTarget {
        EditorTarget(kind: kind, activity: nil)
    }

    static func edit(_ activity: Activity) -> EditorTarget {
        EditorTarget(kind: activity.kind, activity: activity)
    }
}

/// An emoji in a tinted circle. VoiceOver reads `label` instead of the emoji's name, and skips
/// the badge when there's no label because the text next to it already says what it is.
/// It grows with the text size, up to a point, so rows stay balanced.
struct EmojiBadge: View {
    let emoji: String
    let tint: Color
    var size: CGFloat = 40
    var label: String?

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var side: CGFloat { size * min(scale, 1.6) }

    var body: some View {
        Text(emoji)
            .font(.system(size: side * 0.5))
            .frame(width: side, height: side)
            .background(tint.opacity(0.18), in: Circle())
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }
}

struct ActivityRow: View {
    @ObservedObject var activity: Activity
    let unit: VolumeUnit
    var showsDate = false

    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()

    var body: some View {
        // A deleted entry (here, or by the partner through iCloud) can redraw once more before the
        // list drops it, and its dates can't be read any more.
        if activity.isDeleted || activity.managedObjectContext == nil {
            EmptyView()
        } else {
            row
        }
    }

    private var row: some View {
        TimelineView(.everyMinute) { context in
            let detail = activity.detail(unit: unit, now: context.date)
            let caregiverName = activity.caregiver.map { NightPlan(data: nightPlanData).name(of: $0) }
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: activity.emoji, tint: activity.kind.color)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(activity.title)
                        .font(.body.weight(.medium))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !activity.notes.isEmpty {
                        Text(activity.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Spacing.s)

                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    // "≈ 2:10 PM" for an approximate entry added with Catch up.
                    Text(verbatim: "\(activity.isApproximate ? "≈ " : "")\(activity.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.monospacedDigit())
                    if showsDate {
                        Text(activity.startDate, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let caregiver = activity.caregiver, let caregiverName {
                        ParentTag(name: caregiverName, color: caregiver.color)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, Spacing.xxs)
            // One stop for VoiceOver: "Bottle (formula), 120 ml, 2:10 AM, handled by Maya".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel(detail: detail, caregiverName: caregiverName))
        }
        .contentShape(Rectangle())
    }

    private func spokenLabel(detail: String, caregiverName: String?) -> String {
        var parts = [activity.title]
        if !detail.isEmpty { parts.append(Format.spoken(detail)) }
        let time = showsDate
            ? activity.startDate.formatted(.dateTime.month(.wide).day().hour().minute())
            : activity.startDate.formatted(date: .omitted, time: .shortened)
        parts.append(activity.isApproximate
            ? String(localized: "approx. \(time)", comment: "VoiceOver: the time of an approximate entry added with Catch up")
            : time)
        if let caregiverName {
            parts.append(String(localized: "handled by \(caregiverName)", comment: "VoiceOver: which parent handled an entry"))
        }
        if !activity.notes.isEmpty { parts.append(activity.notes) }
        return parts.joined(separator: ", ")
    }
}

/// A short confirmation that slides up from the bottom, with an optional Undo.
struct Toast: Equatable {
    let id = UUID()
    let message: String
    var undo: (() -> Void)?

    /// A literal message is looked up in the String Catalog, like `String(localized:)`.
    init(message: String.LocalizationValue, undo: (() -> Void)? = nil) {
        self.message = String(localized: message)
        self.undo = undo
    }

    /// A message that's already localized is shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(message: S, undo: (() -> Void)? = nil) {
        self.message = String(message)
        self.undo = undo
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    HStack(spacing: Spacing.m) {
                        Text(toast.message)
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel(Format.withoutLeadingEmoji(toast.message))
                        if let undo = toast.undo {
                            Button("Undo") {
                                undo()
                                self.toast = nil
                            }
                            .font(.subheadline.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, Spacing.m)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.l)
                    // Slides up, or only fades in with Reduce Motion on.
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.spring(duration: 0.3), value: toast)
            .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
            .task(id: toast?.id) {
                guard let shown = toast else { return }
                // VoiceOver says it out loud, and gets longer to reach Undo.
                UIAccessibility.post(notification: .announcement, argument: Format.withoutLeadingEmoji(shown.message))
                try? await Task.sleep(for: .seconds(voiceOverEnabled ? 8 : 3))
                if !Task.isCancelled { toast = nil }
            }
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

/// A number with a small title, like "Feeds/day 8.2". The value is `.primary` for contrast; the
/// category's tint is a soft wash behind it.
///
/// A literal title is looked up in the String Catalog, like `Text("…")`; a `String` is shown as it is.
struct StatTile: View {
    private let title: Text
    let value: String
    var emoji: String = ""
    var tint: Color = .accentColor
    /// What VoiceOver reads instead of `title`, e.g. "Feeds per day" for "Feeds/day".
    private var spokenTitle: Text?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: LocalizedStringKey,
        value: String,
        emoji: String = "",
        tint: Color = .accentColor,
        spokenTitle: LocalizedStringKey? = nil
    ) {
        self.title = Text(title)
        self.value = value
        self.emoji = emoji
        self.tint = tint
        self.spokenTitle = spokenTitle.map { Text($0) }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(
        title: S,
        value: String,
        emoji: String = "",
        tint: Color = .accentColor,
        spokenTitle: String? = nil
    ) {
        self.title = Text(title)
        self.value = value
        self.emoji = emoji
        self.tint = tint
        self.spokenTitle = spokenTitle.map { Text($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                if !emoji.isEmpty {
                    Text(emoji)
                        .accessibilityHidden(true)
                }
                title
                    .lineLimit(2)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle(tint: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTitle ?? title)
        .accessibilityValue(Format.spoken(value))
    }
}

/// A titled card. Literal texts are looked up in the String Catalog, like `Text("…")`. When the title
/// or the subtitle is a `String`, both are shown as they are, so a literal next to it needs
/// `String(localized:)`.
struct Card<Content: View>: View {
    private let title: Text
    /// Nil for none.
    private let subtitle: Text?
    let content: Content
    /// Side by side on iPad, as tall as the other cards in its row (see `CardColumns`).
    @Environment(\.cardFillsRow) private var fillsRow

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.content = content()
    }

    /// An empty subtitle shows none.
    @_disfavoredOverload
    init<T: StringProtocol, S: StringProtocol>(_ title: T, subtitle: S, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.subtitle = subtitle.isEmpty ? nil : Text(subtitle)
        self.content = content()
    }

    @_disfavoredOverload
    init<T: StringProtocol>(_ title: T, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.subtitle = nil
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                title
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: fillsRow ? CGFloat.infinity : nil, alignment: .topLeading)
        .cardStyle()
    }
}
