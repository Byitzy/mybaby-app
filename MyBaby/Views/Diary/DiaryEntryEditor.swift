import CoreData
import PhotosUI
import SwiftUI

/// What the diary's editor opens with: a new entry of a kind, a note about a week or month, or an
/// entry to change.
struct DiaryEditorTarget: Identifiable {
    let id = UUID()
    /// The entry to change, or nil for a new one.
    var entry: DiaryEntry?
    var kind: DiaryKind = .moment
    /// For a new note about a week or month, written from its summary.
    var period: DiaryPeriod?

    static func new(_ kind: DiaryKind = .moment) -> DiaryEditorTarget {
        DiaryEditorTarget(entry: nil, kind: kind)
    }

    static func edit(_ entry: DiaryEntry) -> DiaryEditorTarget {
        DiaryEditorTarget(entry: entry, kind: entry.kind)
    }

    static func note(about period: DiaryPeriod) -> DiaryEditorTarget {
        DiaryEditorTarget(entry: nil, kind: .moment, period: period)
    }
}

/// Writes a diary entry, or changes one: a big space for the words, a few gentle prompts to start from,
/// what kind of entry it is, who wrote it, photos, and for a letter for later, when it's meant to be opened.
///
/// Photos work exactly like a milestone's (see `MilestoneEditor`): no permission prompt for the library,
/// and each photo is shrunk to a small JPEG without its location before it's saved.
struct DiaryEntryEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()

    let target: DiaryEditorTarget
    @ObservedObject var baby: Baby

    @State private var kind: DiaryKind = .moment
    @State private var title = ""
    @State private var text = ""
    @State private var date = Date.now
    @State private var author = ""
    @State private var letterOpen: LetterOpen = .birthday
    @State private var openAtAge = 18
    @State private var openOnDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    /// Saved photos still on the entry; ones removed here are deleted when saving.
    @State private var keptPhotoIDs: [NSManagedObjectID] = []
    /// Photos added here, already shrunk, saved with the entry.
    @State private var newPhotos: [NewPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Photos still being read and shrunk.
    @State private var processing = 0
    @State private var takingPhoto = false
    @State private var photoError: String?
    @State private var didLoad = false
    @FocusState private var isWriting: Bool

    /// Plenty for one entry, and keeps its sync quick.
    private static let maxPhotos = 20

    /// When a letter for later is meant to be opened.
    enum LetterOpen: String, CaseIterable, Identifiable {
        case birthday, date, oneDay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .birthday: return String(localized: "On a birthday", comment: "When to open a letter for later")
            case .date: return String(localized: "On a date", comment: "When to open a letter for later")
            case .oneDay: return String(localized: "One day", comment: "When to open a letter for later: some day, no date set")
            }
        }
    }

    private struct NewPhoto: Identifiable {
        let id = UUID()
        let jpeg: Data
        let thumbnail: UIImage
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can read the diary, but only the parents can write in it.") }
                }

                if let period = notePeriod {
                    Section {
                        Label("About \(period.fullTitle())", systemImage: "calendar")
                    }
                } else {
                    Section("What is it?") {
                        kindChips
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    TextField("Title (optional)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    writingSpace
                }

                if text.isEmpty {
                    Section("Need a place to start?") {
                        promptChips
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                if notePeriod == nil {
                    Section {
                        DateField("Date", selection: $date, in: ...Date.now, includesTime: false)
                    } footer: {
                        if let birthDate = baby.birthDate, date >= Calendar.current.startOfDay(for: birthDate) {
                            Text("\(baby.displayName): \(Format.age(birthDate: birthDate, now: date))")
                        }
                    }
                }

                if kind == .letter {
                    letterSection
                }

                authorSection

                photosSection
            }
            .navigationTitle(navigationTitle)
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

    /// The week or month a note is about: the one it was started from, or the one it's linked to.
    private var notePeriod: DiaryPeriod? {
        if let period = target.period { return period }
        guard let id = target.entry?.periodID, let birthDate = baby.birthDate else { return nil }
        return DiaryPeriod.period(id, birthDate: birthDate)
    }

    private var navigationTitle: String {
        if let period = notePeriod {
            return target.entry == nil ? String(localized: "About \(period.title)", comment: "e.g. “About Month 3”") : String(localized: "Edit note")
        }
        if target.entry != nil { return String(localized: "Edit entry") }
        return kind == .letter ? String(localized: "Letter for later") : String(localized: "New entry")
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiaryKind.allCases) { option in
                    let isSelected = kind == option
                    Button {
                        kind = option
                    } label: {
                        Text("\(option.emoji) \(option.shortTitle)")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, 7)
                            .background(isSelected ? Palette.diary : Palette.chipBackground, in: Capsule())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// The big text area, with a soft placeholder while it's empty.
    private var writingSpace: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .focused($isWriting)
                .scrollContentBackground(.hidden)
                .accessibilityLabel(kind == .letter ? "Your letter" : "What you want to remember")
        }
    }

    private var placeholder: String {
        if kind == .letter { return String(localized: "Dear \(baby.displayName), …", comment: "How a letter to the baby starts") }
        if let period = notePeriod {
            return period.kind == .week
                ? String(localized: "A few words about this week, for \(baby.displayName) to read one day…")
                : String(localized: "A few words about this month, for \(baby.displayName) to read one day…")
        }
        return String(localized: "Write as much or as little as you like…")
    }

    private var prompts: [String] {
        guard let period = notePeriod else { return kind.prompts(for: baby) }
        let isWeek = period.kind == .week
        return [
            isWeek ? String(localized: "What made you smile this week?") : String(localized: "What made you smile this month?"),
            DiaryText.whatDidTheyLearn(baby),
            isWeek
                ? String(localized: "What do you want to remember about this week?")
                : String(localized: "What do you want to remember about this month?"),
        ]
    }

    /// Tapping a prompt makes it the title (unless one was typed) and opens the keyboard.
    private var promptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        let typedTitle = !title.isEmpty && !prompts.contains(title)
                        if !typedTitle { title = prompt }
                        isWriting = true
                    } label: {
                        Text(prompt)
                            .font(.subheadline)
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, 7)
                            .background(Palette.diary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Starts your entry with this question")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var letterSection: some View {
        Section {
            Picker("Open", selection: $letterOpen) {
                ForEach(LetterOpen.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            switch letterOpen {
            case .birthday:
                Stepper(value: $openAtAge, in: 1...40) {
                    LabeledContent("Birthday", value: DiaryText.ordinal(openAtAge))
                }
                .accessibilityValue("\(DiaryText.ordinal(openAtAge)) birthday")
            case .date:
                DateField("Open on", selection: $openOnDate, in: Date.now..., includesTime: false)
            case .oneDay:
                EmptyView()
            }
        } header: {
            Text("When to open it")
        } footer: {
            Text("It's kept sealed in the diary until then, as an envelope that says \"\(previewEnvelope)\". You can still read it any time with Read anyway.")
        }
    }

    private var previewEnvelope: String {
        switch letterOpen {
        case .birthday:
            return String(localized: "For \(baby.displayName), to open at \(openAtAge)", comment: "On a sealed letter: to open at that age")
        case .date:
            let day = openOnDate.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "For \(baby.displayName), to open on \(day)", comment: "On a sealed letter")
        case .oneDay:
            return String(localized: "For \(baby.displayName), for one day", comment: "On a sealed letter with no date: for some day")
        }
    }

    /// The parents' names from the night plan, and both together, one tap away.
    private var authorChoices: [String] {
        let plan = NightPlan(data: nightPlanData)
        let first = plan.name(of: .parent1)
        let second = plan.name(of: .parent2)
        return first == second ? [first] : [first, second, "\(first) & \(second)"]
    }

    private var authorSection: some View {
        Section {
            TextField("Your name", text: $author)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Written by")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(authorChoices, id: \.self) { name in
                        let isSelected = author == name
                        Button {
                            author = name
                        } label: {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, Spacing.m)
                                .padding(.vertical, 6)
                                .background(isSelected ? Palette.diary : Palette.chipBackground, in: Capsule())
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Written by \(name)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        } header: {
            Text("Written by")
        } footer: {
            Text("Shown with the entry, so you both know who wrote what.")
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
                ? String(localized: "One photo couldn't be read. If it's in iCloud Photos, check that you're online and try again.")
                : String(localized: "\(failures) photos couldn't be read. If they're in iCloud Photos, check that you're online and try again.")
        }
    }

    private func addTaken(_ image: UIImage) async {
        processing += 1
        if let photo = await Self.prepare({ MilestoneImages.storableJPEG(from: image) }) {
            newPhotos.append(photo)
        } else {
            photoError = String(localized: "The photo couldn't be saved. Please try again.")
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
        let hasWords = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return canEditLog && processing == 0 && (hasWords || !keptPhotoIDs.isEmpty || !newPhotos.isEmpty)
    }

    /// This iPhone's parent (from "This iPhone belongs to" in Night shifts), or the name last used here.
    private var defaultAuthor: String {
        let plan = NightPlan(data: nightPlanData)
        switch plan.alarmOwner {
        case .parent1: return plan.name(of: .parent1)
        case .parent2: return plan.name(of: .parent2)
        case .both: return UserDefaults.standard.string(forKey: SettingsKey.diaryAuthor) ?? ""
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let entry = target.entry else {
            kind = target.kind
            author = defaultAuthor
            return
        }
        kind = entry.kind
        title = entry.title
        text = entry.text
        date = entry.date
        author = entry.authorName
        if let openOn = entry.openOnDate {
            letterOpen = .date
            openOnDate = openOn
        } else if let age = entry.openAtAge {
            letterOpen = .birthday
            openAtAge = age
        } else {
            letterOpen = entry.kind == .letter ? .oneDay : .birthday
        }
        keptPhotoIDs = entry.photoIDs()
    }

    private func save() {
        let isNew = target.entry == nil
        let entry = target.entry ?? DiaryEntry.create(kind, in: context)
        entry.kind = kind
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.authorName = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if let period = target.period, isNew {
            entry.periodID = period.id
            entry.date = period.noteDate()
        } else if notePeriod == nil {
            entry.date = date
        }

        if kind == .letter {
            switch letterOpen {
            case .birthday:
                entry.openAtAge = openAtAge
                entry.openOnDate = nil
            case .date:
                entry.openAtAge = nil
                entry.openOnDate = Calendar.current.startOfDay(for: openOnDate)
            case .oneDay:
                entry.openAtAge = nil
                entry.openOnDate = nil
            }
        } else {
            entry.openAtAge = nil
            entry.openOnDate = nil
        }

        if !isNew {
            let kept = Set(keptPhotoIDs)
            for id in entry.objectIDs(forRelationshipNamed: "photos") where !kept.contains(id) {
                context.delete(context.object(with: id))
            }
        }
        // A thousandth of a second apart, so they keep the order they were added in.
        let start = Date.now
        for (index, photo) in newPhotos.enumerated() {
            DiaryPhoto.create(jpeg: photo.jpeg, for: entry, createdAt: start.addingTimeInterval(Double(index) / 1000), in: context)
        }
        if !entry.authorName.isEmpty {
            UserDefaults.standard.set(entry.authorName, forKey: SettingsKey.diaryAuthor)
        }
        context.saveIfChanged()
        dismiss()
    }
}
