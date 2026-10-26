import Foundation

extension SettingsKey {
    // In `UserDefaults.standard`, per iPhone:
    /// When cry alerts stop listening by themselves (`ListeningStop`).
    static let listeningStop = "listeningStop"
    /// For `.atTime`: minutes after midnight, e.g. 420 for 7:00 AM.
    static let listeningStopMinutes = "listeningStopMinutes"
    /// For `.afterDuration`: hours after listening starts.
    static let listeningStopHours = "listeningStopHours"
}

/// When cry alerts on this iPhone stop listening by themselves. Chosen in Cry alerts; a nursery
/// monitor always listens until it's stopped.
enum ListeningStop: String, CaseIterable, Identifiable {
    /// Keeps listening until the parent taps Stop listening. The default.
    case never
    /// When tonight's last night shift ends, if a night plan is on.
    case endOfShifts
    /// At a chosen time of day, the next time it comes.
    case atTime
    /// A chosen number of hours after listening starts.
    case afterDuration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return String(localized: "When I stop it", comment: "When cry alerts stop listening")
        case .endOfShifts: return String(localized: "When the night shifts end", comment: "When cry alerts stop listening")
        case .atTime: return String(localized: "At a time", comment: "When cry alerts stop listening: at a chosen time of day")
        case .afterDuration: return String(localized: "After a number of hours", comment: "When cry alerts stop listening")
        }
    }

    static let defaultMinutes = 7 * 60
    static let defaultHours = 8
    static let hourChoices = [1, 2, 3, 4, 5, 6, 8, 10, 12]

    static var current: ListeningStop {
        UserDefaults.standard.string(forKey: SettingsKey.listeningStop).flatMap(ListeningStop.init(rawValue:)) ?? .never
    }

    /// When listening that starts at `start` should stop, or nil to keep going until it's stopped.
    static func stopDate(from start: Date, plan: NightPlan, calendar: Calendar = .current) -> Date? {
        let defaults = UserDefaults.standard
        switch current {
        case .never:
            return nil
        case .endOfShifts:
            guard plan.isEnabled, let end = plan.shifts(forNightOf: plan.nightDay(at: start)).last?.end,
                  end > start else { return nil }
            return end
        case .atTime:
            let minutes = defaults.object(forKey: SettingsKey.listeningStopMinutes) as? Int ?? defaultMinutes
            let today = calendar.startOfDay(for: start)
            guard let atToday = calendar.date(byAdding: .minute, value: minutes, to: today) else { return nil }
            // The next time it comes: later today, or tomorrow.
            return atToday > start ? atToday : calendar.date(byAdding: .day, value: 1, to: atToday)
        case .afterDuration:
            let hours = defaults.object(forKey: SettingsKey.listeningStopHours) as? Int ?? defaultHours
            return start.addingTimeInterval(TimeInterval(max(1, hours)) * 3600)
        }
    }
}
