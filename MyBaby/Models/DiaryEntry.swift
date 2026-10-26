import CoreData
import Foundation

/// Something a parent wrote down for the baby: a moment, something new they learned, a first, a funny
/// thing they did, or a letter for them to read when they're older.
///
/// Belongs to the baby like every other entry, so it syncs and is shared with the partner, and each one
/// says who wrote it. A note about a whole week or month (written from its summary) is a diary entry too,
/// linked to that period with `periodKind` and `periodIndex`, so it also shows in the diary.
@objc(DiaryEntry)
final class DiaryEntry: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    /// The day it's about. Notes about a past week or month are dated on its last day.
    @NSManaged var date: Date
    @NSManaged var createdAt: Date
    @NSManaged var title: String
    @NSManaged var text: String
    /// Who wrote it, e.g. "Mom". Empty when nobody said.
    @NSManaged var authorName: String
    /// `DiaryKind`.
    @NSManaged var kindRaw: String
    /// A letter for later: the birthday it's meant to be opened on (18 for the 18th birthday).
    @NSManaged var openAtAgeNumber: NSNumber?
    /// A letter for later: the day it's meant to be opened on.
    @NSManaged var openOnDate: Date?
    /// `DiaryPeriod.Kind`, for a note about a week or month of the baby's life.
    @NSManaged var periodKindRaw: String?
    /// Which week or month (1 is the first), with `periodKindRaw`.
    @NSManaged var periodIndexNumber: NSNumber?
    @NSManaged var photos: NSSet?
    @NSManaged var baby: Baby?

    /// A new entry for the current baby, saved in the baby's store so it's shared with the same people.
    @discardableResult
    static func create(_ kind: DiaryKind = .moment, date: Date = .now, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.uuid = UUID()
        entry.date = date
        entry.createdAt = .now
        entry.title = ""
        entry.text = ""
        entry.authorName = ""
        entry.kind = kind
        Baby.attach(entry, in: context) { entry.baby = $0 }
        return entry
    }

    /// Every entry, newest first.
    static func fetchAll() -> NSFetchRequest<DiaryEntry> {
        let request = NSFetchRequest<DiaryEntry>(entityName: "DiaryEntry")
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
        return request
    }

    /// Entries dated within [start, end), newest first.
    static func between(_ start: Date, _ end: Date) -> NSFetchRequest<DiaryEntry> {
        let request = fetchAll()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        return request
    }

    /// Every letter for later, newest first.
    static func letters() -> NSFetchRequest<DiaryEntry> {
        let request = fetchAll()
        request.predicate = NSPredicate(format: "kindRaw == %@", DiaryKind.letter.rawValue)
        return request
    }

    /// Every note about a week or month, newest first.
    static func periodNotes() -> NSFetchRequest<DiaryEntry> {
        let request = fetchAll()
        request.predicate = NSPredicate(format: "periodKindRaw != nil")
        return request
    }

    // MARK: Values

    var kind: DiaryKind {
        get { DiaryKind(rawValue: kindRaw) ?? .moment }
        set { kindRaw = newValue.rawValue }
    }

    var openAtAge: Int? {
        get { openAtAgeNumber?.intValue }
        set { openAtAgeNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// The week or month this note is about, if it's about one.
    var periodID: DiaryPeriod.ID? {
        get {
            guard let raw = periodKindRaw, let kind = DiaryPeriod.Kind(rawValue: raw),
                  let index = periodIndexNumber?.intValue
            else { return nil }
            return DiaryPeriod.ID(kind: kind, index: index)
        }
        set {
            periodKindRaw = newValue?.kind.rawValue
            periodIndexNumber = newValue.map { NSNumber(value: $0.index) }
        }
    }

    /// When a letter for later is meant to be opened: its date, or that birthday. `nil` when it has
    /// no target, or the target is a birthday and the birth date isn't set.
    func opensOn(birthDate: Date?, calendar: Calendar = .current) -> Date? {
        if let openOnDate { return calendar.startOfDay(for: openOnDate) }
        guard let age = openAtAge, let birthDate else { return nil }
        return calendar.date(byAdding: .year, value: age, to: calendar.startOfDay(for: birthDate))
    }

    /// Whether a letter for later is still waiting for its day. Letters without a day stay sealed,
    /// since they're for "one day". Never true for other kinds.
    func isSealed(birthDate: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard kind == .letter else { return false }
        guard let opens = opensOn(birthDate: birthDate, calendar: calendar) else { return true }
        return now < opens
    }

    /// The title, or the first line of the text, or the kind.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !firstLine.isEmpty { return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine }
        return kind.title
    }

    /// "Mom", trimmed, or nil when nobody said.
    var author: String? {
        let name = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Which photos there are, without loading any. Changes when one is added or removed, here or on
    /// the partner's phone.
    var photoIDSet: Set<NSManagedObjectID> { Set(objectIDs(forRelationshipNamed: "photos")) }

    /// The photos' object IDs, oldest first. Fetched as IDs so the image data stays on disk:
    /// thumbnails are decoded in the background (see `MilestoneImages`).
    func photoIDs() -> [NSManagedObjectID] {
        guard let context = managedObjectContext else { return [] }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "DiaryPhoto")
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "entry == %@", self)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// "Oct 12, 2026 · 6 weeks old", or just the date before a birthday is set (or before birth).
    func dateAndAge(birthDate: Date?) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day().year())
        guard let birthDate, date >= Calendar.current.startOfDay(for: birthDate) else { return day }
        return "\(day) · \(Format.age(birthDate: birthDate, now: date))"
    }
}

/// One photo in a diary entry, as a small JPEG.
///
/// Kept inside the record, exactly like `MilestonePhoto`: an external file would sync as a CKAsset,
/// which isn't covered by the end-to-end encryption the rest of the log uses. Each photo is downscaled
/// by `MilestoneImages` to fit comfortably in a CloudKit record, one photo per record.
@objc(DiaryPhoto)
final class DiaryPhoto: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var createdAt: Date
    @NSManaged var entry: DiaryEntry?

    /// Adds `jpeg` to `entry`, in the same store as its baby so it's shared along with it.
    @discardableResult
    static func create(jpeg: Data, for entry: DiaryEntry, createdAt: Date = .now, in context: NSManagedObjectContext) -> DiaryPhoto {
        let photo = DiaryPhoto(context: context)
        photo.uuid = UUID()
        photo.createdAt = createdAt
        photo.imageData = jpeg
        // A new entry's own ID doesn't know its store until it's saved; its baby's does.
        if let store = entry.baby?.objectID.persistentStore {
            context.assign(photo, to: store)
        }
        photo.entry = entry
        return photo
    }
}

/// What a diary entry is.
enum DiaryKind: String, CaseIterable, Identifiable, Sendable {
    case moment, learned, first, funny, letter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moment: return String(localized: "Moment", comment: "Kind of diary entry")
        case .learned: return String(localized: "Learned something new", comment: "Kind of diary entry: the baby learned something new")
        case .first: return String(localized: "A first", comment: "Kind of diary entry: a first time, like a first smile")
        case .funny: return String(localized: "Funny", comment: "Kind of diary entry: something funny the baby did")
        case .letter: return String(localized: "Letter for later", comment: "Kind of diary entry: a letter for the child to read when older")
        }
    }

    /// For chips and filters, where space is short.
    var shortTitle: String {
        switch self {
        case .moment: return String(localized: "Moment", comment: "Kind of diary entry")
        case .learned: return String(localized: "Learned", comment: "Short kind of diary entry: the baby learned something new")
        case .first: return String(localized: "A first", comment: "Kind of diary entry: a first time, like a first smile")
        case .funny: return String(localized: "Funny", comment: "Kind of diary entry: something funny the baby did")
        case .letter: return String(localized: "Letter", comment: "Short kind of diary entry: a letter for later")
        }
    }

    /// The diary CSV export's Kind column.
    // Not localized: CSV value, read back by the importer
    var exportName: String {
        switch self {
        case .moment: return "Moment"
        case .learned: return "Learned something new"
        case .first: return "A first"
        case .funny: return "Funny"
        case .letter: return "Letter for later"
        }
    }

    var emoji: String {
        switch self {
        case .moment: return "💛"
        case .learned: return "🌱"
        case .first: return "⭐️"
        case .funny: return "😂"
        case .letter: return "💌"
        }
    }

    /// A few gentle questions to start from, using the baby's name and, when it's set, their pronouns.
    /// Each question is written out for "she", "he" and the name, since pronouns change the rest of
    /// the sentence in other languages.
    func prompts(for baby: Baby) -> [String] {
        let name = baby.displayName
        let sex = baby.sex
        func pick(female: String, male: String, named: String) -> String {
            switch sex {
            case .female: return female
            case .male: return male
            case nil: return named
            }
        }
        switch self {
        case .moment:
            return [
                String(localized: "What made you smile this week?", comment: "Diary prompt"),
                String(localized: "What does \(name) love right now?", comment: "Diary prompt"),
                String(localized: "A little moment you don't want to forget", comment: "Diary prompt"),
            ]
        case .learned:
            return [
                pick(female: String(localized: "What did she learn?", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "What did he learn?", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "What did \(name) learn?", comment: "Diary prompt, with the baby's name")),
                pick(female: String(localized: "Something new she can do", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "Something new he can do", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "Something new \(name) can do", comment: "Diary prompt, with the baby's name")),
                pick(female: String(localized: "How she figured it out", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "How he figured it out", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "How \(name) figured it out", comment: "Diary prompt, with the baby's name")),
            ]
        case .first:
            return [
                String(localized: "A first today", comment: "Diary prompt"),
                String(localized: "Where were you, and who was there?", comment: "Diary prompt"),
                pick(female: String(localized: "How she reacted", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "How he reacted", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "How \(name) reacted", comment: "Diary prompt, with the baby's name")),
            ]
        case .funny:
            return [
                String(localized: "What made you laugh?", comment: "Diary prompt"),
                pick(female: String(localized: "The funniest face she made", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "The funniest face he made", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "The funniest face \(name) made", comment: "Diary prompt, with the baby's name")),
                pick(female: String(localized: "Something she did that nobody expected", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "Something he did that nobody expected", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "Something \(name) did that nobody expected", comment: "Diary prompt, with the baby's name")),
            ]
        case .letter:
            return [
                String(localized: "What do you want \(name) to know?", comment: "Diary prompt"),
                pick(female: String(localized: "What were you dreaming of for her?", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "What were you dreaming of for him?", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "What were you dreaming of for \(name)?", comment: "Diary prompt, with the baby's name")),
                pick(female: String(localized: "What her days are like right now", comment: "Diary prompt about a baby girl"),
                     male: String(localized: "What his days are like right now", comment: "Diary prompt about a baby boy"),
                     named: String(localized: "What \(name)'s days are like right now", comment: "Diary prompt, with the baby's name")),
            ]
        }
    }
}

// MARK: - Letters for later

extension DiaryEntry {
    /// "For Mavie, to open at 18", "For Mavie, to open on Feb 12, 2040", or "For Mavie, for one day"
    /// when there's no target: the line on a sealed envelope.
    func envelopeLine(babyName: String) -> String {
        if let openOnDate {
            let day = openOnDate.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "For \(babyName), to open on \(day)", comment: "A letter for later, on its envelope: the child's name and the day to open it")
        }
        if let age = openAtAge {
            return String(localized: "For \(babyName), to open at \(age)", comment: "A letter for later, on its envelope: the child's name and the birthday (age in years) to open it")
        }
        return String(localized: "For \(babyName), for one day", comment: "A letter for later with no day to open it, on its envelope")
    }
}

// MARK: - Baby

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var diaryEntries: NSSet?

    /// "she", "he", or the baby's name when their sex isn't set, so nothing is assumed.
    ///
    /// The words are translated, but they only fit English sentences: in other languages a pronoun
    /// changes the rest of the sentence, so a localized sentence is better written out for "she",
    /// "he" and the name (see `DiaryKind.prompts(for:)`).
    var subjectPronoun: String {
        switch sex {
        case .female: return String(localized: "she", comment: "Pronoun for a baby girl, as the subject of a sentence")
        case .male: return String(localized: "he", comment: "Pronoun for a baby boy, as the subject of a sentence")
        case nil: return displayName
        }
    }

    /// "her", "him", or the name.
    var objectPronoun: String {
        switch sex {
        case .female: return String(localized: "her", comment: "Pronoun for a baby girl, as the object of a sentence (“for her”)")
        case .male: return String(localized: "him", comment: "Pronoun for a baby boy, as the object of a sentence (“for him”)")
        case nil: return displayName
        }
    }

    /// "her", "his", or "Mavie's".
    var possessivePronoun: String {
        switch sex {
        case .female: return String(localized: "pronoun.possessive.her", defaultValue: "her", comment: "Possessive for a baby girl (“her birthday”)")
        case .male: return String(localized: "his", comment: "Possessive for a baby boy (“his birthday”)")
        case nil: return String(localized: "\(displayName)'s", comment: "Possessive with the baby's name (“Mavie's birthday”)")
        }
    }
}

// MARK: - Settings

extension SettingsKey {
    /// The monthly "Mavie is 3 months today" diary reminder (`DiaryReminder`). Off by default.
    static let diaryReminderEnabled = "diaryReminderEnabled"
    /// The name last written under "Written by" on this iPhone, offered first next time.
    static let diaryAuthor = "diaryAuthor"
    /// Ids of the week and month summaries whose card on Today was dismissed (`DiaryPeriod.ID.key`).
    static let dismissedDiaryCards = "dismissedDiaryCards"
}
