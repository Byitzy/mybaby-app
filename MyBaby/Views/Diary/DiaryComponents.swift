import CoreData
import SwiftUI

/// One diary entry in a list: its kind, title, date and age, who wrote it, the start of the text and a
/// strip of photos. A letter for later that's still sealed shows as an envelope instead, without its words.
struct DiaryEntryRow: View {
    @ObservedObject var entry: DiaryEntry
    @ObservedObject var baby: Baby

    @State private var photoIDs: [NSManagedObjectID] = []

    /// How many thumbnails fit in the strip before "+3".
    private static let shownPhotos = 4

    var body: some View {
        // An entry deleted here or by the partner can redraw once more before the list drops it.
        if entry.isDeleted || entry.managedObjectContext == nil {
            EmptyView()
        } else if entry.isSealed(birthDate: baby.birthDate) {
            SealedLetterCard(entry: entry, baby: baby)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            EmojiBadge(emoji: entry.kind.emoji, tint: Palette.diary, size: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.displayTitle)
                    .font(.body.weight(.semibold))
                Text(DiaryText.byline(entry, baby: baby))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !entry.text.isEmpty, entry.text != entry.displayTitle {
                    Text(entry.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if !photoIDs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(photoIDs.prefix(Self.shownPhotos)), id: \.self) { id in
                            MilestoneThumbnail(photoID: id, side: 56, cornerRadius: Radius.photo)
                        }
                        if photoIDs.count > Self.shownPhotos {
                            Text("+\(photoIDs.count - Self.shownPhotos)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.kind.title): \(entry.displayTitle)")
        .accessibilityValue(spokenValue)
        .task(id: entry.photoIDSet) {
            photoIDs = entry.photoIDs()
        }
    }

    private var spokenValue: String {
        var parts = [DiaryText.byline(entry, baby: baby).replacingOccurrences(of: " · ", with: ", ")]
        if !entry.text.isEmpty, entry.text != entry.displayTitle { parts.append(String(entry.text.prefix(200))) }
        if !photoIDs.isEmpty { parts.append(String(localized: "\(photoIDs.count) photos")) }
        return parts.joined(separator: ". ")
    }
}

/// A letter for later, drawn as a sealed envelope: "For Mavie, to open at 18", with who wrote it.
/// The words aren't shown; the letter's own screen has Read anyway.
struct SealedLetterCard: View {
    @ObservedObject var entry: DiaryEntry
    @ObservedObject var baby: Baby

    @ScaledMetric(relativeTo: .title) private var envelopeSize: CGFloat = 34

    var body: some View {
        HStack(spacing: Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.badge)
                    .fill(Palette.diary.opacity(0.18))
                Image(systemName: isSealed ? "envelope.fill" : "envelope.open.fill")
                    .font(.system(size: min(envelopeSize, 56) * 0.6))
                    .foregroundStyle(Palette.diary)
            }
            .frame(width: min(envelopeSize, 56) * 1.5, height: min(envelopeSize, 56) * 1.2)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.envelopeLine(babyName: baby.displayName))
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSealed ? "Sealed letter. \(entry.envelopeLine(babyName: baby.displayName))" : "Letter, ready to open. \(entry.envelopeLine(babyName: baby.displayName))")
        .accessibilityValue(subtitle)
    }

    private var isSealed: Bool { entry.isSealed(birthDate: baby.birthDate) }

    /// "From Mom · written Oct 12, 2026", or "Ready to open 💌" once its day has come.
    private var subtitle: String {
        var parts: [String] = []
        if !isSealed { parts.append(String(localized: "Ready to open", comment: "A letter for later whose day has come")) }
        if let author = entry.author { parts.append(String(localized: "From \(author)", comment: "Who wrote a letter")) }
        parts.append(String(localized: "written \(entry.date.formatted(date: .abbreviated, time: .omitted))", comment: "When a letter was written, after “From Sam ·”"))
        return parts.joined(separator: " · ")
    }
}

/// A small grid of photos that open full screen, for a summary or an entry.
struct DiaryPhotoGrid: View {
    let photoIDs: [NSManagedObjectID]
    let title: String

    @State private var viewing: PhotoViewerStart?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                Button {
                    viewing = PhotoViewerStart(index: index)
                } label: {
                    MilestoneThumbnail(photoID: id, side: nil, cornerRadius: Radius.photo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(index + 1) of \(photoIDs.count)")
                .accessibilityHint("Opens the photo full screen")
            }
        }
        .fullScreenCover(item: $viewing) { start in
            PhotoViewer(photoIDs: photoIDs, startIndex: start.index, title: title)
        }
    }
}

/// Wording shared by the diary's screens.
enum DiaryText {
    /// "Oct 12, 2026 · 6 weeks old · by Mom", plus "about Month 3" for a note about a period.
    static func byline(_ entry: DiaryEntry, baby: Baby) -> String {
        var parts = [entry.dateAndAge(birthDate: baby.birthDate)]
        if let author = entry.author { parts.append(String(localized: "by \(author)", comment: "Who wrote a diary entry, after its date")) }
        if let id = entry.periodID {
            parts.append(id.kind == .week
                ? String(localized: "about Week \(id.index)", comment: "A note about one week of the baby's life")
                : String(localized: "about Month \(id.index)", comment: "A note about one month of the baby's life"))
        }
        return parts.joined(separator: " · ")
    }

    /// "Mavie's diary", or "Diary" before a name is set.
    static func title(for baby: Baby) -> String {
        baby.name.isEmpty ? String(localized: "Diary") : String(localized: "\(baby.name)'s diary")
    }

    /// The sentence that fits the baby: `female` or `male` when the sex is set, or `unknown`, which uses
    /// the name so nothing is assumed. Whole sentences, since a pronoun changes more than one word in
    /// other languages.
    static func bySex(
        _ baby: Baby,
        female: @autoclosure () -> String,
        male: @autoclosure () -> String,
        unknown: @autoclosure () -> String
    ) -> String {
        switch baby.sex {
        case .female: return female()
        case .male: return male()
        case nil: return unknown()
        }
    }

    /// "What did she learn?", a prompt for a note about a week or month.
    static func whatDidTheyLearn(_ baby: Baby) -> String {
        let name = baby.displayName
        return bySex(
            baby,
            female: String(localized: "What did she learn?"),
            male: String(localized: "What did he learn?"),
            unknown: String(localized: "What did \(name) learn?")
        )
    }

    /// The age the baby reaches when `period` ends, as a number and a unit, like `DiaryPeriod.ageReached`
    /// ("6 weeks", "3 months", "1 year"). For whole sentences that say it, each with its own plurals,
    /// rather than gluing the English words into a sentence.
    static func ageReached(_ period: DiaryPeriod) -> (unit: AgeUnit, count: Int) {
        switch period.kind {
        case .week: return (.weeks, period.index)
        case .month: return period.index % 12 == 0 ? (.years, period.index / 12) : (.months, period.index)
        }
    }

    enum AgeUnit {
        case weeks, months, years
    }

    /// "3 months old", for the keepsake's "2 months old → 3 months old".
    static func ageOld(_ period: DiaryPeriod) -> String {
        let age = ageReached(period)
        switch age.unit {
        case .weeks: return String(localized: "\(age.count) weeks old", comment: "The baby's age")
        case .months: return String(localized: "\(age.count) months old", comment: "The baby's age")
        case .years: return String(localized: "\(age.count) years old", comment: "The baby's age")
        }
    }

    /// "18th", written the way the person's language writes it.
    static func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
