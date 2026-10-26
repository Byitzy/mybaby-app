import CoreData
import Foundation

// Entries brought in by Settings › Your data › Import from another app carry the id of the import
// that added them, so the whole import can be removed again in one go ("Remove this import"), on
// either parent's iPhone. Entries logged in MyBaby leave it `nil`. Declared here rather than on each
// model, next to the importer that sets it (`Services/Import/`).

extension Activity {
    /// The import that added this entry (`ImportRecord.id`), or `nil` when it was logged in MyBaby.
    @NSManaged var importBatchID: String?
}

extension GrowthEntry {
    /// The import that added this measurement, or `nil` when it was entered in MyBaby.
    @NSManaged var importBatchID: String?
}

extension Vaccine {
    /// The import that added this vaccine, or `nil` when it was entered in MyBaby.
    @NSManaged var importBatchID: String?
}

extension TrackingPeriod {
    /// The import that added this marked time, or `nil` when it was marked in MyBaby.
    @NSManaged var importBatchID: String?
}
