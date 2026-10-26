import CoreData
import SwiftUI

/// What goes on the allergy card for caregivers (daycare, grandparents, a babysitter): the baby's
/// name and age, confirmed and suspected allergies with severity and reactions, the epinephrine
/// auto-injector and where it's kept, recent reactions, and what to do in an emergency with the
/// regional emergency number.
///
/// A snapshot of plain values, so the PDF and the text say the same thing.
struct AllergyCardContent {
    struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let statusAndSeverity: String
        let reactionsSeen: String
        let diagnosed: String
        let notes: String
    }

    let babyName: String
    /// "Born Apr 2, 2026 · 6 months old", when there's a birthday.
    let ageLine: String?
    let allergies: [Entry]
    /// Where the epinephrine auto-injectors are kept, one line each ("Diaper bag"), or "Ask a
    /// parent where it's kept" when that wasn't written down.
    let autoInjectors: [String]
    let recentReactions: [String]
    /// "911", or nil when the region isn't listed.
    let emergencyNumbers: String?
    /// The parents' own note for caregivers, like who to call.
    let note: String

    /// How far back "Recent reactions" goes.
    static let recentDays = 90

    init(baby: Baby, emergencyNumbers: String?, note: String, now: Date = .now) {
        babyName = baby.displayName
        ageLine = baby.birthDate.map {
            String(localized: "Born \($0.formatted(date: .abbreviated, time: .omitted)) · \(Format.age(birthDate: $0, now: now))")
        }
        let active = baby.allergyList().filter(\.isActive)
        allergies = active.map { allergy -> Entry in
            let doctor = allergy.diagnosedBy.trimmingCharacters(in: .whitespacesAndNewlines)
            let diagnosedOn = allergy.diagnosedDate?.formatted(date: .abbreviated, time: .omitted)
            let diagnosed: String
            switch (doctor.isEmpty, diagnosedOn) {
            case (false, let date?): diagnosed = String(localized: "Diagnosed by \(doctor) on \(date)")
            case (false, nil): diagnosed = String(localized: "Diagnosed by \(doctor)")
            case (true, let date?): diagnosed = String(localized: "Diagnosed on \(date)")
            case (true, nil): diagnosed = ""
            }
            return Entry(
                name: allergy.displayName,
                statusAndSeverity: "\(allergy.status.title), \(allergy.severity.title.lowercased())",
                reactionsSeen: allergy.reactionsSeen.trimmingCharacters(in: .whitespacesAndNewlines),
                diagnosed: diagnosed,
                notes: allergy.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        var places: [String] = []
        for allergy in active where allergy.hasAutoInjector {
            let place = allergy.autoInjectorLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = place.isEmpty ? String(localized: "Ask a parent where it's kept") : place
            if !places.contains(line) { places.append(line) }
        }
        autoInjectors = places
        let since = Calendar.current.date(byAdding: .day, value: -Self.recentDays, to: now) ?? now
        recentReactions = baby.allergyReactionList(since: since).prefix(5).map(\.reportLine)
        self.emergencyNumbers = emergencyNumbers
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Call 911 right away if Mavie has trouble breathing, or swelling of the face, lips or tongue."
    var emergencyLine: String {
        if let emergencyNumbers {
            return String(localized: "Call \(emergencyNumbers) right away if \(babyName) has trouble breathing, or swelling of the face, lips or tongue.")
        }
        return String(localized: "Call your local emergency number right away if \(babyName) has trouble breathing, or swelling of the face, lips or tongue.")
    }

    /// The card as plain text, for Messages or Mail.
    var text: String {
        var lines = [String(localized: "\(babyName) — Allergy card")]
        if let ageLine { lines.append(ageLine) }
        lines.append("")
        lines.append(String(localized: "IN AN EMERGENCY"))
        lines.append(emergencyLine)
        for place in autoInjectors {
            lines.append(String(localized: "Epinephrine auto-injector: \(place)"))
        }
        lines.append("")
        lines.append(String(localized: "ALLERGIES", comment: "Heading in the allergy card's text"))
        if allergies.isEmpty {
            lines.append(String(localized: "None listed."))
        }
        for entry in allergies {
            lines.append("• \(entry.name) (\(entry.statusAndSeverity))")
            if !entry.reactionsSeen.isEmpty { lines.append("  " + String(localized: "Reactions: \(entry.reactionsSeen)")) }
            if !entry.diagnosed.isEmpty { lines.append("  \(entry.diagnosed)") }
            if !entry.notes.isEmpty { lines.append("  \(entry.notes)") }
        }
        if !recentReactions.isEmpty {
            lines.append("")
            lines.append(String(localized: "RECENT REACTIONS"))
            lines += recentReactions.map { "• \($0)" }
        }
        if !note.isEmpty {
            lines.append("")
            lines.append(String(localized: "FROM THE PARENTS"))
            lines.append(note)
        }
        lines.append("")
        lines.append(String(localized: "Written by \(babyName)'s parents with MyBaby on \(Date.now.formatted(date: .long, time: .omitted)). Not a medical record."))
        return lines.joined(separator: "\n")
    }
}

/// The allergy card as a printable page, shared as a PDF (see `Exporter.pdf`). Laid out like
/// `ReportDocument`, with the emergency box first so it's the first thing a caregiver reads.
struct AllergyCardDocument: View {
    let content: AllergyCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(content.babyName) — Allergy card")
                    .font(.system(size: 26, weight: .bold))
                if let ageLine = content.ageLine {
                    Text(ageLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("IN AN EMERGENCY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.75, green: 0.1, blue: 0.1))
                Text(content.emergencyLine)
                    .font(.system(size: 14, weight: .semibold))
                ForEach(content.autoInjectors, id: \.self) { place in
                    Text("Epinephrine auto-injector: \(place)")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(red: 1, green: 0.93, blue: 0.92), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(String(localized: "Allergies"))
                if content.allergies.isEmpty {
                    Text("None listed.").font(.system(size: 11)).foregroundStyle(.gray)
                }
                ForEach(content.allergies) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.name)  ·  \(entry.statusAndSeverity)")
                            .font(.system(size: 14, weight: .semibold))
                        if !entry.reactionsSeen.isEmpty {
                            Text("Reactions: \(entry.reactionsSeen)").font(.system(size: 11))
                        }
                        if !entry.diagnosed.isEmpty {
                            Text(entry.diagnosed).font(.system(size: 10)).foregroundStyle(.gray)
                        }
                        if !entry.notes.isEmpty {
                            Text(entry.notes).font(.system(size: 10)).foregroundStyle(.gray)
                        }
                    }
                }
            }

            if !content.recentReactions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle(String(localized: "Recent reactions"))
                    ForEach(Array(content.recentReactions.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.system(size: 10))
                    }
                }
            }

            if !content.note.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle(String(localized: "From the parents"))
                    Text(content.note).font(.system(size: 11))
                }
            }

            Text("Written by \(content.babyName)'s parents with MyBaby on \(Date.now.formatted(date: .long, time: .shortened)). Not a medical record.")
                .font(.system(size: 9))
                .foregroundStyle(.gray)
        }
        .padding(40)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 0.75, green: 0.3, blue: 0.45))
    }
}

/// Health › Allergies › Allergy card: what the card says, an optional note from the parents, and
/// sharing it as a PDF or as text. Nothing is sent anywhere except where the parent shares it.
struct AllergyCardView: View {
    @AppStorage(SupportDirectory.regionKey) private var regionOverride = ""
    @AppStorage private var note: String
    @ObservedObject var baby: Baby
    @FetchRequest private var allergies: FetchedResults<Allergy>
    @FetchRequest private var reactions: FetchedResults<AllergyReaction>

    @State private var share: SharePayload?
    @FocusState private var noteFocused: Bool

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        // Kept on this iPhone only, per baby.
        _note = AppStorage(wrappedValue: "", "allergyCardNote.\(baby.uuid?.uuidString ?? "baby")")
        // Watched so the card redraws when the list changes.
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
        _reactions = FetchRequest(fetchRequest: baby.entries(AllergyReaction.fetchAll()))
    }

    var body: some View {
        // Read so the card is redrawn when an allergy or reaction changes, here or on the partner's phone.
        let _ = (allergies.count, reactions.count)
        let content = makeContent()
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(content.babyName) — Allergy card")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let ageLine = content.ageLine {
                        Text(ageLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }

            Section {
                Label {
                    Text(content.emergencyLine)
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                }
                ForEach(content.autoInjectors, id: \.self) { place in
                    Label("Epinephrine auto-injector: \(place)", systemImage: "cross.vial")
                        .font(.subheadline)
                }
            } header: {
                Text("In an emergency")
            } footer: {
                Text("The emergency number follows your region, as in your support lines.")
            }

            Section("Allergies") {
                if content.allergies.isEmpty {
                    Text("None listed. Confirmed and suspected allergies go on the card.")
                        .foregroundStyle(.secondary)
                }
                ForEach(content.allergies) { entry in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(entry.name)
                            .font(.body.weight(.medium))
                        Text(entry.statusAndSeverity)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !entry.reactionsSeen.isEmpty {
                            Text("Reactions: \(entry.reactionsSeen)")
                                .font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !content.recentReactions.isEmpty {
                Section("Recent reactions") {
                    ForEach(Array(content.recentReactions.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.subheadline)
                    }
                }
            }

            Section {
                TextField("e.g. Call Sam on 555-0100 first", text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($noteFocused)
            } header: {
                Text("Note for caregivers (optional)")
            } footer: {
                Text("Kept on this iPhone only, and added to the card when you share it.")
            }

            Section {
                Button {
                    noteFocused = false
                    sharePDF(content)
                } label: {
                    Label("Share as PDF", systemImage: "doc.richtext")
                }
                ShareLink(item: content.text, subject: Text("\(content.babyName)'s allergy card")) {
                    Label("Share as text", systemImage: "text.bubble")
                }
            } footer: {
                Text("The card goes only where you share it.")
            }
        }
        .navigationTitle("Allergy card")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
    }

    private func makeContent() -> AllergyCardContent {
        let region = SupportDirectory.bundled?.resolvedRegion(override: regionOverride)
        return AllergyCardContent(baby: baby, emergencyNumbers: region?.emergencyText, note: note)
    }

    @MainActor
    private func sharePDF(_ content: AllergyCardContent) {
        let fileName = "\(baby.fileSafeName)-allergy-card.pdf"
        if let url = Exporter.pdf(AllergyCardDocument(content: content), named: fileName) {
            share = SharePayload(items: [url])
        }
    }
}
