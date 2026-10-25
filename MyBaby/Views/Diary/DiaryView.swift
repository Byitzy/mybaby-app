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
            case .entries: return "Diary"
            case .summaries: return "Summaries"
            case .letters: return "Letters"
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
private struct DiaryEntriesList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var baby: Baby
    let write: (DiaryEditorTarget) -> Void

    @FetchRequest private var entries: FetchedResults<DiaryEntry>
    @State private var search = ""
    @State private var filter: DiaryKind?
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: DiaryEntry?

    init(baby: Baby, write: @escaping (DiaryEditorTarget) -> Void) {
        self.baby = baby
        self.write = write
        _entries = FetchRequest(fetchRequest: baby.entries(DiaryEntry.fetchAll()))
    }

    private struct EntryGroup: Identifiable {
        let id: String
        let title: String
        var entries: [DiaryEntry]
    }

    var body: some View {
        List {
            if !canEditLog {
                Section { ViewOnlyBanner(message: "You can read the diary, but only the parents can write in it.") }
            }

            if entries.isEmpty {
                EmptyStateView(
                    "Nothing written yet",
                    systemImage: "book.closed",
                    message: "Write down the little things: what made you smile, something new \(baby.subjectPronoun) learned, a first, or a letter for \(baby.objectPronoun) to read one day.",
                    actionTitle: "Write the first entry",
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

                let groups = self.groups
                if groups.isEmpty {
                    EmptyStateView(
                        "No entries found",
                        systemImage: "magnifyingglass",
                        message: search.isEmpty ? "No entries of this kind yet." : "Nothing in the diary matches \"\(search)\"."
                    )
                    .listRowBackground(Color.clear)
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
            }
        }
        .searchable(text: $search, prompt: "Search the diary")
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", spokenTitle: "All entries", isSelected: filter == nil) { filter = nil }
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

    /// The entries that match the filter and the search. A sealed letter is only found by its
    /// envelope and who wrote it, so searching never gives its words away.
    private var matching: [DiaryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
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
                return ("before-birth", "Before \(baby.displayName) was born")
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
        let example = "\"\(baby.displayName) is 3 months today. Write something \(baby.sex == nil ? "\(baby.displayName) will" : "\(baby.subjectPronoun)'ll") love to read one day?\""
        var text = "A gentle note at 10 AM each time \(baby.displayName) turns another month old: \(example) Only on this iPhone."
        if baby.birthDate == nil {
            text += " Add \(baby.possessivePronoun) birthday in the profile first."
        }
        return text
    }
}
