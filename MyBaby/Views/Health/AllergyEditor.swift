import CoreData
import SwiftUI

/// Adds an allergy, or edits `allergy`: the allergen (common ones one tap away), what kind it is,
/// how sure and how bad, the reactions seen, who diagnosed it, the epinephrine auto-injector and notes.
struct AllergyEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    let allergy: Allergy?
    let baby: Baby
    @FetchRequest private var existing: FetchedResults<Allergy>

    @State private var name = ""
    /// The common allergen picked, kept while the name still says it.
    @State private var picked: CommonAllergen?
    @State private var category: AllergyCategory = .food
    @State private var status: AllergyStatus = .suspected
    @State private var severity: AllergySeverity = .mild
    @State private var reactionsSeen = ""
    @State private var diagnosedBy = ""
    @State private var hasDiagnosisDate = false
    @State private var diagnosedDate = Date.now
    @State private var hasAutoInjector = false
    @State private var autoInjectorLocation = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmingDelete = false

    init(allergy: Allergy?, baby: Baby) {
        self.allergy = allergy
        self.baby = baby
        _existing = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this allergy, but only the parents can save changes.") }
                }

                if allergy == nil {
                    Section {
                        commonChips(CommonAllergen.foods)
                    } header: {
                        Text("Common foods")
                    }
                    Section {
                        commonChips(CommonAllergen.medicines + CommonAllergen.others)
                    } header: {
                        Text("Medicines and more")
                    } footer: {
                        Text("Tap one, or type any allergen below.")
                    }
                }

                Section {
                    TextField("Allergen (e.g. peanut)", text: $name)
                        .textInputAutocapitalization(.sentences)
                    Picker("Type", selection: $category) {
                        ForEach(AllergyCategory.allCases) { category in
                            Text("\(category.emoji) \(category.title)").tag(category)
                        }
                    }
                } footer: {
                    if let duplicate {
                        NoticeLabel("\(duplicate.displayName) is already on the list.", systemImage: "info.circle", tint: Palette.allergy)
                    }
                }

                Section {
                    Picker("Status", selection: $status) {
                        ForEach(AllergyStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Status")
                    Picker("Severity", selection: $severity) {
                        ForEach(AllergySeverity.allCases) { severity in
                            Text(severity.title).tag(severity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Severity")
                } header: {
                    Text("Status and severity")
                } footer: {
                    Text(statusFooter)
                }

                Section("Reactions seen") {
                    TextField("e.g. hives around the mouth, vomiting", text: $reactionsSeen, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    TextField("Diagnosed by (optional)", text: $diagnosedBy)
                        .textContentType(.name)
                    Toggle("Diagnosis date", isOn: $hasDiagnosisDate)
                    if hasDiagnosisDate {
                        DateField("Date", selection: $diagnosedDate, in: ...Date.now, includesTime: false)
                    }
                } header: {
                    Text("Diagnosis")
                }

                Section {
                    Toggle("Has an epinephrine auto-injector", isOn: $hasAutoInjector)
                    if hasAutoInjector {
                        TextField("Where it's kept (e.g. diaper bag)", text: $autoInjectorLocation)
                    }
                } footer: {
                    Text("Shown on the allergy card, so caregivers know where to find it.")
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let allergy, canEditLog {
                    Section {
                        Button("Delete allergy", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Delete this allergy?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                context.delete(allergy)
                                context.saveIfChanged()
                                dismiss()
                            }
                        } message: {
                            Text("Reactions linked to it stay in the reactions log.")
                        }
                    }
                }
            }
            .navigationTitle(allergy == nil ? "New allergy" : "Edit allergy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || !canEditLog)
                }
            }
            .onAppear(perform: load)
        }
        .threeAMSheet()
    }

    // MARK: Pieces

    private func commonChips(_ allergens: [CommonAllergen]) -> some View {
        AllergyChipFlow {
            ForEach(allergens) { allergen in
                AllergenChip(allergen: allergen, isSelected: picked == allergen && trimmedName == allergen.name) {
                    picked = allergen
                    name = allergen.name
                    category = allergen.category
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var statusFooter: String {
        switch status {
        case .suspected: return "Suspected: you've seen a reaction, or think there might be one, but it hasn't been confirmed."
        case .confirmed: return "Confirmed: a doctor or allergist confirmed it."
        case .outgrown: return "Outgrown: a doctor said it's gone. It stays on the list, but no longer shows warnings or goes on the allergy card."
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another allergy with the same name, so the same one isn't added twice by accident.
    private var duplicate: Allergy? {
        let key = AllergyMatch.key(trimmedName)
        guard !key.isEmpty else { return nil }
        return existing.first { $0 != allergy && AllergyMatch.key($0.displayName) == key }
    }

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let allergy else { return }
        name = allergy.name
        picked = allergy.commonAllergen ?? CommonAllergen.named(allergy.name)
        category = allergy.category
        status = allergy.status
        severity = allergy.severity
        reactionsSeen = allergy.reactionsSeen
        diagnosedBy = allergy.diagnosedBy
        hasDiagnosisDate = allergy.diagnosedDate != nil
        diagnosedDate = allergy.diagnosedDate ?? .now
        hasAutoInjector = allergy.hasAutoInjector
        autoInjectorLocation = allergy.autoInjectorLocation
        notes = allergy.notes
    }

    /// The common allergen this is: the one picked while the name still mentions it, or one with
    /// exactly this name.
    private var allergenForName: CommonAllergen? {
        if let picked, AllergyMatch.mentions(picked.name, in: trimmedName) || picked.keywords.contains(where: { AllergyMatch.mentions($0, in: trimmedName) }) {
            return picked
        }
        return CommonAllergen.named(trimmedName)
    }

    private func save() {
        let target = allergy ?? Allergy.create(for: baby, in: context)
        target.name = trimmedName
        target.allergenRaw = allergenForName?.id
        target.category = category
        target.status = status
        target.severity = severity
        target.reactionsSeen = reactionsSeen.trimmingCharacters(in: .whitespacesAndNewlines)
        target.diagnosedBy = diagnosedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        target.diagnosedDate = hasDiagnosisDate ? diagnosedDate : nil
        target.hasAutoInjector = hasAutoInjector
        target.autoInjectorLocation = hasAutoInjector ? autoInjectorLocation.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        dismiss()
    }
}
