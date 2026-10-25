import Charts
import CoreData
import SwiftUI

enum ReportRange: Int, CaseIterable, Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: return "7 days"
        case .twoWeeks: return "14 days"
        case .month: return "30 days"
        }
    }
}

struct ReportsView: View {
    @ObservedObject var baby: Baby
    @State private var range: ReportRange = .week

    var body: some View {
        NavigationStack {
            ReportContent(range: $range, baby: baby)
                .id(range)
                .navigationTitle("Reports")
        }
    }
}

private struct ReportContent: View {
    @Binding var range: ReportRange
    let baby: Baby

    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var growthUnits: GrowthUnits = .localeDefault
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @FetchRequest private var activities: FetchedResults<Activity>
    @FetchRequest private var vaccines: FetchedResults<Vaccine>
    @FetchRequest private var growthEntries: FetchedResults<GrowthEntry>
    /// Times marked as not tracked, nothing happened or caught up, for each day's coverage.
    @FetchRequest private var periods: FetchedResults<TrackingPeriod>

    @State private var share: SharePayload?

    init(range: Binding<ReportRange>, baby: Baby) {
        _range = range
        self.baby = baby
        // Start a day early so a sleep that began the night before is counted.
        let start = Calendar.current.date(
            byAdding: .day, value: -1, to: ReportBuilder.startDay(days: range.wrappedValue.rawValue)
        ) ?? .distantPast
        _activities = FetchRequest(fetchRequest: baby.entries(Activity.since(start)))
        _vaccines = FetchRequest(fetchRequest: baby.entries(Vaccine.fetchAll()))
        _growthEntries = FetchRequest(fetchRequest: baby.entries(GrowthEntry.fetchAll()))
        _periods = FetchRequest(fetchRequest: baby.entries(TrackingPeriod.overlapping(start, .distantFuture)))
    }

    /// Each day with how much of it was tracked, so days nobody logged show as "No data", not zero.
    private var summaries: [DaySummary] {
        let coverage = Coverage(activities: Array(activities), periods: Array(periods), plan: nightPlan)
        return ReportBuilder.summaries(for: Array(activities), days: range.rawValue, coverage: coverage)
    }

    private var medications: [Activity] {
        let start = ReportBuilder.startDay(days: range.rawValue)
        return activities.filter { $0.kind == .medication && $0.startDate >= start }.reversed()
    }

    /// Temperature readings in the range, oldest first, for the PDF.
    private var temperatures: [Activity] {
        let start = ReportBuilder.startDay(days: range.rawValue)
        return activities.filter { $0.kind == .temperature && $0.startDate >= start }
    }

    var body: some View {
        let days = self.summaries
        let averages = ReportAverages(days)

        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(ReportRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                averagesGrid(averages)

                PatternsLink(baby: baby)

                Card("Feedings", subtitle: "Number of feedings per day") {
                    Chart {
                        noDataMarks(days)
                        ForEach(Self.withData(days)) { day in
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Feedings", day.feedings)
                            )
                            .foregroundStyle(ActivityKind.feeding.color.gradient)
                            .cornerRadius(4)
                            .opacity(Self.barOpacity(day))
                            .accessibilityLabel(Self.dayLabel(day.day))
                            .accessibilityValue(Self.spoken(Format.plural(day.feedings, "feeding"), day))
                        }
                    }
                    .frame(height: 160)
                    CoverageLegend(days: days, tint: ActivityKind.feeding.color)
                }

                if days.contains(where: { $0.bottleML > 0 }) {
                    Card("Bottle amount", subtitle: "Total \(unit.rawValue) per day") {
                        Chart {
                            noDataMarks(days)
                            ForEach(Self.withData(days)) { day in
                                BarMark(
                                    x: .value("Day", day.day, unit: .day),
                                    y: .value("Amount", unit.fromML(day.bottleML))
                                )
                                .foregroundStyle(Palette.bottle.opacity(0.7).gradient)
                                .cornerRadius(4)
                                .opacity(Self.barOpacity(day))
                                .accessibilityLabel(Self.dayLabel(day.day))
                                .accessibilityValue(Self.spoken(unit.format(ml: day.bottleML), day))
                            }
                        }
                        .frame(height: 160)
                        CoverageLegend(days: days, tint: Palette.bottle)
                    }
                }

                if days.contains(where: { $0.breastMinutes > 0 }) {
                    Card("Breastfeeding", subtitle: "Total minutes per day") {
                        Chart {
                            noDataMarks(days)
                            ForEach(Self.withData(days)) { day in
                                BarMark(
                                    x: .value("Day", day.day, unit: .day),
                                    y: .value("Minutes", day.breastMinutes)
                                )
                                .foregroundStyle(Palette.breastfeeding.opacity(0.7).gradient)
                                .cornerRadius(4)
                                .opacity(Self.barOpacity(day))
                                .accessibilityLabel(Self.dayLabel(day.day))
                                .accessibilityValue(Self.spoken(Format.plural(day.breastMinutes, "minute"), day))
                            }
                        }
                        .frame(height: 160)
                        CoverageLegend(days: days, tint: Palette.breastfeeding)
                    }
                }

                if days.contains(where: { $0.pumpedML > 0 }) {
                    Card("Pumped per day", subtitle: "Total \(unit.rawValue) pumped per day") {
                        Chart {
                            noDataMarks(days)
                            ForEach(Self.withData(days)) { day in
                                BarMark(
                                    x: .value("Day", day.day, unit: .day),
                                    y: .value("Pumped", unit.fromML(day.pumpedML))
                                )
                                .foregroundStyle(ActivityKind.pumping.color.gradient)
                                .cornerRadius(4)
                                .opacity(Self.barOpacity(day))
                                .accessibilityLabel(Self.dayLabel(day.day))
                                .accessibilityValue(Self.spoken("\(unit.format(ml: day.pumpedML)) pumped", day))
                            }
                        }
                        .frame(height: 160)
                        CoverageLegend(days: days, tint: ActivityKind.pumping.color)
                    }
                }

                // Wet and dirty side by side rather than stacked, named in the legend (with an emoji
                // each) and on every bar for VoiceOver, so the two aren't told apart by color alone.
                Card("Diapers", subtitle: "Wet and dirty diapers per day") {
                    Chart {
                        noDataMarks(days)
                        ForEach(Self.withData(days)) { day in
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Count", day.wet)
                            )
                            .foregroundStyle(by: .value("Type", "Wet 💧"))
                            .position(by: .value("Type", "Wet 💧"))
                            .opacity(Self.barOpacity(day))
                            .accessibilityLabel(Self.dayLabel(day.day))
                            .accessibilityValue(Self.spoken(Format.plural(day.wet, "wet diaper"), day))
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Count", day.dirty)
                            )
                            .foregroundStyle(by: .value("Type", "Dirty 💩"))
                            .position(by: .value("Type", "Dirty 💩"))
                            .opacity(Self.barOpacity(day))
                            .accessibilityLabel(Self.dayLabel(day.day))
                            .accessibilityValue(Self.spoken(Format.plural(day.dirty, "dirty diaper"), day))
                        }
                    }
                    // Domain and range in order, so the legend always reads wet, then dirty.
                    .chartForegroundStyleScale(domain: ["Wet 💧", "Dirty 💩"], range: [Palette.wetDiaper, Palette.dirtyDiaper])
                    .frame(height: 160)
                    CoverageLegend(days: days, tint: Palette.wetDiaper)
                }

                Card("Sleep", subtitle: "Hours of sleep per day") {
                    Chart {
                        noDataMarks(days)
                        ForEach(Self.withData(days)) { day in
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Hours", day.sleepHours)
                            )
                            .foregroundStyle(ActivityKind.sleep.color.gradient)
                            .cornerRadius(4)
                            .opacity(Self.barOpacity(day))
                            .accessibilityLabel(Self.dayLabel(day.day))
                            .accessibilityValue(Self.spoken(day.sleepSeconds > 0 ? "\(Format.spokenDuration(day.sleepSeconds)) of sleep" : "No sleep logged", day))
                        }
                    }
                    .frame(height: 160)
                    CoverageLegend(days: days, tint: ActivityKind.sleep.color)
                }

                if nightPlan.isEnabled {
                    nightDutyCard
                }

                if !growthEntries.isEmpty {
                    growthCard
                }

                Card("Medicine given", subtitle: "Last \(range.title)") {
                    if medications.isEmpty {
                        Text("No medicine logged.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(medications) { med in
                            // The time moves under the name when they don't fit on one line.
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    medicineName(med)
                                    Spacer()
                                    medicineTime(med)
                                }
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    medicineName(med)
                                    medicineTime(med)
                                }
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Palette.screenBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sharePDF(summaries: days, averages: averages)
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
    }

    private var nightPlan: NightPlan { NightPlan(data: nightPlanData) }

    /// "Monday, Oct 20", for VoiceOver on each bar.
    static func dayLabel(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: Coverage

    /// Days that get a bar: every day except those nobody tracked, which get a "No data" column instead.
    static func withData(_ days: [DaySummary]) -> [DaySummary] {
        days.filter { $0.coverage != .none }
    }

    /// Partly tracked days are drawn lighter, and the legend under the chart says why.
    static func barOpacity(_ day: DaySummary) -> Double {
        day.coverage == .partial ? 0.45 : 1
    }

    /// A bar's VoiceOver value, saying when the day was only partly tracked.
    static func spoken(_ value: String, _ day: DaySummary) -> String {
        day.coverage == .partial ? "\(value), partly tracked" : value
    }

    /// A light gray full-height column for each day nobody tracked, instead of a zero bar. Labelled
    /// "No data" when the columns are wide enough (7 days); the legend under the chart names it too.
    @ChartContentBuilder
    private func noDataMarks(_ days: [DaySummary]) -> some ChartContent {
        let labelled = range == .week
        ForEach(days.filter { $0.coverage == .none }) { day in
            RectangleMark(
                xStart: .value("Day", day.day),
                xEnd: .value("Day", Calendar.current.date(byAdding: .day, value: 1, to: day.day) ?? day.day)
            )
            .foregroundStyle(Palette.inactive.opacity(0.15))
            .annotation(position: .overlay, alignment: .center) {
                Text(labelled ? "No\ndata" : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(Self.dayLabel(day.day))
            .accessibilityValue("No data")
        }
    }

    private func medicineName(_ med: Activity) -> some View {
        HStack {
            EmojiTitle("💊", med.title)
            if let dose = med.dosage, !dose.isEmpty {
                Text(dose).foregroundStyle(.secondary)
            }
        }
    }

    private func medicineTime(_ med: Activity) -> some View {
        Text(med.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
            .foregroundStyle(.secondary)
    }

    /// Night feeds and diaper changes each parent handled, next to the hours they were scheduled for.
    private var nightDutyCard: some View {
        let plan = nightPlan
        let start = ReportBuilder.startDay(days: range.rawValue)
        let nightCare = activities.filter {
            $0.startDate >= start
                && ($0.kind == .feeding || $0.kind == .diaper)
                && plan.shift(at: $0.startDate) != nil
        }
        let nights = (0..<range.rawValue).compactMap { offset -> [NightShift]? in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: start) else { return nil }
            let shifts = plan.shifts(forNightOf: day)
            return (shifts.first?.start ?? .distantFuture) <= .now ? shifts : nil
        }
        let duty = NightPlan.dutyTotals(nights)
        let unassigned = nightCare.filter { $0.caregiver == nil }.count

        return Card("Night duty", subtitle: "Night feeds and diapers each of you handled, last \(range.title)") {
            ForEach(Parent.allCases) { parent in
                let handled = nightCare.filter { $0.caregiver == parent }.count
                HStack {
                    Circle().fill(parent.color).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(plan.name(of: parent))
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text("\(handled) handled")
                            .font(.subheadline.weight(.semibold))
                        Text("\(Format.hours(duty[parent] ?? 0)) on duty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(Format.spoken(Format.hours(duty[parent] ?? 0))) on duty")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if unassigned > 0 {
                Text("\(unassigned) not assigned to anyone. Edit an entry to set who handled it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The latest weight and length, whenever they were measured.
    private var growthCard: some View {
        let weighed = growthEntries.last(where: { $0.weightKg != nil })
        let measured = growthEntries.last(where: { $0.lengthCm != nil })

        return Card("Growth", subtitle: "Latest measurements") {
            if let weighed, let kg = weighed.weightKg {
                growthRow("⚖️", "Weight", value: growthUnits.formatWeight(kg: kg), date: weighed.date)
            }
            if let measured, let cm = measured.lengthCm {
                growthRow("📏", "Length", value: growthUnits.formatLength(cm: cm), date: measured.date)
            }
        }
    }

    private func growthRow(_ emoji: String, _ title: String, value: String, date: Date) -> some View {
        HStack {
            EmojiTitle(emoji, title)
            Spacer()
            Text(value).fontWeight(.semibold)
            Text(date, format: .dateTime.month(.abbreviated).day())
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func averagesGrid(_ averages: ReportAverages) -> some View {
        // Two columns at the largest text sizes, so the numbers stay readable.
        let columns = Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.gridColumns(3))
        return VStack(alignment: .leading, spacing: Spacing.s) {
            LazyVGrid(columns: columns, spacing: 10) {
                StatTile(title: "Feeds/day", value: decimal(averages.feedings), emoji: "🍼", tint: ActivityKind.feeding.color, spokenTitle: "Feeds per day")
                StatTile(title: "Bottle/day", value: unit.format(ml: averages.bottleML), emoji: "🍼", tint: Palette.bottle, spokenTitle: "Bottle per day")
                StatTile(title: "Sleep/day", value: Format.hours(averages.sleepHours * 3600), emoji: "😴", tint: ActivityKind.sleep.color, spokenTitle: "Sleep per day")
                StatTile(title: "Wet/day", value: decimal(averages.wet), emoji: "💧", tint: Palette.wetDiaper, spokenTitle: "Wet diapers per day")
                StatTile(title: "Dirty/day", value: decimal(averages.dirty), emoji: "💩", tint: Palette.dirtyDiaper, spokenTitle: "Dirty diapers per day")
                StatTile(title: "Baths", value: "\(averages.totalBaths)", emoji: "🛁", tint: ActivityKind.bath.color, spokenTitle: "Baths in all")
            }
            Text(averagesNote(averages))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func averagesNote(_ averages: ReportAverages) -> String {
        averages.basisNote
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    @MainActor
    private func sharePDF(summaries: [DaySummary], averages: ReportAverages) {
        let document = ReportDocument(
            babyName: baby.name,
            birthDate: baby.birthDate,
            range: range,
            summaries: summaries,
            averages: averages,
            medications: medications,
            vaccines: vaccines.filter(\.isGiven),
            upcomingVaccines: vaccines.filter { !$0.isGiven },
            unit: unit,
            growthEntries: Array(growthEntries),
            growthUnits: growthUnits,
            temperatures: temperatures,
            temperatureUnit: TemperatureUnit.current,
            sex: baby.sex,
            allergies: baby.allergyList(),
            reactions: baby.allergyReactionList(since: ReportBuilder.startDay(days: range.rawValue))
        )
        let fileName = "\(baby.fileSafeName)-report-\(range.rawValue)-days.pdf"
        if let url = Exporter.pdf(document, named: fileName) {
            share = SharePayload(items: [url])
        }
    }
}

/// Under a Reports chart: what the gray columns and the lighter bars mean. Only shown when the range has
/// such days. Each swatch has its words next to it, so it isn't told by color alone.
private struct CoverageLegend: View {
    let days: [DaySummary]
    let tint: Color
    @ScaledMetric(relativeTo: .caption) private var swatch: CGFloat = 10

    var body: some View {
        let noData = days.contains { $0.coverage == .none }
        let partial = days.contains { $0.coverage == .partial }
        if noData || partial {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.m) { items(noData: noData, partial: partial) }
                VStack(alignment: .leading, spacing: Spacing.xs) { items(noData: noData, partial: partial) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func items(noData: Bool, partial: Bool) -> some View {
        if noData {
            HStack(spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.inactive.opacity(0.3))
                    .frame(width: swatch, height: swatch)
                    .accessibilityHidden(true)
                Text("No data: nothing tracked")
            }
        }
        if partial {
            HStack(spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.45))
                    .frame(width: swatch, height: swatch)
                    .accessibilityHidden(true)
                Text("Lighter: partly tracked")
            }
        }
    }
}
