import CoreData
import PhotosUI
import SwiftUI
import UIKit

/// Logs a reaction, or edits `reaction`: when, what the baby had (filled in from the last solids
/// log), the symptoms, how bad it was, what you did, an optional photo of a rash and notes. It can
/// add the food as a suspected allergy, or update an allergy, in one tap.
///
/// Ticking trouble breathing or swelling shows the emergency banner at the top, with the emergency
/// number for the person's region. The editor gives no other medical advice.
struct AllergyReactionEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let reaction: AllergyReaction?
    let baby: Baby
    /// For a new reaction logged from an allergy's row: the allergy it's linked to.
    let presetAllergy: Allergy?
    @FetchRequest private var allergies: FetchedResults<Allergy>

    @State private var date = Date.now
    @State private var food = ""
    @State private var symptoms: Set<ReactionSymptom> = []
    @State private var severity: AllergySeverity = .mild
    @State private var actions: Set<ReactionAction> = []
    @State private var notes = ""
    @State private var linkedAllergyID: NSManagedObjectID?
    @State private var plan: AllergyPlan?
    /// The last solids log, offered for "What did baby have?".
    @State private var lastSolids: SolidsSuggestion?

    /// The saved photo, while it's kept; removing it here deletes it when saving.
    @State private var keptPhotoID: NSManagedObjectID?
    @State private var newPhoto: NewPhoto?
    @State private var pickerItem: PhotosPickerItem?
    @State private var processingPhoto = false
    @State private var takingPhoto = false
    @State private var viewingPhoto = false
    @State private var photoError: String?

    @State private var didLoad = false
    @State private var confirmingDelete = false

    init(reaction: AllergyReaction?, baby: Baby, allergy: Allergy? = nil) {
        self.reaction = reaction
        self.baby = baby
        self.presetAllergy = allergy
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
    }

    /// What saving also does to the allergy list, picked with one tap.
    private enum AllergyPlan: Equatable {
        /// Adds a suspected allergy and links the reaction to it.
        case add(name: String, allergenID: String?)
        /// Marks the linked (outgrown) allergy as suspected again.
        case markSuspected
        /// Raises the linked allergy's severity to this reaction's.
        case raiseSeverity
    }

    private struct SolidsSuggestion {
        let food: String
        let date: Date
        let allergens: [CommonAllergen]
    }

    private struct NewPhoto {
        let jpeg: Data
        let thumbnail: UIImage
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this reaction, but only the parents can save changes.") }
                }

                Section {
                    DateField("When", selection: $date)
                    TextField("What did \(baby.displayName) have?", text: $food, axis: .vertical)
                        .lineLimit(1...3)
                    if let lastSolids, AllergyMatch.key(lastSolids.food) != AllergyMatch.key(food) {
                        Button {
                            food = lastSolids.food
                        } label: {
                            Label("Last solids: \(lastSolids.food) · \(Format.timeAgo(lastSolids.date).lowercased())", systemImage: "arrow.uturn.left")
                                .font(.subheadline)
                        }
                        .accessibilityLabel("Use last solids: \(lastSolids.food), \(Format.spokenTimeAgo(lastSolids.date).lowercased())")
                    }
                }

                Section("Symptoms") {
                    ForEach(ReactionSymptom.allCases) { symptom in
                        checkRow(symptom.title, isOn: symptoms.contains(symptom)) {
                            symptoms.formSymmetricDifference([symptom])
                        }
                    }
                }

                Section {
                    Picker("Severity", selection: $severity) {
                        ForEach(AllergySeverity.allCases) { severity in
                            Text(severity.title).tag(severity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Severity")
                } header: {
                    Text("How bad was it?")
                }

                Section("What you did") {
                    ForEach(ReactionAction.allCases) { action in
                        checkRow(action.title, isOn: actions.contains(action)) {
                            actions.formSymmetricDifference([action])
                        }
                    }
                }

                allergySection

                photoSection

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let reaction, canEditLog {
                    Section {
                        Button("Delete reaction", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Delete this reaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                context.delete(reaction)
                                context.saveIfChanged()
                                dismiss()
                            }
                        } message: {
                            Text("Its photo is deleted too.")
                        }
                    }
                }
            }
            // Pinned at the top, so it's in view wherever the form is scrolled to.
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsEmergencyBanner {
                    AllergyEmergencyBanner()
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.s)
                        .background(.bar)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.25), value: showsEmergencyBanner)
            .navigationTitle(reaction == nil ? "Log a reaction" : "Edit reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canEditLog || processingPhoto)
                }
            }
            .onAppear(perform: load)
            .onChange(of: showsEmergencyBanner) { _, shown in
                // Said out loud too, since the banner appears above where VoiceOver is.
                if shown {
                    UIAccessibility.post(notification: .announcement, argument: AllergyEmergencyBanner.currentMessage)
                }
            }
            .onChange(of: linkedAllergyID) { _, _ in
                // A one-tap change was for the allergy that was linked before, or for none.
                plan = nil
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task { await addPicked(item) }
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
            .fullScreenCover(isPresented: $viewingPhoto) {
                if let keptPhotoID {
                    PhotoViewer(photoIDs: [keptPhotoID], startIndex: 0, title: String(localized: "Reaction photo"))
                }
            }
            .alert("Couldn't add the photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoError ?? "")
            }
        }
        .threeAMSheet()
    }

    private var showsEmergencyBanner: Bool {
        symptoms.contains { $0.showsEmergencyBanner }
    }

    /// A row that ticks or unticks, like the symptoms of a temperature.
    private func checkRow(_ title: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Allergy

    private var linkedAllergy: Allergy? {
        guard let linkedAllergyID else { return nil }
        return allergies.first { $0.objectID == linkedAllergyID }
    }

    /// The allergy already on the list for what they had, to link in one tap.
    private var matchingAllergy: Allergy? {
        let tags = Set(foodAllergens.map(\.id))
        return allergies.sortedForDisplay().first { allergy in
            AllergyMatch.foodMatches(allergyName: allergy.displayName, allergenID: allergy.allergenRaw, tags: tags, food: food)
        }
    }

    /// The common allergens what they had mentions, or the ones tagged on the last solids when
    /// that's what's written.
    private var foodAllergens: [CommonAllergen] {
        let mentioned = AllergyMatch.foodAllergensMentioned(in: food)
        if !mentioned.isEmpty { return mentioned }
        if let lastSolids, AllergyMatch.key(lastSolids.food) == AllergyMatch.key(food) {
            return lastSolids.allergens
        }
        return []
    }

    /// What "Add as a suspected allergy" would add: the one allergen what they had mentions, or
    /// what they had as it's written.
    private var suggestedAllergy: (name: String, allergenID: String?)? {
        let allergens = foodAllergens
        if allergens.count == 1, let allergen = allergens.first {
            return (allergen.name, allergen.id)
        }
        let written = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, allergens.isEmpty else { return nil }
        return (written, nil)
    }

    @ViewBuilder
    private var allergySection: some View {
        Section {
            Picker("Linked allergy", selection: $linkedAllergyID) {
                Text("None").tag(NSManagedObjectID?.none)
                ForEach(allergies.sortedForDisplay()) { allergy in
                    Text(allergy.displayName).tag(NSManagedObjectID?.some(allergy.objectID))
                }
            }

            if canEditLog {
                planRows
            }
        } header: {
            Text("Allergy")
        } footer: {
            Text("A suspected allergy goes on \(baby.displayName)'s allergy list and allergy card. Your pediatrician can help you find out more.")
        }
    }

    @ViewBuilder
    private var planRows: some View {
        if let plan {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                NoticeLabel(planText(plan), systemImage: "checkmark.circle.fill", tint: Palette.ok)
                Button("Undo") { self.plan = nil }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        } else if let linked = linkedAllergy {
            if linked.status == .outgrown {
                Button("Mark \(linked.displayName) as suspected again") { plan = .markSuspected }
            } else if severity > linked.severity {
                Button("Update \(linked.displayName) to \(severity.title.lowercased())") { plan = .raiseSeverity }
            }
        } else if let match = matchingAllergy {
            Button("Link to \(match.displayName)") { linkedAllergyID = match.objectID }
        } else if let suggestion = suggestedAllergy {
            Button("Add \(suggestion.name) as a suspected allergy") {
                plan = .add(name: suggestion.name, allergenID: suggestion.allergenID)
            }
        }
    }

    private func planText(_ plan: AllergyPlan) -> String {
        switch plan {
        case .add(let name, _):
            return String(localized: "\(name) will be added as a suspected allergy when you save.")
        case .markSuspected:
            guard let name = linkedAllergy?.displayName else {
                return String(localized: "The allergy will be marked as suspected when you save.")
            }
            return String(localized: "\(name) will be marked as suspected when you save.")
        case .raiseSeverity:
            let level = severity.title.lowercased()
            guard let name = linkedAllergy?.displayName else {
                return String(localized: "The allergy will be updated to \(level) when you save.", comment: "The new severity: mild, moderate or severe")
            }
            return String(localized: "\(name) will be updated to \(level) when you save.", comment: "An allergy, then its new severity: mild, moderate or severe")
        }
    }

    // MARK: Photo

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if let keptPhotoID {
                HStack(spacing: Spacing.m) {
                    Button {
                        viewingPhoto = true
                    } label: {
                        MilestoneThumbnail(photoID: keptPhotoID, side: 76, cornerRadius: Radius.photo)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("View photo")
                    Spacer()
                    removePhotoButton { self.keptPhotoID = nil }
                }
            } else if let newPhoto {
                HStack(spacing: Spacing.m) {
                    Image(uiImage: newPhoto.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
                        .accessibilityLabel("Photo to add")
                    Spacer()
                    removePhotoButton { self.newPhoto = nil }
                }
            } else if processingPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Adding photo…")
                        .foregroundStyle(.secondary)
                }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
                if CameraPicker.isAvailable {
                    Button {
                        takingPhoto = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                }
            }
        } header: {
            Text("Photo (optional)")
        } footer: {
            Text("A photo of a rash can help when you talk to the doctor. It's saved smaller, without its location, and stays end-to-end encrypted with the rest of the log.")
        }
        .disabled(!canEditLog && keptPhotoID == nil)
    }

    private func removePhotoButton(_ remove: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: remove) {
            Label("Remove photo", systemImage: "trash")
        }
        .buttonStyle(.borderless)
        .disabled(!canEditLog)
    }

    private func addPicked(_ item: PhotosPickerItem) async {
        processingPhoto = true
        let data = try? await item.loadTransferable(type: Data.self)
        if let data, let photo = await Self.prepare({ MilestoneImages.storableJPEG(from: data) }) {
            keptPhotoID = nil
            newPhoto = photo
        } else {
            photoError = String(localized: "The photo couldn't be read. If it's in iCloud Photos, check that you're online and try again.")
        }
        processingPhoto = false
    }

    private func addTaken(_ image: UIImage) async {
        processingPhoto = true
        if let photo = await Self.prepare({ MilestoneImages.storableJPEG(from: image) }) {
            keptPhotoID = nil
            newPhoto = photo
        } else {
            photoError = String(localized: "The photo couldn't be saved. Please try again.")
        }
        processingPhoto = false
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

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let solids = loadLastSolids()
        lastSolids = solids

        guard let reaction else {
            linkedAllergyID = presetAllergy?.objectID
            // Filled in from the last solids log when it was in the last day.
            if let solids, Date.now.timeIntervalSince(solids.date) <= AllergenIntroduction.reactionWindow {
                food = solids.food
            } else if let presetAllergy {
                food = presetAllergy.displayName
            }
            return
        }
        date = reaction.date
        food = reaction.food
        symptoms = Set(reaction.symptoms)
        severity = reaction.severity
        actions = Set(reaction.actions)
        notes = reaction.notes
        linkedAllergyID = reaction.allergy?.objectID
        keptPhotoID = reaction.photoIDs().first
    }

    /// The most recent solids log, with what baby ate (or the allergens tagged on it).
    private func loadLastSolids() -> SolidsSuggestion? {
        let request = baby.entries(Activity.fetch(
            NSPredicate(format: "kindRaw == %@ AND feedingTypeRaw == %@", ActivityKind.feeding.rawValue, FeedingType.solids.rawValue),
            limit: 1
        ))
        guard let last = try? context.fetch(request).first else { return nil }
        let allergens = last.allergens
        let written = (last.foodDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let food = written.isEmpty ? allergens.map(\.name).joined(separator: ", ") : written
        guard !food.isEmpty else { return nil }
        return SolidsSuggestion(food: food, date: last.startDate, allergens: allergens)
    }

    private func save() {
        let target = reaction ?? AllergyReaction.create(for: baby, in: context)
        target.date = date
        target.food = food.trimmingCharacters(in: .whitespacesAndNewlines)
        target.symptoms = ReactionSymptom.allCases.filter { symptoms.contains($0) }
        target.severity = severity
        target.actions = ReactionAction.allCases.filter { actions.contains($0) }
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var allergy = linkedAllergy
        switch plan {
        case .add(let name, let allergenID)?:
            let added = Allergy.create(for: baby, in: context)
            added.name = name
            added.allergenRaw = allergenID
            added.category = allergenID.flatMap(CommonAllergen.with(id:))?.category ?? .food
            added.status = .suspected
            added.severity = severity
            added.reactionsSeen = target.symptomsText
            allergy = added
        case .markSuspected?:
            allergy?.status = .suspected
        case .raiseSeverity?:
            if let allergy, severity > allergy.severity { allergy.severity = severity }
        case nil:
            break
        }
        target.allergy = allergy

        // The photo: the saved one goes if it was removed or replaced; a new one is added.
        if let reaction {
            for id in reaction.objectIDs(forRelationshipNamed: "photos") where id != keptPhotoID {
                context.delete(context.object(with: id))
            }
        }
        if let newPhoto {
            AllergyReactionPhoto.create(jpeg: newPhoto.jpeg, for: target, in: context)
        }

        context.saveIfChanged()
        dismiss()
    }
}
