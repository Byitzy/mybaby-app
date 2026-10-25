import Foundation

/// One of the two parents sharing night duty. Names come from the plan.
enum Parent: String, CaseIterable, Identifiable, Codable {
    case parent1, parent2

    var id: String { rawValue }

    var other: Parent { self == .parent1 ? .parent2 : .parent1 }
}

enum NightPlanMode: String, CaseIterable, Identifiable, Codable {
    /// Each night is cut in two at a handoff time; one parent takes each half.
    case split
    /// One parent covers the whole night, then the other takes the next night(s).
    case alternate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .split: return "Split each night"
        case .alternate: return "Take turns by night"
        }
    }
}

/// Whose night-shift reminders this iPhone should ring for: who the phone belongs to, picked in
/// Settings › Parents. `both` is a phone the two parents share.
enum AlarmOwner: String, CaseIterable, Identifiable, Codable {
    case parent1, parent2, both

    var id: String { rawValue }

    init(_ parent: Parent) {
        self = parent == .parent1 ? .parent1 : .parent2
    }

    /// The one parent this phone belongs to, or `nil` for a shared phone.
    var parent: Parent? {
        switch self {
        case .parent1: return .parent1
        case .parent2: return .parent2
        case .both: return nil
        }
    }

    func includes(_ parent: Parent) -> Bool {
        self == .both || rawValue == parent.rawValue
    }
}

/// How a night-shift reminder gets someone's attention.
enum AlarmStyle: String, CaseIterable, Identifiable, Codable {
    /// Buzzes without making a sound, so the partner and baby keep sleeping.
    case vibrate
    case sound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibrate: return "Vibrate only"
        case .sound: return "Sound"
        }
    }
}

/// How easily a cry triggers an alert.
enum CrySensitivity: String, CaseIterable, Identifiable, Codable {
    case low, medium, high

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// Minimum classifier confidence (0–1) that counts as hearing a cry.
    var threshold: Double {
        switch self {
        case .low: return 0.8
        case .medium: return 0.6
        case .high: return 0.4
        }
    }
}

/// A stretch of the night one parent is on duty for.
struct NightShift: Identifiable, Equatable {
    let parent: Parent
    let start: Date
    let end: Date

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// How two parents share the nights.
///
/// The rotation is worked out from `anchorDay` and `anchorParent`, so two phones set up with
/// the same plan agree on who's on duty without needing to sync.
struct NightPlan: Codable, Equatable {
    var isEnabled = false
    var mode: NightPlanMode = .split
    /// Empty until the parents give their names (Settings › Parents); `name(of:)` says "Parent 1"
    /// and "Parent 2" until then. Plans saved by older versions keep the names they were saved with.
    var parent1Name = ""
    var parent2Name = ""

    /// Times of day, as minutes after midnight.
    var nightStartMinutes = 21 * 60
    var nightEndMinutes = 7 * 60
    var handoffMinutes = 2 * 60

    /// Split mode: switch who takes the first half every night, so both get the "good" half equally.
    var swapEachNight = true
    /// Alternate mode: how many nights in a row each parent covers.
    var nightsPerTurn = 1

    /// The parent who is on duty first on the night that starts on `anchorDay`.
    var anchorDay = Calendar.current.startOfDay(for: .now)
    var anchorParent: Parent = .parent1

    var alarmOwner: AlarmOwner = .both
    var wakeUpAlarms = true
    var bedtimeHeadsUp = false
    var alarmStyle: AlarmStyle = .vibrate

    // Cry alerts
    var crySensitivity: CrySensitivity = .medium
    /// Also buzz the off-duty parent if crying goes on this long. 0 means never.
    var cryEscalationMinutes = 5

    func name(of parent: Parent) -> String {
        let name = givenName(of: parent)
        if !name.isEmpty { return name }
        return parent == .parent1 ? "Parent 1" : "Parent 2"
    }

    /// The name as typed, without spaces around it. Empty when it hasn't been given.
    func givenName(of parent: Parent) -> String {
        (parent == .parent1 ? parent1Name : parent2Name).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True once both parents have a name, rather than "Parent 1" and "Parent 2".
    var hasBothNames: Bool {
        !givenName(of: .parent1).isEmpty && !givenName(of: .parent2).isEmpty
    }

    // MARK: Schedule

    /// The shifts for the night that begins on `day`, in order.
    func shifts(forNightOf day: Date, calendar: Calendar = .current) -> [NightShift] {
        let start = time(nightStartMinutes, on: calendar.startOfDay(for: day), calendar: calendar)
        let end = time(nightEndMinutes, after: start, calendar: calendar)
        let index = nightIndex(of: day, calendar: calendar)

        switch mode {
        case .split:
            var handoff = time(handoffMinutes, after: start, calendar: calendar)
            if handoff >= end {
                handoff = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            }
            let first = swapEachNight && !index.isMultiple(of: 2) ? anchorParent.other : anchorParent
            return [
                NightShift(parent: first, start: start, end: handoff),
                NightShift(parent: first.other, start: handoff, end: end),
            ]
        case .alternate:
            let turn = Self.floorDivide(index, max(nightsPerTurn, 1))
            let parent = turn.isMultiple(of: 2) ? anchorParent : anchorParent.other
            return [NightShift(parent: parent, start: start, end: end)]
        }
    }

    /// The night that is going on at `date`, or the next one to start (tonight) during the day.
    func nightDay(at date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        // Yesterday's night may still be going; otherwise today's may not have ended yet.
        // A night that starts after midnight (e.g. 00:30–07:00) has already ended by daytime,
        // so the next one is tomorrow's.
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if let end = shifts(forNightOf: day, calendar: calendar).last?.end, date < end { return day }
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// The shift covering `date`, or `nil` during the day or when the plan is off.
    func shift(at date: Date, calendar: Calendar = .current) -> NightShift? {
        guard isEnabled else { return nil }
        return shifts(forNightOf: nightDay(at: date, calendar: calendar), calendar: calendar)
            .first { $0.contains(date) }
    }

    /// Nights starting with the current (or next) one.
    func upcomingNights(from date: Date = .now, count: Int, calendar: Calendar = .current) -> [[NightShift]] {
        let first = nightDay(at: date, calendar: calendar)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first).map { shifts(forNightOf: $0, calendar: calendar) }
        }
    }

    /// Hours each parent is on duty over the given nights.
    static func dutyTotals(_ nights: [[NightShift]]) -> [Parent: TimeInterval] {
        var totals: [Parent: TimeInterval] = [.parent1: 0, .parent2: 0]
        for shift in nights.joined() {
            totals[shift.parent, default: 0] += shift.duration
        }
        return totals
    }

    /// Makes `parent` the one on duty first for the night going on at (or starting after) `date`.
    mutating func setFirstOnDuty(_ parent: Parent, from date: Date = .now, calendar: Calendar = .current) {
        anchorDay = nightDay(at: date, calendar: calendar)
        anchorParent = parent
    }

    /// Moves the handoff to the middle of the night so both halves are the same length.
    mutating func centerHandoff() {
        let length = (nightEndMinutes - nightStartMinutes + 1440) % 1440
        let night = length == 0 ? 1440 : length
        handoffMinutes = (nightStartMinutes + night / 2) % 1440
    }

    // MARK: Persistence

    static func load(from defaults: UserDefaults = .shared) -> NightPlan {
        guard let data = defaults.data(forKey: SettingsKey.nightPlan) else { return NightPlan() }
        return NightPlan(data: data)
    }

    init() {}

    /// Missing keys fall back to defaults, so a plan saved by an older version still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NightPlan()
        // A missing or unreadable value keeps its default instead of resetting the whole plan.
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        isEnabled = value(.isEnabled, defaults.isEnabled)
        mode = value(.mode, defaults.mode)
        parent1Name = value(.parent1Name, defaults.parent1Name)
        parent2Name = value(.parent2Name, defaults.parent2Name)
        nightStartMinutes = value(.nightStartMinutes, defaults.nightStartMinutes)
        nightEndMinutes = value(.nightEndMinutes, defaults.nightEndMinutes)
        handoffMinutes = value(.handoffMinutes, defaults.handoffMinutes)
        swapEachNight = value(.swapEachNight, defaults.swapEachNight)
        nightsPerTurn = value(.nightsPerTurn, defaults.nightsPerTurn)
        anchorDay = value(.anchorDay, defaults.anchorDay)
        anchorParent = value(.anchorParent, defaults.anchorParent)
        alarmOwner = value(.alarmOwner, defaults.alarmOwner)
        wakeUpAlarms = value(.wakeUpAlarms, defaults.wakeUpAlarms)
        bedtimeHeadsUp = value(.bedtimeHeadsUp, defaults.bedtimeHeadsUp)
        alarmStyle = value(.alarmStyle, defaults.alarmStyle)
        crySensitivity = value(.crySensitivity, defaults.crySensitivity)
        cryEscalationMinutes = value(.cryEscalationMinutes, defaults.cryEscalationMinutes)
    }

    init(data: Data) {
        self = (try? JSONDecoder().decode(NightPlan.self, from: data)) ?? NightPlan()
    }

    func save(to defaults: UserDefaults = .shared) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: SettingsKey.nightPlan)
        }
    }

    // MARK: Sharing between parents

    /// This plan with the schedule taken from `other`, keeping this phone's own settings
    /// (whose phone it is, alert style and cry alert preferences). The names are part of the schedule,
    /// so they're shared too.
    func adoptingSchedule(from other: NightPlan) -> NightPlan {
        var merged = self
        merged.alarmOwner = owner(renumberedFor: other)
        merged.isEnabled = other.isEnabled
        merged.mode = other.mode
        merged.parent1Name = other.parent1Name
        merged.parent2Name = other.parent2Name
        merged.nightStartMinutes = other.nightStartMinutes
        merged.nightEndMinutes = other.nightEndMinutes
        merged.handoffMinutes = other.handoffMinutes
        merged.swapEachNight = other.swapEachNight
        merged.nightsPerTurn = other.nightsPerTurn
        merged.anchorDay = other.anchorDay
        merged.anchorParent = other.anchorParent
        return merged
    }

    // MARK: Helpers

    /// Whose phone this is, in `other`'s numbering of the parents. Each parent may have typed their
    /// own name first, so when this phone's owner's name moved to the other place, the phone
    /// follows the person rather than the number.
    private func owner(renumberedFor other: NightPlan) -> AlarmOwner {
        guard let mine = alarmOwner.parent else { return alarmOwner }
        let ownName = givenName(of: mine).lowercased()
        guard !ownName.isEmpty,
              other.givenName(of: mine).lowercased() != ownName,
              other.givenName(of: mine.other).lowercased() == ownName
        else { return alarmOwner }
        return AlarmOwner(mine.other)
    }

    private func nightIndex(of day: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: anchorDay), to: calendar.startOfDay(for: day)).day ?? 0
    }

    private func time(_ minutes: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    /// The first moment after `start` with the given time of day.
    private func time(_ minutes: Int, after start: Date, calendar: Calendar) -> Date {
        let sameDay = time(minutes, on: start, calendar: calendar)
        if sameDay > start { return sameDay }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return time(minutes, on: nextDay, calendar: calendar)
    }

    private static func floorDivide(_ value: Int, _ divisor: Int) -> Int {
        value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
    }
}

extension Date {
    /// Minutes after midnight, for storing a time of day.
    var minutesIntoDay: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Today's date at a time of day stored as minutes after midnight.
    static func today(atMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}
