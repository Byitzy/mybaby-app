import CoreData
import SwiftUI

/// One milestone: its photos (tap one to see it full screen), the date and age, and the note.
/// Share sends the photos with a caption through the share sheet.
struct MilestoneDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var milestone: Milestone
    @ObservedObject var baby: Baby

    @State private var photoIDs: [NSManagedObjectID] = []
    @State private var editing = false
    @State private var viewing: PhotoViewerStart?
    @State private var share: SharePayload?
    @State private var isPreparingShare = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            // Deleted here or on the partner's phone.
            if milestone.isDeleted || milestone.managedObjectContext == nil {
                EmptyStateView(
                    "This milestone was deleted",
                    systemImage: "star.slash",
                    message: "It was deleted on this iPhone or on a phone that shares the log."
                )
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    EmojiBadge(emoji: milestone.displayEmoji, tint: Palette.milestone, size: 56)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(milestone.displayTitle)
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(milestone.dateAndAge(birthDate: baby.birthDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if !photoIDs.isEmpty {
                Section("Photos") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                            Button {
                                viewing = PhotoViewerStart(index: index)
                            } label: {
                                MilestoneThumbnail(photoID: id, side: nil, cornerRadius: Radius.photo)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Photo \(index + 1) of \(photoIDs.count)")
                            .accessibilityHint("Opens the photo full screen")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !milestone.notes.isEmpty {
                Section("Notes") {
                    Text(milestone.notes)
                }
            }

            if canEditLog {
                Section {
                    Button("Delete milestone", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isPreparingShare {
                    ProgressView()
                } else {
                    Button(action: prepareShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $editing) {
            MilestoneEditor(milestone: milestone, baby: baby)
        }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $viewing) { start in
            PhotoViewer(photoIDs: photoIDs, startIndex: start.index, title: milestone.displayTitle)
        }
        .confirmationDialog("Delete this milestone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete milestone and photos", role: .destructive) {
                context.delete(milestone)
                context.saveIfChanged()
                dismiss()
            }
        } message: {
            Text(PersistenceController.isSyncEnabled ? "It's deleted from iCloud and every phone that shares the log." : "This can't be undone.")
        }
        .task(id: milestone.photoIDSet) {
            photoIDs = milestone.photoIDs()
        }
    }

    // MARK: Sharing

    /// "😊 First smile", "Ava · Oct 12, 2026 · 6 weeks old", and the note.
    private var caption: String {
        var lines = [
            "\(milestone.displayEmoji) \(milestone.displayTitle)",
            "\(baby.displayName) · \(milestone.dateAndAge(birthDate: baby.birthDate))",
        ]
        if !milestone.notes.isEmpty { lines.append(milestone.notes) }
        return lines.joined(separator: "\n")
    }

    /// Decodes the photos in the background, then opens the share sheet with them and the caption.
    /// Images are handed over directly, so no copies are left in the temporary folder.
    private func prepareShare() {
        isPreparingShare = true
        let ids = photoIDs
        let text = caption
        Task {
            var items: [Any] = await MilestoneImages.fullImages(for: ids)
            items.append(text)
            isPreparingShare = false
            share = SharePayload(items: items)
        }
    }
}

/// Which photo the full-screen viewer opens on.
struct PhotoViewerStart: Identifiable {
    let id = UUID()
    let index: Int
}
