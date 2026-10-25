import CoreData
import SwiftUI

struct VaccinesList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @FetchRequest private var vaccines: FetchedResults<Vaccine>

    @State private var editing: Vaccine?
    @State private var addingNew = false
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: Vaccine?

    init(baby: Baby) {
        _vaccines = FetchRequest(fetchRequest: baby.entries(Vaccine.fetchAll()))
    }

    var body: some View {
        let upcoming = vaccines.filter { !$0.isGiven }
        let given = vaccines.filter(\.isGiven).reversed()

        List {
            if vaccines.isEmpty {
                EmptyStateView(
                    "No vaccines yet",
                    systemImage: "syringe",
                    message: "Record each shot with its date and lot number, and add upcoming ones from your pediatrician's schedule.",
                    actionTitle: "Add vaccine",
                    isDisabled: !canEditLog
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            }

            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { vaccine in
                        row(vaccine)
                            .swipeActions(edge: .leading) {
                                if canEditLog {
                                    Button("Given today", systemImage: "checkmark") {
                                        vaccine.isGiven = true
                                        vaccine.date = .now
                                        context.saveIfChanged()
                                    }
                                    .tint(Palette.vaccineGiven)
                                }
                            }
                    }
                }
            }
            if !given.isEmpty {
                Section("Given") {
                    ForEach(Array(given)) { row($0) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add vaccine", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $addingNew) {
            VaccineEditor(vaccine: nil)
        }
        .sheet(item: $editing) { vaccine in
            VaccineEditor(vaccine: vaccine)
        }
        .confirmDelete("Delete this vaccine?", item: $deleting) { vaccine in
            context.delete(vaccine)
            context.saveIfChanged()
        }
    }

    private func row(_ vaccine: Vaccine) -> some View {
        Button {
            editing = vaccine
        } label: {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "💉", tint: vaccine.isGiven ? Palette.vaccineGiven : Palette.vaccineDue)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(vaccine.name.isEmpty ? "Vaccine" : vaccine.name)
                        .font(.body.weight(.medium))
                    let details = [vaccine.doseLabel, vaccine.provider].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    // Said in words with an icon, not only in green or orange.
                    NoticeLabel(
                        vaccine.isGiven ? "Given" : "Due",
                        systemImage: vaccine.isGiven ? "checkmark.circle.fill" : "clock",
                        tint: vaccine.isGiven ? Palette.vaccineGiven : Palette.vaccineDue
                    )
                    .font(.caption.weight(.semibold))
                    Text(vaccine.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .swipeActions {
            if canEditLog {
                // Not `.destructive`, which would remove the row before the answer.
                Button("Delete", systemImage: "trash") {
                    deleting = vaccine
                }
                .tint(.red)
            }
        }
    }
}

struct VaccineEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    let vaccine: Vaccine?

    @State private var name = ""
    @State private var date = Date.now
    @State private var isGiven = true
    @State private var doseLabel = ""
    @State private var provider = ""
    @State private var lotNumber = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this vaccine, but only the parents can save changes.") }
                }

                Section {
                    HStack {
                        TextField("Vaccine name", text: $name)
                        Menu {
                            ForEach(Vaccine.commonNames, id: \.self) { suggestion in
                                Button(suggestion) { name = suggestion }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Common vaccines")
                    }
                    TextField("Dose (e.g. Dose 1 of 3)", text: $doseLabel)
                }

                Section {
                    Toggle("Already given", isOn: $isGiven)
                    DateField(isGiven ? "Date given" : "Due date", selection: $date, includesTime: false)
                }

                Section {
                    TextField("Clinic or provider", text: $provider)
                    TextField("Lot number", text: $lotNumber)
                        .textInputAutocapitalization(.characters)
                } footer: {
                    Text("The lot number is on the vaccine record your clinic gives you.")
                }

                Section("Notes") {
                    TextField("Reactions, fever, fussiness…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let vaccine, canEditLog {
                    Section {
                        Button("Delete vaccine", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Delete this vaccine?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                context.delete(vaccine)
                                context.saveIfChanged()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(vaccine == nil ? "New vaccine" : "Edit vaccine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !canEditLog)
                }
            }
            .onAppear(perform: load)
        }
        .threeAMSheet()
    }

    private func load() {
        guard !didLoad, let vaccine else { return }
        didLoad = true
        name = vaccine.name
        date = vaccine.date
        isGiven = vaccine.isGiven
        doseLabel = vaccine.doseLabel
        provider = vaccine.provider
        lotNumber = vaccine.lotNumber
        notes = vaccine.notes
    }

    private func save() {
        let target = vaccine ?? Vaccine.create(in: context)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.date = date
        target.isGiven = isGiven
        target.doseLabel = doseLabel.trimmingCharacters(in: .whitespaces)
        target.provider = provider.trimmingCharacters(in: .whitespaces)
        target.lotNumber = lotNumber.trimmingCharacters(in: .whitespaces)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        dismiss()
    }
}
