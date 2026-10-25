import Charts
import CoreData
import SwiftUI

/// The card on Reports that opens Patterns.
struct PatternsLink: View {
    let baby: Baby

    var body: some View {
        NavigationLink {
            PatternsView(baby: baby)
        } label: {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "🔍", tint: Palette.patterns)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Patterns")
                        .font(.headline)
                    Text("Night wake-ups, time between feeds, longest sleep and busiest diaper times")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .cardStyle()
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

/// Rhythms in the last 7 or 14 days of the current baby's log, in plain sentences and small charts.
struct PatternsView: View {
    let baby: Baby
    @State private var range: ReportRange = .week

    var body: some View {
        PatternsContent(range: $range, baby: baby)
            // Rebuilt for each range, so its fetch starts at the right day.
            .id(range)
            .navigationTitle("Patterns")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PatternsContent: View {
    @Binding var range: ReportRange
    let baby: Baby

    @FetchRequest private var activities: FetchedResults<Activity>
    /// Marked "not tracked" (or "nothing happened") times, so a gap in the log isn't read as a pattern.
    @FetchRequest private var periods: FetchedResults<TrackingPeriod>

    static let ranges: [ReportRange] = [.week, .twoWeeks]

    init(range: Binding<ReportRange>, baby: Baby) {
        _range = range
        self.baby = baby
        // A day early, so a sleep that began the evening before is counted.
        let start = Calendar.current.date(
            byAdding: .day, value: -1, to: ReportBuilder.startDay(days: range.wrappedValue.rawValue)
        ) ?? .distantPast
        _activities = FetchRequest(fetchRequest: baby.entries(Activity.since(start)))
        _periods = FetchRequest(fetchRequest: baby.entries(TrackingPeriod.overlapping(start, .distantFuture)))
    }

    private var name: String { baby.displayName }

    var body: some View {
        let coverage = Coverage(activities: Array(activities), periods: Array(periods))
        let report = PatternFinder.report(for: Array(activities), days: range.rawValue, untracked: coverage.untracked)

        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(Self.ranges) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Text("What \(name)'s log shows over the last \(range.title). Night is 9 PM to 7 AM. Times nobody logged are left out, so a gap in the log isn't read as a long time between feeds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                nightCard(report.nightWakes)
                feedCard(report.feedGaps)
                sleepCard(report.longestSleep)
                awakeCard(report.awake)
                diaperCard(report.diapers)

                Text("Patterns describe what was logged, not what's expected. Every baby is different. If something worries you, talk to your pediatrician.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Palette.screenBackground)
    }

    // MARK: Night wake-ups

    private func nightCard(_ wakes: PatternFinder.NightWakes?) -> some View {
        Card("Night wake-ups", subtitle: "Night feeds and wake-ups") {
            if let wakes {
                if wakes.usualTimes.isEmpty {
                    sentence("There's no regular wake-up time yet. Night wake-ups have been at different times.")
                } else {
                    let times = wakes.usualTimes.map { "around \(Self.clockText($0.minuteOfDay))" }
                    sentence("\(name) usually wakes \(times.formatted(.list(type: .and))).")
                    // By position: two usual times can round to the same quarter hour.
                    ForEach(Array(wakes.usualTimes.enumerated()), id: \.offset) { item in
                        HStack {
                            Text("Around \(Self.clockText(item.element.minuteOfDay))")
                            Spacer()
                            Text("\(item.element.nights) of \(Format.plural(wakes.nights, "night"))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("About \(decimal(wakes.averagePerNight)) wake-ups a night, over \(Format.plural(wakes.nights, "night")) with entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                nightChart(wakes.allWakes)
            } else {
                notEnough("Log a few nights of feeds and sleep to see when \(name) usually wakes.")
            }
        }
    }

    /// Wake-ups in each hour of the night.
    private func nightChart(_ minutes: [Int]) -> some View {
        let hours = (0..<10).map { offset -> HourCount in
            let hour = (21 + offset) % 24
            return HourCount(date: Self.nightClockDate(hour * 60), count: minutes.filter { $0 / 60 == hour }.count)
        }
        return Chart {
            ForEach(hours) { bin in
                BarMark(
                    x: .value("Time", bin.date, unit: .hour),
                    y: .value("Wake-ups", bin.count)
                )
                .foregroundStyle(ActivityKind.sleep.color.gradient)
                .cornerRadius(3)
                .accessibilityLabel(bin.date.formatted(.dateTime.hour()))
                .accessibilityValue(Format.plural(bin.count, "wake-up"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 120)
    }

    // MARK: Feeds

    private func feedCard(_ gaps: PatternFinder.FeedGaps?) -> some View {
        Card("Time between feeds", subtitle: "From the start of one feed to the start of the next") {
            if let gaps {
                let parts = [
                    gaps.day.map { "During the day, feeds were about \(Format.duration($0)) apart." },
                    gaps.night.map { "At night, about \(Format.duration($0))." },
                ].compactMap { $0 }
                sentence(parts.joined(separator: " "))
                let bars = [
                    gaps.day.map { GapBar(label: "Day", hours: $0 / 3600) },
                    gaps.night.map { GapBar(label: "Night", hours: $0 / 3600) },
                ].compactMap { $0 }
                Chart {
                    ForEach(bars) { bar in
                        BarMark(
                            x: .value("Hours", bar.hours),
                            y: .value("When", bar.label)
                        )
                        .foregroundStyle(ActivityKind.feeding.color.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text(Format.duration(bar.hours * 3600))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(bar.label)
                        .accessibilityValue(Format.duration(bar.hours * 3600))
                    }
                }
                .chartXAxisLabel("Hours")
                .frame(height: CGFloat(bars.count) * 44 + 24)
            } else {
                notEnough("Log a few more feeds to see how far apart they are.")
            }
        }
    }

    // MARK: Sleep

    private func sleepCard(_ sleep: PatternFinder.LongestSleep?) -> some View {
        Card("Longest sleep", subtitle: "The longest stretch each day (days run 7 AM to 7 AM)") {
            if let sleep {
                let start = sleep.longest.day.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                sentence("The longest stretch was \(Format.duration(sleep.longest.duration)), starting \(start).\(trendText(sleep.trend))")
                Chart {
                    ForEach(sleep.byDay) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Hours", day.duration / 3600)
                        )
                        .foregroundStyle(ActivityKind.sleep.color.gradient)
                        .cornerRadius(4)
                        .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .accessibilityValue(Format.duration(day.duration))
                    }
                }
                .chartYAxisLabel("Hours")
                .frame(height: 140)
            } else {
                notEnough("Log sleep with a start and an end for a few days to see the longest stretches.")
            }
        }
    }

    private func trendText(_ trend: PatternFinder.Trend?) -> String {
        switch trend {
        case .longer: return " The longest stretch has been getting longer."
        case .steady: return " It's been about the same from day to day."
        case .shorter: return " It's been a little shorter lately."
        case nil: return ""
        }
    }

    // MARK: Awake

    private func awakeCard(_ awake: PatternFinder.AwakeStretches?) -> some View {
        Card("Awake between sleeps", subtitle: "Daytime wake-ups, from the end of one sleep to the start of the next") {
            if let awake {
                sentence("\(name) was usually awake for \(Format.duration(awake.low)) to \(Format.duration(awake.high)) between daytime sleeps, about \(Format.duration(awake.median)) in the middle.")
                Chart {
                    ForEach(awake.stretches) { stretch in
                        PointMark(
                            x: .value("Woke up", Self.dayClockDate(stretch.start)),
                            y: .value("Minutes awake", stretch.duration / 60)
                        )
                        .foregroundStyle(ActivityKind.sleep.color.opacity(0.7))
                        .accessibilityLabel("Woke at \(stretch.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .accessibilityValue("Awake \(Format.duration(stretch.duration))")
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxisLabel("Minutes")
                .frame(height: 140)
                Text("Each dot is one awake stretch, placed at the time of day \(name) woke up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                notEnough("Log a few days of naps with a start and an end to see awake stretches.")
            }
        }
    }

    // MARK: Diapers

    private func diaperCard(_ diapers: PatternFinder.DiaperTimes?) -> some View {
        Card("Busiest diaper times", subtitle: "Changes logged in each hour, last \(range.title)") {
            if let diapers {
                if diapers.busiest.isEmpty {
                    sentence("Diaper changes have been spread through the day.")
                } else {
                    let windows = diapers.busiest.map {
                        "between \(Self.hourText($0)) and \(Self.hourText(($0 + 2) % 24))"
                    }
                    sentence("Diaper changes were most often logged \(windows.joined(separator: ", and again ")).")
                }
                let hours = diapers.byHour.indices.map { hour in
                    HourCount(date: Self.dayClockDate(minuteOfDay: hour * 60), count: diapers.byHour[hour])
                }
                Chart {
                    ForEach(hours) { bin in
                        BarMark(
                            x: .value("Hour", bin.date, unit: .hour),
                            y: .value("Changes", bin.count)
                        )
                        .foregroundStyle(ActivityKind.diaper.color.gradient)
                        .cornerRadius(2)
                        .accessibilityLabel(bin.date.formatted(.dateTime.hour()))
                        .accessibilityValue(Format.plural(bin.count, "change"))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 120)
            } else {
                notEnough("Log a few more diaper changes to see the busiest times.")
            }
        }
    }

    // MARK: Helpers

    private func sentence(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func notEnough(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// A clock time on today's date, for charts that only care about the time of day.
    private static func dayClockDate(minuteOfDay: Int) -> Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minuteOfDay * 60))
    }

    private static func dayClockDate(_ date: Date) -> Date {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return dayClockDate(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// A clock time on tonight's timeline, so 11 PM comes before 2 AM.
    private static func nightClockDate(_ minuteOfDay: Int) -> Date {
        let date = dayClockDate(minuteOfDay: minuteOfDay)
        return minuteOfDay < 12 * 60 ? date.addingTimeInterval(86_400) : date
    }

    /// "2:30 AM".
    static func clockText(_ minuteOfDay: Int) -> String {
        dayClockDate(minuteOfDay: minuteOfDay).formatted(date: .omitted, time: .shortened)
    }

    /// "7 AM".
    static func hourText(_ hour: Int) -> String {
        dayClockDate(minuteOfDay: hour * 60).formatted(.dateTime.hour())
    }
}

/// How many times something happened in one hour, for an hour-by-hour chart.
private struct HourCount: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

/// The average gap between feeds, by day or night.
private struct GapBar: Identifiable {
    let label: String
    let hours: Double
    var id: String { label }
}
