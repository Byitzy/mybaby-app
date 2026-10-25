import AppIntents
import CoreData
import Foundation

// What the Siri and Shortcuts actions in this folder share: which baby an action is for, the words Siri
// uses for them, keeping Siri's list of baby names up to date, and the app's types Siri can be asked about.

/// The baby a Siri or Shortcuts action is for.
///
/// Every action has an optional `baby` (`BabyEntity`, in Shared/BabyEntity.swift). Left out, or set to
/// "Follow the app", it's the baby shown in the app, as before babies could be picked.
@MainActor
enum SiriBaby {
    /// The baby picked, or the baby shown in the app when none was. Throws when there's no baby yet, or
    /// when the one picked isn't in MyBaby any more: then nothing is logged, rather than logging it for
    /// the other twin.
    static func resolve(_ entity: BabyEntity?) throws -> Baby {
        guard let id = entity?.babyID else { return try QuickLog.currentBaby() }
        // `baby(withID:)` falls back to the baby shown in the app, so check it's the one asked for.
        guard let baby = QuickLog.baby(withID: id), baby.uuid?.uuidString == id else {
            _ = try QuickLog.currentBaby()
            throw IntentFailure.babyNotFound
        }
        return baby
    }

    /// Like `resolve(_:)`, for actions that add or change entries: also throws on a log that's view only
    /// on this iPhone (someone the owner invited as view only, like a grandparent).
    static func resolveForLogging(_ entity: BabyEntity?) throws -> Baby {
        let baby = try resolve(entity)
        try checkCanEdit(baby)
        return baby
    }

    static func checkCanEdit(_ baby: Baby) throws {
        guard PersistenceController.shared.canEdit(baby) else { throw IntentFailure.viewOnly }
    }

    /// Every baby, oldest first, as Siri and Shortcuts list them. Never "Follow the app".
    static func entities() -> [BabyEntity] {
        let babies = (try? QuickLog.context.fetch(Baby.fetchAll())) ?? []
        return babies.compactMap { baby -> BabyEntity? in
            guard let id = baby.uuid?.uuidString else { return nil }
            return BabyEntity(id: id, name: baby.displayName)
        }
    }
}

/// Babies whose name matches what was said or typed, so "Log a diaper for Mavie" finds Mavie, and Shortcuts
/// can search the list. Only in the app: the widget extension builds `BabyEntityQuery` without it.
extension BabyEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [BabyEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let babies = await SiriBaby.entities()
        guard !query.isEmpty else { return babies }
        return babies.filter {
            $0.name.localizedStandardContains(query) || query.localizedStandardContains($0.name)
        }
    }
}

/// The words Siri says about a baby.
@MainActor
enum SiriText {
    /// Whether the baby has been given a name, rather than showing as "Baby".
    static func hasName(_ baby: Baby) -> Bool {
        !baby.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// " for Mavie", or nothing before the baby has a name: "Logged a wet diaper for Mavie."
    static func forBaby(_ baby: Baby) -> String {
        hasName(baby) ? " for \(baby.displayName)" : ""
    }

    /// "Mavie", or "The baby" ("the baby" when `capitalized` is false) before the baby has a name.
    static func name(_ baby: Baby, capitalized: Bool = true) -> String {
        if hasName(baby) { return baby.displayName }
        return capitalized ? "The baby" : "the baby"
    }

    /// "Mavie's last feed". Before the baby has a name, `QuickLog.babyPrefix`: "The last feed", or
    /// "Baby's last feed" with twins. Lowercased at the start when `capitalized` is false.
    static func subject(_ baby: Baby, _ thing: String, capitalized: Bool = true) -> String {
        let text = hasName(baby) ? "\(baby.displayName)'s \(thing)" : QuickLog.babyPrefix(baby, thing)
        guard !capitalized, text.hasPrefix("The ") else { return text }
        return "the " + text.dropFirst(4)
    }

    /// "just now" or "2 hours, 10 minutes ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "just now" : "\(QuickLog.spokenDuration(seconds)) ago"
    }

    /// "4:10 AM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The parent's unit for amounts, ml or oz.
    static var volumeUnit: VolumeUnit {
        VolumeUnit(rawValue: UserDefaults.shared.string(forKey: SettingsKey.volumeUnit) ?? "") ?? .ml
    }
}

/// Keeps the baby names Siri listens for ("Log a diaper for Mavie in MyBaby") in step with the babies in
/// MyBaby: at launch, and whenever a baby is added, renamed or removed, on this iPhone or the partner's.
///
/// Babies change in a few places (adding one, their profile, removing one, merging, joining a shared log,
/// iCloud), so rather than each of them remembering to tell Siri, this watches every save and remote
/// change and compares the names. Started once at launch (`MyBabyApp.init`).
@MainActor
final class SiriBabyNames {
    static let shared = SiriBabyNames()

    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// The ids and names Siri was last given.
    private var lastNames: [String]?

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            NSManagedObjectContext.didSaveObjectsNotification,
            .NSPersistentStoreRemoteChange,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        refresh(force: true)
    }

    /// Checks again shortly, once changes from iCloud have been merged into the view context.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Tells Siri the baby names when they've changed (or always, with `force`).
    func refresh(force: Bool = false) {
        let names = SiriBaby.entities().map { "\($0.id) \($0.name)" }
        // While iCloud is switched on or off the stores are reopened and look empty for a moment.
        guard !names.isEmpty, force || names != lastNames else { return }
        lastNames = names
        MyBabyShortcuts.updateAppShortcutParameters()
    }
}

// MARK: - App types Siri can be asked about

/// Where pumped milk goes in the stash, for "Log Pumping".
extension MilkStorage: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Storage"
    static var caseDisplayRepresentations: [MilkStorage: DisplayRepresentation] = [
        .room: "Room temperature",
        .fridge: "Fridge",
        .freezer: "Freezer",
    ]
}

/// How a temperature was taken, for "Log Bath or Temperature". The fever line depends on it.
extension TemperatureMethod: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Taken"
    static var caseDisplayRepresentations: [TemperatureMethod: DisplayRepresentation] = [
        .rectal: "Rectal",
        .armpit: DisplayRepresentation(title: "Armpit", synonyms: ["under the arm"]),
        .ear: "Ear",
        .forehead: "Forehead",
        .oral: DisplayRepresentation(title: "Oral", synonyms: ["by mouth"]),
    ]
}
