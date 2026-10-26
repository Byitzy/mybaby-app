import SwiftUI

/// Turn crying alerts on for the night and see what the monitor has heard.
struct CryMonitorView: View {
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage(SettingsKey.listeningStop) private var listeningStop: ListeningStop = .never
    @AppStorage(SettingsKey.listeningStopMinutes) private var stopMinutes = ListeningStop.defaultMinutes
    @AppStorage(SettingsKey.listeningStopHours) private var stopHours = ListeningStop.defaultHours
    @ScaledMetric(relativeTo: .headline) private var statusSize: CGFloat = 56
    private let monitor = CryMonitor.shared

    var body: some View {
        Form {
            Section {
                statusRow
                Button {
                    if monitor.isListening {
                        monitor.stop()
                    } else {
                        Task { await monitor.start() }
                    }
                } label: {
                    Label(
                        monitor.isListening ? "Stop listening" : "Start listening",
                        systemImage: monitor.isListening ? "stop.circle.fill" : "ear.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.isListening ? Palette.danger : Color.accentColor)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let error = monitor.errorMessage, monitor.mode == .phone {
                    NoticeLabel(error, systemImage: "exclamationmark.circle.fill", tint: Palette.danger)
                        .font(.subheadline)
                }
                stopPicker
                if monitor.isLowPowerMode {
                    NoticeLabel(
                        "Low Power Mode is on: listening uses a little less battery, and a soft cry may take a moment longer to notice.",
                        systemImage: "battery.25",
                        tint: Palette.warning
                    )
                    .font(.subheadline)
                }
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Listening is done on this iPhone. Audio is never recorded, saved or sent anywhere.")
                    #if DEBUG
                    Text(debugMetricsText)
                        .monospacedDigit()
                    #endif
                }
            }

            Section {
                LabeledContent("Buzzes", value: whoGetsBuzzed)
                Picker("Sensitivity", selection: planBinding(\.crySensitivity)) {
                    ForEach(CrySensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                }
                Picker("Wake the other parent after", selection: planBinding(\.cryEscalationMinutes)) {
                    Text("Never").tag(0)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                }
                NavigationLink("Night shifts & alert style") {
                    NightPlanView()
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text(alertsFooter)
            }

            if !monitor.episodes.isEmpty {
                Section("Heard tonight") {
                    ForEach(monitor.episodes) { episode in
                        LabeledContent(
                            episode.start.formatted(date: .omitted, time: .shortened),
                            value: String(localized: "Cried for \(Format.duration(max(episode.duration, 60)))", comment: "How long, like \"3 min\"")
                        )
                    }
                }
            }

            NurseryMonitorSection()

            Section("For the best results") {
                Label("Put the phone within a few feet of the baby, with the microphone uncovered.", systemImage: "iphone")
                Label("Keep it plugged in. Listening all night uses battery.", systemImage: "battery.100.bolt")
                Label("Wearing an Apple Watch? Alerts tap your wrist while the iPhone is locked. When the watch is charging, the iPhone buzzes instead.", systemImage: "applewatch")
                Label("Using a Sleep Focus or Do Not Disturb? Add MyBaby to its allowed apps so alerts get through.", systemImage: "moon.fill")
                Label("Leave MyBaby running in the background. Don't swipe it away, or listening stops.", systemImage: "app.badge")
                Label("Loud white noise or a fan close to the phone can hide crying. Use High sensitivity, or move the phone closer to the baby.", systemImage: "fan")
                Label("This helps you rest. It isn't a medical or safety monitor.", systemImage: "info.circle")
            }
            .font(.subheadline)
        }
        .navigationTitle("Cry alerts")
        .navigationBarTitleDisplayMode(.inline)
        // The level bar is only kept up to date while it's on screen.
        .onAppear { monitor.meterAppeared() }
        .onDisappear { monitor.meterDisappeared() }
    }

    #if DEBUG
    /// For comparing battery use on a device: how much the classifier ran since listening started.
    private var debugMetricsText: String {
        let metrics = monitor.debugMetrics
        let hours = max(1.0 / 60, Date.now.timeIntervalSince(monitor.listeningSince ?? .now) / 3600)
        let state = monitor.isClassifierActive ? "on" : "off"
        return "Debug · classifier \(state) · \(metrics.buffersGated) buffers gated · \(Int(metrics.classifierSeconds / hours)) classifier s/h · \(Int(Double(metrics.inferences) / hours)) inferences/h"
    }
    #endif

    // MARK: Pieces

    private var statusRow: some View {
        // Redrawn each minute so VoiceOver reads how long the crying has gone on in words.
        TimelineView(.everyMinute) { timeline in
            statusContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenStatus(now: timeline.date))
        }
    }

    /// "Baby is crying, for 3 minutes", "Listening for crying, stops by itself at 7:00 AM".
    private func spokenStatus(now: Date) -> String {
        var parts: [String] = []
        if let cryStart = monitor.cryStart {
            let duration = Format.spokenDuration(now.timeIntervalSince(cryStart))
            parts.append(String(localized: "Baby is crying, for \(duration)", comment: "Read by VoiceOver. How long, like \"3 minutes\""))
        } else if let stopsAt = monitor.stopsAt {
            let time = stopsAt.formatted(date: .omitted, time: .shortened)
            parts.append(String(localized: "\(statusTitle), stops by itself at \(time)", comment: "Read by VoiceOver: \"Listening for crying\", then a time"))
        } else {
            parts.append(statusTitle)
        }
        if let action = monitor.lastAction { parts.append(action) }
        return parts.joined(separator: ", ")
    }

    /// When listening stops by itself on this iPhone (`ListeningStop`). Changing it while listening
    /// moves the stop time at once.
    @ViewBuilder
    private var stopPicker: some View {
        Picker("Stop listening", selection: $listeningStop) {
            ForEach(ListeningStop.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .onChange(of: listeningStop) { monitor.updateStopTime() }
        switch listeningStop {
        case .atTime:
            DatePicker("Stop at", selection: stopTime, displayedComponents: .hourAndMinute)
                .onChange(of: stopMinutes) { monitor.updateStopTime() }
        case .afterDuration:
            Picker("Stop after", selection: $stopHours) {
                ForEach(ListeningStop.hourChoices, id: \.self) { hours in
                    Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                }
            }
            .onChange(of: stopHours) { monitor.updateStopTime() }
        case .endOfShifts:
            if !NightPlan(data: nightPlanData).isEnabled {
                Text("Night shifts are off, so listening goes on until you stop it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .never:
            EmptyView()
        }
    }

    /// `stopMinutes` as a time of day today, for the time picker.
    private var stopTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: stopMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                stopMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var statusContent: some View {
        HStack(spacing: 14) {
            Text(statusEmoji)
                .font(.system(size: min(statusSize, 84) * 0.6))
                .frame(width: min(statusSize, 84), height: min(statusSize, 84))
                .background(statusColor.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(statusTitle)
                    .font(.headline)
                if let cryStart = monitor.cryStart {
                    Text("For \(Text(cryStart, style: .timer))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let stopsAt = monitor.stopsAt {
                    Text("Stops by itself at \(stopsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if monitor.isListening {
                    ProgressView(value: monitor.level)
                        .tint(statusColor)
                        // A sound level that changes all the time; the words above say what matters.
                        .accessibilityHidden(true)
                }
                if let action = monitor.lastAction {
                    Text(action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusEmoji: String {
        if monitor.cryStart != nil { return "😭" }
        return monitor.isListening ? "🎧" : "😴"
    }

    private var statusTitle: String {
        if monitor.cryStart != nil { return String(localized: "Baby is crying") }
        return monitor.isListening ? String(localized: "Listening for crying") : String(localized: "Not listening")
    }

    private var statusColor: Color {
        if monitor.cryStart != nil { return Palette.cryAlerts }
        return monitor.isListening ? Palette.listening : Palette.inactive
    }

    private var plan: NightPlan { NightPlan(data: nightPlanData) }

    private var whoGetsBuzzed: String {
        guard plan.isEnabled else { return String(localized: "This phone", comment: "Who gets buzzed") }
        switch plan.alarmOwner {
        case .both: return String(localized: "Whoever is on duty", comment: "Who gets buzzed")
        case .parent1, .parent2:
            let owner: Parent = plan.alarmOwner == .parent1 ? .parent1 : .parent2
            let name = plan.name(of: owner)
            return String(localized: "\(name), on their shifts", comment: "Who gets buzzed: a parent's name")
        }
    }

    private var alertsFooter: String {
        guard plan.isEnabled else {
            return String(localized: "Turn on Night shifts to buzz only the parent on duty. Until then, this phone buzzes whenever it hears crying.")
        }
        return String(localized: "Run cry alerts on both parents' phones. Both hear the baby, but each phone buzzes only when its owner is on duty, so the parent who's off can keep sleeping. If the crying keeps going, the other parent's phone buzzes too.")
    }

    private func planBinding<Value>(_ keyPath: WritableKeyPath<NightPlan, Value>) -> Binding<Value> {
        Binding(
            get: { plan[keyPath: keyPath] },
            set: { newValue in
                var updated = plan
                updated[keyPath: keyPath] = newValue
                updated.save()
            }
        )
    }
}

#Preview {
    NavigationStack {
        CryMonitorView()
    }
}
