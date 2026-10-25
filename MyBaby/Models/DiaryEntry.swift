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
enum DiaryKind: String, CaseIterable, Identifiable {
    case moment, learned, first, funny, letter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moment: return "Moment"
        case .learned: return "Learned something new"
        case .first: return "A first"
        case .funny: return "Funny"
        case .letter: return "Letter for later"
        }
    }

    /// For chips and filters, where space is short.
    var shortTitle: String {
        switch self {
        case .moment: return "Moment"
        case .learned: return "Learned"
        case .first: return "A first"
        case .funny: return "Funny"
        case .letter: return "Letter"
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
    func prompts(for baby: Baby) -> [String] {
        let name = baby.displayName
        let they = baby.subjectPronoun
        let them = baby.objectPronoun
        let their = baby.possessivePronoun
        switch self {
        case .moment:
            return [
                "What made you smile this week?",
                "What does \(name) love right now?",
                "A little moment you don't want to forget",
            ]
        case .learned:
            return [
                "What did \(they) learn?",
                "Something new \(they) can do",
                "How \(they) figured it out",
            ]
        case .first:
            return [
                "A first today",
                "Where were you, and who was there?",
                "How \(they) reacted",
            ]
        case .funny:
            return [
                "What made you laugh?",
                "The funniest face \(they) made",
                "Something \(they) did that nobody expected",
            ]
        case .letter:
            return [
                "What do you want \(name) to know?",
                "What were you dreaming of for \(them)?",
                "What \(their) days are like right now",
            ]
        }
    }
}

// MARK: - Letters for later

extension DiaryEntry {
    /// "to open at 18", "to open on Feb 12, 2040", or "for one day" when there's no target.
    var openWhenText: String {
        if let openOnDate {
            return "to open on \(openOnDate.formatted(date: .abbreviated, time: .omitted))"
        }
        if let age = openAtAge {
            return "to open at \(age)"
        }
        return "for one day"
    }

    /// "For Mavie, to open at 18", the line on a sealed envelope.
    func envelopeLine(babyName: String) -> String {
        "For \(babyName), \(openWhenText)"
    }
}

// MARK: - Baby

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var diaryEntries: NSSet?

    /// "she", "he", or the baby's name when their sex isn't set, so nothing is assumed.
    var subjectPronoun: String {
        switch sex {
        case .female: return "she"
        case .male: return "he"
        case nil: return displayName
        }
    }

    /// "her", "him", or the name.
    var objectPronoun: String {
        switch sex {
        case .female: return "her"
        case .male: return "him"
        case nil: return displayName
        }
    }

    /// "her", "his", or "Mavie's".
    var possessivePronoun: String {
        switch sex {
        case .female: return "her"
        case .male: return "his"
        case nil: return "\(displayName)'s"
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
