import SwiftUI

/// The watch app's one screen: who's on duty and how long since the last feed, diaper and sleep, then
/// big buttons to log, and the breastfeeding timer. Scroll with the Digital Crown.
struct ContentView: View {
    @Environment(WatchStore.self) var store
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        // Once a minute: switches to the night colors and keeps "Last synced" and who's on duty current.
        // The times since the last feed and so on count by themselves (`Text(_:style: .relative)`).
        TimelineView(.everyMinute) { timeline in
            let isNight = WatchTheme.isNight(at: timeline.date, snapshot: store.context?.snapshot)
            NavigationStack {
                HomeView(now: timeline.date)
            }
            .tint(isNight ? WatchTheme.night : Color.accentColor)
            .environment(\.isNightMode, isNight)
        }
        .overlay(alignment: .bottom) {
            if let confirmation = store.confirmation {
                ConfirmationBanner(confirmation: confirmation)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.requestSync()
            }
        }
    }
}

struct HomeView: View {
    @Environment(WatchStore.self) var store

    let now: Date

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let context = store.context, let snapshot = context.snapshot {
                    // A breastfeeding timer going on is what matters most right now.
                    if snapshot.feedingTimer != nil {
                        FeedingSection(context: context, snapshot: snapshot)
                    }
                    StatusSection(snapshot: snapshot, now: now)
                    SyncStatusView(now: now)
                    QuickLogGrid(context: context, snapshot: snapshot)
                    if snapshot.feedingTimer == nil {
                        FeedingSection(context: context, snapshot: snapshot)
                    }
                } else {
                    EmptyStateView(hasContext: store.context != nil)
                    SyncStatusView(now: now)
                }
            }
        }
        .navigationTitle(store.context?.snapshot?.babyName ?? "MyBaby")
    }
}

// MARK: - Status

/// On duty, last feed, last diaper, and asleep or awake for.
struct StatusSection: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let shift = snapshot.shift(at: now) {
                Text("🌙 \(shift.parentName) on duty")
                    .font(.footnote.weight(.semibold))
                    // The name says who; the color only matches the app.
                    .foregroundStyle(shift.isParent1 ? Color.pink : Color.blue)
                    .accessibilityLabel("\(shift.parentName) is on night duty")
            }

            if let feed = snapshot.lastFeed {
                StatusRow(
                    emoji: feed.emoji,
                    title: feed.detail.isEmpty ? "Last feed · \(feed.shortTitle)" : "Last feed · \(feed.shortTitle) · \(feed.detail)",
                    since: feed.date
                )
            } else {
                StatusRow(emoji: "🍼", title: "No feed logged yet", since: nil)
            }

            if let diaper = snapshot.lastDiaper {
                StatusRow(emoji: diaper.emoji, title: "Last diaper · \(diaper.title)", since: diaper.date)
            } else {
                StatusRow(emoji: "🧷", title: "No diaper logged yet", since: nil)
            }

            if let start = snapshot.sleepStart {
                StatusRow(emoji: "😴", title: "Asleep for", since: start, ago: false)
            } else if let wake = snapshot.lastWake {
                StatusRow(emoji: "🌤️", title: "Awake for", since: wake, ago: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A caption ("Last diaper · Pee") over the time since ("45 min ago"), counting by itself.
/// VoiceOver reads both together, without the emoji.
struct StatusRow: View {
    let emoji: String
    let title: String
    let since: Date?
    var ago = true

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(emoji)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let since {
                    (Text(since, style: .relative) + Text(ago ? " ago" : ""))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quick log

/// Wet, Dirty, Both, Sleep / Woke up, Bottle and Medicine.
struct QuickLogGrid: View {
    @Environment(WatchStore.self) var store
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    let context: WatchContext
    let snapshot: WidgetSnapshot

    /// Two buttons a row, or one with the largest text sizes so titles don't get cut off.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(WatchCommand.Diaper.allCases, id: \.self) { diaper in
                BigButton(emoji: diaper.buttonEmoji, title: diaper.buttonTitle, tint: .teal, label: diaper.accessibilityLabel) {
                    store.log(.logDiaper(diaper), message: diaper.confirmation)
                }
            }

            if snapshot.isSleeping {
                BigButton(emoji: "🌤️", title: "Woke up", tint: .indigo, label: "Baby woke up, end the sleep") {
                    store.log(.endSleep, message: "Sleep ended")
                }
            } else {
                BigButton(emoji: "😴", title: "Sleep", tint: .indigo, label: "Baby fell asleep, start a sleep") {
                    store.log(.startSleep, message: "Sleep started")
                }
            }

            BigLink(emoji: "🍼", title: "Bottle", tint: .orange, label: "Log a bottle") {
                BottleView(context: context)
            }

            BigLink(emoji: "💊", title: "Medicine", tint: .purple, label: "Log a medicine") {
                MedicineView(medicines: context.medicines)
            }
        }
    }
}

// MARK: - Breastfeeding

/// Start left or right, or while the timer runs: the time on each side, Switch, and Stop & save.
struct FeedingSection: View {
    @Environment(WatchStore.self) var store

    let context: WatchContext
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let timer = snapshot.feedingTimer {
                running(timer)
            } else {
                Text("Breastfeed")
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(BreastSide.allCases) { side in
                        BigButton(
                            emoji: side == context.suggestedSide ? "⭐️" : "🤱",
                            title: "Start \(side.title.lowercased())",
                            tint: .pink,
                            label: side == context.suggestedSide
                                ? "Start breastfeeding on the \(side.title.lowercased()) side, suggested"
                                : "Start breastfeeding on the \(side.title.lowercased()) side"
                        ) {
                            store.log(.timerStart(side), message: "Timer started, \(side.title.lowercased())")
                        }
                    }
                }
                if let suggested = context.suggestedSide {
                    Text("⭐️ \(suggested.title) is suggested from the last feed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(suggested.title) side is suggested from the last feed")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func running(_ timer: FeedingTimerState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timer.isRunning ? "🤱 Feeding on the \(timer.side.title.lowercased())" : "⏸ Paused on the \(timer.side.title.lowercased())")
                .font(.footnote.weight(.semibold))
            FeedingClockText(state: timer)
                .font(.system(.title, design: .rounded).weight(.semibold))
            HStack(spacing: 10) {
                ForEach(BreastSide.allCases) { side in
                    HStack(spacing: 3) {
                        Text(side.letter)
                            .foregroundStyle(.secondary)
                        FeedingClockText(state: timer, side: side)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(side.title) side")
                }
            }
            .font(.caption)
            if snapshot.babyCount > 1 {
                Text("For \(timer.babyName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if timer.isRunning {
            BigButton(
                emoji: "🔄",
                title: "Switch to \(timer.side.other.title.lowercased())",
                tint: .pink,
                label: "Switch to the \(timer.side.other.title.lowercased()) side"
            ) {
                store.log(.timerSwitch, message: "Now on the \(timer.side.other.title.lowercased())")
            }
        } else {
            BigButton(
                emoji: "▶️",
                title: "Resume \(timer.side.title.lowercased())",
                tint: .pink,
                label: "Resume on the \(timer.side.title.lowercased()) side"
            ) {
                store.log(.timerStart(timer.side), message: "Timer resumed")
            }
        }
        BigButton(emoji: "✅", title: "Stop & save", tint: .green, label: "Stop the timer and save the feed") {
            store.log(.timerStop, message: "Breastfeeding saved")
        }
    }
}

// MARK: - Empty

/// Before the iPhone has sent anything, or before a baby has been added.
struct EmptyStateView: View {
    /// Whether the iPhone has been heard from (it just has no baby yet).
    let hasContext: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("👶")
                .font(.largeTitle)
                .accessibilityHidden(true)
            if hasContext {
                Text("Add your baby in MyBaby on your iPhone to start logging here.")
            } else {
                Text("Open MyBaby on your iPhone, with your watch nearby, to connect.")
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
