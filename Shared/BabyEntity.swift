import AppIntents
import Foundation

/// A baby to pick in Edit Widget, so each widget can show its own baby (twins side by side), or
/// "Follow the app": whichever baby the app is showing, as widgets did before they could be set up.
///
/// "Follow the app" is an entity of its own (`followApp`) rather than an empty choice, so it's listed
/// first, reads as a choice, and is the default (`BabyEntityQuery.defaultResult()`). Widget parameters
/// are optional as well, and `nil` also means following the app.
///
/// The list comes from the widget snapshot in the App Group (`WidgetSnapshot.babies`), so it works in the
/// widget extension, which never opens the database. Built into the app and MyBabyWidgets; the Apple
/// Watch targets leave it out (see the project's exceptions for Shared/).
struct BabyEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Baby"
    static var defaultQuery = BabyEntityQuery()

    /// The `Baby.uuid`, or `followAppID`.
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        if followsApp {
            return DisplayRepresentation(title: "Follow the app", subtitle: "The baby shown in MyBaby")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    static let followAppID = "follow-app"

    /// The baby shown in the app, whichever that is at the time.
    static var followApp: BabyEntity {
        BabyEntity(id: followAppID, name: "Follow the app")
    }

    var followsApp: Bool { id == Self.followAppID }

    /// The `Baby.uuid` to show, or `nil` to follow the app.
    var babyID: String? { followsApp ? nil : id }

    /// "Follow the app", then every baby in the latest snapshot, oldest first.
    static func all() -> [BabyEntity] {
        let babies = (WidgetSnapshot.load()?.babies ?? []).filter { !$0.id.isEmpty }
        return [followApp] + babies.map { BabyEntity(id: $0.id, name: $0.name) }
    }
}

/// In the widget extension, the list comes from the snapshot and starts with "Follow the app". In the app,
/// where Siri and Shortcuts ask (the `baby` of the actions in MyBaby/Intents), the names come straight
/// from the log and "Follow the app" isn't offered: it isn't something to say to Siri, and leaving the
/// baby out already means the baby shown in the app. Each target builds its own copy of this file, so
/// the `#if` only changes the app's.
struct BabyEntityQuery: EntityQuery {
    func entities(for identifiers: [BabyEntity.ID]) async throws -> [BabyEntity] {
        #if WIDGET_EXTENSION
        let known = BabyEntity.all()
        #else
        let known = [BabyEntity.followApp] + (await SiriBaby.entities())
        #endif
        // A baby missing from the snapshot (not written yet, or removed) keeps its place in the widget's
        // settings; the widget shows the baby shown in the app until it's back or another is picked.
        return identifiers.map { id in
            known.first { $0.id == id } ?? BabyEntity(id: id, name: "Baby")
        }
    }

    func suggestedEntities() async throws -> [BabyEntity] {
        #if WIDGET_EXTENSION
        return BabyEntity.all()
        #else
        return await SiriBaby.entities()
        #endif
    }

    func defaultResult() async -> BabyEntity? {
        #if WIDGET_EXTENSION
        return .followApp
        #else
        return nil
        #endif
    }
}
