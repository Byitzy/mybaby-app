import AppIntents
import SwiftUI
import WidgetKit

/// The MyBabyWidgets extension: Home Screen and Lock Screen widgets, and the Live Activities.
///
/// The extension never opens the database. Widgets read the `WidgetSnapshot` the app writes to the App
/// Group, and Live Activities show what the app sends them. Buttons run their intents in the app
/// (see Shared/ButtonIntents.swift).
@main
struct MyBabyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        LockScreenWidget()
        FeedingLiveActivity()
        SleepLiveActivity()
        ListeningLiveActivity()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// `nil` before the app has written one, e.g. before a baby was added.
    let snapshot: WidgetSnapshot?
    /// The baby picked in Edit Widget (`Baby.uuid`), or `nil` to follow the app.
    var babyID: String? = nil
    /// What to show, in order, as picked in Edit Widget.
    var stats: [WidgetStat] = []
    var buttons: [WidgetButton] = []

    /// The baby to show. `nil` without a snapshot.
    var baby: WidgetSnapshot.BabySnapshot? { snapshot?.baby(babyID) }
}

/// Home Screen widgets: reads the app's snapshot, for the baby and details picked in Edit Widget.
struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(
            date: .now,
            snapshot: .example,
            stats: StatusWidgetIntent.defaultStats,
            buttons: StatusWidgetIntent.defaultButtons
        )
    }

    func snapshot(for configuration: StatusWidgetIntent, in context: Context) async -> SnapshotEntry {
        let snapshot = WidgetSnapshot.load() ?? (context.isPreview ? .example : nil)
        return entry(at: .now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: StatusWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let snapshot = WidgetSnapshot.load()
        return SnapshotTimeline.make(snapshot: snapshot, babyID: configuration.baby?.babyID) { date in
            entry(at: date, snapshot: snapshot, configuration: configuration)
        }
    }

    private func entry(at date: Date, snapshot: WidgetSnapshot?, configuration: StatusWidgetIntent) -> SnapshotEntry {
        SnapshotEntry(
            date: date,
            snapshot: snapshot,
            babyID: configuration.baby?.babyID,
            stats: configuration.stats,
            buttons: configuration.buttons
        )
    }
}

/// Lock Screen widgets: the same, with one detail.
struct LockScreenProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .example, stats: [.lastFeed])
    }

    func snapshot(for configuration: LockScreenWidgetIntent, in context: Context) async -> SnapshotEntry {
        let snapshot = WidgetSnapshot.load() ?? (context.isPreview ? .example : nil)
        return entry(at: .now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: LockScreenWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let snapshot = WidgetSnapshot.load()
        return SnapshotTimeline.make(snapshot: snapshot, babyID: configuration.baby?.babyID) { date in
            entry(at: date, snapshot: snapshot, configuration: configuration)
        }
    }

    private func entry(at date: Date, snapshot: WidgetSnapshot?, configuration: LockScreenWidgetIntent) -> SnapshotEntry {
        SnapshotEntry(
            date: date,
            snapshot: snapshot,
            babyID: configuration.baby?.babyID,
            stats: [configuration.stat.stat]
        )
    }
}

/// The app reloads the widgets whenever the snapshot changes; between those, a timeline only needs
/// entries for things that change with time alone: every few minutes for the Lock Screen's "2h 10m"
/// (Home Screen widgets count with `Text(_:style: .relative)`), each night-shift handoff for who's on
/// duty, when a medicine's next dose is allowed, when cry alerts stop listening by themselves, and
/// midnight for the "today" counts.
enum SnapshotTimeline {
    static func make(
        snapshot: WidgetSnapshot?,
        babyID: String?,
        now: Date = .now,
        entry: (Date) -> SnapshotEntry
    ) -> Timeline<SnapshotEntry> {
        let horizon = now.addingTimeInterval(4 * 3600)
        var dates = Set((1...48).map { now.addingTimeInterval(Double($0) * 5 * 60) })

        var boundaries: [Date] = []
        if let snapshot {
            for shift in snapshot.shifts {
                boundaries += [shift.start, shift.end]
            }
            let baby = snapshot.baby(babyID)
            if let next = baby.nextDose?.date { boundaries.append(next) }
            if let next = baby.lastMedicine?.nextAllowed { boundaries.append(next) }
            // The mic badge goes away at the stop time, even if the app can't reload the widgets then.
            if let stop = snapshot.listening?.stopsAt { boundaries.append(stop) }
            let calendar = Calendar.current
            if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                boundaries.append(midnight)
            }
        }
        for boundary in boundaries where boundary > now && boundary < horizon {
            dates.insert(boundary)
        }

        let entries = [entry(now)] + dates.sorted().map { entry($0) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

extension WidgetSnapshot {
    /// Sample data for the widget gallery.
    static var example: WidgetSnapshot {
        let now = Date.now
        var snapshot = WidgetSnapshot(babyName: String(localized: "Baby", comment: "A baby without a name"))
        snapshot.lastFeed = Feed(
            date: now.addingTimeInterval(-(2 * 3600 + 10 * 60)),
            title: String(localized: "Bottle (formula)"),
            shortTitle: String(localized: "Formula", comment: "A bottle of formula, short"),
            emoji: "🍼",
            detail: WidgetFormat.milliliters(120)
        )
        snapshot.lastDiaper = Diaper(
            date: now.addingTimeInterval(-45 * 60),
            title: String(localized: "Pee", comment: "A wet diaper, short"),
            emoji: "💧"
        )
        snapshot.lastWake = now.addingTimeInterval(-65 * 60)

        var baby = snapshot.baby(nil)
        baby.countedDay = Calendar.current.startOfDay(for: now)
        baby.feedsToday = 5
        baby.diapersToday = 4
        baby.lastPumping = BabySnapshot.Pumping(date: now.addingTimeInterval(-3 * 3600), amountText: WidgetFormat.milliliters(150))
        baby.stash = BabySnapshot.Stash(totalText: WidgetFormat.milliliters(840), bagCount: 6)
        baby.usualBottle = BabySnapshot.Bottle(isFormula: true, ml: 120, amountText: WidgetFormat.milliliters(120))
        snapshot.babies = [baby]
        return snapshot
    }
}

// MARK: - Formatting

enum WidgetFormat {
    /// "45m", "2h 10m", like the app's `Format.duration`, in the words of the iPhone's language
    /// ("2 h 10 min" in French). Whole minutes, rounded down.
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        return shortFormatter.string(from: TimeInterval(totalMinutes * 60)) ?? "\(totalMinutes)"
    }

    private static let shortFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    /// "2h 10m ago", or "Just now".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return String(localized: "Just now", comment: "When something was logged, under a minute ago")
        }
        let duration = short(seconds)
        return String(localized: "\(duration) ago", comment: "How long ago something was logged, short, e.g. 2h 10m ago")
    }

    /// "120 ml", for the widget gallery's sample.
    static func milliliters(_ value: Int) -> String {
        String(localized: "\(value) ml", comment: "An amount in milliliters")
    }

    /// "4:10 AM", or "Tue 4:10 AM" when it's not the same day as `now`.
    static func time(_ date: Date, now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
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

extension WidgetSnapshot.Shift {
    /// Pink for parent 1, blue for parent 2, as in the app.
    var color: Color { isParent1 ? .pink : .blue }
}

/// Shown until the app has written a snapshot.
struct NoBabyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("👶")
                .font(.title)
                .accessibilityHidden(true)
            Text("Open MyBaby to add your baby")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}
