import CoreData
import SwiftUI

/// The parent's own medicines, like the baby's medicine list: one tap to log another dose of
/// anything you've taken before, and the history below.
struct MomMedicinesView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: CareEntry.fetchAll(.medication)) private var doses: FetchedResults<CareEntry>

    @State private var editing: CareEntry?
    @State private var addingNew = false
    @State private var toast: Toast?

    var body: some View {
        List {
            Section {
                MomPrivacyNote()
            }

            if doses.isEmpty {
                EmptyStateView(
                    "No medicines yet",
                    systemImage: "pills",
                    message: "Keep track of pain relief, iron, vitamins or prescriptions, so you always know when you last took each one.",
                    actionTitle: "Add medicine"
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(latestPerMedicine) { dose in
                        TimelineView(.everyMinute) { timeline in
                            // The button moves under the details at the largest text sizes.
                            AdaptiveStack(spacing: Spacing.s) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    EmojiTitle("💊", dose.title)
                                        .font(.body.weight(.medium))
                                    Text(lastTaken(dose, now: timeline.date))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(Format.spoken(lastTaken(dose, now: timeline.date)))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                                Button("Took it now") { takeAgain(dose) }
                                    .buttonStyle(.bordered)
                                    .tint(Palette.momCare)
                                    .accessibilityLabel("Took \(dose.title) now")
                            }
                        }
                    }
                } header: {
                    Text("Take again")
                } footer: {
                    Text("Always follow your doctor's or pharmacist's instructions, including how long to wait between doses.")
                }

                Section("History") {
                    ForEach(doses) { dose in
                        Button {
                            editing = dose
                        } label: {
                            CareEntryRow(entry: dose)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                context.delete(dose)
                                context.saveIfChanged()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My medicines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add medicine", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $addingNew) {
            CareEntryEditor(kind: .medication, entry: nil)
        }
        .sheet(item: $editing) { dose in
            CareEntryEditor(kind: .medication, entry: dose)
        }
        .toast($toast)
    }

    /// The most recent dose of each medicine, by name.
    private var latestPerMedicine: [CareEntry] {
        var seen = Set<String>()
        return doses.filter { dose in
            let key = (dose.medicationName ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private func lastTaken(_ dose: CareEntry, now: Date) -> String {
        let timeAgo = Format.timeAgo(dose.date, now: now).lowercased()
        let ago = String(localized: "Last taken \(timeAgo)", comment: "\"2h ago\"")
        guard let dosage = dose.dosage, !dosage.isEmpty else { return ago }
        return "\(dosage) · \(ago)"
    }

    private func takeAgain(_ dose: CareEntry) {
        let newDose = CareEntry.create(.medication, in: context)
        newDose.medicationName = dose.medicationName
        newDose.dosage = dose.dosage
        context.saveIfChanged()
        toast = Toast(message: String(localized: "💊 \(dose.title) logged", comment: "A medicine's name")) { [context] in
            context.delete(newDose)
            context.saveIfChanged()
        }
    }
}
