import SwiftUI

// One place for the app's spacing, corner radii, colors and shared pieces, so screens built at
// different times look like one app. The look is plain iOS: grouped lists, soft category tints,
// emoji badges and the rose accent color (AccentColor in the asset catalog).
//
// Activity colors stay on `ActivityKind.color`; everything else that has a color of its own
// (milestones, the milk stash, Parent care, growth, vaccines, appointments, night shifts) takes it
// from `Palette`.

/// Spacing in points: 4, 8, 12, 16, 24.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Corner radii. Chips and toasts are capsules.
enum Radius {
    /// Cards: Reports, Patterns, Visit summary.
    static let card: CGFloat = 16
    /// Stat tiles and the "time since" cards.
    static let tile: CGFloat = 14
    /// The quick log buttons.
    static let button: CGFloat = 18
    /// Choices drawn as small cards, like the mood faces.
    static let choice: CGFloat = 12
    /// The breastfeeding timer's big side buttons.
    static let largeButton: CGFloat = 22
    /// Small badges, like an appointment's date.
    static let badge: CGFloat = 10
    /// Photo thumbnails.
    static let photo: CGFloat = 8
}

/// Named colors for everything that isn't an `ActivityKind`.
///
/// Tints go on backgrounds and icons. Text stays `.primary` or `.secondary`, because light tints
/// like mint, yellow or teal are hard to read as text, and the words always say what the color
/// means too.
enum Palette {
    // Surfaces
    static let screenBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let chipBackground = Color(.tertiarySystemFill)

    // Things in the app
    static let baby = Color.pink
    static let appointment = Color.accentColor
    static let vaccineGiven = Color.green
    static let vaccineDue = Color.orange
    static let growth = Color.teal
    static let weight = Color.pink
    static let length = Color.teal
    static let milestone = Color.yellow
    /// The diary and its letters for later: a warm coral, like a paper journal's cover.
    static let diary = Color(red: 0.93, green: 0.49, blue: 0.38)
    /// Allergies and reactions: a warm amber, apart from medicine's orange. Severe ones also say so in words.
    static let allergy = Color(red: 0.86, green: 0.55, blue: 0.15)
    static let milkStash = ActivityKind.pumping.color
    static let frozenMilk = Color.blue
    static let momCare = Color.pink
    static let nightShift = Color.indigo
    static let cryAlerts = Color.orange
    static let patterns = Color.indigo
    static let settings = Color.gray

    // Chart series
    static let bottle = Color.pink
    static let breastfeeding = Color.purple
    static let wetDiaper = Color.teal
    static let dirtyDiaper = Color.brown

    // Night shifts: parent 1 and parent 2, always shown with their names.
    static let parent1 = Color.pink
    static let parent2 = Color.blue

    // Status, always with words or an icon
    static let ok = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    /// Cry alerts are listening; also the border around the app while the microphone is on.
    static let listening = Color.green
    static let inactive = Color.gray
}

// MARK: - Cards

/// The look of a card: padded, on the grouped card background, with rounded corners and an
/// optional soft wash of a category's tint.
struct CardStyle: ViewModifier {
    var padding: CGFloat = Spacing.l
    var cornerRadius: CGFloat = Radius.card
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Palette.cardBackground)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(tint.opacity(0.1))
                        }
                    }
            }
    }
}

extension View {
    /// A card: 16 pt padding and corners, on the card background.
    func cardStyle(tint: Color? = nil) -> some View {
        modifier(CardStyle(padding: Spacing.l, cornerRadius: Radius.card, tint: tint))
    }

    /// A tile: 12 pt padding, 14 pt corners, for stat tiles and the "time since" cards.
    func tileStyle(tint: Color? = nil) -> some View {
        modifier(CardStyle(padding: Spacing.m, cornerRadius: Radius.tile, tint: tint))
    }
}

// MARK: - Layout

/// Side by side, or one above the other at the largest (accessibility) text sizes, so tiles
/// and cards in a row don't squeeze their text.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let horizontalAlignment: HorizontalAlignment
    let verticalAlignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content

    init(
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

extension DynamicTypeSize {
    /// Grid columns for tiles and buttons: `regular` normally, two at accessibility text sizes.
    func gridColumns(_ regular: Int = 3) -> Int {
        isAccessibilitySize ? min(regular, 2) : regular
    }
}

// MARK: - Headers

/// A list section header with a short summary on the right, like "Today's log   6 🍼 · 4 🧷".
/// VoiceOver reads `spokenSummary` instead of the emoji.
struct SummaryHeader: View {
    let title: String
    let summary: String
    let spokenSummary: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title)
                Spacer()
                summaryText
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                summaryText
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var summaryText: some View {
        Text(summary)
            .textCase(nil)
            .accessibilityLabel(spokenSummary)
    }
}

/// "🍼 Feeding" where VoiceOver should only read "Feeding".
struct EmojiTitle: View {
    let emoji: String
    let title: String

    init(_ emoji: String, _ title: String) {
        self.emoji = emoji
        self.title = title
    }

    var body: some View {
        Text("\(emoji) \(title)")
            .accessibilityLabel(title)
    }
}

// MARK: - Empty states

/// What a list shows before anything is in it: an icon, a title, a sentence, and one clear action.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String
    let actions: Actions

    init(_ title: String, systemImage: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyStateButton {
    /// With one prominent button, turned off with `isDisabled` (e.g. for view-only family).
    init(
        _ title: String,
        systemImage: String,
        message: String,
        actionTitle: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(title, systemImage: systemImage, message: message) {
            EmptyStateButton(title: actionTitle, isDisabled: isDisabled, action: action)
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    /// With nothing to do.
    init(_ title: String, systemImage: String, message: String) {
        self.init(title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// The one action of an empty state.
struct EmptyStateButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
    }
}

// MARK: - Notices

/// A short message with a tinted icon, like a warning or an "OK to give now". The text stays
/// readable (`.primary`); the icon and the words carry the meaning, so color is never the only signal.
struct NoticeLabel: View {
    let text: String
    let systemImage: String
    let tint: Color

    init(_ text: String, systemImage: String = "exclamationmark.triangle.fill", tint: Color = Palette.warning) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

/// A small colored dot and a parent's name, e.g. who handled a feed. The name says who it is;
/// the dot only matches the color used for them elsewhere.
struct ParentTag: View {
    let name: String
    let color: Color
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 6

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: dot, height: dot)
                .accessibilityHidden(true)
            Text(name)
        }
    }
}

// MARK: - Confirming deletes

extension View {
    /// Asks before deleting `item`, while it's set. Swipe buttons that use this shouldn't have
    /// the `.destructive` role (it removes the row before the answer); tint them red instead.
    func confirmDelete<Item>(
        _ title: String,
        item: Binding<Item?>,
        message: String? = nil,
        buttonTitle: String = "Delete",
        perform: @escaping (Item) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: item.wrappedValue
        ) { value in
            Button(buttonTitle, role: .destructive) { perform(value) }
        } message: { _ in
            if let message {
                Text(message)
            }
        }
    }
}
