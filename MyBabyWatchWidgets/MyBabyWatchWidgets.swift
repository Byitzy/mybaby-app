import SwiftUI
import WidgetKit

/// The watch face complications: time since the last feed (circular and inline), and the last feed and
/// diaper (rectangular).
///
/// They read the `WatchContext` the watch app keeps in its App Group (Shared/WatchContext.swift); the watch
/// app reloads them whenever a new one arrives from the iPhone or after a tap. Tapping one opens the app.
@main
struct MyBabyWatchWidgets: WidgetBundle {
    var body: some Widget {
        LastFeedComplication()
    }
}

struct LastFeedComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyBabyWatchLastFeed", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Last feed")
        .description("How long ago baby last ate, and the last diaper.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct ComplicationEntry: TimelineEntry {
    let date: Date
    /// `nil` before the watch has heard from the iPhone, or before a baby was added.
    let snapshot: WidgetSnapshot?
}

/// Entries every 5 minutes for the next 4 hours, so "2h 10m" moves on without the app.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .complicationExample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let snapshot = WatchContext.load()?.snapshot
        completion(ComplicationEntry(date: .now, snapshot: snapshot ?? (context.isPreview ? .complicationExample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date.now
        let snapshot = WatchContext.load()?.snapshot
        let entries = (0...48).map { step in
            ComplicationEntry(date: now.addingTimeInterval(Double(step) * 5 * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    /// Sample data for the watch face editor.
    static var complicationExample: WidgetSnapshot {
        let now = Date.now
        var snapshot = WidgetSnapshot(babyName: "Baby")
        snapshot.lastFeed = Feed(
            date: now.addingTimeInterval(-(2 * 3600 + 10 * 60)),
            title: "Bottle (formula)",
            shortTitle: "Formula",
            emoji: "🍼",
            detail: "120 ml"
        )
        snapshot.lastDiaper = Diaper(date: now.addingTimeInterval(-45 * 60), title: "Pee", emoji: "💧")
        return snapshot
    }
}

// MARK: - Views

struct ComplicationView: View {
    @Environment(\.widgetFamily) var family

    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    private var isFeeding: Bool { snapshot?.feedingTimer != nil }

    /// "🍼" over "2h 10m".
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(isFeeding ? "🤱" : "🍼")
                    .font(.body)
                    .accessibilityHidden(true)
                Text(circularValue)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedVoiceOver)
    }

    /// "🍼 2h 10m ago".
    private var inline: some View {
        Text("\(isFeeding ? "🤱" : "🍼") \(feedText)")
            .accessibilityLabel(feedVoiceOver)
    }

    /// The last feed and the last diaper, or sleeping / breastfeeding now.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(isFeeding ? "🤱" : "🍼") \(feedText)")
                .font(.headline)
                .accessibilityLabel(feedVoiceOver)
            if let feed = snapshot?.lastFeed, !isFeeding {
                Text(feed.detail.isEmpty ? feed.shortTitle : "\(feed.shortTitle) · \(feed.detail)")
                    .foregroundStyle(.secondary)
            }
            if let diaper = snapshot?.lastDiaper {
                Text("\(diaper.emoji) \(ComplicationFormat.ago(diaper.date, now: entry.date)) · \(diaper.title)")
                    .accessibilityLabel("Last diaper \(ComplicationFormat.spoken(entry.date.timeIntervalSince(diaper.date))) ago, \(diaper.title)")
            }
            if let start = snapshot?.sleepStart {
                Text("😴 Asleep \(ComplicationFormat.short(entry.date.timeIntervalSince(start)))")
                    .accessibilityLabel("Asleep for \(ComplicationFormat.spoken(entry.date.timeIntervalSince(start)))")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Text

    private var circularValue: String {
        guard let snapshot else { return "—" }
        if let timer = snapshot.feedingTimer {
            return ComplicationFormat.short(timer.totalSeconds(at: entry.date))
        }
        guard let feed = snapshot.lastFeed else { return "—" }
        let seconds = entry.date.timeIntervalSince(feed.date)
        return seconds < 60 ? "Now" : ComplicationFormat.short(seconds)
    }

    private var feedText: String {
        guard let snapshot else { return "Open MyBaby" }
        if let timer = snapshot.feedingTimer {
            return "Feeding \(ComplicationFormat.short(timer.totalSeconds(at: entry.date))) · \(timer.side.title)"
        }
        guard let feed = snapshot.lastFeed else { return "No feed yet" }
        return ComplicationFormat.ago(feed.date, now: entry.date)
    }

    private var feedVoiceOver: String {
        guard let snapshot else { return "Open MyBaby on your iPhone to connect" }
        if let timer = snapshot.feedingTimer {
            return "Breastfeeding for \(ComplicationFormat.spoken(timer.totalSeconds(at: entry.date))), \(timer.side.title) side"
        }
        guard let feed = snapshot.lastFeed else { return "No feed logged yet" }
        let seconds = entry.date.timeIntervalSince(feed.date)
        if seconds < 60 { return "Last feed just now, \(feed.shortTitle)" }
        return "Last feed \(ComplicationFormat.spoken(seconds)) ago, \(feed.shortTitle)"
    }
}

// MARK: - Formatting

/// Like the iPhone widgets' `WidgetFormat`.
enum ComplicationFormat {
    /// "45m", "2h 10m".
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// "2h 10m ago", or "Just now".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "Just now" : "\(short(seconds)) ago"
    }

    /// "2 hours, 10 minutes", for VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? short(seconds)
    }
}
