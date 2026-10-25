import CoreData
import PhotosUI
import SwiftUI

/// Adds a milestone, or edits `milestone` when one is passed in: what happened, when, an emoji,
/// photos from the library or the camera, and a note.
///
/// Picking photos needs no permission prompt: PhotosPicker runs outside the app and hands over
/// only the photos chosen. Each one is shrunk to a small JPEG before it's saved (see `MilestoneImages`).
struct MilestoneEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    let milestone: Milestone?
    /// Whose milestone it is, for the age shown under the date.
    @ObservedObject var baby: Baby

    @State private var title = ""
    @State private var emoji = Milestone.defaultEmoji
    @State private var date = Date.now
    @State private var notes = ""
    /// Saved photos still on the milestone; ones removed here are deleted when saving.
    @State private var keptPhotoIDs: [NSManagedObjectID] = []
    /// Photos added here, already shrunk, saved with the milestone.
    @State private var newPhotos: [NewPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Photos still being read and shrunk.
    @State private var processing = 0
    @State private var takingPhoto = false
    @State private var photoError: String?
    @State private var didLoad = false

    /// Plenty for one moment, and keeps a milestone's sync quick.
    private static let maxPhotos = 20

    private struct NewPhoto: Identifiable {
        let id = UUID()
        let jpeg: Data
        let thumbnail: UIImage
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this milestone, but only the parents can save changes.") }
                }

                if milestone == nil {
                    Section("Pick a moment, or write your own") {
                        suggestions
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    TextField("What happened?", text: $title)
                        .textInputAutocapitalization(.sentences)
                    DateField("Date", selection: $date, in: ...Date.now, includesTime: false)
                } footer: {
                    if let birthDate = baby.birthDate {
                        Text("\(baby.displayName): \(Format.age(birthDate: birthDate, now: date))")
                    }
                }

                Section("Emoji") {
                    emojiPicker
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                photosSection

                Section("Notes") {
                    TextField("Where you were, who was there, how it felt…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(milestone == nil ? "New milestone" : "Edit milestone")
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
            .onAppear(perform: load)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pickerItems = []
                Task { await addPicked(items) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in
                    takingPhoto = false
                    if let image {
                        Task { await addTaken(image) }
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Couldn't add a photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoError ?? "")
            }
        }
        .threeAMSheet()
    }

    // MARK: Pieces

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Milestone.suggestions) { suggestion in
                    let isSelected = title == suggestion.text
                    Button {
                        title = suggestion.text
                        emoji = suggestion.emoji
                    } label: {
                        Text("\(suggestion.emoji) \(suggestion.text)")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor : Palette.chipBackground, in: Capsule())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(suggestion.text)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emojiPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Milestone.emojiChoices) { choice in
                    let isSelected = emoji == choice.emoji
                    Button {
                        emoji = choice.emoji
                    } label: {
                        Text(choice.emoji)
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.text)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var photoCount: Int { keptPhotoIDs.count + newPhotos.count + processing }

    @ViewBuilder
    private var photosSection: some View {
        Section {
            if !keptPhotoIDs.isEmpty || !newPhotos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(Array(keptPhotoIDs.enumerated()), id: \.element) { index, id in
                        removable(number: index + 1) {
                            MilestoneThumbnail(photoID: id, side: 76, cornerRadius: Radius.photo)
                        } remove: {
                            keptPhotoIDs.removeAll { $0 == id }
                        }
                    }
                    ForEach(Array(newPhotos.enumerated()), id: \.element.id) { index, photo in
                        removable(number: keptPhotoIDs.count + index + 1) {
                            Image(uiImage: photo.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
                                .accessibilityHidden(true)
                        } remove: {
                            newPhotos.removeAll { $0.id == photo.id }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if processing > 0 {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(processing == 1 ? "Adding photo…" : "Adding \(processing) photos…")
                        .foregroundStyle(.secondary)
                }
            }
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, Self.maxPhotos - photoCount),
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label("Choose photos", systemImage: "photo.on.rectangle")
            }
            .disabled(photoCount >= Self.maxPhotos)
            if CameraPicker.isAvailable {
                Button {
                    takingPhoto = true
                } label: {
                    Label("Take photo", systemImage: "camera")
                }
                .disabled(photoCount >= Self.maxPhotos)
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Photos are saved smaller, without their location, so they sync quickly and stay end-to-end encrypted with the rest of the log.")
        }
    }

    /// A thumbnail with a remove button in its corner.
    private func removable<Thumbnail: View>(
        number: Int,
        @ViewBuilder thumbnail: () -> Thumbnail,
        remove: @escaping () -> Void
    ) -> some View {
        thumbnail()
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.6))
                        .padding(3)
                }
                // Its own tap target, rather than the whole row's.
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove photo \(number)")
            }
    }

    // MARK: Adding photos

    private func addPicked(_ items: [PhotosPickerItem]) async {
        processing += items.count
        var failures = 0
        for item in items {
            let data = try? await item.loadTransferable(type: Data.self)
            if let data, let photo = await Self.prepare({ MilestoneImages.storableJPEG(from: data) }) {
                newPhotos.append(photo)
            } else {
                failures += 1
            }
            processing -= 1
        }
        if failures > 0 {
            photoError = failures == 1
                ? "One photo couldn't be read. If it's in iCloud Photos, check that you're online and try again."
                : "\(failures) photos couldn't be read. If they're in iCloud Photos, check that you're online and try again."
        }
    }

    private func addTaken(_ image: UIImage) async {
        processing += 1
        if let photo = await Self.prepare({ MilestoneImages.storableJPEG(from: image) }) {
            newPhotos.append(photo)
        } else {
            photoError = "The photo couldn't be saved. Please try again."
        }
        processing -= 1
    }

    /// Shrinks a photo and makes its thumbnail, in the background.
    private static func prepare(_ makeJPEG: @escaping @Sendable () -> Data?) async -> NewPhoto? {
        await Task.detached(priority: .userInitiated) { () -> NewPhoto? in
            guard let jpeg = makeJPEG(),
                  let thumbnail = MilestoneImages.downsample(jpeg, maxPixelSize: 240)
            else { return nil }
            return NewPhoto(jpeg: jpeg, thumbnail: UIImage(cgImage: thumbnail))
        }.value
    }

    // MARK: Load & save

    private var canSave: Bool {
        canEditLog && processing == 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let milestone else { return }
        title = milestone.title
        emoji = milestone.displayEmoji
        date = milestone.date
        notes = milestone.notes
        keptPhotoIDs = milestone.photoIDs()
    }

    private func save() {
        let target = milestone ?? Milestone.create(in: context)
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.emoji = emoji
        target.date = date
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let milestone {
            let kept = Set(keptPhotoIDs)
            for id in milestone.objectIDs(forRelationshipNamed: "photos") where !kept.contains(id) {
                context.delete(context.object(with: id))
            }
        }
        // A thousandth of a second apart, so they keep the order they were added in.
        let start = Date.now
        for (index, photo) in newPhotos.enumerated() {
            MilestonePhoto.create(
                jpeg: photo.jpeg, for: target, createdAt: start.addingTimeInterval(Double(index) / 1000), in: context
            )
        }
        context.saveIfChanged()
        dismiss()
    }
}
