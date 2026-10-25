import CoreData
import SwiftUI

/// Which medicine's dose timing to edit, from the medicine list or the medicine editor.
struct DoseTimingTarget: Identifiable {
    let id = UUID()
    let name: String
    let schedule: MedicineSchedule?
}

/// Sets the dose timing for one medicine, as the pediatrician directed. Nothing is filled in for
/// the parent: the app never suggests a dose or an interval.
struct MedicineScheduleEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    let name: String
    let schedule: MedicineSchedule?

    @State private var hoursText = ""
    @State private var maxText = ""
    @State private var notes = ""
    @State private var notify = false
    @State private var didLoad = false
    @State private var showingPermissionAlert = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Medicine", value: name)
                } footer: {
                    Text("Enter the timing exactly as your pediatrician directed. MyBaby never suggests a dose or how often to give it.")
                }

                if let baby = schedule?.baby ?? Baby.current(in: context) {
                    MedicineAllergyWarningSection(medicine: name, baby: baby)
                }

                Section {
                    HStack {
                        Text("At least")
                        TextField("Hours", text: $hoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("hours apart")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("At most")
                        TextField("Optional", text: $maxText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("doses in 24 hours")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Dose timing")
                } footer: {
                    if hasInvalidNumber {
                        NoticeLabel(
                            "Check the numbers: hours above zero (up to 72), and a whole number of doses (up to 24).",
                            systemImage: "exclamationmark.circle.fill",
                            tint: Palette.danger
                        )
                    } else {
                        Text("MyBaby shows when the next dose is allowed and warns you if a dose is logged sooner or over the daily limit. It never stops you from logging one.")
                    }
                }

                Section {
                    Toggle("Notify me when the next dose is allowed", isOn: $notify)
                } footer: {
                    Text("On this iPhone only. It's a reminder of the timing you entered, not a prompt to give another dose.")
                }

                Section("Notes") {
                    TextField("e.g. what your pediatrician said", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if schedule != nil && canEditLog {
                    Section {
                        Button("Remove dose timing", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Remove the dose timing?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Remove", role: .destructive, action: delete)
                        } message: {
                            Text("The doses you logged stay. MyBaby stops showing when the next dose is allowed.")
                        }
                    }
                }
            }
            .navigationTitle("Dose timing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave || !canEditLog)
                }
            }
            .onAppear(perform: load)
            .onChange(of: notify) { _, isOn in
                guard isOn else { return }
                Task {
                    if !(await NotificationManager.requestAuthorization()) {
                        notify = false
                        showingPermissionAlert = true
                    }
                }
            }
            .alert("Notifications are off", isPresented: $showingPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow notifications for MyBaby in the iPhone Settings app to get this reminder.")
            }
        }
        .threeAMSheet()
    }

    // MARK: Parsing

    /// A number typed with either the user's decimal separator or a period, or `nil` if it's empty.
    private func number(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = trimmed
            .replacingOccurrences(of: separator, with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return .some(value)
    }

    /// Hours between doses: `.some(nil)` when empty, `nil` when it can't be used.
    private var parsedHours: Double?? {
        guard let parsed = number(hoursText) else { return nil }
        guard let hours = parsed else { return .some(nil) }
        guard hours > 0, hours <= 72 else { return nil }
        return .some(hours)
    }

    private var parsedMax: Int?? {
        guard let parsed = number(maxText) else { return nil }
        guard let value = parsed else { return .some(nil) }
        guard value == value.rounded(), value >= 1, value <= 24 else { return nil }
        return .some(Int(value))
    }

    private var hasInvalidNumber: Bool {
        parsedHours == nil || parsedMax == nil
    }

    /// At least one of the two, and nothing unreadable.
    private var canSave: Bool {
        guard let hours = parsedHours, let max = parsedMax else { return false }
        return hours != nil || max != nil
    }

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let schedule else { return }
        if let hours = schedule.minHoursBetween {
            hoursText = hours.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        }
        if let max = schedule.maxDosesPer24h {
            maxText = "\(max)"
        }
        notes = schedule.notes
        notify = schedule.notifiesWhenAllowed
    }

    private func save() {
        guard let hours = parsedHours, let max = parsedMax else { return }
        let target = schedule ?? MedicineSchedule.create(name: name, in: context)
        target.minHoursBetween = hours
        target.maxDosesPer24h = max
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        target.notifiesWhenAllowed = notify
        CareReminders.refreshMedicine(context: context)
        dismiss()
    }

    private func delete() {
        guard let schedule else { return }
        schedule.notifiesWhenAllowed = false
        context.delete(schedule)
        context.saveIfChanged()
        CareReminders.refreshMedicine(context: context)
        dismiss()
    }
}

/// Dose timing in the medicine editor: whether the dose being logged fits what the parent entered.
struct MedicineTimingSection: View {
    let name: String
    let date: Date
    /// The timing entered for this medicine, or `nil` when there isn't any.
    let rule: DoseRule?
    /// Other doses of the same medicine, leaving out the one being edited.
    let otherDoses: [Date]
    let onEditTiming: () -> Void

    var body: some View {
        if !MedicineSchedule.key(for: name).isEmpty {
            Section {
                if let rule, !rule.isEmpty {
                    Text(rule.summary)
                        .font(.subheadline)
                    let warnings = MedicineTiming.warnings(rule: rule, at: date, otherDoses: otherDoses)
                    if warnings.isEmpty {
                        NoticeLabel("Fits the dose timing you entered", systemImage: "checkmark.circle", tint: Palette.ok)
                    }
                    ForEach(warnings, id: \.self) { warning in
                        NoticeLabel(warning)
                    }
                }
                Button(rule == nil ? "Set dose timing…" : "Edit dose timing…", action: onEditTiming)
            } header: {
                Text("Dose timing")
            } footer: {
                Text("As directed by your pediatrician. A warning never stops you from saving.")
            }
        }
    }
}

/// "Next dose allowed at 4:10 AM" or "OK to give now", for a medicine with dose timing.
struct DoseStatusLine: View {
    let rule: DoseRule
    let doseDates: [Date]
    let now: Date

    var body: some View {
        // The words say it; the icon's color only backs them up.
        if let next = MedicineTiming.nextAllowed(rule: rule, doseDates: doseDates, now: now) {
            NoticeLabel(MedicineTiming.nextDoseText(next, now: now), systemImage: "clock", tint: Palette.warning)
        } else {
            NoticeLabel("OK to give now", systemImage: "checkmark.circle", tint: Palette.ok)
        }
    }
}
