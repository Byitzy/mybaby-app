import CoreData
import SwiftUI

/// At the top of Settings › Babies when the same baby appears twice (see `DuplicateBabies`):
/// asks whether to merge them, with Merge and Not now. Shows nothing otherwise.
struct DuplicateBabyCard: View {
    @ObservedObject private var duplicates = DuplicateBabies.shared

    var body: some View {
        if let suggestion = duplicates.suggestion {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Palette.baby)
                        .accessibilityHidden(true)
                    Text(DuplicateBabies.question(for: suggestion.name))
                        .fixedSize(horizontal: false, vertical: true)
                }
                AdaptiveStack(spacing: Spacing.m) {
                    Button("Merge") { duplicates.merge() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Keeps one \(suggestion.name) with everything logged for both")
                    Button("Not now") { duplicates.notNow() }
                        .buttonStyle(.bordered)
                        .accessibilityHint("You can still merge them from \(suggestion.name)'s profile")
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

/// In a baby's profile when that baby has a copy: merging is offered here even after "Not now".
struct DuplicateBabySection: View {
    @ObservedObject var baby: Baby
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @State private var confirmingMerge = false

    var body: some View {
        if let match = DuplicateBabies.match(for: baby, among: Array(babies)) {
            Section {
                Button {
                    confirmingMerge = true
                } label: {
                    Label("Merge with the other \(baby.displayName)", systemImage: "arrow.triangle.merge")
                }
                .confirmationDialog(
                    "Merge the two \(baby.displayName) logs?",
                    isPresented: $confirmingMerge,
                    titleVisibility: .visible
                ) {
                    Button("Merge") {
                        Task { await PersistenceController.shared.mergeBabies(keep: match.keep, merge: match.merge) }
                    }
                    Button("Not now", role: .cancel) {}
                } message: {
                    Text(DuplicateBabies.question(for: baby.displayName))
                }
            } footer: {
                Text("\(baby.displayName) appears twice, probably from another iPhone or iPad. Merging keeps everything logged for both.")
            }
        }
    }
}
