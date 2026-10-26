import CoreData
import Foundation
import UserNotifications

/// Cancelling keeps an appointment, struck through under "Cancelled", instead of deleting it: a visit
/// that's called off and later back on doesn't need typing in again, and its questions and notes stay.
///
/// A cancelled appointment sends nothing and is left out of what's ahead: no reminder, no "How did it
/// go?" follow-up or Today card, no calendar event, and it isn't where a quick question goes. The visit
/// summary skips it when looking for the previous visit, the diary leaves it out, and the export marks it.
/// It's part of the shared log, so it's cancelled (and restored) on the partner's phone too.
extension Appointment {
    /// Cancels it, and takes away its reminder and follow-up on this phone right away. The partner's
    /// phone drops its own when the change arrives (`NotificationManager.refreshAppointmentReminders`,
    /// `VisitFollowUp`). With Keep appointments in my calendar on, `CalendarSync` removes the event
    /// when it sees the save, here or on the partner's phone.
    @MainActor
    func cancel(in context: NSManagedObjectContext) {
        guard !isCancelled else { return }
        isCancelled = true
        cancelledAt = .now
        context.saveIfChanged()
        removeNotifications()
    }

    /// Puts it back as it was: the reminder is scheduled again, and the follow-up and calendar event
    /// come back with the save (`VisitFollowUp`, `CalendarSync`).
    @MainActor
    func restore(in context: NSManagedObjectContext) {
        guard isCancelled else { return }
        isCancelled = false
        cancelledAt = nil
        context.saveIfChanged()
        NotificationManager.scheduleReminder(for: self)
        VisitFollowUp.shared.scheduleRefresh()
    }

    /// The reminder and the "How did it go?" follow-up, pending or already in Notification Center.
    @MainActor
    private func removeNotifications() {
        let identifiers = [notificationID, VisitFollowUp.identifier(for: self)]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        VisitFollowUp.shared.scheduleRefresh()
    }

    /// "Cancelled Oct 20", for the list and the editor.
    var cancelledText: String {
        guard let cancelledAt else { return String(localized: "Cancelled", comment: "An appointment that was cancelled") }
        let day = cancelledAt.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "Cancelled \(day)", comment: "An appointment cancelled on a day, e.g. “Cancelled Oct 20”")
    }
}
