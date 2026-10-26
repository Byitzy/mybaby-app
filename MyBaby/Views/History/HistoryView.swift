import CoreData
import SwiftUI

/// Every entry grouped by day, newest first, with the times marked by hand among them.
///
/// It shows the last 30 days to start with, and Show earlier at the bottom reaches back 30 more, so a log
/// years long isn't read and grouped in full each time something changes. Filtering by kind fetches only
/// that kind, so a filter still finds an entry from long ago: when the days shown have none, it reaches
/// back by itself to the newest one.
struct HistoryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    let baby: Baby

    @State private var filter: ActivityKind?
    /// The oldest day shown, at midnight.
    @State private var since = HistoryWindow.initialStart()
    @State private var editorTarget: EditorTarget?
    @State private var coverageTarget: CoverageSheetTarget?
    @State private var deletingPeriod: TrackingPeriod?

    init(baby: Baby) {
        self.baby = baby
    }

    var body: some View {
        NavigationStack {
            HistoryList(
                baby: baby,
                filter: filter,
                since: since,
                selectFilter: { kind in
                    filter = kind
                    // Back to the last 30 days, so going back to All doesn't read every day a filter reached back to.
                    since = HistoryWindow.initialStart()
                },
                showEarlier: { since = $0 },
                editorTarget: $editorTarget,
                coverageTarget: $coverageTarget,
                deletingPeriod: $deletingPeriod
            )
            // A readable column in the middle of a wide iPad window.
            .readableContentWidth()
            // ⌘N with a keyboard: the same choice as the + menu.
            .newEntryKeyboardShortcut(isEnabled: canEditLog) { kind in
                editorTarget = .new(kind)
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    markTimeMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(ActivityKind.allCases) { kind in
                            Button {
                                editorTarget = .new(kind)
                            } label: {
                                Text(verbatim: "\(kind.emoji) \(kind.title)")
                            }
                        }
                    } label: {
                        Label("Add entry", systemImage: "plus")
                    }
                    .disabled(!canEditLog)
                }
            }
            .sheet(item: $editorTarget) { target in
                ActivityEditorView(kind: target.kind, activity: target.activity, baby: baby)
            }
            .sheet(item: $coverageTarget) { target in
                CoverageSheet(target: target)
            }
            .confirmDelete(
                "Delete this marked time?",
                item: $deletingPeriod,
                message: "Entries logged in it stay. Reports go back to working this time out from the log."
            ) { period in
                context.delete(period)
                context.saveIfChanged()
            }
        }
    }

    /// Marking a stretch of time, for the last few hours by default (both ends can be changed).
    private var markTimeMenu: some View {
        Menu {
            Button {
                coverageTarget = .newPeriod(.notTracked, start: Self.defaultMarkStart, end: .now)
            } label: {
                Label("Mark a time as not tracked", systemImage: TrackingPeriodKind.notTracked.systemImage)
            }
            Button {
                coverageTarget = .newPeriod(.nothingHappened, start: Self.defaultMarkStart, end: .now)
            } label: {
                Label("Nothing happened (we were tracking)", systemImage: TrackingPeriodKind.nothingHappened.systemImage)
            }
            Button {
                coverageTarget = .catchUp(start: Self.defaultMarkStart, end: .now)
            } label: {
                Label("Catch up on a time…", systemImage: TrackingPeriodKind.caughtUp.systemImage)
            }
        } label: {
            Label("Mark time", systemImage: "eye.slash")
        }
        .disabled(!canEditLog)
    }

    private static var defaultMarkStart: Date { Date.now.addingTimeInterval(-3 * 3600) }
}

/// How far back History reads: whole days, 30 at a time.
private enum HistoryWindow {
    static let days = 30

    /// Midnight 29 days ago, so today and the 29 days before it are shown.
    static func initialStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }

    /// 30 days before `start`, or further back to the day of `newestOlder` (the newest thing before
    /// `start`) when nothing was logged for longer than that, so each step shows something new.
    static func start(before start: Date, reaching newestOlder: Date, calendar: Calendar = .current) -> Date {
        let stepped = calendar.date(byAdding: .day, value: -days, to: start) ?? start
        return min(stepped, calendar.startOfDay(for: newestOlder))
    }
}

/// History's days: the entries and marked times from `since` on, grouped by day. Its fetches are made
/// from `filter` and `since`, so changing either reads only what's shown.
private struct HistoryList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    let baby: Baby
    let filter: ActivityKind?
    let since: Date
    let selectFilter: (ActivityKind?) -> Void
    let showEarlier: (Date) -> Void
    @Binding var editorTarget: EditorTarget?
    @Binding var coverageTarget: CoverageSheetTarget?
    @Binding var deletingPeriod: TrackingPeriod?

    @FetchRequest private var activities: FetchedResults<Activity>
    /// Times marked as not tracked, nothing happened or caught up, shown as gray rows among the entries.
    @FetchRequest private var periods: FetchedResults<TrackingPeriod>
    /// The newest entry, and marked time, from before `since`: whether there's more, and how far back it is.
    @FetchRequest private var olderActivities: FetchedResults<Activity>
    @FetchRequest private var olderPeriods: FetchedResults<TrackingPeriod>

    init(
        baby: Baby,
        filter: ActivityKind?,
        since: Date,
        selectFilter: @escaping (ActivityKind?) -> Void,
        showEarlier: @escaping (Date) -> Void,
        editorTarget: Binding<EditorTarget?>,
        coverageTarget: Binding<CoverageSheetTarget?>,
        deletingPeriod: Binding<TrackingPeriod?>
    ) {
        self.baby = baby
        self.filter = filter
        self.since = since
        self.selectFilter = selectFilter
        self.showEarlier = showEarlier
        _editorTarget = editorTarget
        _coverageTarget = coverageTarget
        _deletingPeriod = deletingPeriod

        let mine = NSPredicate(format: "baby == %@", baby)
        let fromSince = NSPredicate(format: "startDate >= %@", since as NSDate)
        let beforeSince = NSPredicate(format: "startDate < %@", since as NSDate)
        var entryConditions = [mine]
        if let filter { entryConditions.append(Self.entries(of: filter)) }

        let shown = Activity.fetch(NSCompoundPredicate(andPredicateWithSubpredicates: entryConditions + [fromSince]))
        shown.fetchBatchSize = 50
        _activities = FetchRequest(fetchRequest: shown)
        // Only the first of these is read. Not a fetch limit: the results wouldn't refill when that
        // one is deleted (from the partner's phone, say), and Show earlier would go missing.
        let older = Activity.fetch(NSCompoundPredicate(andPredicateWithSubpredicates: entryConditions + [beforeSince]))
        older.fetchBatchSize = 1
        _olderActivities = FetchRequest(fetchRequest: older)

        // Marked periods only show with all entries, not when filtering by kind. Each one is under the
        // day it starts, so it's read with that day.
        let marked = filter == nil ? mine : NSPredicate(value: false)
        let shownPeriods = TrackingPeriod.fetchAll()
        shownPeriods.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [marked, NSPredicate(format: "start >= %@", since as NSDate)])
        _periods = FetchRequest(fetchRequest: shownPeriods)
        let earlierPeriods = TrackingPeriod.fetchAll()
        earlierPeriods.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [marked, NSPredicate(format: "start < %@", since as NSDate)])
        earlierPeriods.fetchBatchSize = 1
        _olderPeriods = FetchRequest(fetchRequest: earlierPeriods)
    }

    /// Entries of `kind`. One whose kind this version doesn't know reads as a feeding (`Activity.kind`),
    /// so it's listed with the feedings, as it always was.
    private static func entries(of kind: ActivityKind) -> NSPredicate {
        let matching = NSPredicate(format: "kindRaw == %@", kind.rawValue)
        guard kind == .feeding else { return matching }
        let known = ActivityKind.allCases.map(\.rawValue)
        return NSCompoundPredicate(orPredicateWithSubpredicates: [matching, NSPredicate(format: "NOT (kindRaw IN %@)", known)])
    }

    var body: some View {
        List {
            // Grouped once per render, over the days shown only.
            let days = self.days
            let earlier = self.earlierStart

            Section {
                filterBar
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if days.isEmpty {
                if let earlier {
                    // Nothing in the days shown, but there's more before them: reach back to it.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Loading earlier entries")
                        .onAppear { showEarlier(earlier) }
                } else {
                    EmptyStateView(
                        String(localized: "Nothing here yet"),
                        systemImage: "list.bullet.rectangle",
                        message: filter.map(Self.emptyMessage) ?? String(localized: "Everything you log shows up here."),
                        actionTitle: filter.map(Self.logTitle) ?? String(localized: "Log a feeding"),
                        isDisabled: !canEditLog
                    ) {
                        editorTarget = .new(filter ?? .feeding)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(days) { group in
                Section {
                    ForEach(group.items) { item in
                        switch item {
                        case .activity(let activity):
                            Button {
                                editorTarget = .edit(activity)
                            } label: {
                                ActivityRow(activity: activity, unit: unit)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                if canEditLog {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        delete(activity)
                                    }
                                }
                            }
                        case .period(let period):
                            Button {
                                coverageTarget = .editPeriod(period)
                            } label: {
                                TrackingPeriodRow(period: period)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.chipBackground)
                            .swipeActions {
                                if canEditLog {
                                    // Not `.destructive`, which would remove the row before the answer.
                                    Button("Delete", systemImage: "trash") {
                                        deletingPeriod = period
                                    }
                                    .tint(Palette.danger)
                                }
                            }
                        }
                    }
                } header: {
                    SummaryHeader(
                        title: Format.dayTitle(group.day),
                        summary: summary(of: group.activities),
                        spokenSummary: spokenSummary(of: group.activities)
                    )
                }
            }

            if !days.isEmpty, let earlier {
                Section {
                    Button {
                        showEarlier(earlier)
                    } label: {
                        Label("Show earlier", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityHint("Shows earlier days of the log")
                } footer: {
                    Text("Showing from \(since.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())).")
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: String(localized: "All", comment: "History filter: every kind of entry"),
                    voiceOverLabel: String(localized: "All entries"),
                    isSelected: filter == nil
                ) { selectFilter(nil) }
                ForEach(ActivityKind.allCases) { kind in
                    FilterChip(title: "\(kind.emoji) \(kind.pluralTitle)", voiceOverLabel: kind.pluralTitle, isSelected: filter == kind) {
                        selectFilter(filter == kind ? nil : kind)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    /// Where Show earlier goes, or `nil` when everything is already shown.
    private var earlierStart: Date? {
        let olderDates = [olderActivities.first?.startDate, olderPeriods.first?.start].compactMap { $0 }
        guard let newestOlder = olderDates.max(), newestOlder < since else { return nil }
        return HistoryWindow.start(before: since, reaching: newestOlder)
    }

    /// A row in History: an entry, or a marked period.
    private enum HistoryItem: Identifiable {
        case activity(Activity)
        case period(TrackingPeriod)

        var id: NSManagedObjectID {
            switch self {
            case .activity(let activity): return activity.objectID
            case .period(let period): return period.objectID
            }
        }

        var date: Date {
            switch self {
            case .activity(let activity): return activity.startDate
            case .period(let period): return period.start
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        /// Newest first.
        let items: [HistoryItem]
        var id: Date { day }

        var activities: [Activity] {
            items.compactMap { item -> Activity? in
                if case .activity(let activity) = item { return activity }
                return nil
            }
        }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let items = activities.map(HistoryItem.activity) + periods.map(HistoryItem.period)
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private func summary(of items: [Activity]) -> String {
        var parts: [String] = []
        let feeds = items.filter { $0.kind == .feeding }.count
        let diapers = items.filter { $0.kind == .diaper }.count
        let sleep = items.compactMap { $0.duration() }.reduce(0, +)
        if feeds > 0 { parts.append("\(feeds) 🍼") }
        if diapers > 0 { parts.append("\(diapers) 🧷") }
        if sleep > 0 { parts.append("\(Format.duration(sleep)) 😴") }
        return parts.joined(separator: " · ")
    }

    /// The summary in words, for VoiceOver.
    private func spokenSummary(of items: [Activity]) -> String {
        var parts: [String] = []
        let feeds = items.filter { $0.kind == .feeding }.count
        let diapers = items.filter { $0.kind == .diaper }.count
        let sleep = items.compactMap { $0.duration() }.reduce(0, +)
        if feeds > 0 {
            parts.append(feeds == 1 ? String(localized: "1 feeding") : String(localized: "\(feeds) feedings"))
        }
        if diapers > 0 {
            parts.append(diapers == 1 ? String(localized: "1 diaper") : String(localized: "\(diapers) diapers"))
        }
        if sleep > 0 {
            parts.append(String(localized: "\(Format.duration(sleep)) of sleep", comment: "VoiceOver: a day's total sleep, e.g. \"10h 5m of sleep\""))
        }
        return parts.joined(separator: ", ")
    }

    /// The empty list's sentence when filtering by `kind`: one sentence for each, so other languages
    /// can say it their own way.
    private static func emptyMessage(_ kind: ActivityKind) -> String {
        switch kind {
        case .feeding: return String(localized: "No feedings logged yet.")
        case .diaper: return String(localized: "No diapers logged yet.")
        case .sleep: return String(localized: "No sleep logged yet.")
        case .bath: return String(localized: "No baths logged yet.")
        case .medication: return String(localized: "No medicine logged yet.")
        case .pumping: return String(localized: "No pumping logged yet.")
        case .temperature: return String(localized: "No temperatures logged yet.")
        }
    }

    /// The empty list's button when filtering by `kind`.
    private static func logTitle(_ kind: ActivityKind) -> String {
        switch kind {
        case .feeding: return String(localized: "Log feeding")
        case .diaper: return String(localized: "Log diaper")
        case .sleep: return String(localized: "Log sleep")
        case .bath: return String(localized: "Log bath")
        case .medication: return String(localized: "Log medicine")
        case .pumping: return String(localized: "Log pumping")
        case .temperature: return String(localized: "Log temperature")
        }
    }

    private func delete(_ activity: Activity) {
        let wasFeeding = activity.kind == .feeding
        context.delete(activity)
        context.saveIfChanged()
        if wasFeeding {
            NotificationManager.refreshFeedingReminder(context: context)
        }
    }
}

private struct FilterChip: View {
    let title: String
    /// What VoiceOver reads instead of the emoji's name.
    let voiceOverLabel: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Palette.cardBackground, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        // With a pointer on iPad, the chip lights up under it.
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
