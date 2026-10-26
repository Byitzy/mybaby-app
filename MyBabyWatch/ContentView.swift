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
        // Why a medicine on the allergy list wasn't logged.
        .alert("Not logged", isPresented: noticeBinding) {
            Button("OK") { store.dismissNotice() }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { store.notice != nil }, set: { if !$0 { store.dismissNotice() } })
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
                    title: feed.detail.isEmpty
                        ? String(localized: "Last feed · \(feed.shortTitle)", comment: "Watch. What the feed was, e.g. Formula")
                        : String(localized: "Last feed · \(feed.shortTitle) · \(feed.detail)", comment: "Watch. First: what the feed was, e.g. Formula; second: e.g. 120 ml"),
                    since: feed.date
                )
            } else {
                StatusRow(emoji: "🍼", title: String(localized: "No feed logged yet"), since: nil)
            }

            if let diaper = snapshot.lastDiaper {
                StatusRow(
                    emoji: diaper.emoji,
                    title: String(localized: "Last diaper · \(diaper.title)", comment: "Watch. What it was, e.g. Pee"),
                    since: diaper.date
                )
            } else {
                StatusRow(emoji: "🧷", title: String(localized: "No diaper logged yet"), since: nil)
            }

            if let start = snapshot.sleepStart {
                StatusRow(emoji: "😴", title: String(localized: "Asleep for", comment: "Watch: over how long the baby has been asleep"), since: start, ago: false)
            } else if let wake = snapshot.lastWake {
                StatusRow(emoji: "🌤️", title: String(localized: "Awake for", comment: "Watch: over how long the baby has been awake"), since: wake, ago: false)
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
                    Group {
                        if ago {
                            Text("\(since, style: .relative) ago", comment: "Watch: a time that counts up, e.g. 45 min ago")
                        } else {
                            Text(since, style: .relative)
                        }
                    }
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
                BigButton(
                    emoji: "🌤️",
                    title: String(localized: "Woke up", comment: "Watch button: end the sleep"),
                    tint: .indigo,
                    label: String(localized: "Baby woke up, end the sleep")
                ) {
                    store.log(.endSleep, message: String(localized: "Sleep ended"))
                }
            } else {
                BigButton(
                    emoji: "😴",
                    title: String(localized: "Sleep", comment: "Watch button: start a sleep"),
                    tint: .indigo,
                    label: String(localized: "Baby fell asleep, start a sleep")
                ) {
                    store.log(.startSleep, message: String(localized: "Sleep started"))
                }
            }

            BigLink(
                emoji: "🍼",
                title: String(localized: "Bottle", comment: "Watch button: log a bottle"),
                tint: .orange,
                label: String(localized: "Log a bottle")
            ) {
                BottleView(context: context)
            }

            BigLink(
                emoji: "💊",
                title: String(localized: "Medicine", comment: "Watch button: log a medicine"),
                tint: .purple,
                label: String(localized: "Log a medicine")
            ) {
                MedicineView(medicines: context.medicines, babyName: snapshot.babyName)
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
                        let isSuggested = side == context.suggestedSide
                        BigButton(
                            emoji: isSuggested ? "⭐️" : "🤱",
                            title: side == .left
                                ? String(localized: "Start left", comment: "Watch button: start breastfeeding on the left side")
                                : String(localized: "Start right", comment: "Watch button: start breastfeeding on the right side"),
                            tint: .pink,
                            label: Self.startLabel(side, suggested: isSuggested)
                        ) {
                            store.log(
                                .timerStart(side),
                                message: side == .left
                                    ? String(localized: "Timer started, left")
                                    : String(localized: "Timer started, right")
                            )
                        }
                    }
                }
                if let suggested = context.suggestedSide {
                    (suggested == .left ? Text("⭐️ Left is suggested from the last feed") : Text("⭐️ Right is suggested from the last feed"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            suggested == .left
                                ? Text("Left side is suggested from the last feed")
                                : Text("Right side is suggested from the last feed")
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func running(_ timer: FeedingTimerState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.timerTitle(timer))
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
                    .accessibilityLabel(side.sideTitle)
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
            let toLeft = timer.side.other == .left
            BigButton(
                emoji: "🔄",
                title: toLeft
                    ? String(localized: "Switch to left", comment: "Watch button: switch breastfeeding to the left side")
                    : String(localized: "Switch to right", comment: "Watch button: switch breastfeeding to the right side"),
                tint: .pink,
                label: toLeft ? String(localized: "Switch to the left side") : String(localized: "Switch to the right side")
            ) {
                store.log(.timerSwitch, message: toLeft ? String(localized: "Now on the left") : String(localized: "Now on the right"))
            }
        } else {
            let onLeft = timer.side == .left
            BigButton(
                emoji: "▶️",
                title: onLeft
                    ? String(localized: "Resume left", comment: "Watch button: resume breastfeeding on the left side")
                    : String(localized: "Resume right", comment: "Watch button: resume breastfeeding on the right side"),
                tint: .pink,
                label: onLeft ? String(localized: "Resume on the left side") : String(localized: "Resume on the right side")
            ) {
                store.log(.timerStart(timer.side), message: String(localized: "Timer resumed"))
            }
        }
        BigButton(
            emoji: "✅",
            title: String(localized: "Stop & save", comment: "Watch button: stop the breastfeeding timer and save the feed"),
            tint: .green,
            label: String(localized: "Stop the timer and save the feed")
        ) {
            store.log(.timerStop, message: String(localized: "Breastfeeding saved"))
        }
    }

    /// What VoiceOver reads on a Start button: whole sentences for each side.
    private static func startLabel(_ side: BreastSide, suggested: Bool) -> String {
        switch (side, suggested) {
        case (.left, true): return String(localized: "Start breastfeeding on the left side, suggested")
        case (.left, false): return String(localized: "Start breastfeeding on the left side")
        case (.right, true): return String(localized: "Start breastfeeding on the right side, suggested")
        case (.right, false): return String(localized: "Start breastfeeding on the right side")
        }
    }

    /// "🤱 Feeding on the left", or "⏸ Paused on the left".
    private static func timerTitle(_ timer: FeedingTimerState) -> String {
        switch (timer.isRunning, timer.side) {
        case (true, .left): return String(localized: "🤱 Feeding on the left")
        case (true, .right): return String(localized: "🤱 Feeding on the right")
        case (false, .left): return String(localized: "⏸ Paused on the left")
        case (false, .right): return String(localized: "⏸ Paused on the right")
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
