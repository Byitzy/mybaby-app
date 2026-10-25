import CoreData
import SwiftUI

/// Medicine history, with one-tap "give again" for anything given before.
struct MedicineList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    let baby: Baby
    @FetchRequest private var doses: FetchedResults<Activity>
    @FetchRequest private var schedules: FetchedResults<MedicineSchedule>

    @State private var editorTarget: EditorTarget?
    @State private var toast: Toast?
    @State private var doseTiming: DoseTimingTarget?
    /// A "Give now" that's sooner than the dose timing allows, waiting for "Give anyway".
    @State private var earlyDose: Activity?
    /// A "Give now" for a medicine on the baby's allergy list, waiting for "Give anyway".
    @State private var allergyDose: Activity?

    init(baby: Baby) {
        self.baby = baby
        _doses = FetchRequest(fetchRequest: baby.entries(Activity.all(.medication)))
        _schedules = FetchRequest(fetchRequest: baby.entries(MedicineSchedule.fetchAll()))
    }

    var body: some View {
        List {
            if doses.isEmpty {
                EmptyStateView(
                    "No medicine logged",
                    systemImage: "pills",
                    message: "Track vitamin D drops, fever reducers and prescriptions so you always know when the last dose was given.",
                    actionTitle: "Log medicine",
                    isDisabled: !canEditLog
                ) {
                    editorTarget = .new(.medication)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(latestPerMedicine) { dose in
                        TimelineView(.everyMinute) { timeline in
                            // Give now moves under the details at the largest text sizes.
                            AdaptiveStack(spacing: Spacing.s) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        EmojiTitle("💊", dose.title)
                                            .font(.body.weight(.medium))
                                        Text(lastGiven(dose, now: timeline.date))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel(Format.spoken(lastGiven(dose, now: timeline.date)))
                                        if let rule = schedules.matching(dose.medicationName)?.rule, !rule.isEmpty {
                                            DoseStatusLine(rule: rule, doseDates: doseDates(of: dose), now: timeline.date)
                                                .font(.subheadline.weight(.medium))
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    Button("Dose timing") { editDoseTiming(dose) }
                                        .font(.subheadline)
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Dose timing for \(dose.title)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Give now") { giveNowTapped(dose) }
                                    .buttonStyle(.bordered)
                                    .tint(ActivityKind.medication.color)
                                    .disabled(!canEditLog)
                                    .accessibilityLabel("Give \(dose.title) now")
                            }
                        }
                    }
                } header: {
                    Text("Give again")
                } footer: {
                    Text("Always follow your pediatrician's dosing instructions and the minimum time between doses. Dose timing shows when the next dose is allowed, from the timing you enter.")
                }

                Section("History") {
                    ForEach(doses) { dose in
                        Button {
                            editorTarget = .edit(dose)
                        } label: {
                            ActivityRow(activity: dose, unit: unit, showsDate: true)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if canEditLog {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(dose)
                                    context.saveIfChanged()
                                    CareReminders.refreshMedicine(context: context)
                                }
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editorTarget = .new(.medication) } label: {
                    Label("Log medicine", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(item: $editorTarget) { target in
            ActivityEditorView(kind: target.kind, activity: target.activity, baby: baby)
        }
        .sheet(item: $doseTiming) { target in
            MedicineScheduleEditor(name: target.name, schedule: target.schedule)
        }
        .confirmationDialog(
            "Too soon for another dose?", isPresented: earlyDoseBinding, titleVisibility: .visible, presenting: earlyDose
        ) { dose in
            Button("Give anyway") { giveAgain(dose) }
        } message: { dose in
            Text(earlyDoseMessage(dose))
        }
        .confirmationDialog(
            "On the allergy list", isPresented: allergyDoseBinding, titleVisibility: .visible, presenting: allergyDose
        ) { dose in
            Button("Give anyway") { giveAgain(dose) }
        } message: { dose in
            Text(allergyDoseMessage(dose))
        }
        .toast($toast)
    }

    // MARK: Dose timing

    /// When this medicine was given, every time.
    private func doseDates(of dose: Activity) -> [Date] {
        let key = MedicineSchedule.key(for: dose.medicationName)
        return doses.filter { MedicineSchedule.key(for: $0.medicationName) == key }.map(\.startDate)
    }

    private func editDoseTiming(_ dose: Activity) {
        doseTiming = DoseTimingTarget(name: dose.title, schedule: schedules.matching(dose.medicationName))
    }

    /// Asks first when the medicine is on the baby's allergy list. It never blocks it.
    private func giveNowTapped(_ dose: Activity) {
        if !baby.medicineAllergies(matching: dose.medicationName).isEmpty {
            allergyDose = dose
        } else {
            checkTimingAndGive(dose)
        }
    }

    private var allergyDoseBinding: Binding<Bool> {
        Binding(get: { allergyDose != nil }, set: { if !$0 { allergyDose = nil } })
    }

    /// "Mavie's list says she's allergic to amoxicillin. Check with your doctor or pharmacist before giving it.",
    /// and the dose timing warning too when it's also too soon, so one question covers both.
    private func allergyDoseMessage(_ dose: Activity) -> String {
        var lines = baby.medicineAllergies(matching: dose.medicationName).map { allergy in
            AllergyMatch.medicineWarning(
                babyName: baby.displayName, sex: baby.sex, allergyName: allergy.displayName, status: allergy.status
            )
        }
        if let rule = schedules.matching(dose.medicationName)?.rule,
           MedicineTiming.nextAllowed(rule: rule, doseDates: doseDates(of: dose)) != nil {
            lines.append(earlyDoseMessage(dose))
        }
        return lines.joined(separator: "\n\n")
    }

    /// Asks first when a dose is sooner than the timing the parent entered allows. It never blocks it.
    private func checkTimingAndGive(_ dose: Activity) {
        if let rule = schedules.matching(dose.medicationName)?.rule,
           MedicineTiming.nextAllowed(rule: rule, doseDates: doseDates(of: dose)) != nil {
            earlyDose = dose
        } else {
            giveAgain(dose)
        }
    }

    private var earlyDoseBinding: Binding<Bool> {
        Binding(get: { earlyDose != nil }, set: { if !$0 { earlyDose = nil } })
    }

    private func earlyDoseMessage(_ dose: Activity) -> String {
        guard let rule = schedules.matching(dose.medicationName)?.rule else { return "" }
        let dates = doseDates(of: dose)
        var lines = MedicineTiming.warnings(rule: rule, at: .now, otherDoses: dates)
        if let next = MedicineTiming.nextAllowed(rule: rule, doseDates: dates) {
            lines.append("\(MedicineTiming.nextDoseText(next)).")
        }
        lines.append("Check with your pediatrician if you're not sure.")
        return lines.joined(separator: "\n\n")
    }

    /// The most recent dose of each medicine, by name.
    private var latestPerMedicine: [Activity] {
        var seen = Set<String>()
        return doses.filter { dose in
            let key = (dose.medicationName ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private func lastGiven(_ dose: Activity, now: Date) -> String {
        let ago = "Last given \(Format.timeAgo(dose.startDate, now: now).lowercased())"
        guard let dosage = dose.dosage, !dosage.isEmpty else { return ago }
        return "\(dosage) · \(ago)"
    }

    private func giveAgain(_ dose: Activity) {
        let newDose = Activity.create(.medication, in: context)
        newDose.medicationName = dose.medicationName
        newDose.dosage = dose.dosage
        newDose.caregiver = NightPlan.load().shift(at: newDose.startDate)?.parent
        context.saveIfChanged()
        CareReminders.refreshMedicine(context: context)
        toast = Toast(message: "💊 \(dose.title) logged") { [context] in
            context.delete(newDose)
            context.saveIfChanged()
            Task { @MainActor in CareReminders.refreshMedicine(context: context) }
        }
    }
}
