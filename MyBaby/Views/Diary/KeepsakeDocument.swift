import CoreData
import SwiftUI
import UIKit

/// One chapter of the keepsake: a month of the baby's life (or a calendar month before a birthday is set,
/// or the time before the birth), with its summary, the parents' notes and the diary entries.
struct KeepsakeChapter {
    let title: String
    /// "2 months old → 3 months old", or empty.
    let subtitle: String
    /// `nil` for chapters that aren't a month of the baby's life.
    let summary: DiarySummary?
    let notes: [DiaryEntry]
    /// Oldest first.
    let entries: [DiaryEntry]
}

/// Builds the keepsake PDF: a cover, then for each month a page with its summary and the parents'
/// notes, and pages of diary entries with their photos. Rendered like the care report
/// (`ReportDocument`, `Exporter.pdf`), but one page at a time, so a whole year of photos never has to
/// be in memory at once.
@MainActor
enum KeepsakeExporter {
    /// What goes in.
    enum Scope: Hashable {
        /// One month of the baby's life, by its index (3 for Month 3).
        case month(Int)
        case firstYear
        case everything
    }

    /// Entries per page, so pages stay a printable length.
    private static let entriesPerPage = 3
    /// Photos printed per entry; the rest stay in the app.
    private static let photosPerEntry = 6
    /// Printed photos are decoded at this size, sharp enough for paper without making the file huge.
    private static let photoPixels: CGFloat = 700

    /// Writes the PDF to the temporary folder, or returns nil if it couldn't be written.
    static func make(
        baby: Baby,
        range: Scope,
        includesLetters: Bool,
        growthUnits: GrowthUnits,
        context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) async -> URL? {
        let contents = chapters(baby: baby, range: range, includesLetters: includesLetters, context: context, calendar: calendar)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baby.fileSafeName)-keepsake.pdf")
        try? FileManager.default.removeItem(at: url)
        guard let pdf = CGContext(url as CFURL, mediaBox: nil, nil) else { return nil }

        let authors = authorNames(in: contents)
        draw(KeepsakeCover(baby: baby, rangeTitle: rangeTitle(range, baby: baby), authors: authors, isEmpty: contents.isEmpty), into: pdf)

        for chapter in contents {
            let noteImages = await images(for: chapter.notes)
            draw(KeepsakeChapterPage(chapter: chapter, baby: baby, growthUnits: growthUnits, images: noteImages), into: pdf)
            for start in stride(from: 0, to: chapter.entries.count, by: entriesPerPage) {
                let page = Array(chapter.entries[start..<min(start + entriesPerPage, chapter.entries.count)])
                let pageImages = await images(for: page)
                draw(KeepsakeEntriesPage(chapterTitle: chapter.title, entries: page, baby: baby, images: pageImages), into: pdf)
            }
        }
        pdf.closePDF()
        return url
    }

    // MARK: Contents

    private static func chapters(
        baby: Baby,
        range: Scope,
        includesLetters: Bool,
        context: NSManagedObjectContext,
        calendar: Calendar
    ) -> [KeepsakeChapter] {
        let all: [DiaryEntry] = ((try? context.fetch(baby.entries(DiaryEntry.fetchAll()))) ?? [])
            .filter { !$0.isDeleted && (includesLetters || $0.kind != .letter) }
            .reversed()

        guard let birthDate = baby.birthDate else {
            // Without a birthday there are no months of life: calendar months instead, entries only.
            var chapters: [KeepsakeChapter] = []
            var current: (key: DateComponents, entries: [DiaryEntry])?
            for entry in all {
                let key = calendar.dateComponents([.year, .month], from: entry.date)
                if current?.key == key {
                    current?.entries.append(entry)
                } else {
                    if let finished = current { chapters.append(calendarChapter(finished.entries)) }
                    current = (key, [entry])
                }
            }
            if let finished = current { chapters.append(calendarChapter(finished.entries)) }
            return chapters
        }

        var chapters: [KeepsakeChapter] = []
        let birth = calendar.startOfDay(for: birthDate)
        if range == .everything {
            let before = all.filter { $0.date < birth }
            if !before.isEmpty {
                chapters.append(KeepsakeChapter(
                    title: String(localized: "Before \(baby.displayName) was born"), subtitle: "", summary: nil, notes: [], entries: before
                ))
            }
        }

        let months: [DiaryPeriod]
        switch range {
        case .month(let index):
            months = DiaryPeriod.month(index, birthDate: birthDate, calendar: calendar).map { [$0] } ?? []
        case .firstYear:
            months = DiaryPeriod.months(birthDate: birthDate, calendar: calendar).reversed().filter { $0.index <= 12 }
        case .everything:
            months = DiaryPeriod.months(birthDate: birthDate, calendar: calendar).reversed()
        }
        let plan = NightPlan.load()
        // One month asked for on its own is always printed; in longer ranges, a month with nothing at
        // all is left out rather than printing an empty page.
        let keepsEmptyMonths = months.count == 1
        for month in months {
            let summary = DiarySummaryBuilder.summary(for: month, baby: baby, context: context, plan: plan, calendar: calendar)
            let entries = all.filter { month.contains($0.date) && $0.periodID != month.id }
            if !keepsEmptyMonths, summary.hasNoLog, summary.notes.isEmpty, entries.isEmpty, summary.milestones.isEmpty {
                continue
            }
            let subtitle: String
            if month.index == 1 {
                subtitle = String(localized: "Newborn → 1 month old", comment: "The first month of the keepsake")
            } else {
                let before = DiaryPeriod.month(month.index - 1, birthDate: birthDate, calendar: calendar).map(DiaryText.ageOld) ?? ""
                subtitle = "\(before) → \(DiaryText.ageOld(month))"
            }
            chapters.append(KeepsakeChapter(
                title: month.fullTitle(calendar: calendar),
                subtitle: subtitle,
                summary: summary,
                notes: summary.notes,
                entries: entries
            ))
        }
        return chapters
    }

    private static func calendarChapter(_ entries: [DiaryEntry]) -> KeepsakeChapter {
        let title = entries.first.map { $0.date.formatted(.dateTime.month(.wide).year()) } ?? ""
        return KeepsakeChapter(title: title, subtitle: "", summary: nil, notes: [], entries: entries)
    }

    private static func rangeTitle(_ range: Scope, baby: Baby) -> String {
        switch range {
        case .month(let index):
            if let birthDate = baby.birthDate, let month = DiaryPeriod.month(index, birthDate: birthDate) {
                return month.fullTitle()
            }
            return String(localized: "Month \(index)", comment: "A month of the baby's life, e.g. “Month 3”")
        case .firstYear:
            return String(localized: "The first year", comment: "What goes in the keepsake PDF")
        case .everything:
            return String(localized: "Everything so far", comment: "On the keepsake's cover")
        }
    }

    /// "Mom and Dad", from who wrote the entries.
    private static func authorNames(in chapters: [KeepsakeChapter]) -> String {
        var names: [String] = []
        for chapter in chapters {
            for entry in chapter.notes + chapter.entries {
                guard let author = entry.author, !names.contains(author) else { continue }
                names.append(author)
            }
        }
        return names.formatted(.list(type: .and))
    }

    /// The first few photos of each entry, decoded for print.
    private static func images(for entries: [DiaryEntry]) async -> [NSManagedObjectID: UIImage] {
        var images: [NSManagedObjectID: UIImage] = [:]
        for entry in entries {
            for id in entry.photoIDs().prefix(photosPerEntry) {
                if let image = await MilestoneImages.image(for: id, maxPixelSize: photoPixels, caches: false) {
                    images[id] = image
                }
            }
        }
        return images
    }

    /// Adds `page` to the PDF as one page, sized to fit it.
    /// In its own autorelease pool, so what rendering a page leaves behind (its photos' drawing among
    /// it) is freed after each page rather than only once the whole PDF is done.
    private static func draw<Page: View>(_ page: Page, into pdf: CGContext) {
        autoreleasepool {
            let renderer = ImageRenderer(content: page.environment(\.colorScheme, .light))
            renderer.render { size, render in
                var box = CGRect(origin: .zero, size: size)
                pdf.beginPage(mediaBox: &box)
                render(pdf)
                pdf.endPage()
            }
        }
    }
}

// MARK: - Pages

/// The keepsake's look: a white page, serif type and a soft coral for headings.
private enum KeepsakeStyle {
    static let pageWidth: CGFloat = 612
    static let margin: CGFloat = 48
    static let accent = Color(red: 0.78, green: 0.36, blue: 0.27)
    static let soft = Color(white: 0.45)
    static let wash = Color(red: 0.99, green: 0.95, blue: 0.93)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

private extension View {
    /// A page of the keepsake: the page width, margins and a white background.
    func keepsakePage() -> some View {
        self
            .padding(KeepsakeStyle.margin)
            .frame(width: KeepsakeStyle.pageWidth, alignment: .leading)
            .background(Color.white)
            .foregroundStyle(.black)
    }
}

/// "Mavie's diary", the range, the birthday and who wrote it.
private struct KeepsakeCover: View {
    let baby: Baby
    let rangeTitle: String
    let authors: String
    let isEmpty: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 120)
            Text("📖")
                .font(.system(size: 54))
            Text("\(baby.displayName)'s diary")
                .font(KeepsakeStyle.serif(34, .bold))
                .multilineTextAlignment(.center)
            Text(rangeTitle)
                .font(KeepsakeStyle.serif(16))
                .foregroundStyle(KeepsakeStyle.accent)
            if let born = baby.birthText() {
                Text("Born \(born)")
                    .font(KeepsakeStyle.serif(13))
                    .foregroundStyle(KeepsakeStyle.soft)
            }
            if !authors.isEmpty {
                Text("With love, from \(authors)")
                    .font(KeepsakeStyle.serif(14).italic())
                    .padding(.top, 24)
            }
            if isEmpty {
                Text("Nothing has been written for this time yet.")
                    .font(KeepsakeStyle.serif(12))
                    .foregroundStyle(KeepsakeStyle.soft)
            }
            Spacer(minLength: 160)
            Text("Made with MyBaby on \(Date.now.formatted(date: .long, time: .omitted))")
                .font(.system(size: 9))
                .foregroundStyle(KeepsakeStyle.soft)
        }
        .frame(maxWidth: .infinity)
        .keepsakePage()
    }
}

/// A month's opening page: its title, the parents' notes and what the log says about it.
private struct KeepsakeChapterPage: View {
    let chapter: KeepsakeChapter
    let baby: Baby
    let growthUnits: GrowthUnits
    let images: [NSManagedObjectID: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(KeepsakeStyle.serif(24, .bold))
                if !chapter.subtitle.isEmpty {
                    Text(chapter.subtitle)
                        .font(KeepsakeStyle.serif(12))
                        .foregroundStyle(KeepsakeStyle.soft)
                }
            }

            if !chapter.notes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(String(localized: "From the parents"))
                    ForEach(chapter.notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            if !note.title.isEmpty {
                                Text(note.title).font(KeepsakeStyle.serif(13, .semibold))
                            }
                            if !note.text.isEmpty {
                                Text(note.text)
                                    .font(KeepsakeStyle.serif(12))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let author = note.author {
                                Text("— \(author)").font(KeepsakeStyle.serif(11).italic()).foregroundStyle(KeepsakeStyle.soft)
                            }
                            KeepsakePhotos(ids: note.photoIDs(), images: images)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KeepsakeStyle.wash, in: RoundedRectangle(cornerRadius: 10))
            }

            if let summary = chapter.summary {
                summaryBlock(summary)
            }

            if chapter.entries.isEmpty, chapter.summary != nil {
                Text("No diary entries this month.")
                    .font(KeepsakeStyle.serif(11))
                    .foregroundStyle(KeepsakeStyle.soft)
            }
        }
        .keepsakePage()
    }

    @ViewBuilder
    private func summaryBlock(_ summary: DiarySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "The month in the log"))
            Text(summary.coverageText)
                .font(.system(size: 10))
                .foregroundStyle(KeepsakeStyle.soft)
            if summary.hasNoLog {
                Text("Nothing was logged this month.")
                    .font(KeepsakeStyle.serif(11))
            } else {
                line(String(localized: "Feeds"), feedsText(summary))
                line(String(localized: "Sleep"), sleepText(summary))
                line(String(localized: "Diapers"), diapersText(summary))
                if let note = summary.coverageNote {
                    Text(note).font(.system(size: 9)).foregroundStyle(KeepsakeStyle.soft)
                }
            }
            if let weight = summary.weightLine(units: growthUnits, baby: baby) {
                line(String(localized: "Weight"), weight)
            }
            if let length = summary.lengthLine(units: growthUnits, baby: baby) {
                line(String(localized: "Length"), length)
            }
            if !summary.milestones.isEmpty {
                line(String(localized: "Milestones"), summary.milestones.map { "\($0.displayEmoji) \($0.displayTitle) (\($0.date.formatted(.dateTime.day().month(.abbreviated))))" }.joined(separator: ", "))
            }
            if !summary.vaccines.isEmpty {
                line(String(localized: "Vaccines"), summary.vaccines.map(\.name).joined(separator: ", "))
            }
            if !summary.appointments.isEmpty {
                line(String(localized: "Checkups"), summary.appointments.map {
                    "\($0.title.isEmpty ? String(localized: "Appointment") : $0.title) (\($0.date.formatted(.dateTime.day().month(.abbreviated))))"
                }.joined(separator: ", "))
            }
        }
    }

    /// "142, about 8 a day".
    private func feedsText(_ summary: DiarySummary) -> String {
        guard summary.averages.basedOnDays > 0 else { return "\(summary.feeds)" }
        return String(localized: "\(summary.feeds), about \(decimal(summary.averages.feedings)) a day", comment: "e.g. “142, about 8 a day”")
    }

    /// "310h, longest stretch 5h 40m".
    private func sleepText(_ summary: DiarySummary) -> String {
        let total = Format.hours(summary.sleepSeconds)
        guard let longest = summary.longestSleep else { return total }
        return String(localized: "\(total), longest stretch \(Format.duration(longest))", comment: "Sleep in a month, e.g. “310h, longest stretch 5h 40m”")
    }

    /// "180, about 6 a day".
    private func diapersText(_ summary: DiarySummary) -> String {
        guard let perDay = summary.diapersPerDay else { return "\(summary.diapers)" }
        return String(localized: "\(summary.diapers), about \(decimal(perDay)) a day", comment: "e.g. “180, about 6 a day”")
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KeepsakeStyle.accent)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// A page of diary entries, each with its words and photos.
private struct KeepsakeEntriesPage: View {
    let chapterTitle: String
    let entries: [DiaryEntry]
    let baby: Baby
    let images: [NSManagedObjectID: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(chapterTitle)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(KeepsakeStyle.soft)
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(entry.kind.emoji) \(entry.displayTitle)")
                        .font(KeepsakeStyle.serif(16, .semibold))
                    Text(DiaryText.byline(entry, baby: baby))
                        .font(.system(size: 9))
                        .foregroundStyle(KeepsakeStyle.soft)
                    if entry.kind == .letter {
                        Text("A letter for later · \(entry.envelopeLine(babyName: baby.displayName))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(KeepsakeStyle.accent)
                    }
                    if !entry.text.isEmpty, entry.text != entry.displayTitle {
                        Text(entry.text)
                            .font(KeepsakeStyle.serif(12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    KeepsakePhotos(ids: entry.photoIDs(), images: images)
                }
            }
        }
        .keepsakePage()
    }
}

/// Up to three photos a row, square and cropped like the thumbnails in the app.
private struct KeepsakePhotos: View {
    let ids: [NSManagedObjectID]
    let images: [NSManagedObjectID: UIImage]

    private static let side: CGFloat = 164

    var body: some View {
        let shown = ids.compactMap { images[$0] }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(stride(from: 0, to: shown.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(start..<min(start + 3, shown.count), id: \.self) { index in
                            Image(uiImage: shown[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: Self.side, height: Self.side)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}
