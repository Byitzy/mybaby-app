import CoreData
import Foundation

/// A spare device used as the nursery monitor, and when it last checked in.
///
/// The monitor updates `lastSeen` every 5 minutes while it listens, and syncs it with the log, so the
/// parents' phones can show that it's still on, and warn when it goes quiet (see `MonitorStatusRows`).
@objc(MonitorDevice)
final class MonitorDevice: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    /// E.g. "Noah's iPad".
    @NSManaged var deviceName: String
    @NSManaged var isListening: Bool
    @NSManaged var lastSeen: Date
    /// The white noise it plays: a `NoiseColor`.
    @NSManaged var noiseRaw: String
    @NSManaged var baby: Baby?

    /// How often a listening monitor checks in.
    static let checkInInterval: TimeInterval = 5 * 60
    /// A listening monitor that hasn't checked in for this long may be off, unplugged or offline.
    static let staleAfter: TimeInterval = 15 * 60

    var noise: NoiseColor { NoiseColor(rawValue: noiseRaw) ?? .off }

    /// Listening, but hasn't checked in for a while.
    func isStale(at now: Date) -> Bool {
        isListening && now.timeIntervalSince(lastSeen) > Self.staleAfter
    }

    static func fetchAll() -> NSFetchRequest<MonitorDevice> {
        let request = NSFetchRequest<MonitorDevice>(entityName: "MonitorDevice")
        request.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        return request
    }

    /// Monitors seen in the last day: older ones are from another night and aren't worth showing.
    static func recent(now: Date = .now) -> NSFetchRequest<MonitorDevice> {
        let request = fetchAll()
        request.predicate = NSPredicate(format: "lastSeen > %@", now.addingTimeInterval(-24 * 3600) as NSDate)
        return request
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var monitorDevices: NSSet?
}
