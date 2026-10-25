import CoreData
import Foundation

/// A moment worth keeping: a first smile, first steps, a first bath. A keepsake, not a
/// development checklist, so there are no "should happen by" ages anywhere.
///
/// Belongs to the baby like every other entry, so partners share milestones and their photos.
@objc(Milestone)
final class Milestone: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String
    @NSManaged var date: Date
    @NSManaged var notes: String
    @NSManaged var emoji: String
    @NSManaged var photos: NSSet?
    @NSManaged var baby: Baby?

    @discardableResult
    static func create(in context: NSManagedObjectContext) -> Milestone {
        let milestone = Milestone(context: context)
        milestone.uuid = UUID()
        milestone.date = .now
        milestone.title = ""
        milestone.notes = ""
        milestone.emoji = Self.defaultEmoji
        Baby.attach(milestone, in: context) { milestone.baby = $0 }
        return milestone
    }

    /// Every milestone, newest first.
    static func fetchAll() -> NSFetchRequest<Milestone> {
        let request = NSFetchRequest<Milestone>(entityName: "Milestone")
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "title", ascending: true),
        ]
        return request
    }

    static let defaultEmoji = "⭐️"

    var displayTitle: String { title.isEmpty ? "Milestone" : title }
    var displayEmoji: String { emoji.isEmpty ? Self.defaultEmoji : emoji }

    /// Which photos there are, without loading any of them. Changes when one is added or removed,
    /// here or on the partner's phone.
    var photoIDSet: Set<NSManagedObjectID> { Set(objectIDs(forRelationshipNamed: "photos")) }

    /// The photos' object IDs, oldest first. Fetched as IDs so the image data stays on disk:
    /// thumbnails are decoded from it in the background (see `MilestoneImages`).
    func photoIDs() -> [NSManagedObjectID] {
        guard let context = managedObjectContext else { return [] }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "MilestonePhoto")
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "milestone == %@", self)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// "Oct 12, 2026 · 6 weeks old", or just the date before a birthday is set.
    func dateAndAge(birthDate: Date?) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day().year())
        guard let birthDate else { return day }
        return "\(day) · \(Format.age(birthDate: birthDate, now: date))"
    }
}

/// One photo of a milestone, as a small JPEG.
///
/// Kept inside the record rather than as external storage: an external file would sync as a
/// CKAsset, and assets aren't covered by the end-to-end encryption the rest of the log uses.
/// So each photo is downscaled to fit comfortably in a CloudKit record (see `MilestoneImages`),
/// one photo per record.
@objc(MilestonePhoto)
final class MilestonePhoto: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var createdAt: Date
    @NSManaged var milestone: Milestone?

    /// Adds `jpeg` to `milestone`, in the same store as its baby so it's shared along with it.
    @discardableResult
    static func create(jpeg: Data, for milestone: Milestone, createdAt: Date = .now, in context: NSManagedObjectContext) -> MilestonePhoto {
        let photo = MilestonePhoto(context: context)
        photo.uuid = UUID()
        photo.createdAt = createdAt
        photo.imageData = jpeg
        // A new milestone's own ID doesn't know its store until it's saved; its baby's does.
        if let store = milestone.baby?.objectID.persistentStore {
            context.assign(photo, to: store)
        }
        photo.milestone = milestone
        return photo
    }
}

extension Milestone {
    /// Moments to pick from when adding one. In no particular order of age: every baby has their own.
    static let suggestions: [EmojiLabel] = [
        EmojiLabel("😊", "First smile"),
        EmojiLabel("😂", "First laugh"),
        EmojiLabel("💪", "Holds head up"),
        EmojiLabel("🔄", "Rolls over"),
        EmojiLabel("🪑", "Sits up"),
        EmojiLabel("🦷", "First tooth"),
        EmojiLabel("🐾", "Crawls"),
        EmojiLabel("🗣️", "First word"),
        EmojiLabel("👣", "First steps"),
        EmojiLabel("🛁", "First bath"),
        EmojiLabel("🌳", "First outing"),
        EmojiLabel("🥄", "First food"),
    ]

    /// Emoji to choose from, with what VoiceOver reads for each.
    static let emojiChoices: [EmojiLabel] = [
        EmojiLabel("⭐️", "Star"),
        EmojiLabel("😊", "Smile"),
        EmojiLabel("😂", "Laugh"),
        EmojiLabel("💪", "Strong"),
        EmojiLabel("🔄", "Roll"),
        EmojiLabel("🪑", "Sitting"),
        EmojiLabel("🦷", "Tooth"),
        EmojiLabel("🐾", "Crawling"),
        EmojiLabel("🗣️", "Talking"),
        EmojiLabel("👣", "Steps"),
        EmojiLabel("🛁", "Bath"),
        EmojiLabel("🌳", "Outing"),
        EmojiLabel("🥄", "Food"),
        EmojiLabel("🎂", "Birthday"),
        EmojiLabel("❤️", "Love"),
        EmojiLabel("🎉", "Celebration"),
    ]
}

/// An emoji with words: a suggested milestone's title, or what VoiceOver reads for an emoji choice.
struct EmojiLabel: Identifiable {
    let emoji: String
    let text: String
    var id: String { emoji + text }

    init(_ emoji: String, _ text: String) {
        self.emoji = emoji
        self.text = text
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var milestones: NSSet?
}
