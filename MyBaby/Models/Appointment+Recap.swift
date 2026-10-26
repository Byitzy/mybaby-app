import CoreData
import Foundation

/// "How did it go?": what was noted after a visit. It's part of the shared log, so whichever parent
/// fills it in, the other sees it (and their nudge goes away once it syncs).
///
/// Measurements and shots from the visit aren't stored here: they're a `GrowthEntry` and `Vaccine`s
/// dated at the appointment, found again by that date (`measurementAtVisit`, `vaccinesGivenAtVisit`).
/// Head circumference was kept here before GrowthEntry had a field for it. Recaps now save it on
/// the entry and still copy it here, for a partner's phone on an earlier version of MyBaby; older
/// recaps' values are read from here and merged into Growth (`GrowthReading`).
extension Appointment {
    /// What the doctor said or advised.
    @NSManaged var visitNotes: String?
    /// When the recap was saved. `nil` until then; the follow-up nudges only look for these.
    @NSManaged var recapDoneAt: Date?
    @NSManaged var headCircumferenceCmNumber: NSNumber?
    /// Answers to the visit-prep questions, as JSON: question text → answer.
    @NSManaged var questionAnswers: String?

    var hasRecap: Bool { recapDoneAt != nil }

    /// When the visit is taken to have ended: an hour after it starts (appointments have no duration).
    var assumedEnd: Date { date.addingTimeInterval(3600) }

    var headCircumferenceCm: Double? {
        get { headCircumferenceCmNumber?.doubleValue }
        set { headCircumferenceCmNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Question text → answer typed after the visit.
    var answers: [String: String] {
        get {
            guard let data = questionAnswers?.data(using: .utf8), !data.isEmpty,
                  let answers = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return answers
        }
        set {
            let kept = newValue.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !kept.isEmpty, let data = try? JSONEncoder().encode(kept) else {
                questionAnswers = ""
                return
            }
            questionAnswers = String(decoding: data, as: UTF8.self)
        }
    }

    /// Entries saved "at the visit" have the appointment's exact date; a minute either way allows for rounding.
    private func isAtVisit(_ other: Date) -> Bool {
        abs(other.timeIntervalSince(date)) < 60
    }

    /// The weight and length saved from the recap, if any.
    var measurementAtVisit: GrowthEntry? {
        let entries = (baby?.growthEntries as? Set<GrowthEntry>) ?? []
        return entries.first { isAtVisit($0.date) }
    }

    /// Vaccines marked as given at this visit.
    var vaccinesGivenAtVisit: [Vaccine] {
        let vaccines = (baby?.vaccines as? Set<Vaccine>) ?? []
        return vaccines
            .filter { $0.isGiven && isAtVisit($0.date) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "Weighed 5.2 kg · 2 shots · notes", for the appointments list. `nil` before a recap.
    func recapSummary(units: GrowthUnits) -> String? {
        guard hasRecap else { return nil }
        var parts: [String] = []
        let entry = measurementAtVisit
        if let kg = entry?.weightKg {
            parts.append(String(localized: "Weighed \(units.formatWeight(kg: kg))", comment: "Visit recap: the baby's weight at the visit"))
        } else if let cm = entry?.lengthCm {
            // "Length", not "Measured": "Measured %@" is also a date ("Measured Oct 20"), which other
            // languages word differently.
            parts.append(String(localized: "Length \(units.formatLength(cm: cm))", comment: "Visit recap: the baby's length at the visit, or a length percentile: Length 52 cm, Length 62nd"))
        } else if let cm = entry?.headCircumferenceCm ?? headCircumferenceCm {
            parts.append(String(localized: "Head \(units.formatLength(cm: cm))", comment: "Visit recap: the head circumference at the visit"))
        }
        let shots = vaccinesGivenAtVisit.count
        if shots > 0 {
            parts.append(shots == 1 ? String(localized: "1 shot", comment: "Visit recap: one vaccine given") : String(localized: "\(shots) shots", comment: "Visit recap: vaccines given"))
        }
        let hasNotes = !(visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasNotes || !answers.isEmpty { parts.append(String(localized: "notes", comment: "Visit recap: notes were written, after “Weighed 5.2 kg · 2 shots · ”")) }
        return parts.isEmpty ? String(localized: "Visit noted") : parts.joined(separator: " · ")
    }

    /// For "Book the next visit": the next checkup after "2-month checkup" ("4-month checkup"), nothing
    /// after the last checkup, and the same title for anything else (a follow-up with a specialist).
    /// A checkup saved in English finds its place too; the next one is in the iPhone's language.
    static func nextTitle(after title: String) -> String {
        let checkups = checkupTitles
        guard let index = checkups.firstIndex(of: title) ?? englishCheckupTitles.firstIndex(of: title) else { return title }
        let next = checkups.index(after: index)
        return next < checkups.endIndex ? checkups[next] : ""
    }
}

extension GrowthUnits {
    /// The units picked in Growth, for places that don't keep their own `@AppStorage`.
    static var current: GrowthUnits {
        UserDefaults.shared.string(forKey: SettingsKey.growthUnits).flatMap(GrowthUnits.init(rawValue:)) ?? .localeDefault
    }
}
