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

                Text("What \(name)'s log shows over the last \(range.title). Night is \(Self.hourText(21)) to \(Self.hourText(7)). Times nobody logged are left out, so a gap in the log isn't read as a long time between feeds.", comment: "The baby's name, the range (7 days), then the hours night starts and ends: 9 PM, 7 AM")
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
                    sentence(String(localized: "There's no regular wake-up time yet. Night wake-ups have been at different times."))
                } else {
                    let times = wakes.usualTimes.map { String(localized: "around \(Self.clockText($0.minuteOfDay))", comment: "A time of night, in a list: around 2:30 AM") }
                    sentence(String(localized: "\(name) usually wakes \(times.formatted(.list(type: .and))).", comment: "The baby's name, then a list of times: around 11 PM and around 3 AM"))
                    // By position: two usual times can round to the same quarter hour.
                    ForEach(Array(wakes.usualTimes.enumerated()), id: \.offset) { item in
                        HStack {
                            Text("Around \(Self.clockText(item.element.minuteOfDay))")
                            Spacer()
                            Group {
                                if wakes.nights == 1 {
                                    Text("\(item.element.nights) of 1 night")
                                } else {
                                    Text("\(item.element.nights) of \(wakes.nights) nights")
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
                Group {
                    if wakes.nights == 1 {
                        Text("About \(decimal(wakes.averagePerNight)) wake-ups a night, over 1 night with entries.")
                    } else {
                        Text("About \(decimal(wakes.averagePerNight)) wake-ups a night, over \(wakes.nights) nights with entries.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                nightChart(wakes.allWakes)
            } else {
                notEnough(String(localized: "Log a few nights of feeds and sleep to see when \(name) usually wakes."))
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
                .accessibilityValue(String(localized: "\(bin.count) wake-ups"))
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
                    gaps.day.map { String(localized: "During the day, feeds were about \(Format.duration($0)) apart.") },
                    gaps.night.map { String(localized: "At night, about \(Format.duration($0)).", comment: "How far apart night feeds were: At night, about 3h 10m.") },
                ].compactMap { $0 }
                sentence(parts.joined(separator: " "))
                let bars = [
                    gaps.day.map { GapBar(label: String(localized: "Day"), hours: $0 / 3600) },
                    gaps.night.map { GapBar(label: String(localized: "Night"), hours: $0 / 3600) },
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
                notEnough(String(localized: "Log a few more feeds to see how far apart they are."))
            }
        }
    }

    // MARK: Sleep

    private func sleepCard(_ sleep: PatternFinder.LongestSleep?) -> some View {
        Card("Longest sleep", subtitle: "The longest stretch each day (days run 7 AM to 7 AM)") {
            if let sleep {
                let start = sleep.longest.day.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                let longest = String(localized: "The longest stretch was \(Format.duration(sleep.longest.duration)), starting \(start).", comment: "A duration, then a day and time: starting Tue 9:40 PM")
                let trend = trendText(sleep.trend)
                sentence(trend.isEmpty ? longest : longest + " " + trend)
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
                notEnough(String(localized: "Log sleep with a start and an end for a few days to see the longest stretches."))
            }
        }
    }

    private func trendText(_ trend: PatternFinder.Trend?) -> String {
        switch trend {
        case .longer: return String(localized: "The longest stretch has been getting longer.")
        case .steady: return String(localized: "It's been about the same from day to day.")
        case .shorter: return String(localized: "It's been a little shorter lately.")
        case nil: return ""
        }
    }

    // MARK: Awake

    private func awakeCard(_ awake: PatternFinder.AwakeStretches?) -> some View {
        Card("Awake between sleeps", subtitle: "Daytime wake-ups, from the end of one sleep to the start of the next") {
            if let awake {
                sentence(String(localized: "\(name) was usually awake for \(Format.duration(awake.low)) to \(Format.duration(awake.high)) between daytime sleeps, about \(Format.duration(awake.median)) in the middle.", comment: "The baby's name, then three durations: 1h 10m to 2h, about 1h 30m"))
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
                notEnough(String(localized: "Log a few days of naps with a start and an end to see awake stretches."))
            }
        }
    }

    // MARK: Diapers

    private func diaperCard(_ diapers: PatternFinder.DiaperTimes?) -> some View {
        Card("Busiest diaper times", subtitle: "Changes logged in each hour, last \(range.title)") {
            if let diapers {
                if diapers.busiest.isEmpty {
                    sentence(String(localized: "Diaper changes have been spread through the day."))
                } else {
                    sentence(Self.busiestText(diapers.busiest))
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
                        .accessibilityValue(String(localized: "\(bin.count) changes", comment: "Diaper changes"))
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
                notEnough(String(localized: "Log a few more diaper changes to see the busiest times."))
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

    /// "Diaper changes were most often logged between 7 AM and 9 AM, and again between 6 PM and 8 PM.",
    /// for the one or two busiest two-hour windows.
    static func busiestText(_ busiest: [Int]) -> String {
        let first = busiest.first ?? 0
        let from = hourText(first)
        let to = hourText((first + 2) % 24)
        guard busiest.count > 1 else {
            return String(localized: "Diaper changes were most often logged between \(from) and \(to).", comment: "Two clock hours: 7 AM, 9 AM")
        }
        let second = busiest[1]
        return String(
            localized: "Diaper changes were most often logged between \(from) and \(to), and again between \(hourText(second)) and \(hourText((second + 2) % 24)).",
            comment: "Two windows of two clock hours each: 7 AM, 9 AM, then 6 PM, 8 PM"
        )
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
