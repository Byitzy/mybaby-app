import CoreData
import SwiftUI

/// One diary entry: the words, who wrote them, the date and age, and the photos (tap one to see it full
/// screen). Share sends the words and photos through the share sheet.
///
/// A letter for later that's still sealed shows its envelope instead. Parents can tap Read anyway; it's
/// sealed again the next time it's opened, so the words are never shown by accident.
struct DiaryEntryDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @ObservedObject var entry: DiaryEntry
    @ObservedObject var baby: Baby

    @State private var photoIDs: [NSManagedObjectID] = []
    @State private var editing = false
    @State private var viewing: PhotoViewerStart?
    @State private var share: SharePayload?
    @State private var isPreparingShare = false
    @State private var confirmingDelete = false
    /// Read anyway, for this visit only.
    @State private var isOpened = false
    @State private var confirmingOpen = false

    var body: some View {
        Group {
            // Deleted here or on the partner's phone.
            if entry.isDeleted || entry.managedObjectContext == nil {
                EmptyStateView(
                    "This entry was deleted",
                    systemImage: "book.closed",
                    message: "It was deleted on this iPhone or on a phone that shares the log."
                )
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A letter whose day hasn't come, and that wasn't opened with Read anyway.
    private var showsSealed: Bool {
        entry.isSealed(birthDate: baby.birthDate) && !isOpened
    }

    private var content: some View {
        List {
            if showsSealed {
                sealedSection
            } else {
                Section {
                    HStack(spacing: 14) {
                        EmojiBadge(emoji: entry.kind.emoji, tint: Palette.diary, size: 56)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(entry.displayTitle)
                                .font(.title3.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text(DiaryText.byline(entry, baby: baby))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                if !entry.text.isEmpty {
                    Section {
                        Text(entry.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.vertical, Spacing.xs)
                    } footer: {
                        if let author = entry.author {
                            Text("Written by \(author)")
                        }
                    }
                }

                if entry.kind == .letter {
                    Section {
                        LabeledContent("Letter for later", value: entry.envelopeLine(babyName: baby.displayName))
                    }
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
            }

            if canEditLog {
                Section {
                    Button(entry.kind == .letter ? "Delete letter" : "Delete entry", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .toolbar {
            if !showsSealed {
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
        }
        .sheet(isPresented: $editing) {
            DiaryEntryEditor(target: .edit(entry), baby: baby)
        }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $viewing) { start in
            PhotoViewer(photoIDs: photoIDs, startIndex: start.index, title: entry.displayTitle)
        }
        .confirmationDialog(entry.kind == .letter ? "Delete this letter?" : "Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(photoIDs.isEmpty ? "Delete" : "Delete with its photos", role: .destructive) {
                context.delete(entry)
                context.saveIfChanged()
                dismiss()
            }
        } message: {
            Text(PersistenceController.isSyncEnabled ? "It's deleted from iCloud and every phone that shares the log." : "This can't be undone.")
        }
        .confirmationDialog("Read this letter now?", isPresented: $confirmingOpen, titleVisibility: .visible) {
            Button("Read anyway") { isOpened = true }
        } message: {
            Text("It's \(entry.envelopeLine(babyName: baby.displayName).lowercasedFirst). It's sealed again when you leave.")
        }
        .task(id: entry.photoIDSet) {
            photoIDs = entry.photoIDs()
        }
    }

    /// The envelope, and Read anyway for the parents.
    private var sealedSection: some View {
        Section {
            VStack(spacing: Spacing.m) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.diary)
                    .accessibilityHidden(true)
                Text(entry.envelopeLine(babyName: baby.displayName))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(sealedDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if canEditLog {
                    Button("Read anyway") { confirmingOpen = true }
                        .buttonStyle(.bordered)
                        .tint(Palette.diary)
                        .accessibilityHint("Shows the letter's words until you leave this screen")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .accessibilityElement(children: .contain)
        } footer: {
            Text("Sealed so the words aren't read by accident. They're kept safe in the diary, and shared with your partner like everything else.")
        }
    }

    /// "Written by Mom on Oct 12, 2026 · opens Feb 12, 2044".
    private var sealedDetail: String {
        var text = entry.author.map { "Written by \($0) on " } ?? "Written on "
        text += entry.date.formatted(date: .abbreviated, time: .omitted)
        if entry.openOnDate == nil, entry.openAtAge != nil, let opens = entry.opensOn(birthDate: baby.birthDate) {
            text += " · opens \(opens.formatted(date: .abbreviated, time: .omitted))"
        }
        return text
    }

    // MARK: Sharing

    /// "💛 What made you smile", "Mavie · Oct 12, 2026 · 6 weeks old", the words, and who wrote them.
    private var caption: String {
        var lines = [
            "\(entry.kind.emoji) \(entry.displayTitle)",
            "\(baby.displayName) · \(entry.dateAndAge(birthDate: baby.birthDate))",
        ]
        if !entry.text.isEmpty, entry.text != entry.displayTitle { lines.append("\n" + entry.text) }
        if let author = entry.author { lines.append("— \(author)") }
        return lines.joined(separator: "\n")
    }

    /// Decodes the photos in the background, then opens the share sheet with them and the words.
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

private extension String {
    /// "for Mavie, to open at 18" from "For Mavie, to open at 18".
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
