import CoreData
import SwiftUI
import UIKit

/// The diary, pushed from More: what parents write down for the baby (moments, things learned, firsts,
/// funny things and letters for later), the week and month summaries, and the letters on their own.
///
/// Everything here belongs to the baby, so it syncs and is shared with the partner like the rest of
/// the log, and family invited as view only can read it but not write. It's one view on purpose, so it
/// can be wrapped as a whole (for example in a lock) without touching what's inside.
struct DiaryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var baby: Baby

    @State private var tab: DiaryTab
    @State private var editorTarget: DiaryEditorTarget?
    @State private var showingKeepsake = false
    @State private var showingSettings = false
    /// The summary to open right away, when the diary is opened from Today's card.
    @State private var openedPeriod: DiaryPeriod?
    private let opening: DiaryPeriod?
    @State private var didOpen = false

    enum DiaryTab: String, CaseIterable, Identifiable {
        case entries, summaries, letters

        var id: String { rawValue }

        var title: String {
            switch self {
            case .entries: return String(localized: "Diary")
            case .summaries: return String(localized: "Summaries", comment: "Diary tab: the week and month summaries")
            case .letters: return String(localized: "Letters", comment: "Diary tab: the letters for later")
            }
        }
    }

    /// `opening` is a week or month whose summary is shown straight away, e.g. from Today.
    init(baby: Baby, opening: DiaryPeriod? = nil) {
        self.baby = baby
        self.opening = opening
        _tab = State(initialValue: opening == nil ? .entries : .summaries)
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $tab) {
                    ForEach(DiaryTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .background(Palette.screenBackground)
            }
            .navigationTitle(DiaryText.title(for: baby))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .new(tab == .letters ? .letter : .moment)
                    } label: {
                        Label(tab == .letters ? "Write a letter" : "Write in the diary", systemImage: "square.and.pencil")
                    }
                    .disabled(!canEditLog)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingKeepsake = true
                    } label: {
                        Label("Make a keepsake PDF", systemImage: "doc.richtext")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Diary settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                DiaryEntryEditor(target: target, baby: baby)
            }
            .sheet(isPresented: $showingKeepsake) {
                KeepsakeView(baby: baby)
            }
            .sheet(isPresented: $showingSettings) {
                DiarySettingsView(baby: baby)
            }
            .navigationDestination(item: $openedPeriod) { period in
                PeriodSummaryView(baby: baby, period: period)
            }
            .onAppear {
                if let opening, !didOpen {
                    didOpen = true
                    openedPeriod = opening
                }
                DiaryReminder.refresh(context: context)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .entries:
            DiaryEntriesList(baby: baby) { editorTarget = $0 }
        case .summaries:
            DiarySummariesList(baby: baby)
        case .letters:
            LettersList(baby: baby) { editorTarget = $0 }
        }
    }
}

// MARK: - Entries

/// Every entry, grouped by the baby's months ("Month 3 · 12 Jan – 11 Feb"), newest first, with search
/// and a filter by kind. Before a birthday is set, they're grouped by calendar month.
///
/// It reads the last 3 months to start with, and Show earlier reaches back 3 more, so a diary kept for
/// years isn't read and grouped in full each time it changes. A filter reads only that kind, and reaches
/// back by itself when the months shown have none. A search looks through the whole diary.
private struct DiaryEntriesList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var baby: Baby
    let write: (DiaryEditorTarget) -> Void

    /// Whether there's anything in the diary at all, for the first empty state.
    @FetchRequest private var anyEntries: FetchedResults<DiaryEntry>
    @State private var search = ""
    @State private var filter: DiaryKind?
    /// How far back the list reads: from the start of the month this day is in.
    @State private var reach = DiaryWindow.initialReach()
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: DiaryEntry?

    init(baby: Baby, write: @escaping (DiaryEditorTarget) -> Void) {
        self.baby = baby
        self.write = write
        let everything = baby.entries(DiaryEntry.fetchAll())
        // Only the first is ever read. Not a fetch limit: the list wouldn't refill when that one is deleted.
        everything.fetchBatchSize = 1
        _anyEntries = FetchRequest(fetchRequest: everything)
    }

    var body: some View {
        List {
            if !canEditLog {
                Section { ViewOnlyBanner(message: "You can read the diary, but only the parents can write in it.") }
            }

            if anyEntries.isEmpty {
                // String(localized:) since the message is a String: the call takes its String version.
                EmptyStateView(
                    String(localized: "Nothing written yet"),
                    systemImage: "book.closed",
                    message: emptyMessage,
                    actionTitle: String(localized: "Write the first entry"),
                    isDisabled: !canEditLog
                ) {
                    write(.new())
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    filterChips
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

                let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                DiaryEntrySections(
                    baby: baby,
                    query: query,
                    filter: filter,
                    // A search looks through everything.
                    since: query.isEmpty ? DiaryWindow.groupStart(containing: reach, birthDate: baby.birthDate) : nil,
                    showEarlier: { reach = $0 },
                    deleting: $deleting
                )
            }
        }
        .searchable(text: $search, prompt: "Search the diary")
        .onChange(of: filter) {
            // Back to the last few months, so going back to All doesn't read every month a filter reached.
            reach = DiaryWindow.initialReach()
        }
        .confirmDelete(
            "Delete this entry?",
            item: $deleting,
            message: PersistenceController.isSyncEnabled ? "It's deleted from iCloud and every phone that shares the log." : "This can't be undone.",
            buttonTitle: "Delete entry and photos"
        ) { entry in
            context.delete(entry)
            context.saveIfChanged()
        }
    }

    /// What the diary says before anything is written. A sentence for each, since the pronouns change
    /// the whole sentence in other languages.
    private var emptyMessage: String {
        let name = baby.displayName
        return DiaryText.bySex(
            baby,
            female: String(localized: "Write down the little things: what made you smile, something new she learned, a first, or a letter for her to read one day."),
            male: String(localized: "Write down the little things: what made you smile, something new he learned, a first, or a letter for him to read one day."),
            unknown: String(localized: "Write down the little things: what made you smile, something new \(name) learned, a first, or a letter for \(name) to read one day.")
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    title: String(localized: "All", comment: "Diary filter: every kind of entry"),
                    spokenTitle: String(localized: "All entries"),
                    isSelected: filter == nil
                ) { filter = nil }
                ForEach(DiaryKind.allCases) { kind in
                    chip(title: "\(kind.emoji) \(kind.shortTitle)", spokenTitle: kind.title, isSelected: filter == kind) {
                        filter = filter == kind ? nil : kind
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, spokenTitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 7)
                .background(isSelected ? Palette.diary : Palette.chipBackground, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// How far back the diary reads: whole months of the baby's life (or calendar months before a
/// birthday is set), 3 at a time, so a month is never cut in half.
private enum DiaryWindow {
    static let months = 3

    /// A day 2 months ago: its month and the 2 after it are shown.
    static func initialReach(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -(months - 1), to: now) ?? now
    }

    /// The first day of the month `date` is in, as the list groups them, or `nil` when it's before the
    /// birth: everything from before is one group, so it's read whole, and so is the rest of the diary.
    static func groupStart(containing date: Date, birthDate: Date?, calendar: Calendar = .current) -> Date? {
        if let birthDate {
            guard date >= calendar.startOfDay(for: birthDate) else { return nil }
            if let month = DiaryPeriod.month(containing: date, birthDate: birthDate, calendar: calendar) {
                return month.start
            }
        }
        return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// 3 months before `start`, or further back to `newestOlder` (the newest entry before `start`) when
    /// nothing was written for longer than that, so each step shows something new.
    static func reach(before start: Date, newestOlder: Date, calendar: Calendar = .current) -> Date {
        let stepped = calendar.date(byAdding: .month, value: -months, to: start) ?? start
        return min(stepped, newestOlder)
    }
}

/// The diary's month sections, read from `since` on (all of it when `nil`). Its fetches are made from
/// the search, the filter and `since`, so changing any of them reads only what's shown.
private struct DiaryEntrySections: View {
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var baby: Baby
    /// Trimmed; empty when not searching.
    let query: String
    let filter: DiaryKind?
    let since: Date?
    let showEarlier: (Date) -> Void
    @Binding var deleting: DiaryEntry?

    @FetchRequest private var entries: FetchedResults<DiaryEntry>
    /// The entries before `since` that match, newest first: whether there's more, and how far back.
    @FetchRequest private var olderEntries: FetchedResults<DiaryEntry>

    private struct EntryGroup: Identifiable {
        let id: String
        let title: String
        var entries: [DiaryEntry]
    }

    init(
        baby: Baby,
        query: String,
        filter: DiaryKind?,
        since: Date?,
        showEarlier: @escaping (Date) -> Void,
        deleting: Binding<DiaryEntry?>
    ) {
        self.baby = baby
        self.query = query
        self.filter = filter
        self.since = since
        self.showEarlier = showEarlier
        _deleting = deleting

        var conditions = [NSPredicate(format: "baby == %@", baby)]
        if let filter { conditions.append(Self.kindPredicate([filter])) }
        if !query.isEmpty { conditions.append(Self.mightMatch(query)) }

        let shown = DiaryEntry.fetchAll()
        if let since {
            shown.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: conditions + [NSPredicate(format: "date >= %@", since as NSDate)])
        } else {
            shown.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: conditions)
        }
        shown.fetchBatchSize = 30
        _entries = FetchRequest(fetchRequest: shown)

        let older = DiaryEntry.fetchAll()
        if let since {
            older.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: conditions + [NSPredicate(format: "date < %@", since as NSDate)])
        } else {
            older.predicate = NSPredicate(value: false)
        }
        // Only the first is read. Not a fetch limit, which wouldn't refill when that one is deleted.
        older.fetchBatchSize = 1
        _olderEntries = FetchRequest(fetchRequest: older)
    }

    /// Entries of these kinds. One whose kind this version doesn't know reads as a moment
    /// (`DiaryEntry.kind`), so it's found with the moments, as it always was.
    private static func kindPredicate(_ kinds: [DiaryKind]) -> NSPredicate {
        var alternatives = [NSPredicate(format: "kindRaw IN %@", kinds.map(\.rawValue))]
        if kinds.contains(.moment) {
            alternatives.append(NSPredicate(format: "NOT (kindRaw IN %@)", DiaryKind.allCases.map(\.rawValue)))
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: alternatives)
    }

    /// Every entry a search might find, so the rest aren't read: the words in the title, the text or
    /// who wrote it, a kind whose name matches, and every letter, since a sealed one is found by its
    /// envelope, which is worked out from the baby's name and birthday. `matching` then checks each one
    /// exactly as before.
    private static func mightMatch(_ query: String) -> NSPredicate {
        var alternatives = ["title", "text", "authorName"].map { NSPredicate(format: "%K CONTAINS[cd] %@", $0, query) }
        alternatives.append(kindPredicate([.letter]))
        let kinds = DiaryKind.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) }
        if !kinds.isEmpty { alternatives.append(kindPredicate(kinds)) }
        return NSCompoundPredicate(orPredicateWithSubpredicates: alternatives)
    }

    var body: some View {
        let groups = self.groups
        let earlier = self.earlierReach

        if groups.isEmpty {
            if let earlier {
                // Nothing in the months shown, but there's more before them: reach back to it.
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Loading earlier entries")
                    .onAppear { showEarlier(earlier) }
            } else {
                EmptyStateView(
                    "No entries found",
                    systemImage: "magnifyingglass",
                    message: query.isEmpty ? "No entries of this kind yet." : "Nothing in the diary matches \"\(query)\"."
                )
                .listRowBackground(Color.clear)
            }
        }
        ForEach(groups) { group in
            Section(group.title) {
                ForEach(group.entries) { entry in
                    NavigationLink {
                        DiaryEntryDetailView(entry: entry, baby: baby)
                    } label: {
                        DiaryEntryRow(entry: entry, baby: baby)
                    }
                    .swipeActions {
                        if canEditLog {
                            // Not `.destructive`, which would remove the row before the answer.
                            Button("Delete", systemImage: "trash") {
                                deleting = entry
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        if !groups.isEmpty, let earlier, let since {
            Section {
                Button {
                    showEarlier(earlier)
                } label: {
                    Label("Show earlier", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityHint("Shows earlier months of the diary")
            } footer: {
                Text("Showing entries from \(since.formatted(.dateTime.day().month(.abbreviated).year())).")
            }
        }
    }

    /// Where Show earlier reaches back to, or `nil` when everything is already shown.
    private var earlierReach: Date? {
        guard let since, let newestOlder = olderEntries.first?.date, newestOlder < since else { return nil }
        return DiaryWindow.reach(before: since, newestOlder: newestOlder)
    }

    /// The entries that match the filter and the search. A sealed letter is only found by its
    /// envelope and who wrote it, so searching never gives its words away.
    private var matching: [DiaryEntry] {
        entries.filter { entry in
            guard !entry.isDeleted, entry.managedObjectContext != nil else { return false }
            if let filter, entry.kind != filter { return false }
            guard !query.isEmpty else { return true }
            var fields = [entry.authorName, entry.kind.title]
            if entry.isSealed(birthDate: baby.birthDate) {
                fields.append(entry.envelopeLine(babyName: baby.displayName))
            } else {
                fields += [entry.title, entry.text]
            }
            return fields.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Newest month first, each with its entries newest first.
    private var groups: [EntryGroup] {
        var result: [EntryGroup] = []
        var positions: [String: Int] = [:]
        for entry in matching {
            let group = groupFor(entry)
            if let position = positions[group.id] {
                result[position].entries.append(entry)
            } else {
                positions[group.id] = result.count
                result.append(EntryGroup(id: group.id, title: group.title, entries: [entry]))
            }
        }
        return result
    }

    private func groupFor(_ entry: DiaryEntry) -> (id: String, title: String) {
        let calendar = Calendar.current
        if let birthDate = baby.birthDate {
            if entry.date < calendar.startOfDay(for: birthDate) {
                return ("before-birth", String(localized: "Before \(baby.displayName) was born"))
            }
            if let month = DiaryPeriod.month(containing: entry.date, birthDate: birthDate, calendar: calendar) {
                return (month.id.key, month.fullTitle(calendar: calendar))
            }
        }
        let parts = calendar.dateComponents([.year, .month], from: entry.date)
        return ("calendar-\(parts.year ?? 0)-\(parts.month ?? 0)", entry.date.formatted(.dateTime.month(.wide).year()))
    }
}

// MARK: - Letters

/// Every letter for later, as sealed envelopes, with who wrote each and when it's meant to be opened.
private struct LettersList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var baby: Baby
    let write: (DiaryEditorTarget) -> Void

    @FetchRequest private var letters: FetchedResults<DiaryEntry>
    @State private var deleting: DiaryEntry?

    init(baby: Baby, write: @escaping (DiaryEditorTarget) -> Void) {
        self.baby = baby
        self.write = write
        _letters = FetchRequest(fetchRequest: baby.entries(DiaryEntry.letters()))
    }

    var body: some View {
        List {
            if !canEditLog {
                Section { ViewOnlyBanner(message: "You can see the letters, but only the parents can write or open them.") }
            }

            if letters.isEmpty {
                EmptyStateView(
                    "No letters yet",
                    systemImage: "envelope",
                    message: "Write a letter for \(baby.displayName) to read one day. It stays sealed until the birthday or the day you choose.",
                    actionTitle: "Write a letter",
                    isDisabled: !canEditLog
                ) {
                    write(.new(.letter))
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(letters) { letter in
                        if !letter.isDeleted, letter.managedObjectContext != nil {
                            NavigationLink {
                                DiaryEntryDetailView(entry: letter, baby: baby)
                            } label: {
                                SealedLetterCard(entry: letter, baby: baby)
                            }
                            .swipeActions {
                                if canEditLog {
                                    Button("Delete", systemImage: "trash") {
                                        deleting = letter
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Letters stay sealed until their day, so their words aren't shown by accident. You can always open one with Read anyway. They're shared with your partner like the rest of the diary.")
                }
            }
        }
        .confirmDelete(
            "Delete this letter?",
            item: $deleting,
            message: PersistenceController.isSyncEnabled ? "It's deleted from iCloud and every phone that shares the log." : "This can't be undone.",
            buttonTitle: "Delete letter"
        ) { letter in
            context.delete(letter)
            context.saveIfChanged()
        }
    }
}

// MARK: - Settings

/// The diary's own settings: the monthly reminder, kept on this iPhone.
struct DiarySettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var baby: Baby
    @AppStorage(SettingsKey.diaryReminderEnabled) private var reminderEnabled = false
    @State private var showingPermissionAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Month birthday reminder", isOn: $reminderEnabled)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Diary settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: reminderEnabled) { _, enabled in
                guard enabled else {
                    DiaryReminder.refresh(context: context)
                    return
                }
                Task {
                    if await NotificationManager.requestAuthorization() {
                        DiaryReminder.refresh(context: context)
                    } else {
                        reminderEnabled = false
                        showingPermissionAlert = true
                    }
                }
            }
            .alert("Notifications are off", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Allow notifications for MyBaby in the Settings app to get the month birthday reminder.")
            }
        }
        .threeAMSheet()
    }

    private var footer: String {
        let name = baby.displayName
        // The reminder's own words (`DiaryReminder`), a sentence for each, since the pronoun changes it.
        let example = DiaryText.bySex(
            baby,
            female: String(localized: "\"\(name) is 3 months today. Write something she'll love to read one day?\""),
            male: String(localized: "\"\(name) is 3 months today. Write something he'll love to read one day?\""),
            unknown: String(localized: "\"\(name) is 3 months today. Write something \(name) will love to read one day?\"")
        )
        var text = String(
            localized: "A gentle note at \(Format.clockHour(10)) each time \(name) turns another month old: \(example) Only on this iPhone.",
            comment: "The third value is the reminder's words, in quotes"
        )
        if baby.birthDate == nil {
            text += " " + DiaryText.bySex(
                baby,
                female: String(localized: "Add her birthday in the profile first."),
                male: String(localized: "Add his birthday in the profile first."),
                unknown: String(localized: "Add \(name)'s birthday in the profile first.")
            )
        }
        return text
    }
}
