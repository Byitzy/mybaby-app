import CoreData
import Foundation

/// Where a nursery monitor sends alerts for one parent's phone: that phone's private alert inbox in
/// iCloud (see `AlertInboxes`).
///
/// Each parent phone keeps one row per baby, so it syncs to the whole family with the log, end-to-end
/// encrypted like everything else. The monitor reads them to find the phones of the parent on duty.
@objc(AlertInbox)
final class AlertInbox: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    /// Whose shifts the phone is for: an `AlarmOwner` (parent1, parent2 or both), from the phone's
    /// *This iPhone belongs to*.
    @NSManaged var parentRaw: String
    /// The link that lets family devices join the inbox (a zone-wide CloudKit share).
    @NSManaged var shareURL: String
    /// The iCloud user who owns the inbox, so a device on the same Apple ID writes to it directly.
    @NSManaged var ownerUserRecordName: String
    /// E.g. "Sam's iPhone", shown on the monitor.
    @NSManaged var deviceName: String
    @NSManaged var updatedAt: Date
    @NSManaged var baby: Baby?

    var owner: AlarmOwner {
        get { AlarmOwner(rawValue: parentRaw) ?? .both }
        set { parentRaw = newValue.rawValue }
    }

    static func fetchAll() -> NSFetchRequest<AlertInbox> {
        let request = NSFetchRequest<AlertInbox>(entityName: "AlertInbox")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return request
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var alertInboxes: NSSet?
}
