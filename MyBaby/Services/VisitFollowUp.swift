import CoreData
import Foundation
import UIKit
import UserNotifications

/// The "How did it go?" notification, an hour after an appointment ends (it's taken to last an hour,
/// so two hours after it starts). Tapping it opens that appointment's recap (`VisitRecapView`) through
/// `VisitRecapRouter`.
///
/// - Tied to the appointment's own reminder: an appointment with "Reminder: None" gets no follow-up.
/// - Only for the next `maxPending` (3) appointments, to stay within iOS's 64 pending notifications
///   (see the budget at the top of `NotificationManager`). The rest are scheduled as these go by.
/// - Cancelled once the appointment has a recap or is itself cancelled, here or from the partner's
///   phone, and moved when the appointment is edited or deleted.
///
/// Started once at launch (`MyBabyApp.init`). It's worked out again after any save that touches an
/// appointment, when changes arrive from the partner's phone, and when the app opens.
@MainActor
final class VisitFollowUp {
    static let shared = VisitFollowUp()

    nonisolated static let identifierPrefix = "visit-recap-"
    nonisolated static let appointmentKey = "appointmentID"
    /// How long after the start: an hour for the visit, then an hour more.
    static let delay: TimeInterval = 2 * 3600
    private static let maxPending = 3

    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if Self.touchesAppointments(notification) { self?.scheduleRefresh() }
            }
        })
        for name in [Notification.Name.NSPersistentStoreRemoteChange, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
    }

    /// Refreshes shortly, so a burst of changes refreshes once.
    func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Replaces the pending follow-ups with ones for the next appointments that still need one.
    func refresh() {
        pending?.cancel()
        pending = nil
        // While the stores are being reopened they look empty.
        guard CloudStatus.shared.reloadingMessage == nil else { return }

        let context = PersistenceController.shared.viewContext
        let request = Appointment.fetchAll()
        request.predicate = NSPredicate(
            format: "date > %@ AND recapDoneAt == nil",
            Date.now.addingTimeInterval(-Self.delay) as NSDate
        )
        guard let appointments = try? context.fetch(request) else { return }
        // Sorted by date, so these are the soonest.
        let upcoming = appointments
            .filter { $0.reminderMinutes != nil && $0.uuid != nil && !$0.isCancelled }
            .prefix(Self.maxPending)
        let keep = Set(upcoming.map(Self.identifier(for:)))

        let prefix = Self.identifierPrefix
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(prefix) && !keep.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for appointment in upcoming {
            schedule(appointment)
        }
    }

    private func schedule(_ appointment: Appointment) {
        guard let uuid = appointment.uuid else { return }
        let interval = appointment.date.addingTimeInterval(Self.delay).timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "How did it go?", comment: "Notification title after an appointment")
        let question = Self.question(for: appointment)
        content.body = String(
            localized: "\(question) Add notes, measurements or shots from the visit.",
            comment: "Notification after an appointment; the question is like “How did Mavie's 2-month checkup go?”"
        )
        content.sound = .default
        content.userInfo = [Self.appointmentKey: uuid.uuidString]

        // The same identifier replaces the one already pending.
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: appointment),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        Task {
            guard await NotificationManager.requestAuthorization() else { return }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// "How did Mavie's 2-month checkup go?"
    nonisolated static func question(for appointment: Appointment) -> String {
        let title = appointment.title
        switch (appointment.baby?.displayName, title.isEmpty) {
        case (nil, true):
            return String(localized: "How did the appointment go?", comment: "After an appointment with no title")
        case (nil, false):
            return String(localized: "How did the \(title) go?", comment: "After an appointment; its title, like 2-month checkup")
        case (let name?, true):
            return String(localized: "How did \(name)'s appointment go?", comment: "After an appointment with no title; the baby's name")
        case (let name?, false):
            return String(
                localized: "How did \(name)'s \(title) go?",
                comment: "After an appointment; the baby's name, then the appointment's title, like 2-month checkup"
            )
        }
    }

    static func identifier(for appointment: Appointment) -> String {
        identifierPrefix + (appointment.uuid?.uuidString ?? "")
    }

    private static func touchesAppointments(_ notification: Notification) -> Bool {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is Appointment }
        }
    }

    /// Opens the recap when a follow-up is tapped. Called by the app's notification delegate.
    nonisolated static func handle(_ response: UNNotificationResponse) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(identifierPrefix),
              let raw = request.content.userInfo[appointmentKey] as? String,
              let id = UUID(uuidString: raw)
        else { return }
        await MainActor.run {
            VisitRecapRouter.shared.appointmentID = id
        }
    }
}

/// Which appointment's recap a tapped notification asked for, until it's shown (`visitRecapRouting()`).
@MainActor
final class VisitRecapRouter: ObservableObject {
    static let shared = VisitRecapRouter()
    @Published var appointmentID: UUID?

    private init() {}
}
