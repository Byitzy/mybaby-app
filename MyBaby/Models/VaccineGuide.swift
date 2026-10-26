import Foundation

/// Plain-language notes on the vaccines babies and young children are offered: what each one
/// protects against, roughly when it's given, and what's normal afterwards. They're bundled with the
/// app, so they work offline and nothing is looked up.
///
/// Schedules differ between countries and change over time, so the notes never say exactly when a
/// dose is due; that comes from the parents' clinic, and the guide links the official schedule for
/// their region. Written from the vaccine information statements of public health agencies (CDC,
/// NHS, Public Health Agency of Canada) and checked in `reviewed`. The French and Spanish notes are
/// translations of the English ones: change all three together.
enum VaccineGuide {
    /// When the notes and links were last checked. Check them again at least once a year, and when
    /// a schedule changes.
    static let reviewedMonth = DateComponents(year: 2026, month: 10)

    /// "October 2026", written the way the iPhone's language writes it.
    static var reviewed: String {
        let date = Calendar(identifier: .gregorian).date(from: reviewedMonth) ?? .now
        return date.formatted(.dateTime.month(.wide).year())
    }

    enum Group: String, CaseIterable, Identifiable {
        /// On most countries' schedules for babies and toddlers.
        case routine
        /// Several of the routine vaccines in one shot.
        case combination
        /// Routine in some countries, or for babies more likely to be exposed.
        case someBabies

        var id: String { rawValue }

        var title: String {
            switch self {
            case .routine: return String(localized: "For babies and toddlers", comment: "Vaccine guide: group of vaccines")
            case .combination: return String(localized: "Combination shots", comment: "Vaccine guide: group of vaccines")
            case .someBabies: return String(localized: "In some countries, or for some babies", comment: "Vaccine guide: group of vaccines")
            }
        }
    }

    struct Entry: Identifiable, Hashable {
        let id: String
        /// What goes in the vaccine's name field when it's picked, in the iPhone's language.
        let name: String
        /// Not localized: the English name, so a vaccine saved in English (before the app was
        /// translated, or on an English iPhone) still finds its notes in any language.
        let englishName: String
        /// Brand names and abbreviations as they appear on vaccine records (in English and French),
        /// so a vaccine typed in or saved before the guide still finds its notes.
        let otherNames: [String]
        let group: Group
        /// "Hepatitis B, a virus that infects the liver". One line, for the list.
        let protectsAgainst: String
        /// Why it matters, in two or three sentences.
        let about: String
        /// Roughly when, without exact ages, which differ by country.
        let usuallyGiven: String
        /// Normal reactions, which usually pass in a day or two.
        let commonReactions: [String]
        /// Rare reactions worth knowing about, with what to watch for. Empty when the advice for any
        /// vaccine covers it.
        let watchFor: [String]
    }

    /// The names offered in menus, like "Add a shot" in the visit recap: the routine ones.
    static var commonNames: [String] {
        entries.filter { $0.group == .routine }.map(\.name)
    }

    static func entries(in group: Group) -> [Entry] {
        entries.filter { $0.group == group }
    }

    /// The notes for a vaccine's name as saved or typed: "DTaP", "Infanrix hexa", "Rotavirus (RV)",
    /// "RRO-Var". The longest name that matches wins, so "DTaP-IPV-Hib-HepB" finds the 6-in-1, not
    /// DTaP. Names are matched in the iPhone's language and in English, so a name picked in either
    /// still finds its notes. `nil` when nothing matches.
    static func entry(matching typed: String) -> Entry? {
        let text = " \(normalized(typed)) "
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { return nil }
        var best: (entry: Entry, length: Int)?
        for entry in entries {
            for candidate in [entry.name, entry.englishName] + entry.otherNames {
                let name = normalized(candidate)
                guard !name.isEmpty, text.contains(" \(name) ") else { continue }
                if name.count > (best?.length ?? 0) {
                    best = (entry, name.count)
                }
            }
        }
        return best?.entry
    }

    /// Lowercased, accents and punctuation gone, single spaces: "DCaT-HB-VPI-Hib" → "dcat hb vpi hib".
    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let spaced = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }
}

// MARK: - After any vaccine

extension VaccineGuide {
    /// Comfort, for the day of the shots and the day after.
    static let comfort = [
        String(localized: "Hold and cuddle your baby during and right after the shots. Feeding, by breast or bottle, during or just after can soothe them too.", comment: "Vaccine guide: comfort after the shots"),
        String(localized: "A cool, damp cloth on the spot can ease soreness.", comment: "Vaccine guide: comfort after the shots"),
        String(localized: "Offer feeds often. It's normal for babies to be fussier, sleepier or less hungry for a day or two.", comment: "Vaccine guide: comfort after the shots"),
        String(localized: "Ask your clinic before giving any medicine for pain or fever, and how much for your baby's weight.", comment: "Vaccine guide: comfort after the shots"),
    ]

    /// When to call the doctor or nurse line.
    static let callTheDoctor = [
        String(localized: "A fever of 40 °C (104 °F) or higher.", comment: "Vaccine guide: when to call the doctor"),
        String(localized: "Under 3 months old, any fever of 38 °C (100.4 °F) or more, unless your clinic said a mild fever after these shots is expected.", comment: "Vaccine guide: when to call the doctor"),
        String(localized: "Crying that can't be soothed for 3 hours or more.", comment: "Vaccine guide: when to call the doctor"),
        String(localized: "Redness or soreness where the shot was given that gets worse after a day.", comment: "Vaccine guide: when to call the doctor"),
        String(localized: "A seizure, even a short one.", comment: "Vaccine guide: when to call the doctor"),
        String(localized: "Anything else that worries you, or your baby just doesn't seem right.", comment: "Vaccine guide: when to call the doctor"),
    ]

    /// Allergic reactions are very rare, and clinics are ready for them; that's why they ask you to
    /// stay a little while after the shots.
    static let emergencySigns = String(localized: "Hives, swelling of the face or throat, trouble breathing, a racing heartbeat, or being very pale, floppy or hard to wake. These usually start within minutes to an hour.", comment: "Vaccine guide: signs of a severe allergic reaction, an emergency")
}

// MARK: - Official schedules

extension VaccineGuide {
    struct ScheduleLink: Identifiable, Hashable {
        let title: String
        let detail: String
        let url: URL

        var id: URL { url }
    }

    /// Note for the US, where the federal schedule and the pediatricians' one have differed in 2026.
    static let unitedStatesNote = String(localized: "In the US, the CDC's schedule changed in 2026, the change was challenged in court, and the American Academy of Pediatrics publishes its own. Ask your pediatrician which schedule they follow.", comment: "Vaccine guide: note for the United States")

    /// The official schedules for the region picked for support lines (or the iPhone's Region), with
    /// the province's first. Falls back to the WHO's summary for other countries.
    static func scheduleLinks(regionCode: String, subregionCode: String) -> [ScheduleLink] {
        switch regionCode.uppercased() {
        case "US":
            return [
                ScheduleLink(
                    title: String(localized: "American Academy of Pediatrics", comment: "Vaccine guide: the organization that publishes a schedule"),
                    detail: String(localized: "Recommended schedules, for parents (HealthyChildren.org)", comment: "Vaccine guide: what the linked page is"),
                    url: URL(string: "https://www.healthychildren.org/English/safety-prevention/immunizations/Pages/Recommended-Immunization-Schedules.aspx")!
                ),
                ScheduleLink(
                    title: String(localized: "CDC", comment: "Vaccine guide: the US Centers for Disease Control and Prevention"),
                    detail: String(localized: "Child and adolescent immunization schedule", comment: "Vaccine guide: what the linked page is"),
                    url: URL(string: "https://www.cdc.gov/vaccines/hcp/imz-schedules/child-adolescent.html")!
                ),
            ]
        case "CA":
            let canada = ScheduleLink(
                title: String(localized: "Public Health Agency of Canada", comment: "Vaccine guide: the organization that publishes a schedule"),
                detail: String(localized: "Each province's and territory's schedule for infants and children", comment: "Vaccine guide: what the linked page is"),
                url: URL(string: "https://www.canada.ca/en/public-health/services/provincial-territorial-immunization-information/provincial-territorial-routine-vaccination-programs-infants-children.html")!
            )
            guard subregionCode.uppercased() == "QC" else { return [canada] }
            return [
                ScheduleLink(
                    title: String(localized: "Québec", comment: "Vaccine guide: the province, which publishes its own schedule"),
                    detail: String(localized: "Programme québécois d'immunisation (calendrier de vaccination)", comment: "Vaccine guide: the official name of Québec's program, in French, and what the linked page is"),
                    url: URL(string: "https://www.quebec.ca/sante/conseils-et-prevention/vaccination/programme-quebecois-d-immunisation")!
                ),
                canada,
            ]
        case "GB":
            return [
                ScheduleLink(
                    title: String(localized: "NHS", comment: "Vaccine guide: the UK's National Health Service"),
                    detail: String(localized: "NHS vaccinations and when to have them", comment: "Vaccine guide: what the linked page is"),
                    url: URL(string: "https://www.nhs.uk/vaccinations/nhs-vaccinations-and-when-to-have-them/")!
                ),
            ]
        default:
            return [
                ScheduleLink(
                    title: String(localized: "World Health Organization", comment: "Vaccine guide: the organization that publishes a schedule"),
                    detail: String(localized: "Recommended routine vaccines. Your country's health ministry has its own schedule.", comment: "Vaccine guide: what the linked page is"),
                    url: URL(string: "https://www.who.int/teams/immunization-vaccines-and-biologicals/policies/who-recommendations-for-routine-immunization---summary-tables")!
                ),
            ]
        }
    }
}

// MARK: - The vaccines

extension VaccineGuide {
    private static let siteSoreness = String(localized: "Soreness, redness or swelling where the shot was given", comment: "Vaccine guide: a common reaction")
    private static let fussy = String(localized: "Fussiness, sleepiness or less appetite", comment: "Vaccine guide: a common reaction")
    private static let fever = String(localized: "Fever")
    private static let seizureOrHighFever = String(localized: "Rarely, a seizure, nonstop crying for 3 hours or more, or a fever over 40.5 °C (105 °F). Call your doctor.", comment: "Vaccine guide: a rare reaction to watch for")

    static let entries: [Entry] = [
        Entry(
            id: "hepb",
            name: String(localized: "Hepatitis B (HepB)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Hepatitis B (HepB)",
            otherNames: ["Hepatitis B", "HepB", "Hep B", "HBV", "HB", "Hepatitis B (HB)", "Engerix", "Recombivax", "Heplisav"],
            group: .routine,
            protectsAgainst: String(localized: "Hepatitis B, a virus that infects the liver", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Hepatitis B can pass to a baby at birth or later through blood. Babies who catch it usually keep it for life, and it can damage the liver over the years.", comment: "Vaccine guide: about hepatitis B"),
            usuallyGiven: String(localized: "Often a first dose at birth, then more in the first year, sometimes as part of a 6-in-1 shot.", comment: "Vaccine guide: when the hepatitis B vaccine is usually given"),
            commonReactions: [siteSoreness, String(localized: "A low fever", comment: "Vaccine guide: a common reaction")],
            watchFor: []
        ),
        Entry(
            id: "rsv",
            name: String(localized: "RSV antibody (nirsevimab or clesrovimab)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "RSV antibody (nirsevimab or clesrovimab)",
            otherNames: ["RSV antibody", "RSV", "nirsevimab", "VSR", "Beyfortus", "clesrovimab", "Enflonsia", "palivizumab", "Synagis", "VRS"],
            group: .routine,
            protectsAgainst: String(localized: "RSV, the most common cause of bronchiolitis and pneumonia in babies", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Not a vaccine but a ready-made antibody given as a shot, so it protects right away, for about one RSV season. Babies whose parent had the RSV vaccine late in pregnancy may not need it; your clinic will check.", comment: "Vaccine guide: about the RSV antibody"),
            usuallyGiven: String(localized: "Once, just before or during the baby's first RSV season (fall and winter in many places). Some babies at higher risk get a dose in their second season too.", comment: "Vaccine guide: when the RSV antibody is usually given"),
            commonReactions: [siteSoreness, String(localized: "A mild rash", comment: "Vaccine guide: a common reaction")],
            watchFor: []
        ),
        Entry(
            id: "rotavirus",
            name: String(localized: "Rotavirus (RV)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Rotavirus (RV)",
            otherNames: ["Rotavirus", "RV1", "RV5", "RotaTeq", "Rotarix", "Rota"],
            group: .routine,
            protectsAgainst: String(localized: "Rotavirus, which causes severe diarrhea and vomiting", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Rotavirus can dehydrate a baby quickly. This one is drops in the mouth, not a shot. It has to be started young, so it's given in the first months and not started late.", comment: "Vaccine guide: about the rotavirus vaccine"),
            usuallyGiven: String(localized: "2 or 3 doses in the first months, starting around 6 to 8 weeks.", comment: "Vaccine guide: when the rotavirus vaccine is usually given"),
            commonReactions: [
                String(localized: "Fussiness", comment: "Symptom of a reaction"),
                String(localized: "Mild, short-lived diarrhea or vomiting", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: [
                String(localized: "Very rarely, in the week after the first or second dose, a bowel blockage called intussusception. Get care right away for bouts of hard crying with the legs pulled up to the chest, repeated vomiting, blood in the poop, or unusual weakness.", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),
        Entry(
            id: "dtap",
            name: String(localized: "DTaP (diphtheria, tetanus, whooping cough)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "DTaP (diphtheria, tetanus, whooping cough)",
            otherNames: ["DTaP", "DTPa", "DCaT", "Daptacel", "Infanrix", "whooping cough", "pertussis", "coqueluche", "diphtheria", "tetanus"],
            group: .routine,
            protectsAgainst: String(localized: "Diphtheria, tetanus and whooping cough (pertussis)", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Whooping cough is most dangerous for young babies: the coughing fits can stop them breathing. Tetanus comes from germs in dirt getting into a wound, and diphtheria can block the airway. Often given as part of a 5-in-1 or 6-in-1 shot.", comment: "Vaccine guide: about the DTaP vaccine"),
            usuallyGiven: String(localized: "Several doses in the first year, then boosters as a toddler and before school.", comment: "Vaccine guide: when the DTaP vaccine is usually given"),
            commonReactions: [
                siteSoreness,
                fever,
                fussy,
                String(localized: "After a later dose, swelling of the whole arm or leg, which goes away in a few days", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: [seizureOrHighFever]
        ),
        Entry(
            id: "hib",
            name: String(localized: "Hib (Haemophilus influenzae type b)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Hib (Haemophilus influenzae type b)",
            otherNames: ["Hib", "ActHIB", "PedvaxHIB", "Hiberix", "Haemophilus"],
            group: .routine,
            protectsAgainst: String(localized: "Hib bacteria, which can cause meningitis and serious throat and lung infections", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Before the vaccine, Hib was a leading cause of meningitis in young children. Despite the name, it isn't the flu. Often given as part of a 5-in-1 or 6-in-1 shot.", comment: "Vaccine guide: about the Hib vaccine"),
            usuallyGiven: String(localized: "Several doses in the first year, and a booster around the first birthday.", comment: "Vaccine guide: when the vaccine is usually given"),
            commonReactions: [String(localized: "Redness, warmth or swelling where the shot was given", comment: "Vaccine guide: a common reaction"), fever],
            watchFor: []
        ),
        Entry(
            id: "pcv",
            name: String(localized: "Pneumococcal (PCV)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Pneumococcal (PCV)",
            otherNames: ["PCV", "PCV13", "PCV15", "PCV20", "Pneumococcal", "Pneu-C", "VCN", "Pneumococo", "Prevnar", "Prevenar", "Vaxneuvance", "pneumocoque"],
            group: .routine,
            protectsAgainst: String(localized: "Pneumococcal bacteria, which cause ear infections, pneumonia, meningitis and blood infections", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Pneumococcal disease is one of the most common causes of serious infections in children under 2.", comment: "Vaccine guide: about the pneumococcal vaccine"),
            usuallyGiven: String(localized: "2 or 3 doses in the first year, and a booster around the first birthday.", comment: "Vaccine guide: when the pneumococcal vaccine is usually given"),
            commonReactions: [siteSoreness, fever, fussy],
            watchFor: [
                String(localized: "Given at the same visit as a flu shot, there's a small extra chance of a short seizure caused by fever (a febrile seizure).", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),
        Entry(
            id: "ipv",
            name: String(localized: "Polio (IPV)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Polio (IPV)",
            otherNames: ["Polio", "IPV", "IPOL", "VPI"],
            group: .routine,
            protectsAgainst: String(localized: "Polio, a virus that can cause paralysis", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Polio is now rare in most of the world because of vaccination, but it hasn't gone away everywhere. Often given as part of a 5-in-1 or 6-in-1 shot.", comment: "Vaccine guide: about the polio vaccine"),
            usuallyGiven: String(localized: "Several doses in the first years, and a booster before school.", comment: "Vaccine guide: when the polio vaccine is usually given"),
            commonReactions: [String(localized: "A sore spot with redness, swelling or pain where the shot was given", comment: "Vaccine guide: a common reaction")],
            watchFor: []
        ),
        Entry(
            id: "flu",
            name: String(localized: "Influenza (Flu)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Influenza (Flu)",
            otherNames: ["Influenza", "Flu", "FluMist", "Fluenz", "Fluzone", "Fluarix", "FluLaval", "Afluria", "Flucelvax", "grippe"],
            group: .routine,
            protectsAgainst: String(localized: "The flu, which can be serious for babies and young children", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Flu viruses change, so the vaccine is updated every year. The first time, young children often need 2 doses, 4 weeks apart. Babies under 6 months are best protected when the people around them, and the parent during pregnancy, get vaccinated.", comment: "Vaccine guide: about the flu vaccine"),
            usuallyGiven: String(localized: "Every year from 6 months, before flu season. From age 2, some countries offer a nasal spray instead of a shot.", comment: "Vaccine guide: when the flu vaccine is usually given"),
            commonReactions: [
                siteSoreness,
                String(localized: "Fever, aches or a headache", comment: "Vaccine guide: a common reaction"),
                String(localized: "After the nasal spray, a runny or stuffy nose", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: []
        ),
        Entry(
            id: "covid",
            name: String(localized: "COVID-19", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "COVID-19",
            otherNames: ["COVID", "COVID-19", "coronavirus", "Spikevax", "Comirnaty", "Novavax", "Nuvaxovid", "mNEXSPIKE"],
            group: .routine,
            protectsAgainst: String(localized: "COVID-19", comment: "Vaccine name. Use the official name and abbreviation."),
            about: String(localized: "Offered from 6 months in many countries, in some only to babies at higher risk. Advice differs by country and changes over time, so ask your clinic.", comment: "Vaccine guide: about the COVID-19 vaccine"),
            usuallyGiven: String(localized: "From 6 months, as advised where you live.", comment: "Vaccine guide: when the COVID-19 vaccine is usually given"),
            commonReactions: [siteSoreness, fever, fussy],
            watchFor: [
                String(localized: "Very rarely, inflammation of the heart, seen mostly in teenage boys and young men. Get care for trouble breathing, a racing heartbeat or chest pain.", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),
        Entry(
            id: "mmr",
            name: String(localized: "MMR (measles, mumps, rubella)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "MMR (measles, mumps, rubella)",
            otherNames: ["MMR", "SRP", "MMR II", "M-M-R II", "Priorix", "RRO", "ROR", "measles", "mumps", "rubella", "rougeole"],
            group: .routine,
            protectsAgainst: String(localized: "Measles, mumps and rubella (German measles)", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Measles spreads very easily and can cause pneumonia, swelling of the brain and death. Mumps can cause deafness, and rubella is dangerous in pregnancy.", comment: "Vaccine guide: about the MMR vaccine"),
            usuallyGiven: String(localized: "A first dose from 12 months and a second one later in childhood. It can be given from 6 months before travel or during an outbreak.", comment: "Vaccine guide: when the MMR vaccine is usually given"),
            commonReactions: [
                String(localized: "A sore arm", comment: "Vaccine guide: a common reaction"),
                String(localized: "Fever and a mild rash, usually 1 to 2 weeks after the shot. The rash isn't contagious.", comment: "Vaccine guide: a common reaction"),
                String(localized: "Swollen glands in the cheeks or neck", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: [
                String(localized: "Rarely, a short seizure caused by the fever (a febrile seizure), 1 to 2 weeks after. It's frightening but usually harmless; call your doctor.", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),
        Entry(
            id: "varicella",
            name: String(localized: "Varicella (Chickenpox)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Varicella (Chickenpox)",
            otherNames: ["Varicella", "Chickenpox", "Chicken pox", "VAR", "Varivax", "Varilrix", "varicelle"],
            group: .routine,
            protectsAgainst: String(localized: "Chickenpox", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Chickenpox is usually mild but very uncomfortable, and it can lead to serious skin infections, pneumonia and swelling of the brain.", comment: "Vaccine guide: about the chickenpox vaccine"),
            usuallyGiven: String(localized: "From 12 months, with a second dose later in childhood. Some countries give it with MMR in one shot (MMRV).", comment: "Vaccine guide: when the chickenpox vaccine is usually given"),
            commonReactions: [
                String(localized: "A sore arm", comment: "Vaccine guide: a common reaction"),
                fever,
                String(localized: "A mild rash or a few spots, up to a month after the shot", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: [
                String(localized: "Spots from the vaccine can, very rarely, pass it on. Keep them covered around newborns, pregnant people and anyone with a weak immune system.", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),
        Entry(
            id: "hepa",
            name: String(localized: "Hepatitis A (HepA)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Hepatitis A (HepA)",
            otherNames: ["Hepatitis A", "HepA", "Hep A", "Havrix", "Vaqta", "Avaxim"],
            group: .routine,
            protectsAgainst: String(localized: "Hepatitis A, a liver infection spread through food, water and close contact", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Young children often have no symptoms but can pass it on to adults, who get much sicker.", comment: "Vaccine guide: about the hepatitis A vaccine"),
            usuallyGiven: String(localized: "2 doses from 12 months, at least 6 months apart, or before travel.", comment: "Vaccine guide: when the hepatitis A vaccine is usually given"),
            commonReactions: [siteSoreness, String(localized: "Fever, a headache, tiredness or less appetite", comment: "Vaccine guide: a common reaction")],
            watchFor: []
        ),

        Entry(
            id: "6in1",
            name: String(localized: "6-in-1 (DTaP-IPV-Hib-HepB)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "6-in-1 (DTaP-IPV-Hib-HepB)",
            otherNames: ["6-in-1", "6 in 1", "hexavalent", "DTaP-IPV-Hib-HepB", "DTaP-HepB-IPV-Hib", "DCaT-HB-VPI-Hib", "Vaxelis", "Infanrix hexa", "Hexyon", "Hexaxim"],
            group: .combination,
            protectsAgainst: String(localized: "Diphtheria, tetanus, whooping cough, polio, Hib and hepatitis B, in one shot", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Six vaccines in one shot, so your baby gets fewer pokes. What it protects against, and what to expect after, is the same as for each of them.", comment: "Vaccine guide: about the 6-in-1 vaccine"),
            usuallyGiven: String(localized: "Several doses in the first year, and in some countries a booster in the second year.", comment: "Vaccine guide: when the 6-in-1 vaccine is usually given"),
            commonReactions: [siteSoreness, fever, fussy],
            watchFor: [seizureOrHighFever]
        ),
        Entry(
            id: "5in1",
            name: String(localized: "5-in-1 (DTaP-IPV-Hib)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "5-in-1 (DTaP-IPV-Hib)",
            otherNames: ["5-in-1", "5 in 1", "pentavalent", "DTaP-IPV-Hib", "DTaP-IPV/Hib", "DCaT-VPI-Hib", "Pentacel", "Pediacel", "Pentaxim"],
            group: .combination,
            protectsAgainst: String(localized: "Diphtheria, tetanus, whooping cough, polio and Hib, in one shot", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Five vaccines in one shot. What to expect after is the same as for each of them.", comment: "Vaccine guide: about a 5-in-1 vaccine"),
            usuallyGiven: String(localized: "Several doses in the first year and a booster in the second year.", comment: "Vaccine guide: when the 5-in-1 vaccine is usually given"),
            commonReactions: [siteSoreness, fever, fussy],
            watchFor: [seizureOrHighFever]
        ),
        Entry(
            id: "dtap-hepb-ipv",
            name: String(localized: "DTaP-HepB-IPV", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "DTaP-HepB-IPV",
            otherNames: ["DTaP-HepB-IPV", "Pediarix"],
            group: .combination,
            protectsAgainst: String(localized: "Diphtheria, tetanus, whooping cough, hepatitis B and polio, in one shot", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Five vaccines in one shot. What to expect after is the same as for each of them. Fever is a little more common than with separate shots.", comment: "Vaccine guide: about the DTaP-HepB-IPV vaccine"),
            usuallyGiven: String(localized: "Several doses in the first year.", comment: "Vaccine guide: when the vaccine is usually given"),
            commonReactions: [siteSoreness, fever, fussy],
            watchFor: [seizureOrHighFever]
        ),
        Entry(
            id: "dtap-ipv",
            name: String(localized: "4-in-1 booster (DTaP-IPV)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "4-in-1 booster (DTaP-IPV)",
            otherNames: ["4-in-1", "4 in 1", "DTaP-IPV", "dTaP-IPV", "DCaT-VPI", "Kinrix", "Quadracel", "Repevax", "Boostrix-IPV", "Infanrix-IPV", "preschool booster", "pre-school booster"],
            group: .combination,
            protectsAgainst: String(localized: "Diphtheria, tetanus, whooping cough and polio, in one shot", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "The booster most children get before starting school.", comment: "Vaccine guide: about the 4-in-1 booster"),
            usuallyGiven: String(localized: "Once, between about 3 and 6 years old.", comment: "Vaccine guide: when the 4-in-1 booster is usually given"),
            commonReactions: [
                siteSoreness,
                String(localized: "Swelling of the whole upper arm, which goes away in a few days", comment: "Vaccine guide: a common reaction"),
                String(localized: "Fever or tiredness", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: []
        ),
        Entry(
            id: "mmrv",
            name: String(localized: "MMRV (measles, mumps, rubella, chickenpox)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "MMRV (measles, mumps, rubella, chickenpox)",
            otherNames: ["MMRV", "ProQuad", "Priorix-Tetra", "RRO-Var", "RROV"],
            group: .combination,
            protectsAgainst: String(localized: "Measles, mumps, rubella and chickenpox, in one shot", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "The MMR and chickenpox vaccines in one shot. What to expect after is the same as for each of them.", comment: "Vaccine guide: about the MMRV vaccine"),
            usuallyGiven: String(localized: "From 12 months, depending on your country, and often as the second dose later in childhood.", comment: "Vaccine guide: when the MMRV vaccine is usually given"),
            commonReactions: [
                String(localized: "A sore arm", comment: "Vaccine guide: a common reaction"),
                String(localized: "Fever and a mild rash, usually 1 to 2 weeks after the shot", comment: "Vaccine guide: a common reaction"),
                String(localized: "Swollen glands in the cheeks or neck", comment: "Vaccine guide: a common reaction"),
            ],
            watchFor: [
                String(localized: "As a first dose between 12 months and 2 years, a short seizure from fever 1 to 2 weeks later is a little more likely than with separate MMR and chickenpox shots, which is why some clinics give them separately at that age.", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),

        Entry(
            id: "menb",
            name: String(localized: "Meningococcal B (MenB)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Meningococcal B (MenB)",
            otherNames: ["MenB", "Men B", "Meningococcal B", "4CMenB", "Bexsero", "Trumenba", "Men-B"],
            group: .someBabies,
            protectsAgainst: String(localized: "Meningococcal B bacteria, a cause of meningitis and sepsis", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Meningococcal disease is rare but can become life-threatening within hours. In some countries, such as the UK and Ireland, every baby is offered MenB.", comment: "Vaccine guide: about the MenB vaccine"),
            usuallyGiven: String(localized: "Where it's routine, 2 doses in the first months and a booster around the first birthday.", comment: "Vaccine guide: when the MenB vaccine is usually given"),
            commonReactions: [String(localized: "Fever, more often than after other baby vaccines", comment: "Vaccine guide: a common reaction"), siteSoreness, fussy],
            watchFor: [
                String(localized: "Where babies get MenB, clinics often advise giving infant paracetamol (acetaminophen) after the shot to keep fever down. Follow your clinic's advice on when and how much.", comment: "Vaccine guide: advice after the MenB vaccine"),
            ]
        ),
        Entry(
            id: "menc",
            name: String(localized: "Meningococcal C (MenC)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Meningococcal C (MenC)",
            otherNames: ["MenC", "Men C", "Men-C", "Men-C-C", "Meningococcal C", "NeisVac-C", "Menjugate"],
            group: .someBabies,
            protectsAgainst: String(localized: "Meningococcal C bacteria, a cause of meningitis and sepsis", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Meningococcal disease is rare but can become life-threatening within hours. Some countries give MenC to every baby or toddler.", comment: "Vaccine guide: about the MenC vaccine"),
            usuallyGiven: String(localized: "Once or twice in the first years, where it's routine.", comment: "Vaccine guide: when the MenC vaccine is usually given"),
            commonReactions: [siteSoreness, fever, fussy],
            watchFor: []
        ),
        Entry(
            id: "menacwy",
            name: String(localized: "Meningococcal ACWY (MenACWY)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "Meningococcal ACWY (MenACWY)",
            otherNames: ["MenACWY", "Men ACWY", "Men-C-ACYW", "MCV4", "Menveo", "MenQuadfi", "Nimenrix", "Menactra", "Penbraya", "Penmenvy"],
            group: .someBabies,
            protectsAgainst: String(localized: "Four types of meningococcal bacteria (A, C, W and Y), a cause of meningitis and sepsis", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Usually given to preteens and teens. Younger children get it in some countries, when they're at higher risk, or before travel.", comment: "Vaccine guide: about the MenACWY vaccine"),
            usuallyGiven: String(localized: "Often in the preteen and teen years; in some countries also around the first birthday.", comment: "Vaccine guide: when the MenACWY vaccine is usually given"),
            commonReactions: [siteSoreness, String(localized: "Fever, a headache or tiredness", comment: "Vaccine guide: a common reaction")],
            watchFor: []
        ),
        Entry(
            id: "bcg",
            name: String(localized: "BCG (tuberculosis)", comment: "Vaccine name. Use the official name and abbreviation."),
            englishName: "BCG (tuberculosis)",
            otherNames: ["BCG", "tuberculosis", "TB", "tuberculose"],
            group: .someBabies,
            protectsAgainst: String(localized: "Severe forms of tuberculosis (TB) in young children", comment: "Vaccine guide: what the vaccine protects against"),
            about: String(localized: "Given to every baby in countries where TB is common, and elsewhere to babies more likely to be around it.", comment: "Vaccine guide: about the BCG vaccine"),
            usuallyGiven: String(localized: "Once, often soon after birth.", comment: "Vaccine guide: when the BCG vaccine is usually given"),
            commonReactions: [
                String(localized: "A few weeks later, a small red bump where the shot was given. It may become a blister or small sore, then heal over a few months and leave a small scar. That's normal; keep it clean and dry, and don't cover it tightly.", comment: "Vaccine guide: a common reaction to the BCG vaccine"),
            ],
            watchFor: [
                String(localized: "Call your clinic if the sore oozes a lot, the glands in the armpit swell, or it hasn't healed after a few months.", comment: "Vaccine guide: a rare reaction to watch for"),
            ]
        ),
    ]
}
