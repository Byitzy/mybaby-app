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
        if !photoIDs.isEmpty { parts.append(Format.plural(photoIDs.count, "photo")) }
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
        if !isSealed { parts.append("Ready to open") }
        if let author = entry.author { parts.append("From \(author)") }
        parts.append("written \(entry.date.formatted(date: .abbreviated, time: .omitted))")
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
        if let author = entry.author { parts.append("by \(author)") }
        if let id = entry.periodID {
            parts.append("about \(id.kind == .week ? "Week" : "Month") \(id.index)")
        }
        return parts.joined(separator: " · ")
    }

    /// "Mavie's diary", or "Diary" before a name is set.
    static func title(for baby: Baby) -> String {
        baby.name.isEmpty ? "Diary" : "\(baby.name)'s diary"
    }
}
