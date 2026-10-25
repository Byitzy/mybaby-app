import CoreData
import SwiftUI

/// One line of a visit summary: "Feeds per day — 8.2".
struct SummaryRow: Identifiable {
    let label: String
    let value: String
    var detail: String?
    var id: String { label }
}

/// The text both the screen and the PDF show, so they always say the same thing.
extension VisitSummary {
    func feedingRows(unit: VolumeUnit) -> [SummaryRow] {
        var rows = [SummaryRow(label: "Feeds per day", value: decimal(averages.feedings))]
        if averages.bottleML > 0 {
            rows.append(SummaryRow(label: "Bottle per day", value: unit.format(ml: averages.bottleML)))
        }
        if averages.breastMinutes > 0 {
            rows.append(SummaryRow(label: "Breastfeeding per day", value: "\(Int(averages.breastMinutes.rounded())) min"))
        }
        return rows
    }

    var diaperRows: [SummaryRow] {
        [
            SummaryRow(label: "Wet diapers per day", value: decimal(averages.wet)),
            SummaryRow(label: "Dirty diapers per day", value: decimal(averages.dirty)),
        ]
    }

    var sleepRows: [SummaryRow] {
        var rows = [SummaryRow(label: "Sleep per day", value: Format.hours(averages.sleepHours * 3600))]
        if let longestSleep {
            rows.append(SummaryRow(label: "Longest sleep", value: Format.duration(longestSleep)))
        }
        return rows
    }

    func growthRows(_ units: GrowthUnits) -> [SummaryRow] {
        var rows: [SummaryRow] = []
        if let weight {
            rows.append(growthRow("Weight", weight, value: units.formatWeight(kg:), change: units.formatWeightChange(kg:)))
        }
        if let length {
            rows.append(growthRow("Length", length, value: units.formatLength(cm:), change: units.formatLengthChange(cm:)))
        }
        return rows
    }

    private func growthRow(
        _ label: String,
        _ growth: GrowthChange,
        value: (Double) -> String,
        change: (Double) -> String
    ) -> SummaryRow {
        var text = value(growth.value)
        if let percentile = growth.percentile { text += " · \(percentile.text)" }
        var detail = "Measured \(growth.date.formatted(.dateTime.month(.abbreviated).day()))"
        if let difference = growth.change, let previousDate = growth.previousDate {
            detail += ", \(change(difference)) since \(previousDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return SummaryRow(label: label, value: text, detail: detail)
    }

    /// "Oct 3, 2:10 AM — 38.1 °C", in whatever detail the temperature entries carry.
    func temperatureLine(_ entry: Activity, unit: VolumeUnit) -> String {
        let detail = entry.detail(unit: unit)
        let reading = detail.isEmpty ? entry.notes : detail
        let when = entry.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return reading.isEmpty ? when : "\(when) — \(reading)"
    }

    /// "Acetaminophen — 3 doses, last Oct 20 (2.5 ml)".
    func medicineLine(_ medicine: MedicineGiven) -> String {
        var line = "\(medicine.name) — \(Format.plural(medicine.doses, "dose")), last \(medicine.lastGiven.formatted(.dateTime.month(.abbreviated).day()))"
        if !medicine.lastDose.isEmpty { line += " (\(medicine.lastDose))" }
        return line
    }

    func vaccineLine(_ vaccine: Vaccine) -> String {
        var line = "\(vaccine.date.formatted(date: .abbreviated, time: .omitted)) — \(vaccine.name)"
        if !vaccine.doseLabel.isEmpty { line += " (\(vaccine.doseLabel))" }
        return line
    }

    func flaggedLine(_ diaper: FlaggedDiaper) -> String {
        "\(diaper.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())) — \(diaper.color.title) poop"
    }

    /// "Based on 12 fully tracked days (2 partly tracked days not counted)." and, when some days
    /// weren't fully tracked, a caution that low numbers on them may not be real.
    var averagesNote: String {
        guard averages.basedOnDays > 0 else { return "No full days logged in this period yet." }
        let notFull = summaries.filter { $0.coverage == .partial || $0.coverage == .none }.count
        guard notFull > 0 else { return averages.basisNote }
        let untracked = notFull == 1 ? "1 day wasn't fully tracked." : "\(notFull) days weren't fully tracked."
        return "\(averages.basisNote) \(untracked) \(ReportAverages.undercountNote)"
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// What's happened since the last checkup, on screen and as a PDF to share with the pediatrician.
struct VisitSummaryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var growthUnits: GrowthUnits = .localeDefault

    @ObservedObject var appointment: Appointment
    /// The questions as they are in the editor, which may not be saved yet.
    let questions: [VisitQuestion]?
    /// When shown in a sheet of its own rather than pushed.
    let showsDoneButton: Bool

    @State private var summary: VisitSummary? = nil
    @State private var share: SharePayload? = nil

    init(appointment: Appointment, questions: [VisitQuestion]? = nil, showsDoneButton: Bool = false) {
        self.appointment = appointment
        self.questions = questions
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        List {
            if let summary {
                content(summary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Visit summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sharePDF()
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .disabled(summary == nil)
            }
        }
        .onAppear {
            summary = VisitSummaryBuilder.summary(for: appointment, questions: questions, in: context)
        }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func content(_ summary: VisitSummary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(summary.appointmentTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(summary.appointmentDate.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(summary.periodTitle) · \(summary.averagesNote)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }

        Section("Questions to ask") {
            if summary.questions.isEmpty {
                Text("No questions yet. Add them on the appointment.")
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.questions) { question in
                Label {
                    Text(question.text)
                        .strikethrough(question.isAsked)
                } icon: {
                    Image(systemName: question.isAsked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityValue(question.isAsked ? "Asked" : "Not asked yet")
            }
        }

        if !summary.lastVisitNotes.isEmpty {
            Section("From the last visit") {
                Text(summary.lastVisitNotes)
            }
        }

        rows("🍼", "Feeding", summary.feedingRows(unit: unit))
        Section {
            ForEach(summary.diaperRows) { row($0) }
            ForEach(summary.flaggedDiapers) { diaper in
                NoticeLabel(summary.flaggedLine(diaper), systemImage: "exclamationmark.triangle", tint: Palette.warning)
                    .font(.subheadline)
            }
        } header: {
            EmojiTitle("🧷", "Diapers")
        }
        rows("😴", "Sleep", summary.sleepRows)

        let growth = summary.growthRows(growthUnits)
        if !growth.isEmpty {
            Section {
                ForEach(growth) { row($0) }
            } header: {
                EmojiTitle("📏", "Growth")
            } footer: {
                if summary.weight?.percentile != nil || summary.length?.percentile != nil {
                    Text(GrowthList.whoFooter)
                }
            }
        }

        if !summary.temperatures.isEmpty {
            Section {
                ForEach(summary.temperatures) { entry in
                    Text(summary.temperatureLine(entry, unit: unit))
                }
            } header: {
                EmojiTitle("🌡️", "Temperatures")
            }
        }

        Section {
            if summary.medicines.isEmpty {
                Text("None logged.").foregroundStyle(.secondary)
            }
            ForEach(summary.medicines) { medicine in
                Text(summary.medicineLine(medicine))
            }
        } header: {
            EmojiTitle("💊", "Medicine given")
        }

        if !summary.allergies.isEmpty || !summary.reactions.isEmpty {
            Section {
                ForEach(summary.allergies) { allergy in
                    Text(allergy.reportLine)
                }
                ForEach(summary.reactions) { reaction in
                    Text("Reaction: \(reaction.reportLine)")
                }
            } header: {
                EmojiTitle("⚠️", "Allergies and reactions")
            }
        }

        Section {
            if summary.vaccinesGiven.isEmpty {
                Text("None given in this period.").foregroundStyle(.secondary)
            }
            ForEach(summary.vaccinesGiven) { vaccine in
                Text(summary.vaccineLine(vaccine))
            }
            ForEach(summary.vaccinesDue) { vaccine in
                Text("Due: \(summary.vaccineLine(vaccine))")
                    .foregroundStyle(.secondary)
            }
        } header: {
            EmojiTitle("💉", "Vaccines")
        }

        Section {
            Text("Logged by parents; not a medical record. Your pediatrician can tell you what these numbers mean for your baby.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func rows(_ emoji: String, _ title: String, _ rows: [SummaryRow]) -> some View {
        Section {
            ForEach(rows) { row($0) }
        } header: {
            EmojiTitle(emoji, title)
        }
    }

    private func row(_ row: SummaryRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            LabeledContent(row.label, value: row.value)
            if let detail = row.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func sharePDF() {
        guard let summary else { return }
        let document = VisitSummaryDocument(summary: summary, unit: unit, growthUnits: growthUnits)
        let day = Self.fileDateFormatter.string(from: summary.appointmentDate)
        let fileName = "\(appointment.baby?.fileSafeName ?? "Baby")-visit-report-\(day).pdf"
        if let url = Exporter.pdf(document, named: fileName) {
            share = SharePayload(items: [url])
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
