import CoreData
import SwiftUI

/// Every month of the baby's life so far, and the weeks of the first 3 months, newest first. Each opens
/// its summary, worked out from the log when it's opened.
struct DiarySummariesList: View {
    @ObservedObject var baby: Baby
    /// The parents' notes, to mark the weeks and months that have one.
    @FetchRequest private var notes: FetchedResults<DiaryEntry>

    init(baby: Baby) {
        self.baby = baby
        _notes = FetchRequest(fetchRequest: baby.entries(DiaryEntry.periodNotes()))
    }

    var body: some View {
        List {
            if let birthDate = baby.birthDate, birthDate <= .now {
                let months = DiaryPeriod.months(birthDate: birthDate)
                let weeks = DiaryPeriod.weeks(birthDate: birthDate)
                Section {
                    ForEach(months) { period in
                        link(period)
                    }
                } header: {
                    Text("Months")
                } footer: {
                    Text("Each month runs from one month birthday to the day before the next. Summaries are worked out from the log, and days that weren't logged are never counted as zero.")
                }
                if !weeks.isEmpty {
                    Section {
                        ForEach(weeks) { period in
                            link(period)
                        }
                    } header: {
                        Text("The first weeks")
                    } footer: {
                        Text("Week by week for the first 3 months, from the day \(baby.displayName) was born.")
                    }
                }
            } else {
                // String(localized:) since the message is a String: the call takes its String version.
                EmptyStateView(
                    String(localized: "Summaries start with a birthday"),
                    systemImage: "calendar",
                    message: noBirthdayMessage
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    /// A sentence for each, since the pronoun changes it in other languages.
    private var noBirthdayMessage: String {
        let name = baby.displayName
        return DiaryText.bySex(
            baby,
            female: String(localized: "Weeks and months are counted from the day \(name) was born. Add her birthday in More › Babies, and each week and month gets a summary."),
            male: String(localized: "Weeks and months are counted from the day \(name) was born. Add his birthday in More › Babies, and each week and month gets a summary."),
            unknown: String(localized: "Weeks and months are counted from the day \(name) was born. Add \(name)'s birthday in More › Babies, and each week and month gets a summary.")
        )
    }

    private var notedPeriods: Set<DiaryPeriod.ID> {
        Set(notes.filter { !$0.isDeleted && $0.managedObjectContext != nil }.compactMap(\.periodID))
    }

    private func link(_ period: DiaryPeriod) -> some View {
        NavigationLink {
            PeriodSummaryView(baby: baby, period: period)
        } label: {
            PeriodRow(period: period, hasNote: notedPeriods.contains(period.id))
        }
    }
}

/// "Month 3", "12 Jan – 11 Feb", and whether it's still going or has a note.
private struct PeriodRow: View {
    let period: DiaryPeriod
    let hasNote: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(period.title)
                    .font(.body.weight(.semibold))
                Text(period.dateRange())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            if !period.isFinished() {
                Text("So far")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xxs)
                    .background(Palette.chipBackground, in: Capsule())
            } else if hasNote {
                Image(systemName: "text.quote")
                    .foregroundStyle(Palette.diary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status)
    }

    private var status: String {
        if !period.isFinished() { return String(localized: "In progress") }
        return hasNote ? String(localized: "Has a note from you") : ""
    }
}

// MARK: - One summary

/// One week or month: the parents' note at the top ("Write about this month"), how much of it was
/// logged, feeds, sleep and diapers, growth, milestones, vaccines and appointments, and the diary entries
/// and photos from those days.
///
/// Worked out from the log each time (see `DiarySummaryBuilder`), and again whenever anything changes,
/// so the partner's entries show up as they arrive.
struct PeriodSummaryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var growthUnits: GrowthUnits = .localeDefault
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @ObservedObject var baby: Baby
    let period: DiaryPeriod

    @State private var summary: DiarySummary?
    @State private var photoIDs: [NSManagedObjectID] = []
    @State private var editorTarget: DiaryEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if let summary {
                    notesCard(summary)
                    logCard(summary)
                    growthCard(summary)
                    milestonesCard(summary)
                    healthCard(summary)
                    diaryCard(summary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                }
            }
            .padding(Spacing.l)
        }
        .background(Palette.screenBackground)
        .navigationTitle(period.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorTarget) { target in
            DiaryEntryEditor(target: target, baby: baby)
        }
        .onAppear(perform: rebuild)
        // Anything changed here, or arrived from the partner's phone.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context).receive(on: RunLoop.main)) { _ in
            rebuild()
        }
    }

    private func rebuild() {
        let built = DiarySummaryBuilder.summary(for: period, baby: baby, context: context, plan: NightPlan(data: nightPlanData))
        summary = built
        // The period's photos: its diary entries' (sealed letters left out), then its milestones'.
        let open = built.entries.filter { !$0.isSealed(birthDate: baby.birthDate) }
        photoIDs = open.flatMap { $0.photoIDs() } + built.milestones.flatMap { $0.photoIDs() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(headline)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Mavie's third month" / "Mavie's week 6". "First" to "twelfth" in words, then "13th": each its
    /// own sentence, since the ordinal changes with the noun in other languages.
    private var headline: String {
        let name = baby.displayName
        switch period.kind {
        case .week: return String(localized: "\(name)'s week \(period.index)")
        case .month:
            switch period.index {
            case 1: return String(localized: "\(name)'s first month")
            case 2: return String(localized: "\(name)'s second month")
            case 3: return String(localized: "\(name)'s third month")
            case 4: return String(localized: "\(name)'s fourth month")
            case 5: return String(localized: "\(name)'s fifth month")
            case 6: return String(localized: "\(name)'s sixth month")
            case 7: return String(localized: "\(name)'s seventh month")
            case 8: return String(localized: "\(name)'s eighth month")
            case 9: return String(localized: "\(name)'s ninth month")
            case 10: return String(localized: "\(name)'s tenth month")
            case 11: return String(localized: "\(name)'s eleventh month")
            case 12: return String(localized: "\(name)'s twelfth month")
            default:
                return String(localized: "\(name)'s \(DiaryText.ordinal(period.index)) month", comment: "e.g. “Mavie's 13th month”")
            }
        }
    }

    /// "12 Jan – 11 Feb · 3 months old on 12 Feb", or "so far" while it's going.
    private var subheadline: String {
        let range = period.dateRange()
        if period.isFinished() {
            let day = period.end.formatted(.dateTime.day().month(.abbreviated))
            let age = DiaryText.ageReached(period)
            switch age.unit {
            case .weeks:
                return String(localized: "\(range) · \(age.count) weeks old on \(day)", comment: "e.g. “5 Jan – 11 Jan · 6 weeks old on 12 Jan”")
            case .months:
                return String(localized: "\(range) · \(age.count) months old on \(day)", comment: "e.g. “12 Jan – 11 Feb · 3 months old on 12 Feb”")
            case .years:
                return String(localized: "\(range) · \(age.count) years old on \(day)", comment: "e.g. “12 Jan – 11 Feb · 1 year old on 12 Feb”")
            }
        }
        return String(localized: "\(range) · so far", comment: "A week or month that's still going")
    }

    // MARK: Notes

    private func notesCard(_ summary: DiarySummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("From you", systemImage: "text.quote")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if summary.notes.isEmpty {
                Text(notesInvitation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.notes) { note in
                NoteView(note: note, canEdit: canEditLog) {
                    editorTarget = .edit(note)
                }
            }
            Button {
                editorTarget = .note(about: period)
            } label: {
                Label(
                    summary.notes.isEmpty ? (period.kind == .week ? "Write about this week" : "Write about this month") : "Add another note",
                    systemImage: "square.and.pencil"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.diary)
            .disabled(!canEditLog)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(tint: Palette.diary)
    }

    /// "A few words about this month, for Mavie to read one day. What made you smile? What did she learn?"
    private var notesInvitation: String {
        let opening = period.kind == .week
            ? String(localized: "A few words about this week, for \(baby.displayName) to read one day. What made you smile?")
            : String(localized: "A few words about this month, for \(baby.displayName) to read one day. What made you smile?")
        return "\(opening) \(DiaryText.whatDidTheyLearn(baby))"
    }

    // MARK: The log

    private func logCard(_ summary: DiarySummary) -> some View {
        Card(String(localized: "Feeds, sleep and diapers"), subtitle: summary.coverageText) {
            if summary.hasNoLog {
                Text(nothingLogged(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.gridColumns(3))
                LazyVGrid(columns: columns, spacing: 10) {
                    SummaryStat(
                        emoji: "🍼", title: String(localized: "Feeds"), value: "\(summary.feeds)",
                        detail: perDay(summary.averages.feedings, summary), tint: ActivityKind.feeding.color
                    )
                    SummaryStat(
                        emoji: "😴", title: String(localized: "Sleep"), value: Format.hours(summary.sleepSeconds),
                        detail: summary.longestSleep.map { String(localized: "Longest \(Format.duration($0))", comment: "The longest sleep") },
                        tint: ActivityKind.sleep.color
                    )
                    SummaryStat(
                        emoji: "🧷", title: String(localized: "Diapers"), value: "\(summary.diapers)",
                        detail: summary.diapersPerDay.flatMap { perDay($0, summary) }, tint: ActivityKind.diaper.color
                    )
                }
                if summary.averages.basedOnDays > 0, summary.averages.sleepHours > 0 {
                    Text("About \(Format.hours(summary.averages.sleepHours * 3600)) of sleep a day. \(summary.averages.basisNote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = summary.coverageNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Nothing logged yet this month.", or that nothing was, once it's over.
    private func nothingLogged(_ summary: DiarySummary) -> String {
        switch (period.kind, summary.isInProgress) {
        case (.week, true): return String(localized: "Nothing logged yet this week.")
        case (.month, true): return String(localized: "Nothing logged yet this month.")
        case (.week, false):
            return String(localized: "Nothing was logged this week, so there's nothing to count. That's okay: notes and photos still belong here.")
        case (.month, false):
            return String(localized: "Nothing was logged this month, so there's nothing to count. That's okay: notes and photos still belong here.")
        }
    }

    /// "About 8 a day", from fully tracked days, or nil when there are none.
    private func perDay(_ value: Double, _ summary: DiarySummary) -> String? {
        guard summary.averages.basedOnDays > 0 else { return nil }
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "About \(number) a day", comment: "e.g. “About 8 a day”")
    }

    // MARK: Growth, milestones and health

    @ViewBuilder
    private func growthCard(_ summary: DiarySummary) -> some View {
        let weight = summary.weightLine(units: growthUnits, baby: baby)
        let length = summary.lengthLine(units: growthUnits, baby: baby)
        if weight != nil || length != nil {
            Card(String(localized: "Growth"), subtitle: String(localized: "\(summary.growth.count) measurements", comment: "Growth measurements")) {
                if let weight {
                    LabeledContent("Weight", value: weight)
                        .font(.subheadline)
                }
                if let length {
                    LabeledContent("Length", value: length)
                        .font(.subheadline)
                }
                if baby.canShowGrowthPercentiles {
                    Text("Percentiles from the WHO Child Growth Standards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func milestonesCard(_ summary: DiarySummary) -> some View {
        if !summary.milestones.isEmpty {
            Card("Milestones") {
                ForEach(summary.milestones) { milestone in
                    NavigationLink {
                        MilestoneDetailView(milestone: milestone, baby: baby)
                    } label: {
                        HStack(spacing: Spacing.m) {
                            EmojiBadge(emoji: milestone.displayEmoji, tint: Palette.milestone, size: 36)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(milestone.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(milestone.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func healthCard(_ summary: DiarySummary) -> some View {
        if !summary.vaccines.isEmpty || !summary.appointments.isEmpty {
            Card("Checkups and vaccines") {
                ForEach(summary.appointments) { appointment in
                    healthLine(
                        "🩺",
                        appointment.title.isEmpty ? String(localized: "Appointment") : appointment.title,
                        appointment.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    )
                }
                ForEach(summary.vaccines) { vaccine in
                    healthLine(
                        "💉",
                        vaccine.doseLabel.isEmpty ? vaccine.name : "\(vaccine.name) (\(vaccine.doseLabel))",
                        vaccine.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    )
                }
            }
        }
    }

    private func healthLine(_ emoji: String, _ title: String, _ date: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            EmojiTitle(emoji, title)
            Spacer(minLength: Spacing.s)
            Text(date)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    // MARK: Diary

    @ViewBuilder
    private func diaryCard(_ summary: DiarySummary) -> some View {
        // Notes about this period are at the top already.
        let entries = summary.entries.filter { $0.periodID != period.id }
        if !entries.isEmpty || !photoIDs.isEmpty {
            Card(String(localized: "From the diary"), subtitle: diarySubtitle(entries: entries.count)) {
                ForEach(entries) { entry in
                    NavigationLink {
                        DiaryEntryDetailView(entry: entry, baby: baby)
                    } label: {
                        DiaryEntryRow(entry: entry, baby: baby)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !photoIDs.isEmpty {
                    DiaryPhotoGrid(photoIDs: photoIDs, title: period.title)
                }
            }
        }
    }

    private func diarySubtitle(entries: Int) -> String {
        var parts: [String] = []
        if entries > 0 {
            parts.append(entries == 1 ? String(localized: "1 entry", comment: "Diary entries") : String(localized: "\(entries) entries", comment: "Diary entries"))
        }
        if !photoIDs.isEmpty { parts.append(String(localized: "\(photoIDs.count) photos")) }
        return parts.joined(separator: " · ")
    }
}

/// A parent's note about a week or month: the words, and who wrote them. Tapping it edits it.
private struct NoteView: View {
    @ObservedObject var note: DiaryEntry
    let canEdit: Bool
    let edit: () -> Void

    var body: some View {
        if note.isDeleted || note.managedObjectContext == nil {
            EmptyView()
        } else {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    if !note.text.isEmpty {
                        Text(note.text)
                            .font(.body)
                    }
                    if let author = note.author {
                        Text("— \(author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityHint(canEdit ? "Edits the note" : "")
        }
    }
}

/// A number with a small line under it: "142", "About 8 a day".
private struct SummaryStat: View {
    let emoji: String
    let title: String
    let value: String
    let detail: String?
    let tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(emoji) \(title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .tileStyle(tint: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Format.spoken([value, detail].compactMap { $0 }.joined(separator: " · ")))
    }
}
