import CoreData
import SwiftUI

/// Adds or edits one of the parent's own entries: a check-in, a medicine they took, or a recovery note.
struct CareEntryEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let kind: CareKind
    let entry: CareEntry?

    @State private var date = Date.now
    @State private var mood: Mood?
    @State private var sleepHours: Double?
    @State private var painLevel: Int?
    @State private var bleeding: Bleeding?
    @State private var medicationName = ""
    @State private var dosage = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .mood:
                    Section {
                        DateField("Date", selection: $date, in: ...Date.now)
                    }
                    Section("How were you feeling?") {
                        MoodPicker(selection: $mood)
                        SleepStepper(title: String(localized: "Sleep the night before"), hours: $sleepHours)
                        PainPicker(level: $painLevel)
                    }
                case .medication:
                    Section {
                        DateField("Time taken", selection: $date)
                        TextField("Medicine (e.g. Ibuprofen)", text: $medicationName)
                            .textInputAutocapitalization(.words)
                        TextField("Dose (e.g. 400 mg)", text: $dosage)
                    } footer: {
                        Text("Always follow your doctor's or pharmacist's instructions, including how long to wait between doses.")
                    }
                case .recovery:
                    Section {
                        DateField("Date", selection: $date, in: ...Date.now)
                    }
                    Section {
                        PainPicker(level: $painLevel)
                        BleedingPicker(bleeding: $bleeding)
                    } footer: {
                        if bleeding == .heavy {
                            HeavyBleedingNote()
                        }
                    }
                }

                Section("Notes") {
                    TextField(notesPrompt, text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if entry != nil {
                    Section {
                        Button(deleteTitle, role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry {
                        context.delete(entry)
                        context.saveIfChanged()
                    }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
        .threeAMSheet()
        // Private, like the care page it opens from.
        .privateScreen()
    }

    private var notesPrompt: String {
        switch kind {
        case .mood: return String(localized: "Anything on your mind?")
        case .medication: return String(localized: "Optional")
        case .recovery: return String(localized: "Stitches, healing, feeding, how your body feels…")
        }
    }

    /// "New check-in", "Edit medicine"… One string for each, so each language can say it its own way.
    private var title: String {
        switch (kind, entry == nil) {
        case (.mood, true): return String(localized: "New check-in")
        case (.mood, false): return String(localized: "Edit check-in")
        case (.medication, true): return String(localized: "New medicine")
        case (.medication, false): return String(localized: "Edit medicine")
        case (.recovery, true): return String(localized: "New recovery note")
        case (.recovery, false): return String(localized: "Edit recovery note")
        }
    }

    private var deleteTitle: String {
        switch kind {
        case .mood: return String(localized: "Delete check-in")
        case .medication: return String(localized: "Delete medicine")
        case .recovery: return String(localized: "Delete recovery note")
        }
    }

    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        switch kind {
        case .mood:
            return mood != nil || sleepHours != nil || painLevel != nil || !trimmedNotes.isEmpty
        case .medication:
            return !medicationName.trimmingCharacters(in: .whitespaces).isEmpty
        case .recovery:
            return painLevel != nil || bleeding != nil || !trimmedNotes.isEmpty
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let entry else { return }
        date = entry.date
        mood = entry.mood
        sleepHours = entry.sleepHours
        painLevel = entry.painLevel
        bleeding = entry.bleeding
        medicationName = entry.medicationName ?? ""
        dosage = entry.dosage ?? ""
        notes = entry.notes
    }

    private func save() {
        let target = entry ?? CareEntry.create(kind, in: context)
        target.date = date
        target.notes = trimmedNotes
        switch kind {
        case .mood:
            target.mood = mood
            target.sleepHours = sleepHours
            target.painLevel = painLevel
        case .medication:
            target.medicationName = medicationName.trimmingCharacters(in: .whitespaces)
            target.dosage = dosage.trimmingCharacters(in: .whitespaces)
        case .recovery:
            target.painLevel = painLevel
            target.bleeding = bleeding
        }
        context.saveIfChanged()
        dismiss()
    }
}

/// Every check-in or every recovery note, newest first. Tap to edit, swipe to delete.
struct CareLogList: View {
    @Environment(\.managedObjectContext) private var context
    let kind: CareKind
    @FetchRequest private var entries: FetchedResults<CareEntry>

    @State private var editing: CareEntry?
    @State private var addingNew = false

    init(kind: CareKind) {
        self.kind = kind
        _entries = FetchRequest(fetchRequest: CareEntry.fetchAll(kind))
    }

    var body: some View {
        List {
            Section {
                MomPrivacyNote()
            }

            if entries.isEmpty {
                EmptyStateView(
                    kind == .mood ? "No check-ins yet" : "No recovery notes yet",
                    systemImage: kind == .mood ? "heart" : "note.text",
                    message: kind == .mood
                        ? "Your daily check-ins show up here."
                        : "Jot down how you're healing: stitches, pain, bleeding, anything you want to remember or ask your doctor or midwife about.",
                    actionTitle: kind == .mood ? "Add a check-in" : "Add a note"
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            editing = entry
                        } label: {
                            CareEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                context.delete(entry)
                                context.saveIfChanged()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(kind == .mood ? "Past check-ins" : "Recovery notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label(kind == .mood ? "Add check-in" : "Add note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $addingNew) {
            CareEntryEditor(kind: kind, entry: nil)
        }
        .sheet(item: $editing) { entry in
            CareEntryEditor(kind: entry.kind, entry: entry)
        }
    }
}
