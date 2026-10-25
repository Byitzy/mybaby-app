import CoreData
import SwiftUI

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    let baby: Baby
    @FetchRequest private var activities: FetchedResults<Activity>
    /// Times marked as not tracked, nothing happened or caught up, shown as gray rows among the entries.
    @FetchRequest private var periods: FetchedResults<TrackingPeriod>

    @State private var filter: ActivityKind?
    @State private var editorTarget: EditorTarget?
    @State private var coverageTarget: CoverageSheetTarget?
    @State private var deletingPeriod: TrackingPeriod?

    init(baby: Baby) {
        self.baby = baby
        _activities = FetchRequest(fetchRequest: baby.entries(Activity.fetch()))
        _periods = FetchRequest(fetchRequest: baby.entries(TrackingPeriod.fetchAll()))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterBar
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if days.isEmpty {
                    EmptyStateView(
                        "Nothing here yet",
                        systemImage: "list.bullet.rectangle",
                        message: filter.map { "No \($0.pluralTitle.lowercased()) logged yet." } ?? "Everything you log shows up here.",
                        actionTitle: filter.map { "Log \($0.title.lowercased())" } ?? "Log a feeding",
                        isDisabled: !canEditLog
                    ) {
                        editorTarget = .new(filter ?? .feeding)
                    }
                    .listRowBackground(Color.clear)
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
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    markTimeMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(ActivityKind.allCases) { kind in
                            Button("\(kind.emoji) \(kind.title)") { editorTarget = .new(kind) }
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", voiceOverLabel: "All entries", isSelected: filter == nil) { filter = nil }
                ForEach(ActivityKind.allCases) { kind in
                    FilterChip(title: "\(kind.emoji) \(kind.pluralTitle)", voiceOverLabel: kind.pluralTitle, isSelected: filter == kind) {
                        filter = filter == kind ? nil : kind
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
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
        let filtered = filter.map { kind in activities.filter { $0.kind == kind } } ?? Array(activities)
        // Marked periods only show with all entries, not when filtering by kind.
        let marked = filter == nil ? Array(periods) : []
        let items = filtered.map(HistoryItem.activity) + marked.map(HistoryItem.period)
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
        if feeds > 0 { parts.append(Format.plural(feeds, "feeding")) }
        if diapers > 0 { parts.append(Format.plural(diapers, "diaper")) }
        if sleep > 0 { parts.append("\(Format.duration(sleep)) of sleep") }
        return parts.joined(separator: ", ")
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
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
