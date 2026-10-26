import CoreData
import SwiftUI

/// A timeline of the baby's milestones, newest first, with their photos. Pushed from More.
///
/// A keepsake rather than a checklist: there are no expected ages, just the moments you want to
/// remember and how old the baby was.
struct MilestonesView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var baby: Baby
    @FetchRequest private var milestones: FetchedResults<Milestone>

    @State private var addingNew = false
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: Milestone?

    init(baby: Baby) {
        self.baby = baby
        let request = baby.entries(Milestone.fetchAll())
        // In batches: the list only reads the milestones scrolled into view.
        request.fetchBatchSize = 30
        _milestones = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        List {
            if !canEditLog {
                Section { ViewOnlyBanner() }
            }

            if milestones.isEmpty {
                EmptyStateView(
                    "No milestones yet",
                    systemImage: "star",
                    message: "Keep the moments you want to remember, like a first smile or a first bath, with photos and a few words.",
                    actionTitle: "Add a milestone",
                    isDisabled: !canEditLog
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(milestones) { milestone in
                        NavigationLink {
                            MilestoneDetailView(milestone: milestone, baby: baby)
                        } label: {
                            MilestoneRow(milestone: milestone, birthDate: baby.birthDate)
                        }
                        .swipeActions {
                            if canEditLog {
                                // Not `.destructive`, which would remove the row before the answer.
                                Button("Delete", systemImage: "trash") {
                                    deleting = milestone
                                }
                                .tint(.red)
                            }
                        }
                    }
                } footer: {
                    Text("Every baby has their own pace, so there are no target ages here. If you share the log, milestones and their photos are shared too.")
                }
            }
        }
        .navigationTitle(baby.name.isEmpty ? "Milestones" : "\(baby.name)'s milestones")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDelete(
            "Delete this milestone?",
            item: $deleting,
            message: PersistenceController.isSyncEnabled ? "It's deleted from iCloud and every phone that shares the log." : "This can't be undone.",
            buttonTitle: "Delete milestone and photos"
        ) { milestone in
            context.delete(milestone)
            context.saveIfChanged()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add milestone", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $addingNew) {
            MilestoneEditor(milestone: nil, baby: baby)
        }
    }
}

/// One milestone in the timeline: its emoji, title, date and age, and a strip of photos.
private struct MilestoneRow: View {
    @ObservedObject var milestone: Milestone
    let birthDate: Date?

    @State private var photoIDs: [NSManagedObjectID] = []

    /// How many thumbnails fit in the strip before "+3".
    private static let shownPhotos = 4

    var body: some View {
        // A milestone deleted here or by the partner can redraw once more before the list drops it.
        if milestone.isDeleted || milestone.managedObjectContext == nil {
            EmptyView()
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            EmojiBadge(emoji: milestone.displayEmoji, tint: Palette.milestone, size: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(milestone.displayTitle)
                    .font(.body.weight(.semibold))
                Text(milestone.dateAndAge(birthDate: birthDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !milestone.notes.isEmpty {
                    Text(milestone.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !photoIDs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(photoIDs.prefix(Self.shownPhotos)), id: \.self) { id in
                            MilestoneThumbnail(photoID: id, side: 56, cornerRadius: Radius.photo)
                        }
                        if photoIDs.count > Self.shownPhotos {
                            Text("+\(photoIDs.count - Self.shownPhotos)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(photoIDs.isEmpty ? "" : String(localized: "\(photoIDs.count) photos"))
        .task(id: milestone.photoIDSet) {
            photoIDs = milestone.photoIDs()
        }
    }
}
