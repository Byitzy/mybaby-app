import CoreData
import SwiftUI

struct TodayView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var baby: Baby
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()

    @FetchRequest private var todaysActivities: FetchedResults<Activity>
    @FetchRequest private var lastFeeding: FetchedResults<Activity>
    @FetchRequest private var lastDiaper: FetchedResults<Activity>
    @FetchRequest private var lastSleep: FetchedResults<Activity>
    @FetchRequest private var ongoingSleep: FetchedResults<Activity>
    /// For the baby switcher in the header.
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>

    @State private var editorTarget: EditorTarget?
    @State private var showingDiaperOptions = false
    @State private var addingBaby = false
    @State private var toast: Toast?
    @State private var showingFeedOptions = false
    @State private var showingBreastfeedingTimer = false
    /// Catch up, or marking a gap as not tracked, from the "Nothing logged since…" card.
    @State private var coverageTarget: CoverageSheetTarget?
    /// Moves on every minute, so the "Nothing logged since…" card appears when a gap begins.
    @State private var now = Date.now
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 56
    private let feedingTimer = FeedingTimer.shared

    init(day: Date, baby: Baby) {
        self.baby = baby
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _todaysActivities = FetchRequest(fetchRequest: baby.entries(Activity.between(start, end)))
        _lastFeeding = FetchRequest(fetchRequest: baby.entries(Activity.latest(.feeding)))
        _lastDiaper = FetchRequest(fetchRequest: baby.entries(Activity.latest(.diaper)))
        _lastSleep = FetchRequest(fetchRequest: baby.entries(Activity.latest(.sleep)))
        _ongoingSleep = FetchRequest(fetchRequest: baby.entries(Activity.ongoingSleep))
    }

    var body: some View {
        NavigationStack {
            List {
                header

                if let sleep = ongoingSleep.first {
                    Section {
                        SleepingBanner(sleep: sleep) {
                            wakeUp(sleep)
                        } onFix: {
                            editorTarget = .edit(sleep)
                        }
                        .disabled(!canEditLog)
                    }
                }

                GapPromptSection(baby: baby, now: now, toast: $toast) { coverageTarget = $0 }

                DeviceOwnerPromptSection(baby: baby)
                // "How did the 2-month checkup go?", for a visit in the last 3 days.
                VisitRecapPromptSection(baby: baby, now: now)
                // "After Tuesday's shots" or "MMR was 9 days ago": what to look out for after a vaccine.
                VaccineFollowUpSection(baby: baby, now: now)
                // "Mavie is 3 months old today 🎉": a week or month summary is ready in the diary.
                DiaryReadyCard(baby: baby, now: now)

                if feedingTimer.isActive {
                    Section {
                        FeedingTimerCard(babyName: baby.displayName) {
                            showingBreastfeedingTimer = true
                        } onSaved: { feed in
                            feedingSaved(feed)
                        }
                    }
                }

                Section {
                    if nightPlan.isEnabled {
                        NavigationLink {
                            NightPlanView()
                                .readableContentWidth()
                        } label: {
                            NightDutyCard(plan: nightPlan)
                        }
                    }
                    NavigationLink {
                        CryMonitorView()
                            .readableContentWidth()
                    } label: {
                        CryAlertsRow()
                    }
                    MonitorStatusRows(baby: baby)
                }

                if usesTwoColumns {
                    sideBySideSection
                } else {
                    Section {
                        sinceLastRow(stacked: false)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                    Section("Quick log") {
                        if !canEditLog {
                            ViewOnlyBanner()
                                .tileStyle()
                        }
                        quickLogGrid
                            .disabled(!canEditLog)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                Section {
                    if todaysActivities.isEmpty {
                        Text("Nothing logged yet today. Tap a button above to start.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(todaysActivities) { activity in
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
                    }
                } header: {
                    SummaryHeader(title: "Today's log", summary: todaySummary, spokenSummary: todaySummaryForVoiceOver)
                }
            }
            .listStyle(.insetGrouped)
            // Wider than other lists on iPad, for the two columns of cards.
            .readableContentWidth(ReadableWidth.twoColumns)
            // ⌘N with a keyboard: pick what to log.
            .newEntryKeyboardShortcut(isEnabled: canEditLog) { kind in
                editorTarget = .new(kind)
            }
            .navigationTitle("Today")
            .sheet(item: $editorTarget) { target in
                ActivityEditorView(kind: target.kind, activity: target.activity, baby: baby)
            }
            .sheet(isPresented: $addingBaby) {
                AddBabyView()
            }
            .sheet(item: $coverageTarget) { target in
                CoverageSheet(target: target) { message in
                    toast = Toast(message: message)
                }
            }
            .task {
                while !Task.isCancelled {
                    now = .now
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .confirmationDialog("Diaper change", isPresented: $showingDiaperOptions, titleVisibility: .visible) {
                ForEach([DiaperType.wet, .dirty, .mixed, .dry]) { type in
                    Button("\(type.emoji) \(type.quickTitle)") { logDiaper(type) }
                }
                Button("Add color & details…") { editorTarget = .new(.diaper) }
            }
            .confirmationDialog("Feeding", isPresented: $showingFeedOptions, titleVisibility: .visible) {
                Button(feedingTimer.isActive ? "🤱 Open breastfeeding timer" : "🤱 Breastfeed · start timer") {
                    showingBreastfeedingTimer = true
                }
                Button("✏️ Log a feeding") { editorTarget = .new(.feeding) }
            }
            .sheet(isPresented: $showingBreastfeedingTimer) {
                BreastfeedingTimerView(baby: baby) { feed in
                    feedingSaved(feed)
                }
            }
            .toast($toast)
        }
    }

    // MARK: Sections

    /// The baby's name and age. Tapping it switches babies, or adds one.
    private var header: some View {
        Section {
            Menu {
                if babies.count > 1 {
                    ForEach(babies) { other in
                        Button {
                            Baby.select(other)
                        } label: {
                            if other == baby {
                                Label(other.displayName, systemImage: "checkmark")
                            } else {
                                Text(other.displayName)
                            }
                        }
                    }
                    Divider()
                }
                Button {
                    addingBaby = true
                } label: {
                    Label("Add a baby", systemImage: "plus")
                }
            } label: {
                headerContent
            }
            .accessibilityHint(babies.count > 1 ? "Switch to another baby, or add one" : "Add another baby")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
    }

    private var headerContent: some View {
        HStack(spacing: 14) {
            Text("👶")
                .font(.system(size: avatarSide * 0.6))
                .frame(width: avatarSide, height: avatarSide)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: 6) {
                    Text(baby.name)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    if babies.count > 1 {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                if let birthDate = baby.birthDate {
                    Text(Format.age(birthDate: birthDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // Under the name at the largest text sizes, so the row doesn't overflow.
                if dynamicTypeSize.isAccessibilitySize {
                    todayDate
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
                todayDate
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var todayDate: some View {
        Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    /// The baby's emoji circle, growing a little with the text size.
    private var avatarSide: CGFloat { min(avatarSize, 84) }

    /// On iPad (a regular width), the "time since" cards and the quick log sit side by side. In a
    /// compact width, such as Split View or Slide Over, and at the accessibility text sizes they stay
    /// one above the other, as on iPhone.
    private var usesTwoColumns: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    private func sinceLastRow(stacked: Bool) -> some View {
        SinceLastRow(
            feeding: lastFeeding.first,
            diaper: lastDiaper.first,
            sleep: lastSleep.first,
            unit: unit,
            baby: baby,
            stacked: stacked
        )
    }

    /// iPad: the "time since" cards on the left, the quick log on the right, each under its own header.
    private var sideBySideSection: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    columnHeader(String(localized: "Time since", comment: "Header over the time-since-last cards on iPad"))
                    sinceLastRow(stacked: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    columnHeader(String(localized: "Quick log"))
                    if !canEditLog {
                        ViewOnlyBanner()
                            .tileStyle()
                    }
                    quickLogGrid
                        .disabled(!canEditLog)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private var quickLogGrid: some View {
        let columns = dynamicTypeSize.gridColumns(3)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            QuickLogButton(
                emoji: "🍼",
                title: String(localized: "Feed", comment: "Quick log button: log a feeding"),
                voiceOverLabel: String(localized: "Log a feeding"),
                tint: ActivityKind.feeding.color
            ) {
                showingFeedOptions = true
            }
            QuickLogButton(
                emoji: "🧷",
                title: String(localized: "Diaper", comment: "Quick log button: log a diaper change"),
                voiceOverLabel: String(localized: "Log a diaper change"),
                tint: ActivityKind.diaper.color
            ) {
                showingDiaperOptions = true
            }
            if let sleep = ongoingSleep.first {
                QuickLogButton(
                    emoji: "🌤️",
                    title: String(localized: "Woke up", comment: "Button: the baby woke up, stops the sleep timer"),
                    voiceOverLabel: String(localized: "Baby woke up, stop the sleep timer"),
                    tint: ActivityKind.sleep.color
                ) {
                    wakeUp(sleep)
                }
            } else {
                QuickLogButton(
                    emoji: "😴",
                    title: String(localized: "Sleep", comment: "Quick log button: starts the sleep timer"),
                    voiceOverLabel: String(localized: "Start the sleep timer"),
                    tint: ActivityKind.sleep.color
                ) {
                    startSleep()
                }
            }
            QuickLogButton(
                emoji: "🛁",
                title: String(localized: "Bath", comment: "Quick log button: log a bath"),
                voiceOverLabel: String(localized: "Log a bath"),
                tint: ActivityKind.bath.color
            ) {
                insert(.bath, message: String(localized: "🛁 Bath logged"))
            }
            QuickLogButton(
                emoji: "💊",
                title: String(localized: "Medicine", comment: "Quick log button: log a medicine dose"),
                voiceOverLabel: String(localized: "Log medicine"),
                tint: ActivityKind.medication.color
            ) {
                editorTarget = .new(.medication)
            }
            QuickLogButton(
                emoji: "✏️",
                title: String(localized: "Past sleep", comment: "Quick log button: add a sleep that already ended"),
                voiceOverLabel: String(localized: "Add a past sleep"),
                tint: Palette.inactive
            ) {
                editorTarget = .new(.sleep)
            }
            QuickLogButton(
                emoji: "🫙",
                title: String(localized: "Pump", comment: "Quick log button: log a pumping session"),
                voiceOverLabel: String(localized: "Log a pumping session"),
                tint: ActivityKind.pumping.color
            ) {
                editorTarget = .new(.pumping)
            }
            QuickLogButton(
                emoji: "🌡️",
                title: String(localized: "Temp", comment: "Quick log button, short for temperature"),
                voiceOverLabel: String(localized: "Log a temperature"),
                tint: ActivityKind.temperature.color
            ) {
                editorTarget = .new(.temperature)
            }
        }
    }

    private var todaySummary: String {
        let feeds = todaysActivities.filter { $0.kind == .feeding }.count
        let diapers = todaysActivities.filter { $0.kind == .diaper }.count
        return "\(feeds) 🍼 · \(diapers) 🧷"
    }

    private var todaySummaryForVoiceOver: String {
        let feeds = todaysActivities.filter { $0.kind == .feeding }.count
        let diapers = todaysActivities.filter { $0.kind == .diaper }.count
        // One phrase per count, so each language has its own plurals.
        return [
            String(localized: "\(feeds) feedings", comment: "VoiceOver: how many feeds today"),
            String(localized: "\(diapers) diapers", comment: "VoiceOver: how many diaper changes today"),
        ].formatted(.list(type: .and, width: .narrow))
    }

    // MARK: Actions

    private var nightPlan: NightPlan { NightPlan(data: nightPlanData) }

    private func insert(_ kind: ActivityKind, message: String, configure: (Activity) -> Void = { _ in }) {
        let activity = Activity.create(kind, in: context)
        configure(activity)
        activity.caregiver = nightPlan.shift(at: activity.startDate)?.parent
        context.saveIfChanged()
        toast = Toast(message: message) { [context] in
            context.delete(activity)
            context.saveIfChanged()
        }
    }

    private func logDiaper(_ type: DiaperType) {
        insert(.diaper, message: type.loggedMessage) { $0.diaperType = type }
    }

    private func startSleep() {
        insert(.sleep, message: String(localized: "😴 Sleep timer started"))
    }

    private func wakeUp(_ sleep: Activity) {
        let end = Date.now
        sleep.endDate = end
        context.saveIfChanged()
        toast = Toast(message: "🌤️ Slept \(Format.duration(end.timeIntervalSince(sleep.startDate)))") { [context] in
            sleep.endDate = nil
            context.saveIfChanged()
        }
    }

    /// After the breastfeeding timer saved a feed: a confirmation with Undo.
    private func feedingSaved(_ feed: Activity) {
        toast = Toast(message: "🤱 Breastfeeding saved · \(feed.breastMinutes) min") { [context] in
            context.delete(feed)
            context.saveIfChanged()
            NotificationManager.refreshFeedingReminder(context: context)
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

// MARK: - Pieces

/// Whether the phone is listening for crying.
private struct CryAlertsRow: View {
    private let monitor = CryMonitor.shared

    var body: some View {
        HStack(spacing: Spacing.m) {
            EmojiBadge(emoji: monitor.cryStart != nil ? "😭" : "🎧", tint: monitor.isListening ? Palette.listening : Palette.inactive)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Cry alerts")
                    .font(.body.weight(.medium))
                // The words say it; crying is also in bold rather than only in orange.
                Text(subtitle)
                    .font(monitor.cryStart != nil ? Font.subheadline.weight(.semibold) : Font.subheadline)
                    .foregroundStyle(monitor.cryStart != nil ? Color.primary : Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if monitor.cryStart != nil { return String(localized: "Baby is crying") }
        return monitor.isListening
            ? String(localized: "Listening", comment: "Cry alerts are listening for crying")
            : String(localized: "Off · tap to listen tonight")
    }
}

/// Who's on night duty now, or tonight's plan during the day.
private struct NightDutyCard: View {
    let plan: NightPlan

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let tonight = plan.shifts(forNightOf: plan.nightDay(at: now))
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "🌙", tint: Palette.nightShift, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    if let current = tonight.first(where: { $0.contains(now) }) {
                        ParentTag(name: "\(plan.name(of: current.parent)) is on duty", color: current.parent.color)
                            .font(.headline)
                        Text(onDutyDetail(current, in: tonight, emoji: "😴 "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(onDutyDetail(current, in: tonight, emoji: ""))
                    } else {
                        Text("Tonight's shifts")
                            .font(.headline)
                        ForEach(tonight) { shift in
                            ParentTag(
                                name: "\(plan.name(of: shift.parent)) \(shift.start.formatted(date: .omitted, time: .shortened))–\(shift.end.formatted(date: .omitted, time: .shortened))",
                                color: shift.parent.color
                            )
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Until 2:00 AM · Sam is sleeping 😴 and takes over then". VoiceOver gets it without `emoji`.
    private func onDutyDetail(_ current: NightShift, in night: [NightShift], emoji: String) -> String {
        let until = current.end.formatted(date: .omitted, time: .shortened)
        let partner = plan.name(of: current.parent.other)
        if night.contains(where: { $0.start >= current.end }) {
            return String(
                localized: "Until \(until) · \(partner) is sleeping \(emoji)and takes over then",
                comment: "The third value is an emoji and a space, or nothing for VoiceOver"
            )
        }
        return String(
            localized: "Until \(until) · \(partner) is sleeping \(emoji)",
            comment: "The third value is an emoji and a space, or nothing for VoiceOver"
        ).trimmingCharacters(in: .whitespaces)
    }
}

private struct QuickLogButton: View {
    let emoji: String
    let title: String
    /// What VoiceOver reads instead of the emoji's name.
    let voiceOverLabel: String
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .subheadline) private var emojiSize: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 84

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: min(emojiSize, 48)))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, Spacing.s)
            .padding(.horizontal, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Radius.button).strokeBorder(tint.opacity(0.35)))
            // Dimmed when turned off, e.g. for view-only family.
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        // With a pointer on iPad, the button lights up under it, in its own rounded shape.
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Radius.button))
        .hoverEffect(.highlight)
        .accessibilityLabel(voiceOverLabel)
    }
}

/// Shrinks a little while pressed, or only dims with Reduce Motion on.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct SleepingBanner: View {
    let sleep: Activity
    let onWake: () -> Void
    /// Opens the sleep, to set when the baby woke up, after a timer that has probably been forgotten.
    let onFix: () -> Void

    var body: some View {
        // Redrawn each minute, so VoiceOver's "sleeping for" stays current.
        TimelineView(.everyMinute) { context in
            banner(now: context.date)
        }
    }

    private func banner(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            timer(now: now)
            // A sleep timer running this long was most likely left on by mistake.
            if now.timeIntervalSince(sleep.startDate) > Coverage.forgottenSleep {
                Button(action: onFix) {
                    NoticeLabel("Still asleep? Over 12 hours — set the wake-up time")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Opens the sleep to set when the baby woke up")
            }
        }
    }

    private func timer(now: Date) -> some View {
        AdaptiveStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "😴", tint: ActivityKind.sleep.color, size: 44)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Sleeping since \(sleep.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(sleep.startDate, style: .timer)
                        .font(.title2.weight(.semibold).monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Read once, in words, rather than as a clock ticking every second.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenStatus(now: now))
            Button("Woke up", action: onWake)
                .buttonStyle(.borderedProminent)
                .tint(ActivityKind.sleep.color)
                .accessibilityLabel("Woke up, stop the sleep timer")
        }
        .padding(.vertical, Spacing.xs)
    }

    private func spokenStatus(now: Date) -> String {
        String(localized: "Sleeping for \(Format.spokenDuration(now.timeIntervalSince(sleep.startDate))), since \(sleep.startDate.formatted(date: .omitted, time: .shortened))")
    }
}

/// "Time since last" cards for feeding, diaper and sleep.
private struct SinceLastRow: View {
    let feeding: Activity?
    let diaper: Activity?
    let sleep: Activity?
    let unit: VolumeUnit
    /// For the "Next feed around…" lines (`CarePredictionLine`).
    let baby: Baby
    /// One above the other, for Today's narrower column on iPad.
    var stacked = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            if stacked {
                VStack(spacing: 10) {
                    cards(now: context.date)
                }
            } else {
                // One above the other at the largest text sizes.
                AdaptiveStack(verticalAlignment: .top, spacing: 10) {
                    cards(now: context.date)
                }
            }
        }
    }

    @ViewBuilder
    private func cards(now: Date) -> some View {
        SinceLastCard(
            emoji: "🍼",
            title: String(localized: "Last feed"),
            value: feeding.map { Format.timeAgo($0.startDate, now: now) } ?? "—",
            spokenValue: feeding.map { Format.spokenTimeAgo($0.startDate, now: now) } ?? String(localized: "None yet"),
            detail: feeding.map(feedingDetail) ?? String(localized: "Not logged yet"),
            tint: ActivityKind.feeding.color,
            prediction: .feed,
            baby: baby
        )
        SinceLastCard(
            emoji: "🧷",
            title: String(localized: "Last diaper"),
            value: diaper.map { Format.timeAgo($0.startDate, now: now) } ?? "—",
            spokenValue: diaper.map { Format.spokenTimeAgo($0.startDate, now: now) } ?? String(localized: "None yet"),
            detail: diaper?.diaperType?.quickTitle ?? String(localized: "Not logged yet"),
            tint: ActivityKind.diaper.color,
            prediction: .diaper,
            baby: baby
        )
        SinceLastCard(
            emoji: "😴",
            title: sleep?.isOngoing == true ? String(localized: "Asleep for") : String(localized: "Awake for"),
            value: sleepValue(now: now),
            spokenValue: sleepSeconds(now: now).map(Format.spokenDuration) ?? String(localized: "Unknown"),
            detail: sleepDetail,
            tint: ActivityKind.sleep.color
        )
    }

    private func feedingDetail(_ feeding: Activity) -> String {
        let detail = feeding.detail(unit: unit)
        let type = feeding.feedingType?.shortTitle ?? String(localized: "Feeding")
        return detail.isEmpty ? type : "\(type) · \(detail)"
    }

    private func sleepSeconds(now: Date) -> TimeInterval? {
        guard let sleep else { return nil }
        if sleep.isOngoing { return now.timeIntervalSince(sleep.startDate) }
        guard let end = sleep.endDate else { return nil }
        return now.timeIntervalSince(end)
    }

    private func sleepValue(now: Date) -> String {
        sleepSeconds(now: now).map(Format.duration) ?? "—"
    }

    private var sleepDetail: String {
        guard let sleep else { return String(localized: "Not logged yet") }
        if sleep.isOngoing { return String(localized: "Sleeping now") }
        guard let duration = sleep.duration() else { return "" }
        return String(localized: "Slept \(Format.duration(duration))")
    }
}

private struct SinceLastCard: View {
    let emoji: String
    let title: String
    let value: String
    /// The value in words, e.g. "2 hours, 10 minutes ago".
    let spokenValue: String
    let detail: String
    let tint: Color
    /// Shows "Next feed around…" under it (`CarePredictionLine`).
    var prediction: PredictionKind?
    var baby: Baby?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(emoji) \(title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            // "Last feed, 2 hours, 10 minutes ago, Formula · 120 ml".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(spokenValue), \(Format.spoken(detail))")
            // Its own stop for VoiceOver, since it opens an explanation.
            if let prediction, let baby {
                CarePredictionLine(kind: prediction, baby: baby)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .tileStyle(tint: tint)
    }
}

private extension DiaperType {
    /// "💧 Pee logged", the toast after a one-tap diaper. A whole sentence for each, since the words
    /// around the type change with it in other languages.
    var loggedMessage: String {
        switch self {
        case .wet: return String(localized: "💧 Pee logged")
        case .dirty: return String(localized: "💩 Poop logged")
        case .mixed: return String(localized: "💩 Pee + poop logged")
        case .dry: return String(localized: "✨ Dry logged", comment: "A dry diaper was logged")
        }
    }
}
