import SwiftUI
import UIKit

/// Settings › Feed & diaper reminders, set on each phone: the feeding reminder (off, every few hours, or
/// smart), how early a smart one goes off, the longest to wait between feeds, "Let baby sleep" and the
/// diaper check. `SmartReminders` picks up every change by itself.
struct CareRemindersSection: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.feedReminderMode, store: .shared) private var mode: FeedReminderMode = .off
    @AppStorage(SettingsKey.feedingReminderHours, store: .shared) private var fixedHours = 3.0
    @AppStorage(SettingsKey.feedReminderLeadMinutes, store: .shared) private var leadMinutes = 10
    /// 0 until it's changed: then the "every few hours" setting, or 3 hours.
    @AppStorage(SettingsKey.feedMaxIntervalHours, store: .shared) private var maxHours = 0.0
    @AppStorage(SettingsKey.letBabySleep, store: .shared) private var letBabySleep = false
    @AppStorage(SettingsKey.diaperReminderEnabled, store: .shared) private var diaperChecks = false
    /// The old on/off switch, kept in step for anything that still reads it.
    @AppStorage(SettingsKey.feedingReminderEnabled, store: .shared) private var feedingReminderEnabled = false

    @State private var showingPermissionAlert = false

    init() {}

    var body: some View {
        Section {
            Picker("Feeding reminder", selection: $mode) {
                ForEach(FeedReminderMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            switch mode {
            case .off:
                EmptyView()
            case .fixed:
                Stepper(value: $fixedHours, in: 1...6, step: 0.5) {
                    LabeledContent("Remind me after", value: Format.duration(fixedHours * 3600))
                }
            case .smart:
                Picker("Remind me", selection: $leadMinutes) {
                    ForEach([0, 5, 10, 15], id: \.self) { minutes in
                        Text(minutes == 0 ? "At the predicted time" : "\(minutes) min before").tag(minutes)
                    }
                }
                Stepper(value: maxBinding, in: 1...6, step: 0.5) {
                    LabeledContent("Never wait longer than", value: Format.duration(effectiveMaxHours * 3600))
                }
            }

            if mode != .off {
                Toggle(isOn: $letBabySleep) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Let baby sleep")
                        Text("No feed reminders during a sleep")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(isOn: $diaperChecks) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Diaper check")
                    Text("A gentle \"Diaper check?\" when a change is probably due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Feed & diaper reminders")
        } footer: {
            Text(footer)
        }
        .onChange(of: mode) { old, new in
            feedingReminderEnabled = new != .off
            guard old == .off, new != .off else { return }
            askPermission { mode = .off }
        }
        .onChange(of: diaperChecks) { _, enabled in
            guard enabled else { return }
            askPermission { diaperChecks = false }
        }
        .alert("Notifications are off", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow notifications for MyBaby in the Settings app to get feed and diaper reminders.")
        }
    }

    /// The saved maximum, or what it defaults to.
    private var effectiveMaxHours: Double {
        maxHours > 0 ? maxHours : CareSettings.load().maxInterval / 3600
    }

    private var maxBinding: Binding<Double> {
        Binding(
            get: { effectiveMaxHours },
            set: { maxHours = $0 }
        )
    }

    private var footer: String {
        var parts: [String] = []
        switch mode {
        case .off:
            break
        case .fixed:
            parts.append("A reminder when it's been this long since the last feed began.")
        case .smart:
            parts.append("Smart learns how far apart feeds usually are from the last few days of your log, day and night separately, and moves the reminder whenever either of you logs. Until there's enough logged, it uses the time you chose for Every few hours, or a common gap for your baby's age. It never waits longer than your limit.")
        }
        parts.append("Diaper check waits while the baby sleeps. During a night shift only the parent on duty gets these, with their alert style; otherwise both phones do. None while the breastfeeding timer is running.")
        if mode != .off {
            parts.append("Ask your pediatrician how long your baby can go between feeds, especially in the first weeks.")
        }
        return parts.joined(separator: " ")
    }

    /// Asks for notifications the first time; `undo` turns the switch back off when they're not allowed.
    private func askPermission(undo: @escaping () -> Void) {
        Task {
            if await NotificationManager.requestAuthorization() {
                NotificationManager.refreshFeedingReminder(context: context)
            } else {
                undo()
                showingPermissionAlert = true
            }
        }
    }
}
