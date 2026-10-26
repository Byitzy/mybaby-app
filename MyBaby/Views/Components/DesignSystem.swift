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
    static let headCircumference = Color.indigo
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
///
/// A literal title is looked up in the String Catalog, like `Text("…")`; a `String` is shown as it is.
struct SummaryHeader: View {
    private let title: Text
    let summary: String
    let spokenSummary: String

    init(title: LocalizedStringKey, summary: String, spokenSummary: String) {
        self.title = Text(title)
        self.summary = summary
        self.spokenSummary = spokenSummary
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, summary: String, spokenSummary: String) {
        self.title = Text(title)
        self.summary = summary
        self.spokenSummary = spokenSummary
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                title
                Spacer()
                summaryText
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                title
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

/// "🍼 Feeding" where VoiceOver should only read "Feeding". A literal title is looked up in the
/// String Catalog, like `Text("…")`; a `String` is shown as it is.
struct EmojiTitle: View {
    let emoji: String
    private let title: Text

    init(_ emoji: String, _ title: LocalizedStringKey) {
        self.emoji = emoji
        self.title = Text(title)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ emoji: String, _ title: S) {
        self.emoji = emoji
        self.title = Text(title)
    }

    var body: some View {
        Text(joining: [Text(verbatim: emoji), title], separator: " ")
            .accessibilityLabel(title)
    }
}

extension Text {
    /// Pieces of text in one `Text`, so they wrap as one line of words: "🍼 Feeding", or "Birthday,
    /// Monday, March 3, 2025" for VoiceOver.
    ///
    /// Built piece by piece rather than from a `"\(a) \(b)"` literal, which would add a "%@ %@" key to
    /// the String Catalog for translators. With no such key, the pieces are shown as they are.
    init(joining parts: [Text], separator: String) {
        var line = LocalizedStringKey.StringInterpolation(literalCapacity: separator.count, interpolationCount: parts.count)
        for (index, part) in parts.enumerated() {
            if index > 0 { line.appendLiteral(separator) }
            line.appendInterpolation(part)
        }
        self.init(LocalizedStringKey(stringInterpolation: line))
    }
}

// MARK: - Empty states

/// What a list shows before anything is in it: an icon, a title, a sentence, and one clear action.
///
/// Literal texts are looked up in the String Catalog, like `Text("…")`. When any of them is a `String`,
/// the `String` versions are used and every text is shown as it is, so the literals in that call need
/// `String(localized:)`.
struct EmptyStateView<Actions: View>: View {
    private let title: Text
    let systemImage: String
    private let message: Text
    let actions: Actions

    init(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey, @ViewBuilder actions: () -> Actions) {
        self.init(title: Text(title), systemImage: systemImage, message: Text(message), actions: actions())
    }

    @_disfavoredOverload
    init<T: StringProtocol, M: StringProtocol>(_ title: T, systemImage: String, message: M, @ViewBuilder actions: () -> Actions) {
        self.init(title: Text(title), systemImage: systemImage, message: Text(message), actions: actions())
    }

    fileprivate init(title: Text, systemImage: String, message: Text, actions: Actions) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            message
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyStateButton {
    /// With one prominent button, turned off with `isDisabled` (e.g. for view-only family).
    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        actionTitle: LocalizedStringKey,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: Text(title),
            systemImage: systemImage,
            message: Text(message),
            actions: EmptyStateButton(label: Text(actionTitle), isDisabled: isDisabled, action: action)
        )
    }

    @_disfavoredOverload
    init<T: StringProtocol, M: StringProtocol, A: StringProtocol>(
        _ title: T,
        systemImage: String,
        message: M,
        actionTitle: A,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: Text(title),
            systemImage: systemImage,
            message: Text(message),
            actions: EmptyStateButton(label: Text(actionTitle), isDisabled: isDisabled, action: action)
        )
    }
}

extension EmptyStateView where Actions == EmptyView {
    /// With nothing to do.
    init(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) {
        self.init(title: Text(title), systemImage: systemImage, message: Text(message), actions: EmptyView())
    }

    @_disfavoredOverload
    init<T: StringProtocol, M: StringProtocol>(_ title: T, systemImage: String, message: M) {
        self.init(title: Text(title), systemImage: systemImage, message: Text(message), actions: EmptyView())
    }
}

/// The one action of an empty state. A literal title is looked up in the String Catalog.
struct EmptyStateButton: View {
    private let label: Text
    var isDisabled = false
    let action: () -> Void

    init(title: LocalizedStringKey, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.init(label: Text(title), isDisabled: isDisabled, action: action)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.init(label: Text(title), isDisabled: isDisabled, action: action)
    }

    fileprivate init(label: Text, isDisabled: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled)
    }
}

// MARK: - Notices

/// A short message with a tinted icon, like a warning or an "OK to give now". The text stays
/// readable (`.primary`); the icon and the words carry the meaning, so color is never the only signal.
///
/// A literal is looked up in the String Catalog, like `Text("…")`; a `String` is shown as it is.
struct NoticeLabel: View {
    private let text: Text
    let systemImage: String
    let tint: Color

    init(_ key: LocalizedStringKey, systemImage: String = "exclamationmark.triangle.fill", tint: Color = Palette.warning) {
        self.init(text: Text(key), systemImage: systemImage, tint: tint)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ text: S, systemImage: String = "exclamationmark.triangle.fill", tint: Color = Palette.warning) {
        self.init(text: Text(text), systemImage: systemImage, tint: tint)
    }

    private init(text: Text, systemImage: String, tint: Color) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            text
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
    ///
    /// Literal texts are looked up in the String Catalog, like `Text("…")`. With a `String` title,
    /// the texts are shown as they are.
    func confirmDelete<Item>(
        _ title: LocalizedStringKey,
        item: Binding<Item?>,
        message: LocalizedStringKey? = nil,
        buttonTitle: LocalizedStringKey = "Delete",
        perform: @escaping (Item) -> Void
    ) -> some View {
        confirmDeleteDialog(Text(title), item: item, message: message.map { Text($0) }, buttonTitle: Text(buttonTitle), perform: perform)
    }

    @_disfavoredOverload
    func confirmDelete<Item, S: StringProtocol>(
        _ title: S,
        item: Binding<Item?>,
        message: String? = nil,
        buttonTitle: String = String(localized: "Delete"),
        perform: @escaping (Item) -> Void
    ) -> some View {
        confirmDeleteDialog(Text(title), item: item, message: message.map { Text($0) }, buttonTitle: Text(buttonTitle), perform: perform)
    }

    fileprivate func confirmDeleteDialog<Item>(
        _ title: Text,
        item: Binding<Item?>,
        message: Text?,
        buttonTitle: Text,
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
            Button(role: .destructive) {
                perform(value)
            } label: {
                buttonTitle
            }
        } message: { _ in
            if let message {
                message
            }
        }
    }
}
