import CoreData
import SwiftUI

/// Adds a new activity of `kind`, or edits `activity` when one is passed in.
struct ActivityEditorView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage(SettingsKey.temperatureUnit, store: .shared) private var temperatureUnit: TemperatureUnit = .localeDefault

    let kind: ActivityKind
    let activity: Activity?
    /// The baby shown in the app, whose earlier entries suggest values for a new one.
    let baby: Baby

    @FetchRequest private var pastMedications: FetchedResults<Activity>
    @FetchRequest private var medicineSchedules: FetchedResults<MedicineSchedule>

    @State private var didLoad = false
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var isOngoing = false
    @State private var notes = ""

    @State private var feedingType: FeedingType = .formula
    @State private var amount: Double = 0
    @State private var leftMinutes = 0
    @State private var rightMinutes = 0
    @State private var foodDescription = ""
    /// Common allergens the solids contained (`CommonAllergen` ids).
    @State private var allergenTags: Set<String> = []

    @State private var diaperType: DiaperType = .wet
    @State private var poopColor: PoopColor = .yellow
    @State private var poopConsistency: PoopConsistency = .seedy

    @State private var medicationName = ""
    @State private var dosage = ""
    @State private var doseTiming: DoseTimingTarget?

    @State private var pumping = PumpingDraft()
    @State private var temperature = TemperatureDraft()

    @State private var caregiver: Parent?
    /// Set once someone picks a caregiver, so changing the time no longer re-guesses it.
    @State private var caregiverChosen = false

    @State private var confirmingDelete = false

    init(kind: ActivityKind, activity: Activity?, baby: Baby) {
        self.kind = kind
        self.activity = activity
        self.baby = baby
        _pastMedications = FetchRequest(fetchRequest: baby.entries(Activity.all(.medication)))
        _medicineSchedules = FetchRequest(fetchRequest: baby.entries(MedicineSchedule.fetchAll()))
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this entry, but only the parents can save changes.") }
                }

                switch kind {
                case .feeding: feedingSections
                case .diaper: diaperSections
                case .sleep: sleepSections
                case .bath: bathSections
                case .medication: medicationSections
                case .pumping:
                    PumpingSections(draft: $pumping, startDate: $startDate, unit: unit, isNew: activity == nil)
                case .temperature:
                    TemperatureSections(
                        draft: $temperature, startDate: $startDate, unit: temperatureUnit, birthDate: baby.birthDate
                    )
                }

                if nightPlan.isEnabled || caregiver != nil {
                    Section {
                        Picker("Handled by", selection: caregiverSelection) {
                            Text("Not set").tag(Parent?.none)
                            ForEach(Parent.allCases) { parent in
                                Text(nightPlan.name(of: parent)).tag(Parent?.some(parent))
                            }
                        }
                    } footer: {
                        Text("Counts toward who got up at night in Reports.")
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if activity != nil && canEditLog {
                    Section {
                        Button(kind.deleteTitle, role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(activity == nil ? kind.logTitle : kind.editTitle)
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
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteActivity)
            }
            .onAppear(perform: load)
            .sheet(item: $doseTiming) { target in
                MedicineScheduleEditor(name: target.name, schedule: target.schedule)
            }
            .onChange(of: startDate) { _, newDate in
                if activity == nil && !caregiverChosen {
                    caregiver = nightPlan.shift(at: newDate)?.parent
                }
            }
        }
        .threeAMSheet()
    }

    // MARK: Feeding

    @ViewBuilder
    private var feedingSections: some View {
        Section {
            DateField("Time", selection: $startDate)
            Picker("Type", selection: $feedingType) {
                ForEach(FeedingType.allCases) { type in
                    Text("\(type.emoji) \(type.title)").tag(type)
                }
            }
        }

        switch feedingType {
        case .breast:
            Section {
                Stepper(value: $leftMinutes, in: 0...120) {
                    LabeledContent("Left side", value: String(localized: "\(leftMinutes) min", comment: "Minutes, abbreviated"))
                }
                Stepper(value: $rightMinutes, in: 0...120) {
                    LabeledContent("Right side", value: String(localized: "\(rightMinutes) min", comment: "Minutes, abbreviated"))
                }
            } header: {
                Text("How long on each side")
            } footer: {
                if leftMinutes + rightMinutes > 0 {
                    Text("Total \(leftMinutes + rightMinutes) minutes")
                }
            }
        case .breastMilkBottle, .formula:
            Section("Amount") { amountControls }
        case .solids:
            Section("What did baby eat?") {
                TextField("e.g. mashed banana, oatmeal", text: $foodDescription)
            }
            SolidsAllergenSection(selection: $allergenTags, food: foodDescription, baby: baby)
            Section("Amount (optional)") { amountControls }
        }
    }

    private var amountControls: some View {
        Group {
            Stepper(value: $amount, in: 0...unit.maxValue, step: unit.step) {
                LabeledContent("Amount", value: unit.format(value: amount))
                    .monospacedDigit()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unit.presets, id: \.self) { preset in
                        Button(unit.format(value: preset)) { amount = preset }
                            .buttonStyle(.bordered)
                            .tint(amount == preset ? Color.accentColor : Color.secondary)
                            .accessibilityAddTraits(amount == preset ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: Diaper

    @ViewBuilder
    private var diaperSections: some View {
        Section {
            DateField("Time", selection: $startDate)
            Picker("Type", selection: $diaperType) {
                ForEach(DiaperType.allCases) { type in
                    Text(type.quickTitle).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }

        if diaperType == .dirty || diaperType == .mixed {
            Section {
                Picker("Color", selection: $poopColor) {
                    ForEach(PoopColor.allCases) { color in
                        Text("\(color.emoji) \(color.title)").tag(color)
                    }
                }
                Picker("Consistency", selection: $poopConsistency) {
                    ForEach(PoopConsistency.allCases) { consistency in
                        Text(consistency.title).tag(consistency)
                    }
                }
            } header: {
                Text("Poop details")
            } footer: {
                if poopColor.needsAttention {
                    NoticeLabel("Red, black (after the first few days) or white/pale poop can be a sign to call your pediatrician.")
                }
            }
        }
    }

    // MARK: Sleep

    @ViewBuilder
    private var sleepSections: some View {
        Section {
            DateField("Fell asleep", selection: $startDate)
            Toggle("Still sleeping", isOn: $isOngoing)
            if !isOngoing {
                DateField("Woke up", selection: $endDate, in: startDate...)
            }
        } footer: {
            if !isOngoing {
                if endDate > startDate {
                    Text("Slept \(Format.duration(endDate.timeIntervalSince(startDate)))")
                } else {
                    NoticeLabel(
                        "Wake-up time must be after the time baby fell asleep.",
                        systemImage: "exclamationmark.circle.fill",
                        tint: Palette.danger
                    )
                }
            }
        }
    }

    // MARK: Bath

    private var bathSections: some View {
        Section {
            DateField("Time", selection: $startDate)
        }
    }

    // MARK: Medication

    @ViewBuilder
    private var medicationSections: some View {
        Section {
            DateField("Time given", selection: $startDate)
            TextField("Medicine (e.g. Vitamin D drops)", text: $medicationName)
                .textInputAutocapitalization(.words)
            TextField("Dose (e.g. 1 ml)", text: $dosage)
        } footer: {
            Text("Always follow your pediatrician's dosing instructions.")
        }

        MedicineAllergyWarningSection(medicine: medicationName, baby: baby)

        MedicineTimingSection(
            name: medicationName,
            date: startDate,
            rule: medicineSchedules.matching(medicationName)?.rule,
            otherDoses: otherDoseDates
        ) {
            doseTiming = DoseTimingTarget(
                name: medicationName.trimmingCharacters(in: .whitespaces),
                schedule: medicineSchedules.matching(medicationName)
            )
        }

        if !recentMedications.isEmpty {
            Section("Recent medicines") {
                ForEach(recentMedications, id: \.name) { med in
                    Button {
                        medicationName = med.name
                        dosage = med.dosage
                    } label: {
                        LabeledContent(med.name, value: med.dosage)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    /// Unique medicine names, most recent first, with the dose that was last used.
    private var recentMedications: [RecentMedication] {
        var seen = Set<String>()
        var result: [RecentMedication] = []
        for med in pastMedications {
            guard let name = med.medicationName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            guard seen.insert(name.lowercased()).inserted else { continue }
            result.append(RecentMedication(name: name, dosage: med.dosage ?? ""))
            if result.count == 5 { break }
        }
        return result
    }

    /// Earlier doses of the medicine being logged, leaving out this one, for the dose timing warnings.
    private var otherDoseDates: [Date] {
        let key = MedicineSchedule.key(for: medicationName)
        return pastMedications
            .filter { $0 != activity && MedicineSchedule.key(for: $0.medicationName) == key }
            .map(\.startDate)
    }

    private struct RecentMedication {
        let name: String
        let dosage: String
    }

    // MARK: Load & save

    private var canSave: Bool {
        switch kind {
        case .sleep: return isOngoing || endDate > startDate
        case .medication: return !medicationName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private var nightPlan: NightPlan { NightPlan(data: nightPlanData) }

    private var caregiverSelection: Binding<Parent?> {
        Binding(
            get: { caregiver },
            set: {
                caregiver = $0
                caregiverChosen = true
            }
        )
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let activity else {
            loadDefaultsForNewEntry()
            caregiver = nightPlan.shift(at: startDate)?.parent
            return
        }

        startDate = activity.startDate
        caregiver = activity.caregiver
        caregiverChosen = true
        notes = activity.notes
        switch kind {
        case .feeding:
            feedingType = activity.feedingType ?? .formula
            amount = activity.amountML.map(unit.fromML) ?? 0
            leftMinutes = activity.leftMinutes ?? 0
            rightMinutes = activity.rightMinutes ?? 0
            foodDescription = activity.foodDescription ?? ""
            allergenTags = activity.allergenIDs
        case .diaper:
            diaperType = activity.diaperType ?? .wet
            poopColor = activity.poopColor ?? .yellow
            poopConsistency = activity.poopConsistency ?? .seedy
        case .sleep:
            isOngoing = activity.endDate == nil
            endDate = activity.endDate ?? .now
        case .medication:
            medicationName = activity.medicationName ?? ""
            dosage = activity.dosage ?? ""
        case .bath:
            break
        case .pumping:
            pumping.load(from: activity, unit: unit)
        case .temperature:
            temperature.load(from: activity, unit: temperatureUnit)
        }
    }

    /// Start new entries from what was logged last time, since babies tend to repeat.
    private func loadDefaultsForNewEntry() {
        switch kind {
        case .feeding:
            if let last = try? context.fetch(baby.entries(Activity.latest(.feeding))).first {
                feedingType = last.feedingType ?? .formula
                if let ml = last.amountML, feedingType.isBottle {
                    amount = unit.fromML(ml)
                }
            }
        case .diaper:
            if let last = try? context.fetch(baby.entries(Activity.latest(.diaper))).first {
                poopColor = last.poopColor ?? .yellow
                poopConsistency = last.poopConsistency ?? .seedy
            }
            diaperType = .dirty
        case .sleep:
            startDate = Date.now.addingTimeInterval(-3600)
            endDate = .now
        case .temperature:
            let last = try? context.fetch(baby.entries(Activity.latest(.temperature))).first
            temperature.startNew(unit: temperatureUnit, lastMethod: last?.temperatureMethod)
        default:
            break
        }
    }

    private func save() {
        let target = activity ?? Activity.create(kind, startDate: startDate, in: context)
        target.caregiver = caregiver
        target.startDate = startDate
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .feeding:
            target.feedingType = feedingType
            target.leftMinutes = feedingType == .breast ? leftMinutes : nil
            target.rightMinutes = feedingType == .breast ? rightMinutes : nil
            target.amountML = feedingType != .breast && amount > 0 ? unit.toML(amount) : nil
            let food = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            target.foodDescription = feedingType == .solids && !food.isEmpty ? food : nil
            target.allergenIDs = feedingType == .solids ? allergenTags : []
        case .diaper:
            let isDirty = diaperType == .dirty || diaperType == .mixed
            target.diaperType = diaperType
            target.poopColor = isDirty ? poopColor : nil
            target.poopConsistency = isDirty ? poopConsistency : nil
        case .sleep:
            target.endDate = isOngoing ? nil : endDate
        case .medication:
            target.medicationName = medicationName.trimmingCharacters(in: .whitespaces)
            target.dosage = dosage.trimmingCharacters(in: .whitespaces)
        case .bath:
            break
        case .pumping:
            pumping.apply(to: target, unit: unit)
            if activity == nil {
                pumping.addBags(pumpedAt: startDate, unit: unit, in: context)
            }
        case .temperature:
            temperature.apply(to: target, unit: temperatureUnit)
        }

        context.saveIfChanged()
        if kind == .feeding {
            NotificationManager.refreshFeedingReminder(context: context)
        }
        refreshCareReminders()
        dismiss()
    }

    private func deleteActivity() {
        guard let activity else { return }
        context.delete(activity)
        context.saveIfChanged()
        if kind == .feeding {
            NotificationManager.refreshFeedingReminder(context: context)
        }
        refreshCareReminders()
        dismiss()
    }

    /// Medicine doses move the "next dose allowed" reminder; pumping can add bags to the stash.
    private func refreshCareReminders() {
        switch kind {
        case .medication: CareReminders.refreshMedicine(context: context)
        case .pumping: CareReminders.refreshMilkStash(context: context)
        default: break
        }
    }
}

private extension ActivityKind {
    /// The editor's titles, each a whole phrase, since the article and the word order change with the
    /// kind in other languages.
    var logTitle: String {
        switch self {
        case .feeding: return String(localized: "Log feeding", comment: "Title of the editor for a new feed")
        case .diaper: return String(localized: "Log diaper", comment: "Title of the editor for a new diaper change")
        case .sleep: return String(localized: "Log sleep", comment: "Title of the editor for a new sleep")
        case .bath: return String(localized: "Log bath", comment: "Title of the editor for a new bath")
        case .medication: return String(localized: "Log medicine", comment: "Title of the editor for a new medicine dose")
        case .pumping: return String(localized: "Log pumping", comment: "Title of the editor for a new pumping session")
        case .temperature: return String(localized: "Log temperature", comment: "Title of the editor for a new temperature")
        }
    }

    var editTitle: String {
        switch self {
        case .feeding: return String(localized: "Edit feeding")
        case .diaper: return String(localized: "Edit diaper")
        case .sleep: return String(localized: "Edit sleep")
        case .bath: return String(localized: "Edit bath")
        case .medication: return String(localized: "Edit medicine")
        case .pumping: return String(localized: "Edit pumping")
        case .temperature: return String(localized: "Edit temperature")
        }
    }

    var deleteTitle: String {
        switch self {
        case .feeding: return String(localized: "Delete feeding")
        case .diaper: return String(localized: "Delete diaper")
        case .sleep: return String(localized: "Delete sleep")
        case .bath: return String(localized: "Delete bath")
        case .medication: return String(localized: "Delete medicine")
        case .pumping: return String(localized: "Delete pumping")
        case .temperature: return String(localized: "Delete temperature")
        }
    }
}
