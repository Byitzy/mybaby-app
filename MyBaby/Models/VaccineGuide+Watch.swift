import Foundation

/// What to look out for after each vaccine, and when: the days after the shot when Today shows a
/// card (`VaccineFollowUpSection`), and the two or three short lines it says. Day 0 is the day of
/// the shot, counted in calendar days on this iPhone.
///
/// Most reactions come in the first day or two. A few vaccines have a second, later window: MMR and
/// MMRV about a week to two weeks after (fever, rash, swollen glands), chickenpox spots for up to
/// about four weeks, rotavirus's rare bowel blockage in the first week, and BCG's bump and blister
/// from about two weeks to three months. The windows are when reactions usually show up, not a
/// promise that nothing happens outside them, so every card links to the vaccine's notes and to
/// *Comfort, and when to call*.
///
/// Written from the same vaccine information statements as the rest of the guide (CDC, NHS, Public
/// Health Agency of Canada), conservatively, in the same words where they overlap. Reviewed with
/// the guide (`reviewedMonth`); change the French and Spanish with the English.
extension VaccineGuide {
    /// One short line on a card.
    struct WatchLine: Hashable {
        let text: String
        /// The signs to call about or get care for. A card that brings several vaccines together keeps
        /// these even when it has to leave other lines out (see `VaccineFollowUp.Card.lines`).
        var isKey = false
    }

    /// The optional 9 AM reminder on the day a later window starts (`VaccineFollowUp.refresh`).
    enum WatchReminder: Hashable {
        /// MMR: fever, or a rash that isn't contagious.
        case feverOrRash
        /// MMRV: the same, and chickenpox spots.
        case feverRashOrSpots
        /// BCG: the bump and blister where it was given.
        case bcgSite
    }

    /// The days after a shot when a card shows, and what it says.
    struct WatchWindow: Hashable {
        /// Stable, for remembering a dismissed card on this iPhone (with the vaccine): "first-days",
        /// "first-week", "later", "spots" or "site". Never change one that has shipped.
        let id: String
        /// The first and last day it covers; day 0 is the day of the shot.
        let days: ClosedRange<Int>
        let lines: [WatchLine]
        /// Set on the windows that start days after the shot, so a heads-up can come that morning.
        var reminder: WatchReminder?
        /// The first days after most vaccines, nothing specific to this one. On a card with other
        /// vaccines, their own lines come first.
        var isGeneral = false
    }

    /// The windows for a vaccine in the guide, in order. A vaccine that isn't in the guide (`nil`),
    /// such as one typed by hand, gets the first days after any vaccine.
    static func watchWindows(for entry: Entry?) -> [WatchWindow] {
        switch entry?.id ?? "" {
        case "rsv":
            return [WatchWindow(id: "first-days", days: 0...2, lines: [rsvMild, cuddles])]
        case "menb":
            return [WatchWindow(id: "first-days", days: 0...2, lines: [menBFever, cuddles, menBParacetamol])]
        case "rotavirus":
            return [WatchWindow(id: "first-week", days: 0...7, lines: [rotavirusMild, intussusception])]
        case "mmr":
            return [
                firstDays,
                WatchWindow(id: "later", days: 6...14, lines: [mmrLater, mmrGlands, febrileSeizure], reminder: .feverOrRash),
            ]
        case "mmrv":
            return [
                firstDays,
                WatchWindow(id: "later", days: 6...14, lines: [mmrvLater, febrileSeizure, coverSpots], reminder: .feverRashOrSpots),
                WatchWindow(id: "spots", days: 15...28, lines: [spotsUpToFourWeeks, coverSpots]),
            ]
        case "varicella":
            return [
                firstDays,
                WatchWindow(id: "spots", days: 3...28, lines: [spotsUpToFourWeeks, coverSpots]),
            ]
        case "bcg":
            // Nothing to see in the first days: the bump comes after a couple of weeks.
            return [WatchWindow(id: "site", days: 14...84, lines: [bcgBump, bcgCare, bcgCall], reminder: .bcgSite)]
        default:
            return [firstDays]
        }
    }

    /// A short name for a card's title or a reminder: "MMR was 9 days ago", or "MMR and the chickenpox
    /// vaccine were 9 days ago", so the ones in words are lowercase (the title's first letter is
    /// capitalized). Only the vaccines with a window past the first days need one; `nil` for the
    /// others, which use their name.
    static func watchShortName(for entry: Entry) -> String? {
        switch entry.id {
        case "mmr": return String(localized: "MMR", comment: "Short vaccine name, in a title like “MMR was 9 days ago”. Use the local abbreviation.")
        case "mmrv": return String(localized: "MMRV", comment: "Short vaccine name, in a title like “MMRV was 9 days ago”. Use the local abbreviation.")
        case "varicella": return String(localized: "the chickenpox vaccine", comment: "Short vaccine name, in a title like “MMR and the chickenpox vaccine were 9 days ago”. Lowercase: the title's first letter is capitalized.")
        case "rotavirus": return String(localized: "the rotavirus vaccine", comment: "Short vaccine name, in a title like “The rotavirus vaccine was 4 days ago”. Lowercase: the title's first letter is capitalized.")
        case "bcg": return String(localized: "BCG", comment: "Short vaccine name, in a title like “BCG was 3 weeks ago”")
        default: return nil
        }
    }

    /// The reminder's text the morning a later window starts: "MMR was 6 days ago: a fever or mild
    /// rash can show up around now. Here's what's normal." Whole sentences, so each language has its
    /// own word order.
    static func reminderBody(_ reminder: WatchReminder, name: String, day: Int) -> String {
        switch reminder {
        case .feverOrRash:
            return String(
                localized: "\(name) was \(day) days ago: a fever or mild rash can show up around now. Here's what's normal.",
                comment: "Notification after a vaccine; a short vaccine name like MMR, then a number of days. Medical: keep the meaning exact"
            )
        case .feverRashOrSpots:
            return String(
                localized: "\(name) was \(day) days ago: a fever, a mild rash or a few spots can show up around now. Here's what's normal.",
                comment: "Notification after a vaccine; a short vaccine name like MMRV, then a number of days. Medical: keep the meaning exact"
            )
        case .bcgSite:
            return String(
                localized: "\(name) was \(day / 7) weeks ago: a small red bump or blister where it was given is normal from around now. Here's what to expect.",
                comment: "Notification after the BCG vaccine; a short vaccine name, then a number of weeks. Medical: keep the meaning exact"
            )
        }
    }
}

// MARK: - The lines

extension VaccineGuide {
    /// The first days after most vaccines.
    private static let firstDays = WatchWindow(id: "first-days", days: 0...2, lines: [firstDaysCommon, cuddles], isGeneral: true)

    private static let firstDaysCommon = WatchLine(text: String(localized: "Soreness where the shot was given, a low fever, fussiness or extra sleep are common for a day or two.", comment: "Vaccine follow-up card on Today. Medical: keep the meaning exact"))
    private static let cuddles = WatchLine(text: String(localized: "Cuddles, extra feeds and a cool, damp cloth on the spot can help.", comment: "Vaccine follow-up card on Today: comfort after the shots"))

    private static let rsvMild = WatchLine(text: String(localized: "Reactions to the RSV antibody are uncommon and mild, like a sore spot or a mild rash.", comment: "Vaccine follow-up card on Today. Medical: keep the meaning exact"))

    private static let menBFever = WatchLine(text: String(localized: "Fever is more common after MenB than after other baby vaccines, usually in the first day or two.", comment: "Vaccine follow-up card on Today. Medical: keep the meaning exact"))
    private static let menBParacetamol = WatchLine(
        text: String(localized: "Follow your clinic's advice on giving infant paracetamol (acetaminophen) after this shot, and how much.", comment: "Vaccine follow-up card on Today, after the MenB vaccine. Medical: keep the meaning exact"),
        isKey: true
    )

    private static let rotavirusMild = WatchLine(text: String(localized: "Some babies are a little fussy, or have mild, short-lived diarrhea or vomiting.", comment: "Vaccine follow-up card on Today, after the rotavirus vaccine. Medical: keep the meaning exact"))
    private static let intussusception = WatchLine(
        text: String(localized: "Very rarely, a bowel blockage (intussusception), usually in the week after the first or second dose. Get care right away for bouts of hard crying with the legs pulled up, repeated vomiting, blood in the poop, or unusual weakness.", comment: "Vaccine follow-up card on Today, after the rotavirus vaccine. Medical: keep the meaning exact"),
        isKey: true
    )

    private static let mmrLater = WatchLine(text: String(localized: "A fever or a mild rash that isn't contagious can show up around now, usually for 2 or 3 days.", comment: "Vaccine follow-up card on Today, a week or two after the MMR vaccine. Medical: keep the meaning exact"))
    private static let mmrGlands = WatchLine(text: String(localized: "Swollen glands in the cheeks or neck can come too, sometimes a few weeks after the shot.", comment: "Vaccine follow-up card on Today, after the MMR vaccine. Medical: keep the meaning exact"))
    private static let mmrvLater = WatchLine(text: String(localized: "A fever, a mild rash or a few spots can show up around now.", comment: "Vaccine follow-up card on Today, a week or two after the MMRV vaccine. Medical: keep the meaning exact"))
    private static let febrileSeizure = WatchLine(
        text: String(localized: "Rarely, the fever brings on a short seizure (a febrile seizure). It's frightening but usually harmless: call your doctor.", comment: "Vaccine follow-up card on Today. Medical: keep the meaning exact"),
        isKey: true
    )

    private static let spotsUpToFourWeeks = WatchLine(text: String(localized: "A mild rash or a few spots can show up, up to about 4 weeks after the shot.", comment: "Vaccine follow-up card on Today, after a chickenpox vaccine. Medical: keep the meaning exact"))
    private static let coverSpots = WatchLine(
        text: String(localized: "Spots from the vaccine can, very rarely, pass it on: keep them covered around newborns, pregnant people and anyone with a weak immune system.", comment: "Vaccine follow-up card on Today, after a chickenpox vaccine. Medical: keep the meaning exact"),
        isKey: true
    )

    private static let bcgBump = WatchLine(text: String(localized: "A small red bump where it was given, which may become a blister or small sore, is normal. It heals over a few months and leaves a small scar.", comment: "Vaccine follow-up card on Today, after the BCG vaccine. Medical: keep the meaning exact"))
    private static let bcgCare = WatchLine(text: String(localized: "Keep it clean and dry, and don't cover it tightly.", comment: "Vaccine follow-up card on Today: the spot where the BCG vaccine was given"))
    private static let bcgCall = WatchLine(
        text: String(localized: "Call your clinic if it oozes a lot, the glands in the armpit swell, or it hasn't healed after a few months.", comment: "Vaccine follow-up card on Today, after the BCG vaccine. Medical: keep the meaning exact"),
        isKey: true
    )
}
