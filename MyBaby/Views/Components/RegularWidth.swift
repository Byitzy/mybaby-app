import SwiftUI

// The pieces that make MyBaby fit an iPad: a readable width for lists, cards in two columns, form-sized
// sheets and keyboard shortcuts. Everything here checks the horizontal size class (or only does
// something with a hardware keyboard), so the iPhone looks and works exactly as before. In Split View
// and Slide Over the size class turns compact and the iPhone layout comes back by itself.

// MARK: - Readable width

/// Keeps a list or a scroll view's content to a comfortable reading width in the middle of a wide
/// window, while the list itself, its background and its scrolling still fill the window.
///
/// It adds side room to the safe area rather than framing the view, so a swipe anywhere still
/// scrolls and grouped list sections keep their usual inset inside the narrower column. Nothing
/// changes in a compact width, or when the window isn't wider than `maxWidth`.
private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Measured outside the padding, so the padding can't feed back into it.
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.horizontal, sideRoom)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }

    private var sideRoom: CGFloat {
        guard horizontalSizeClass == .regular, width > maxWidth else { return 0 }
        return ((width - maxWidth) / 2).rounded(.down)
    }
}

enum ReadableWidth {
    /// Lists and forms: about the width of a printed page.
    static let standard: CGFloat = 700
    /// Screens laid out in two columns on iPad (Today, Reports).
    static let twoColumns: CGFloat = 1000
}

extension View {
    /// Centers the content at `maxWidth` in a regular-width window (see `ReadableContentWidth`).
    func readableContentWidth(_ maxWidth: CGFloat = ReadableWidth.standard) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}

// MARK: - Cards in columns

/// Cards in rows of `columns`, each card in a row as tall as the tallest one, so the rows line up.
/// A view marked `spansCardColumns()` (a picker, a grid of tiles) takes a row to itself, full width
/// and centered. Used for Reports on iPad; on iPhone Reports keeps its plain stack.
struct CardColumns: Layout {
    var columns = 2
    var spacing: CGFloat = Spacing.l

    /// One row: the subviews in it, or a single full-width one.
    private struct Row {
        var indices: [Int]
        var spans: Bool
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = rows(subviews).map { rowHeight(of: $0, width: width, subviews: subviews) }
        let height = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews) {
            let height = rowHeight(of: row, width: bounds.width, subviews: subviews)
            if row.spans, let index = row.indices.first {
                let proposal = ProposedViewSize(width: bounds.width, height: nil)
                let size = subviews[index].sizeThatFits(proposal)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + max(0, (bounds.width - size.width) / 2), y: y),
                    anchor: .topLeading,
                    proposal: proposal
                )
            } else {
                let itemWidth = columnWidth(bounds.width)
                for (column, index) in row.indices.enumerated() {
                    subviews[index].place(
                        at: CGPoint(x: bounds.minX + CGFloat(column) * (itemWidth + spacing), y: y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(width: itemWidth, height: height)
                    )
                }
            }
            y += height + spacing
        }
    }

    private var columnCount: Int { max(columns, 1) }

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
    }

    /// Cards fill the columns in order; a full-width view ends the row before it.
    private func rows(_ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current: [Int] = []
        for index in subviews.indices {
            if subviews[index][SpansCardColumns.self] {
                if !current.isEmpty {
                    rows.append(Row(indices: current, spans: false))
                    current = []
                }
                rows.append(Row(indices: [index], spans: true))
            } else {
                current.append(index)
                if current.count == columnCount {
                    rows.append(Row(indices: current, spans: false))
                    current = []
                }
            }
        }
        if !current.isEmpty {
            rows.append(Row(indices: current, spans: false))
        }
        return rows
    }

    /// A row's height: its tallest card at the column's width.
    private func rowHeight(of row: Row, width: CGFloat, subviews: Subviews) -> CGFloat {
        let itemWidth = row.spans ? width : columnWidth(width)
        return row.indices
            .map { subviews[$0].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }
            .max() ?? 0
    }
}

private struct SpansCardColumns: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// In `CardColumns`, a full-width row of its own rather than one of the columns. Nothing
    /// changes in any other layout.
    func spansCardColumns() -> some View {
        layoutValue(key: SpansCardColumns.self, value: true)
    }
}

private struct CardFillsRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set where cards sit side by side (`CardColumns`), so a `Card` grows to its row's height and
    /// the backgrounds line up. Off everywhere else, so a card is as tall as its content.
    var cardFillsRow: Bool {
        get { self[CardFillsRowKey.self] }
        set { self[CardFillsRowKey.self] = newValue }
    }
}

// MARK: - Sheets

extension View {
    /// On iPad (iOS 18), a sheet opens as a form-sized card in the middle of the screen, like a
    /// settings sheet, rather than a page that nearly fills it. iPhone sheets are the same either way.
    @ViewBuilder
    func formSheetSizing() -> some View {
        if #available(iOS 18, *) {
            presentationSizing(.form)
        } else {
            self
        }
    }
}

// MARK: - Keyboard shortcuts

/// A keyboard shortcut with no button on screen, for an iPad (or iPhone) with a hardware keyboard.
/// Holding ⌘ lists it under `title`. Invisible and hidden from VoiceOver, which has the real buttons.
/// A literal title is looked up in the String Catalog, like `Text("…")`.
struct KeyboardShortcutButton: View {
    private let title: Text
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    let action: () -> Void

    init(title: LocalizedStringKey, key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) {
        self.title = Text(title)
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) {
        self.title = Text(title)
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
        }
        .keyboardShortcut(key, modifiers: modifiers)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// ⌘1 to ⌘5 open the five tabs, in the order the tab bar and the sidebar show them.
private struct TabKeyboardShortcuts: ViewModifier {
    @Binding var selection: AppTab

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                shortcut("Today", key: "1", tab: .today)
                shortcut("History", key: "2", tab: .history)
                shortcut("Reports", key: "3", tab: .reports)
                shortcut("Health", key: "4", tab: .health)
                shortcut("More", key: "5", tab: .more)
            }
        }
    }

    private func shortcut(_ title: LocalizedStringKey, key: KeyEquivalent, tab: AppTab) -> some View {
        KeyboardShortcutButton(title: title, key: key) { selection = tab }
    }
}

/// ⌘N asks what to log, then opens that kind's editor. Turned off with `isEnabled` (view-only family).
private struct NewEntryKeyboardShortcut: ViewModifier {
    let isEnabled: Bool
    let onPick: (ActivityKind) -> Void
    @State private var choosing = false

    func body(content: Content) -> some View {
        content
            .background {
                KeyboardShortcutButton(title: "New entry", key: "n") { choosing = true }
                    .disabled(!isEnabled)
            }
            .confirmationDialog("New entry", isPresented: $choosing, titleVisibility: .visible) {
                ForEach(ActivityKind.allCases) { kind in
                    Button {
                        onPick(kind)
                    } label: {
                        Text(verbatim: "\(kind.emoji) \(kind.title)")
                    }
                }
            }
    }
}

extension View {
    /// ⌘1 to ⌘5 switch tabs (see `TabKeyboardShortcuts`).
    func tabKeyboardShortcuts(_ selection: Binding<AppTab>) -> some View {
        modifier(TabKeyboardShortcuts(selection: selection))
    }

    /// ⌘N starts a new entry (see `NewEntryKeyboardShortcut`).
    func newEntryKeyboardShortcut(isEnabled: Bool, onPick: @escaping (ActivityKind) -> Void) -> some View {
        modifier(NewEntryKeyboardShortcut(isEnabled: isEnabled, onPick: onPick))
    }
}
