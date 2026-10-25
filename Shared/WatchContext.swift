import Foundation

/// Everything the Apple Watch app shows, sent from the iPhone over WatchConnectivity.
///
/// The iPhone (`WatchBridge`, in the app) sends it with `updateApplicationContext` whenever it changes,
/// and in reply to each `WatchCommand`. The watch keeps the last one it got in its own App Group, so the
/// app opens straight to it and the complications can show it, and says "Last synced 3 min ago" when it
/// may be out of date.
///
/// **Privacy:** it goes straight from the iPhone to the paired Apple Watch through Apple's
/// WatchConnectivity, encrypted between the two devices. No server is involved, and it holds only what
/// the watch shows.
///
/// Text is already formatted in the parent's units (ml or oz), so the watch needs no settings of its own.
struct WatchContext: Codable, Equatable {
    /// A bottle amount button: "120 ml" or "4 oz", and the milliliters it logs.
    struct BottlePreset: Codable, Equatable, Hashable {
        var title: String
        var ml: Double
    }

    /// A medicine given before, with the dose logged last time (as the parent wrote it).
    struct Medicine: Codable, Equatable, Hashable {
        var name: String
        var dosage: String
    }

    /// Bumped if the format changes in a way older readers can't handle.
    var version = 1
    /// What the widgets show (last feed, diaper, sleep, night shifts, breastfeeding timer), for the baby
    /// shown in the iPhone app. `nil` before a baby has been added.
    var snapshot: WidgetSnapshot?
    /// "ml" or "oz".
    var volumeUnit = "ml"
    var bottlePresets: [BottlePreset] = []
    /// What the last bottle was, to pick it by default.
    var lastBottle: WatchCommand.Bottle?
    /// Most recent first.
    var medicines: [Medicine] = []
    /// The side to start breastfeeding on, as the app suggests from the last feed.
    var suggestedSide: BreastSide?
    /// When the iPhone sent it.
    var sentAt = Date.now

    /// The key in the application context and in replies.
    static let key = "context"

    /// Same content, ignoring when it was made.
    func hasSameContent(as other: WatchContext) -> Bool {
        var copy = other
        copy.sentAt = sentAt
        if let updatedAt = snapshot?.updatedAt {
            copy.snapshot?.updatedAt = updatedAt
        }
        return copy == self
    }
}

// MARK: - Sending

extension WatchContext {
    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    init?(data: Data?) {
        guard let data, let context = try? JSONDecoder().decode(WatchContext.self, from: data) else { return nil }
        self = context
    }

    /// From an application context or a reply.
    init?(message: [String: Any]) {
        self.init(data: message[Self.key] as? Data)
    }

    /// For `updateApplicationContext` or a reply.
    var message: [String: Any] {
        guard let data = encoded() else { return [:] }
        return [Self.key: data]
    }
}

// MARK: - Storage (on the watch)

extension WatchContext {
    /// `WatchContext.json` in the watch's App Group, which the complications read too. Without the App
    /// Group it falls back to the watch app's caches, so the app still opens to the last context.
    static var fileURL: URL? {
        let folder = AppGroup.containerURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return folder?.appendingPathComponent("WatchContext.json")
    }

    /// The last context the watch received, or `nil` before the first one.
    static func load() -> WatchContext? {
        guard let url = fileURL else { return nil }
        return WatchContext(data: try? Data(contentsOf: url))
    }

    static func save(_ context: WatchContext?) {
        guard let url = fileURL else { return }
        guard let data = context?.encoded() else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
