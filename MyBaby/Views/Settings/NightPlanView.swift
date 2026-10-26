import CoreData
import SwiftUI

extension Parent {
    /// Always shown next to the parent's name, never on its own.
    var color: Color { self == .parent1 ? Palette.parent1 : Palette.parent2 }
}

/// Set up how two parents share the nights so they both get a fair amount of sleep.
struct NightPlanView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var plan = NightPlan.load()
    /// The plan as this screen last loaded or saved it.
    @State private var savedPlan = NightPlan.load()

    var body: some View {
        Form {
            Section {
                Toggle("Share night duty", isOn: $plan.isEnabled)
            } footer: {
                Text("Take turns with the baby at night so you each get a protected stretch of sleep.")
            }

            if plan.isEnabled {
                parentsSection
                nightSection
                sharingSection
                tonightSection
                fairnessSection
                scheduleSection
                remindersSection
            }
        }
        .navigationTitle("Night shifts")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: plan) { _, newPlan in
            // A plan reloaded from the partner's change is already saved; saving it again would push it back.
            if newPlan != savedPlan {
                // Picked here, so Today doesn't ask "Who's using this iPhone?" as well.
                if newPlan.alarmOwner != savedPlan.alarmOwner {
                    ParentSettings.markOwnerChosen()
                }
                newPlan.save()
                savedPlan = newPlan
                SharedPlanSync.push(newPlan, context: context)
            }
            Task { await NotificationManager.refreshNightShiftReminders() }
        }
        .onAppear {
            // The names and who this iPhone belongs to can change in Settings, or on Today.
            let stored = NightPlan.load()
            guard stored != plan else { return }
            savedPlan = stored
            plan = stored
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: RunLoop.main)
        ) { _ in
            // Show the partner's schedule change, unless an edit made here hasn't been saved yet.
            guard plan == savedPlan else { return }
            SharedPlanSync.pull(context: context)
            let stored = NightPlan.load()
            guard stored != plan else { return }
            savedPlan = stored
            plan = stored
        }
    }

    // MARK: Sections

    /// The names, which are set in Settings › Parents.
    private var parentsSection: some View {
        Section {
            ForEach(Parent.allCases) { parent in
                HStack(spacing: Spacing.s) {
                    Circle().fill(parent.color).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(plan.name(of: parent))
                }
            }
            if let baby = Baby.current(in: context) {
                NavigationLink("Edit names in Settings") {
                    SettingsView(baby: baby)
                }
            }
        } header: {
            Text("Parents")
        } footer: {
            if !plan.hasBothNames {
                Text("Add your names in Settings › Parents, so the schedule and reminders use them.")
            }
        }
    }

    private var nightSection: some View {
        Section {
            DatePicker("Night starts", selection: timeBinding(\.nightStartMinutes), displayedComponents: .hourAndMinute)
            DatePicker("Night ends", selection: timeBinding(\.nightEndMinutes), displayedComponents: .hourAndMinute)
        } header: {
            Text("The night")
        } footer: {
            Text("From when you go to bed until the morning, about \(Format.duration(averageNightLength)) in all.")
        }
    }

    @ViewBuilder
    private var sharingSection: some View {
        Section {
            Picker("How to share", selection: $plan.mode) {
                ForEach(NightPlanMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch plan.mode {
            case .split:
                DatePicker("Handoff at", selection: timeBinding(\.handoffMinutes), displayedComponents: .hourAndMinute)
                Button("Split the night evenly") { plan.centerHandoff() }
                Toggle("Swap who goes first each night", isOn: $plan.swapEachNight)
            case .alternate:
                Stepper(value: $plan.nightsPerTurn, in: 1...7) {
                    LabeledContent("Nights in a row", value: "\(plan.nightsPerTurn)")
                }
            }
        } header: {
            Text("How you share")
        } footer: {
            switch plan.mode {
            case .split:
                Text("One of you covers the first part of the night and the other wakes up at the handoff to take over. Swapping every night means you each get the first half and the second half equally often.")
            case .alternate:
                Text("One of you covers the whole night while the other sleeps through, then you switch.")
            }
        }
    }

    private var tonightSection: some View {
        Section {
            Picker(plan.mode == .split ? "First shift tonight" : "On duty tonight", selection: firstOnDutyTonight) {
                ForEach(Parent.allCases) { parent in
                    Text(plan.name(of: parent)).tag(parent)
                }
            }
        } footer: {
            Text("The rotation continues from here automatically.")
        }
    }

    private var fairnessSection: some View {
        let nights = plan.upcomingNights(count: fairnessNightCount)
        let totals = NightPlan.dutyTotals(nights)
        let nightCount = Double(max(nights.count, 1))
        let gap = abs((totals[.parent1] ?? 0) - (totals[.parent2] ?? 0)) / nightCount

        return Section {
            ForEach(Parent.allCases) { parent in
                let duty = (totals[parent] ?? 0) / nightCount
                HStack {
                    Circle().fill(parent.color).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(plan.name(of: parent))
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text("\(Format.duration(averageNightLength - duty)) sleep")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel("\(Format.spokenDuration(averageNightLength - duty)) sleep")
                        Text("\(Format.duration(duty)) on duty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(Format.spokenDuration(duty)) on duty")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if gap >= 15 * 60 {
                NoticeLabel("One of you is getting about \(Format.duration(gap)) less sleep a night.")
                    .font(.subheadline)
                Button("Make it even") { makeEven() }
            } else {
                NoticeLabel("You're sharing the nights evenly.", systemImage: "checkmark.seal.fill", tint: Palette.ok)
                    .font(.subheadline)
            }
        } header: {
            Text("Average per night")
        } footer: {
            Text("Based on the coming weeks of the schedule. Sleep means time off duty during the night.")
        }
    }

    private var scheduleSection: some View {
        Section("Next 7 nights") {
            ForEach(plan.upcomingNights(count: 7), id: \.first?.start) { night in
                VStack(alignment: .leading, spacing: 6) {
                    if let start = night.first?.start {
                        Text(start, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(night) { shift in
                        HStack(spacing: Spacing.s) {
                            Capsule()
                                .fill(shift.parent.color)
                                .frame(width: 4, height: 16)
                                .accessibilityHidden(true)
                            Text(plan.name(of: shift.parent))
                                .font(.subheadline)
                            Spacer()
                            Text("\(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xxs)
                // "Monday, Oct 27, Maya 9:00 PM – 2:00 AM, Sam 2:00 AM – 7:00 AM".
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Picker("This iPhone belongs to", selection: $plan.alarmOwner) {
                Text(plan.name(of: .parent1)).tag(AlarmOwner.parent1)
                Text(plan.name(of: .parent2)).tag(AlarmOwner.parent2)
                Text("Shared iPhone (both of us)").tag(AlarmOwner.both)
            }
            Picker("Alert style", selection: $plan.alarmStyle) {
                ForEach(AlarmStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            if plan.mode == .split {
                Toggle("Wake me at the handoff", isOn: $plan.wakeUpAlarms)
            }
            Toggle("Bedtime heads-up", isOn: $plan.bedtimeHeadsUp)
        } header: {
            Text("Reminders on this iPhone")
        } footer: {
            Text(remindersFooter)
        }
    }

    // MARK: Helpers

    private var remindersFooter: String {
        var text = String(localized: "The wake-up repeats every 30 seconds, up to 5 times, until you tap “I'm up”.") + " "
        switch plan.alarmStyle {
        case .vibrate:
            text += String(localized: "Vibrate only makes no sound, so your partner and baby keep sleeping. Keep the phone under your pillow or in your hand, since a phone buzzing on a nightstand can still be heard. If you don't feel anything, turn on haptics in iPhone Settings › Sounds & Haptics.")
        case .sound:
            text += String(localized: "Sound uses the standard notification sound, so keep your ringer on.")
        }
        text += "\n\n" + String(localized: "Apple Watch: while you wear it and your iPhone is locked, alerts come as a tap on your wrist, and you can tap “I'm up” there. When the watch is on its charger, your iPhone gets them instead. There's nothing to set up.")
        text += "\n\n" + String(localized: "If you use a Sleep Focus or Do Not Disturb at night, add MyBaby to its allowed apps, or the alerts will stay silent.")
        text += "\n\n" + String(localized: "With Family sharing on, the schedule syncs to your partner's phone automatically. On each phone, pick its owner under “This iPhone belongs to” (here or in Settings › Parents) so it only wakes them.")
        return text
    }

    private var averageNightLength: TimeInterval {
        let nights = plan.upcomingNights(count: 7)
        let total = nights.compactMap { night -> TimeInterval? in
            guard let start = night.first?.start, let end = night.last?.end else { return nil }
            return end.timeIntervalSince(start)
        }.reduce(0, +)
        return total / Double(max(nights.count, 1))
    }

    /// About two weeks, rounded to whole rotations so a run of several nights doesn't look unfair.
    private var fairnessNightCount: Int {
        let cycle = plan.mode == .alternate ? 2 * max(plan.nightsPerTurn, 1) : 2
        return cycle * Int((14.0 / Double(cycle)).rounded(.up))
    }

    private var firstOnDutyTonight: Binding<Parent> {
        Binding(
            get: { plan.shifts(forNightOf: plan.nightDay(at: .now)).first?.parent ?? .parent1 },
            set: { plan.setFirstOnDuty($0) }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<NightPlan, Int>) -> Binding<Date> {
        Binding(
            get: { Date.today(atMinutes: plan[keyPath: keyPath]) },
            set: { plan[keyPath: keyPath] = $0.minutesIntoDay }
        )
    }

    private func makeEven() {
        switch plan.mode {
        case .split:
            plan.centerHandoff()
            plan.swapEachNight = true
        case .alternate:
            plan.nightsPerTurn = 1
        }
    }
}

#Preview {
    NavigationStack {
        NightPlanView()
    }
}
