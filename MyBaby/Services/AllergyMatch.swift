import Foundation

/// Matching medicines and foods against the baby's allergy list, and the words the warnings use.
///
/// Pure functions over names and ids, so they can be tested without Core Data. They only compare
/// names: MyBaby never says which medicines or foods are related to each other.
enum AllergyMatch {
    /// How names are compared: trimmed, ignoring case and accents, so "Amoxicillin " matches "amoxicillin".
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Medicine

    /// Whether a medicine being logged matches a medicine allergy's name: ignoring case, either one
    /// containing the other ("Amoxicillin 250 mg" and "amoxicillin", or "amoxi" while it's typed).
    /// Names shorter than 3 letters never match, so typing a first letter doesn't warn.
    ///
    /// - "Amoxicillin" / "amoxicillin" → true
    /// - "Amoxicillin-clavulanate" / "Amoxicillin" → true
    /// - "Penicillin VK" / "penicillin" → true
    /// - "Ibuprofen" / "Amoxicillin" → false
    /// - "Am" / "Amoxicillin" → false
    static func medicineMatches(_ medicine: String, allergy allergyName: String) -> Bool {
        let medicine = key(medicine)
        let allergy = key(allergyName)
        guard medicine.count >= 3, allergy.count >= 3 else { return false }
        return medicine.contains(allergy) || allergy.contains(medicine)
    }

    /// The confirmed and suspected medicine allergies that match `medicine`. An allergy picked from
    /// the common medicines counts as a medicine allergy whatever category it was saved under.
    static func medicineAllergies(matching medicine: String, in allergies: [Allergy]) -> [Allergy] {
        allergies.filter { allergy in
            let isMedicine = allergy.category == .medicine || allergy.commonAllergen?.category == .medicine
            return isMedicine && allergy.isActive && medicineMatches(medicine, allergy: allergy.displayName)
        }
    }

    /// "Mavie's list says she's allergic to amoxicillin. Check with your doctor or pharmacist before
    /// giving it." Uses "she" or "he" only once the baby's sex is set.
    static func medicineWarning(babyName: String, sex: BabySex?, allergyName: String, status: AllergyStatus) -> String {
        let allergen = allergyName.lowercased()
        let check = "Check with your doctor or pharmacist before giving it."
        guard let sex else {
            let suspected = status == .suspected ? " as a suspected allergy" : ""
            return "\(babyName)'s allergy list includes \(allergen)\(suspected). \(check)"
        }
        let pronoun = sex == .female ? "she" : "he"
        let allergic = status == .suspected ? "\(pronoun) might be allergic" : "\(pronoun)'s allergic"
        return "\(babyName)'s list says \(allergic) to \(allergen). \(check)"
    }

    // MARK: Food

    /// Whether a solids log may contain an allergy's allergen: one of its tags is that allergen,
    /// or its description mentions it as a word ("scrambled eggs" for egg, but not "eggplant").
    ///
    /// - `allergenID`: the allergy's common allergen, if it was picked from the list.
    /// - `allergyName`: matched as a word when it isn't a common allergen, and checked against the
    ///   tags' words too, so a typed-in "Peanuts" matches the Peanut tag.
    static func foodMatches(allergyName: String, allergenID: String?, tags: Set<String>, food: String) -> Bool {
        if let allergenID {
            if tags.contains(allergenID) { return true }
            if let allergen = CommonAllergen.with(id: allergenID) {
                return allergen.keywords.contains { mentions($0, in: food) }
            }
        }
        let name = key(allergyName)
        guard name.count >= 3 else { return false }
        if mentions(name, in: food) { return true }
        // A typed-in name like "Peanuts" or "Hen's egg" against the tags.
        return CommonAllergen.foods.contains { allergen in
            tags.contains(allergen.id) && allergen.keywords.contains { mentions($0, in: allergyName) }
        }
    }

    /// Whether `word` appears in `text` as a whole word, ignoring case, also as a plural
    /// ("egg" in "Eggs and toast", not in "eggplant").
    static func mentions(_ word: String, in text: String) -> Bool {
        let word = key(word)
        guard !word.isEmpty, !text.isEmpty else { return false }
        let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: word) + "(s|es)?(?![\\p{L}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let folded = text.folding(options: [.diacriticInsensitive], locale: nil)
        return regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
    }

    /// The common food allergens a description mentions, in the chips' order.
    static func foodAllergensMentioned(in text: String) -> [CommonAllergen] {
        CommonAllergen.foods.filter { allergen in allergen.keywords.contains { mentions($0, in: text) } }
    }

    /// "Mavie has a suspected egg allergy." The gentle warning in the solids editor.
    static func foodWarning(babyName: String, allergyName: String, status: AllergyStatus) -> String {
        let article = status == .suspected ? "a suspected" : "a confirmed"
        return "\(babyName) has \(article) \(allergyName.lowercased()) allergy."
    }
}

// MARK: - Introducing foods

/// One common food allergen on the "Introducing foods" screen: whether it's been tried, how often,
/// when it was first and last given, and any reactions logged around then.
///
/// It only counts what was tagged on solids logs. It doesn't say when or how often to give a food:
/// that's for the pediatrician.
struct AllergenIntroduction: Identifiable, Equatable {
    /// A solids log, with the allergens tagged on it.
    struct Feed {
        let date: Date
        let allergenIDs: Set<String>
    }

    /// A logged reaction, with the common allergen of the allergy it's linked to, if any.
    struct Reaction {
        let date: Date
        let allergenID: String?
    }

    let allergen: CommonAllergen
    let timesGiven: Int
    let firstGiven: Date?
    let lastGiven: Date?
    /// Reactions linked to an allergy to it, or logged within `reactionWindow` after it was given.
    let reactionDates: [Date]

    var id: String { allergen.id }
    var isTried: Bool { timesGiven > 0 }

    /// A reaction this soon after a feed with the allergen is shown next to it.
    static let reactionWindow: TimeInterval = 24 * 3600

    /// One entry per allergen, in the chips' order.
    ///
    /// Example: egg tagged on Oct 2 and Oct 9, a reaction on Oct 9 three hours later, and one on
    /// Oct 20 linked to nothing → egg: tried 2 times, first Oct 2, last Oct 9, one reaction (Oct 9).
    static func build(
        allergens: [CommonAllergen] = CommonAllergen.foods,
        feeds: [Feed],
        reactions: [Reaction]
    ) -> [AllergenIntroduction] {
        allergens.map { allergen -> AllergenIntroduction in
            let dates = feeds.filter { $0.allergenIDs.contains(allergen.id) }.map(\.date).sorted()
            let linked = reactions.filter { reaction in
                if reaction.allergenID == allergen.id { return true }
                return dates.contains { reaction.date >= $0 && reaction.date.timeIntervalSince($0) <= reactionWindow }
            }
            return AllergenIntroduction(
                allergen: allergen,
                timesGiven: dates.count,
                firstGiven: dates.first,
                lastGiven: dates.last,
                reactionDates: linked.map(\.date).sorted(by: >)
            )
        }
    }

    /// "Tried 4 times · first Oct 2", or "Not tried yet".
    var triedText: String {
        guard let firstGiven else { return "Not tried yet" }
        let times = timesGiven == 1 ? "Tried once" : "Tried \(timesGiven) times"
        return "\(times) · first \(firstGiven.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "Last given today", "Last given yesterday", "Last given 9 days ago", by calendar day.
    func lastGivenText(now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let lastGiven else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: lastGiven), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ..<1: return "Last given today"
        case 1: return "Last given yesterday"
        default: return "Last given \(days) days ago"
        }
    }
}

// MARK: - Lines for reports

extension Allergy {
    /// "Peanut — Confirmed, severe · Food · Reactions: hives · Auto-injector (diaper bag)", for the
    /// visit summary and the PDF report.
    var reportLine: String {
        var parts = ["\(status.title), \(severity.title.lowercased())", category.title]
        let seen = reactionsSeen.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seen.isEmpty { parts.append("Reactions: \(seen)") }
        let doctor = diagnosedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !doctor.isEmpty || diagnosedDate != nil {
            var diagnosed = "Diagnosed"
            if !doctor.isEmpty { diagnosed += " by \(doctor)" }
            if let diagnosedDate { diagnosed += " on \(diagnosedDate.formatted(date: .abbreviated, time: .omitted))" }
            parts.append(diagnosed)
        }
        if hasAutoInjector {
            let place = autoInjectorLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(place.isEmpty ? "Has an auto-injector" : "Auto-injector (\(place))")
        }
        return "\(displayName) — \(parts.joined(separator: " · "))"
    }
}

extension AllergyReaction {
    /// "Oct 3, 6:10 PM — Scrambled egg · Hives or rash, Vomiting · Moderate · Gave an antihistamine".
    var reportLine: String {
        var parts = [displayTitle]
        if !symptoms.isEmpty { parts.append(symptomsText) }
        parts.append(severity.title)
        if !actions.isEmpty { parts.append(actions.map(\.title).joined(separator: ", ")) }
        let when = date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "\(when) — \(parts.joined(separator: " · "))"
    }
}
