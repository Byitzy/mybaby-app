import SwiftUI
import UIKit

/// Writes shareable files (CSV and PDF) to the temporary directory.
enum Exporter {
    static func activitiesCSV(_ activities: [Activity], plan: NightPlan = .load()) -> String {
        var rows = [[
            "Category", "Start", "End", "Type", "Amount (ml)", "Left breast (min)", "Right breast (min)",
            "Food", "Poop color", "Poop consistency", "Medicine", "Dose", "Handled by", "Notes",
            "Pumped left (ml)", "Pumped right (ml)", "Duration (min)",
            "Temperature (°C)", "Temperature method", "Symptoms",
            "Approximate", "Allergens",
        ]]
        for a in activities.sorted(by: { $0.startDate < $1.startDate }) {
            rows.append([
                a.kind.title,
                timestamp(a.startDate),
                a.endDate.map { timestamp($0) } ?? "",
                a.feedingType?.title ?? a.diaperType?.title ?? "",
                a.amountML.map { String(Int($0.rounded())) } ?? "",
                a.leftMinutes.map { String($0) } ?? "",
                a.rightMinutes.map { String($0) } ?? "",
                a.foodDescription ?? "",
                a.poopColor?.title ?? "",
                a.poopConsistency?.title ?? "",
                a.medicationName ?? "",
                a.dosage ?? "",
                a.caregiver.map { plan.name(of: $0) } ?? "",
                a.notes,
            ])
            rows[rows.count - 1] += pumpingAndTemperatureColumns(a)
            // Added later with Catch up, rather than logged at the time.
            rows[rows.count - 1].append(a.isApproximate ? "Yes" : "")
            // Common allergens tagged on a solids log.
            rows[rows.count - 1].append(a.allergens.map(\.name).joined(separator: "; "))
        }
        return csv(rows)
    }

    /// Times marked as not tracked, nothing happened or caught up (`TrackingPeriod`).
    static func trackingCSV(_ periods: [TrackingPeriod]) -> String {
        var rows = [["Start", "End", "Kind", "Reason", "Notes"]]
        for p in periods.sorted(by: { $0.start < $1.start }) {
            rows.append([timestamp(p.start), timestamp(p.end), p.kind.title, p.reason?.title ?? "", p.notes])
        }
        return csv(rows)
    }

    /// The columns added for pumping and temperatures, at the end so older spreadsheets still line up.
    private static func pumpingAndTemperatureColumns(_ a: Activity) -> [String] {
        var columns: [String] = []
        columns.append(a.pumpLeftML.map { String(Int($0.rounded())) } ?? "")
        columns.append(a.pumpRightML.map { String(Int($0.rounded())) } ?? "")
        columns.append(a.durationMinutes.map { String($0) } ?? "")
        columns.append(a.temperatureC.map { decimal($0, digits: 2) } ?? "")
        columns.append(a.temperatureMethod?.title ?? "")
        columns.append(a.symptoms.map(\.title).joined(separator: "; "))
        return columns
    }

    /// Diary entries, oldest first, letters for later included (an export is the parents' own copy).
    static func diaryCSV(_ entries: [DiaryEntry]) -> String {
        var rows = [["Date", "Kind", "Title", "Text", "Written by", "About", "Open on", "Open at age", "Photos"]]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            let about = e.periodID.map { "\($0.kind == .week ? "Week" : "Month") \($0.index)" } ?? ""
            rows.append([
                timestamp(e.date), e.kind.title, e.title, e.text, e.authorName, about,
                e.openOnDate.map { timestamp($0) } ?? "", e.openAtAge.map { String($0) } ?? "",
                String(e.photoIDSet.count),
            ])
        }
        return csv(rows)
    }

    /// The allergy list (Health › Allergies), oldest first.
    static func allergiesCSV(_ allergies: [Allergy]) -> String {
        var rows = [[
            "Allergen", "Type", "Status", "Severity", "Reactions seen", "Diagnosed by", "Diagnosed on",
            "Auto-injector", "Auto-injector kept", "Notes",
        ]]
        for a in allergies.sorted(by: { $0.createdAt < $1.createdAt }) {
            rows.append([
                a.displayName, a.category.title, a.status.title, a.severity.title, a.reactionsSeen, a.diagnosedBy,
                a.diagnosedDate.map { timestamp($0) } ?? "", a.hasAutoInjector ? "Yes" : "", a.autoInjectorLocation, a.notes,
            ])
        }
        return csv(rows)
    }

    /// The reactions log, oldest first.
    static func reactionsCSV(_ reactions: [AllergyReaction]) -> String {
        var rows = [["Date", "What they had", "Symptoms", "Severity", "What you did", "Allergy", "Photo", "Notes"]]
        for r in reactions.sorted(by: { $0.date < $1.date }) {
            rows.append([
                timestamp(r.date), r.food, r.symptoms.map(\.title).joined(separator: "; "), r.severity.title,
                r.actions.map(\.title).joined(separator: "; "), r.allergy?.displayName ?? "",
                r.photoIDSet.isEmpty ? "" : "Yes", r.notes,
            ])
        }
        return csv(rows)
    }

    static func vaccinesCSV(_ vaccines: [Vaccine]) -> String {
        var rows = [["Vaccine", "Date", "Status", "Dose", "Provider", "Lot number", "Notes"]]
        for v in vaccines.sorted(by: { $0.date < $1.date }) {
            rows.append([v.name, timestamp(v.date), v.isGiven ? "Given" : "Due", v.doseLabel, v.provider, v.lotNumber, v.notes])
        }
        return csv(rows)
    }

    static func appointmentsCSV(_ appointments: [Appointment]) -> String {
        var rows = [["Appointment", "Date", "Provider", "Location", "Notes", "Questions", "Visit notes"]]
        for a in appointments.sorted(by: { $0.date < $1.date }) {
            rows.append([a.title, timestamp(a.date), a.provider, a.location, a.notes, a.questions, a.visitNotes ?? ""])
        }
        return csv(rows)
    }

    /// Weight and length in kilograms and centimeters, whatever units the app shows.
    static func growthCSV(_ entries: [GrowthEntry]) -> String {
        var rows = [["Date", "Weight (kg)", "Length (cm)", "Notes"]]
        for g in entries.sorted(by: { $0.date < $1.date }) {
            rows.append([
                timestamp(g.date),
                g.weightKg.map { decimal($0, digits: 3) } ?? "",
                g.lengthCm.map { decimal($0, digits: 2) } ?? "",
                g.notes,
            ])
        }
        return csv(rows)
    }

    static func write(_ text: String, named fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Renders a SwiftUI view into a single-page PDF sized to fit its content.
    @MainActor
    static func pdf<Content: View>(_ content: Content, named fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
        var didRender = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            didRender = true
        }
        return didRender ? url : nil
    }

    /// Deletes an exported file once it has been shared. Only files directly inside the temporary
    /// directory are removed, so nothing else the share sheet was given is touched.
    static func removeTemporaryFile(_ url: URL) {
        guard url.isFileURL else { return }
        let temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let folder = url.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
        guard folder.path == temporaryDirectory.path else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes CSV and PDF exports left in the temporary directory, for example if the app was
    /// closed while the share sheet was open.
    static func removeOldExports() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for url in urls {
            let name = url.lastPathComponent
            let isCSV = name.hasPrefix("MyBaby-") && url.pathExtension.lowercased() == "csv"
            let isPDF = (name.contains("-report-") || name.hasSuffix("-keepsake.pdf") || name.hasSuffix("-allergy-card.pdf"))
                && url.pathExtension.lowercased() == "pdf"
            if isCSV || isPDF {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: Helpers

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    /// "4.25", always with a period so spreadsheets in any region read it the same way.
    private static func decimal(_ value: Double, digits: Int) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...digits)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    private static func csv(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// A file (or files) ready to hand to the share sheet.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let sharedItems = items
        // Shared exports are copies of the baby's data, so don't leave them in the temporary
        // directory once sharing finishes, whether it completed or was cancelled.
        controller.completionWithItemsHandler = { _, _, _, _ in
            ShareSheet.removeFiles(in: sharedItems)
        }
        context.coordinator.items = sharedItems
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Also cleans up if the sheet is swiped away without the share sheet reporting back.
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) {
        removeFiles(in: coordinator.items)
    }

    final class Coordinator {
        var items: [Any] = []
    }

    private static func removeFiles(in items: [Any]) {
        for case let url as URL in items {
            Exporter.removeTemporaryFile(url)
        }
    }
}
