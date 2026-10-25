import CoreData
import SwiftUI

/// Which allergy editor sheet to show: a new allergy, or an existing one.
struct AllergyEditorTarget: Identifiable {
    let id = UUID()
    var allergy: Allergy?
}

/// Which reaction editor sheet to show: a new reaction (optionally for an allergy), or an existing one.
struct ReactionEditorTarget: Identifiable {
    let id = UUID()
    var reaction: AllergyReaction?
    var allergy: Allergy?
}

/// Health › Allergies: the baby's allergies, the reactions log, introducing foods and the allergy
/// card to share with caregivers.
struct AllergiesList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    let baby: Baby
    @FetchRequest private var allergies: FetchedResults<Allergy>
    @FetchRequest private var reactions: FetchedResults<AllergyReaction>

    @State private var allergyTarget: AllergyEditorTarget?
    @State private var reactionTarget: ReactionEditorTarget?
    /// Waiting for "Delete" after a swipe.
    @State private var deletingAllergy: Allergy?
    @State private var deletingReaction: AllergyReaction?

    init(baby: Baby) {
        self.baby = baby
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
        _reactions = FetchRequest(fetchRequest: baby.entries(AllergyReaction.fetchAll()))
    }

    var body: some View {
        let sorted = allergies.sortedForDisplay()
        let active = sorted.filter(\.isActive)
        let outgrown = sorted.filter { !$0.isActive }

        List {
            if allergies.isEmpty && reactions.isEmpty {
                EmptyStateView(
                    "No allergies listed",
                    systemImage: "allergens",
                    message: "Keep \(baby.displayName)'s allergies and any reactions in one place, and share an allergy card with daycare, grandparents or a babysitter."
                ) {
                    EmptyStateButton(title: "Add an allergy", isDisabled: !canEditLog) {
                        allergyTarget = AllergyEditorTarget()
                    }
                    Button("Log a reaction") {
                        reactionTarget = ReactionEditorTarget()
                    }
                    .disabled(!canEditLog)
                }
                .listRowBackground(Color.clear)
            }

            if !active.isEmpty {
                Section("Allergies") {
                    ForEach(active) { allergyRow($0) }
                }
            } else if !allergies.isEmpty || !reactions.isEmpty {
                Section("Allergies") {
                    Text("No allergies listed right now.")
                        .foregroundStyle(.secondary)
                    Button("Add an allergy") { allergyTarget = AllergyEditorTarget() }
                        .disabled(!canEditLog)
                }
            }

            Section {
                NavigationLink {
                    AllergyCardView(baby: baby)
                } label: {
                    Label("Allergy card for caregivers", systemImage: "person.text.rectangle")
                }
                NavigationLink {
                    IntroducingFoodsView(baby: baby)
                } label: {
                    Label("Introducing foods", systemImage: "fork.knife")
                }
            } footer: {
                Text("The card is a one-page summary to share as a PDF or text. It goes only where you send it.")
            }

            if !reactions.isEmpty {
                Section {
                    ForEach(reactions) { reaction in
                        Button {
                            reactionTarget = ReactionEditorTarget(reaction: reaction)
                        } label: {
                            AllergyReactionRow(reaction: reaction)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if canEditLog {
                                // Not `.destructive`, which would remove the row before the answer.
                                Button("Delete", systemImage: "trash") { deletingReaction = reaction }
                                    .tint(.red)
                            }
                        }
                    }
                } header: {
                    Text("Reactions")
                }
            }

            if !outgrown.isEmpty {
                Section("Outgrown") {
                    ForEach(outgrown) { allergyRow($0) }
                }
            }

            if !allergies.isEmpty || !reactions.isEmpty {
                Section {
                    Text("Written down by you, not a diagnosis. Your pediatrician or an allergist can tell you what a reaction means.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        allergyTarget = AllergyEditorTarget()
                    } label: {
                        Label("Add an allergy", systemImage: "allergens")
                    }
                    Button {
                        reactionTarget = ReactionEditorTarget()
                    } label: {
                        Label("Log a reaction", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(item: $allergyTarget) { target in
            AllergyEditor(allergy: target.allergy, baby: baby)
        }
        .sheet(item: $reactionTarget) { target in
            AllergyReactionEditor(reaction: target.reaction, baby: baby, allergy: target.allergy)
        }
        .confirmDelete(
            "Delete this allergy?",
            item: $deletingAllergy,
            message: "Reactions linked to it stay in the reactions log."
        ) { allergy in
            context.delete(allergy)
            context.saveIfChanged()
        }
        .confirmDelete("Delete this reaction?", item: $deletingReaction, message: "Its photo is deleted too.") { reaction in
            context.delete(reaction)
            context.saveIfChanged()
        }
    }

    private func allergyRow(_ allergy: Allergy) -> some View {
        Button {
            allergyTarget = AllergyEditorTarget(allergy: allergy)
        } label: {
            AllergyRow(allergy: allergy)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if canEditLog {
                Button("Log a reaction", systemImage: "exclamationmark.triangle") {
                    reactionTarget = ReactionEditorTarget(allergy: allergy)
                }
                .tint(Palette.allergy)
            }
        }
        .swipeActions {
            if canEditLog {
                Button("Delete", systemImage: "trash") { deletingAllergy = allergy }
                    .tint(.red)
            }
        }
    }
}
