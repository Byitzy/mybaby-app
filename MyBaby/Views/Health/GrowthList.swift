import Charts
import CoreData
import SwiftUI

/// Weight and length over time, with the latest of each up top. With the baby's sex and birthday
/// set, each is placed on the WHO growth charts.
struct GrowthList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var units: GrowthUnits = .localeDefault
    @FetchRequest private var entries: FetchedResults<GrowthEntry>
    /// Observed so setting the sex or birthday shows the percentiles right away.
    @ObservedObject private var baby: Baby

    @State private var editing: GrowthEntry?
    @State private var addingNew = false
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: GrowthEntry?

    init(baby: Baby) {
        self.baby = baby
        _entries = FetchRequest(fetchRequest: baby.entries(GrowthEntry.fetchAll()))
    }

    var body: some View {
        let weights = entries.compactMap { entry in
            entry.weightKg.map { GrowthPoint(id: entry.objectID, date: entry.date, value: $0) }
        }
        let lengths = entries.compactMap { entry in
            entry.lengthCm.map { GrowthPoint(id: entry.objectID, date: entry.date, value: $0) }
        }
        let showsPercentiles = baby.canShowGrowthPercentiles
        // With reference curves to compare with, one measurement is already worth a chart.
        let pointsForChart = showsPercentiles ? 1 : 2

        List {
            if entries.isEmpty {
                EmptyStateView(
                    "No measurements yet",
                    systemImage: "ruler",
                    message: "Add your baby's weight and length from each checkup to see how they're growing.",
                    actionTitle: "Add measurement",
                    isDisabled: !canEditLog
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    AdaptiveStack(verticalAlignment: .top, spacing: 10) {
                        GrowthStat(
                            title: "Weight",
                            emoji: "⚖️",
                            value: weights.last.map { units.formatWeight(kg: $0.value) },
                            change: changeText(weights, format: units.formatWeightChange(kg:)),
                            percentile: weights.last.flatMap { percentile(.weight, $0) }
                        )
                        GrowthStat(
                            title: "Length",
                            emoji: "📏",
                            value: lengths.last.map { units.formatLength(cm: $0.value) },
                            change: changeText(lengths, format: units.formatLengthChange(cm:)),
                            percentile: lengths.last.flatMap { percentile(.length, $0) }
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if showsPercentiles {
                        Text(Self.whoFooter)
                    }
                }

                if !showsPercentiles && GrowthStandards.who != nil {
                    percentileHint
                }

                if weights.count >= pointsForChart {
                    Section("Weight (\(units.weightUnit))") {
                        chart(weights, measure: .weight, label: "Weight", color: Palette.weight, convert: units.fromKg, format: units.formatWeight(kg:))
                    }
                }
                if lengths.count >= pointsForChart {
                    Section("Length (\(units.lengthUnit))") {
                        chart(lengths, measure: .length, label: "Length", color: Palette.length, convert: units.fromCm, format: units.formatLength(cm:))
                    }
                }

                Section("Measurements") {
                    ForEach(Array(entries.reversed())) { row($0) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Units", selection: $units) {
                        ForEach(GrowthUnits.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label("Units", systemImage: "scalemass")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add measurement", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $addingNew) {
            GrowthEditor(entry: nil)
        }
        .sheet(item: $editing) { entry in
            GrowthEditor(entry: entry)
        }
        .confirmDelete("Delete this measurement?", item: $deleting) { entry in
            context.delete(entry)
            context.saveIfChanged()
        }
    }

    /// "+180 g since Oct 12", or when it was measured if there's nothing to compare with.
    private func changeText(_ points: [GrowthPoint], format: (Double) -> String) -> String? {
        guard let latest = points.last else { return nil }
        guard points.count >= 2 else {
            return "Measured \(latest.date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let previous = points[points.count - 2]
        return "\(format(latest.value - previous.value)) since \(previous.date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    static let whoFooter = "WHO Child Growth Standards. Your pediatrician can explain what these mean for your baby. Percentiles use age from the birthday; for a baby born early, your pediatrician may use a corrected age."

    private func percentile(_ measure: GrowthMeasure, _ point: GrowthPoint) -> GrowthPercentile? {
        baby.growthPercentile(measure, value: point.value, on: point.date)
    }

    /// Asks for what the WHO charts need: the baby's sex (right here) and birthday (in Settings).
    private var percentileHint: some View {
        Section {
            if baby.sex == nil {
                BabySexPicker(selection: baby.sexBinding(saving: context))
                    .disabled(!canEditLog)
            }
            if baby.birthDate == nil {
                Text("Add \(baby.displayName)'s birthday in More › Settings.")
            }
        } header: {
            Text("Growth percentiles")
        } footer: {
            Text("Set your baby's sex and birthday to see where each measurement falls on the WHO growth charts.")
        }
    }

    /// The WHO 3rd, 15th, 50th, 85th and 97th percentiles over the measured ages, with a margin.
    private func referenceCurves(_ points: [GrowthPoint], measure: GrowthMeasure) -> [GrowthCurve] {
        guard let sex = baby.sex, let birthDate = baby.birthDate, let standards = GrowthStandards.who,
              let first = points.first?.date, let last = points.last?.date
        else { return [] }
        let margin = max(14 * 86_400, last.timeIntervalSince(first) * 0.15)
        return standards.curves(
            measure, sex: sex, birthDate: birthDate,
            from: first.addingTimeInterval(-margin), to: last.addingTimeInterval(margin)
        )
    }

    private func chart(
        _ points: [GrowthPoint],
        measure: GrowthMeasure,
        label: String,
        color: Color,
        convert: @escaping (Double) -> Double,
        format: @escaping (Double) -> String
    ) -> some View {
        let curves = referenceCurves(points, measure: measure)

        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                // Faint reference lines behind the baby's own, the median solid and the rest dashed.
                ForEach(curves) { curve in
                    ForEach(curve.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(label, convert(point.value)),
                            series: .value("Line", curve.label)
                        )
                        .foregroundStyle(Color.gray.opacity(curveOpacity(curve)))
                        .lineStyle(curveStroke(curve))
                        .accessibilityHidden(true)
                    }
                }
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(label, convert(point.value)),
                        series: .value("Line", label)
                    )
                    .foregroundStyle(color)
                    // VoiceOver reads each measurement once, from its point.
                    .accessibilityHidden(true)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(label, convert(point.value))
                    )
                    .foregroundStyle(color)
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(spokenValue(measure, point, format: format))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)

            if !curves.isEmpty {
                Text("Gray lines: WHO 3rd, 15th, 50th (solid), 85th and 97th percentiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    /// "4.2 kg, 48th percentile", for a point on the chart.
    private func spokenValue(_ measure: GrowthMeasure, _ point: GrowthPoint, format: (Double) -> String) -> String {
        let value = format(point.value)
        guard let percentile = percentile(measure, point) else { return value }
        return "\(value), \(percentile.spokenText)"
    }

    private func curveOpacity(_ curve: GrowthCurve) -> Double {
        curve.percentile == 50 ? 0.5 : 0.3
    }

    private func curveStroke(_ curve: GrowthCurve) -> StrokeStyle {
        StrokeStyle(lineWidth: 1, dash: curve.percentile == 50 ? [] : [4, 3])
    }

    /// "Weight 48th · Length 62nd percentile" for a row, when the WHO charts apply.
    private func percentileLine(_ entry: GrowthEntry) -> String? {
        var parts: [String] = []
        if let kg = entry.weightKg, let p = baby.growthPercentile(.weight, value: kg, on: entry.date) {
            parts.append("Weight \(p.shortText)")
        }
        if let cm = entry.lengthCm, let p = baby.growthPercentile(.length, value: cm, on: entry.date) {
            parts.append("Length \(p.shortText)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + " percentile"
    }

    private func row(_ entry: GrowthEntry) -> some View {
        Button {
            editing = entry
        } label: {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "📏", tint: Palette.growth)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    let values = [
                        entry.weightKg.map { units.formatWeight(kg: $0) },
                        entry.lengthCm.map { units.formatLength(cm: $0) },
                    ].compactMap { $0 }.joined(separator: " · ")
                    Text(values.isEmpty ? "Measurement" : values)
                        .font(.body.weight(.medium))
                    if let percentiles = percentileLine(entry) {
                        Text(percentiles)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .swipeActions {
            if canEditLog {
                // Not `.destructive`, which would remove the row before the answer.
                Button("Delete", systemImage: "trash") {
                    deleting = entry
                }
                .tint(.red)
            }
        }
    }
}

/// One weight or length reading, in storage units (kg or cm).
private struct GrowthPoint: Identifiable {
    let id: NSManagedObjectID
    let date: Date
    let value: Double
}

/// The latest weight or length, with the change since the measurement before it.
private struct GrowthStat: View {
    let title: String
    let emoji: String
    let value: String?
    let change: String?
    /// On the WHO chart, when the baby's sex and birthday are set.
    var percentile: GrowthPercentile?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(emoji)
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text(value ?? "–")
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(value ?? "Not measured yet")

            if let percentile {
                Text(percentile.text)
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel(percentile.spokenText)
            }

            Text(change ?? "Not measured yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
        // "Weight, 4.2 kg, 48th percentile, +180 g since Oct 12".
        .accessibilityElement(children: .combine)
    }
}

struct GrowthEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var units: GrowthUnits = .localeDefault

    let entry: GrowthEntry?

    @State private var date = Date.now
    /// Kilograms, when metric.
    @State private var weightText = ""
    /// Pounds and ounces, when imperial.
    @State private var poundsText = ""
    @State private var ouncesText = ""
    /// Centimeters or inches.
    @State private var lengthText = ""
    @State private var notes = ""
    /// The fields as first shown, so an unchanged value is saved as it was instead of being
    /// converted back from rounded text.
    @State private var loadedFields: [String] = []
    @State private var didLoad = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this measurement, but only the parents can save changes.") }
                }

                Section {
                    DateField("Date", selection: $date, includesTime: false)
                }

                Section("Weight") {
                    switch units {
                    case .metric:
                        numberField("Weight", text: $weightText, unit: "kg")
                    case .imperial:
                        numberField("Pounds", text: $poundsText, unit: "lb")
                        numberField("Ounces", text: $ouncesText, unit: "oz")
                    }
                }

                Section {
                    numberField("Length", text: $lengthText, unit: units.lengthUnit)
                } header: {
                    Text("Length")
                } footer: {
                    if hasInvalidNumber {
                        NoticeLabel(
                            "Check the numbers. Use digits with one decimal point, and more than zero.",
                            systemImage: "exclamationmark.circle.fill",
                            tint: Palette.danger
                        )
                    } else {
                        Text("Add a weight, a length, or both.")
                    }
                }

                Section("Notes") {
                    TextField("Measured at 2-month checkup", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let entry, canEditLog {
                    Section {
                        Button("Delete measurement", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Delete this measurement?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                context.delete(entry)
                                context.saveIfChanged()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "New measurement" : "Edit measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave || !canEditLog)
                }
            }
            .onAppear(perform: load)
        }
        .threeAMSheet()
    }

    private func numberField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Parsing

    private enum Parsed {
        case empty
        case invalid
        case value(Double)

        var number: Double? {
            if case .value(let value) = self { return value }
            return nil
        }

        var isInvalid: Bool {
            if case .invalid = self { return true }
            return false
        }
    }

    /// For keyboards that type the locale's own digits, e.g. Arabic.
    private static let localeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter
    }()

    /// Reads a number typed with either the user's decimal separator or a period.
    private func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = trimmed
            .replacingOccurrences(of: separator, with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) ?? Self.localeFormatter.number(from: trimmed)?.doubleValue,
              value.isFinite, value >= 0
        else { return .invalid }
        return .value(value)
    }

    /// The weight in kilograms, from whichever fields the units use.
    private var parsedWeight: Parsed {
        switch units {
        case .metric:
            guard case .value(let kg) = parse(weightText) else { return parse(weightText) }
            return kg > 0 ? .value(kg) : .invalid
        case .imperial:
            let pounds = parse(poundsText)
            let ounces = parse(ouncesText)
            switch (pounds, ounces) {
            case (.empty, .empty):
                return .empty
            case (.invalid, _), (_, .invalid):
                return .invalid
            default:
                let kg = GrowthUnits.kg(pounds: pounds.number ?? 0, ounces: ounces.number ?? 0)
                return kg > 0 ? .value(kg) : .invalid
            }
        }
    }

    /// The length in centimeters.
    private var parsedLength: Parsed {
        guard case .value(let value) = parse(lengthText) else { return parse(lengthText) }
        return value > 0 ? .value(units.toCm(value)) : .invalid
    }

    private var hasInvalidNumber: Bool {
        parsedWeight.isInvalid || parsedLength.isInvalid
    }

    /// At least one of weight or length, and nothing unreadable.
    private var canSave: Bool {
        !hasInvalidNumber && (parsedWeight.number != nil || parsedLength.number != nil)
    }

    private var weightFields: [String] { [weightText, poundsText, ouncesText] }

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let entry else { return }
        date = entry.date
        notes = entry.notes
        if let kg = entry.weightKg {
            weightText = number(kg, digits: 3)
            let parts = GrowthUnits.poundsAndOunces(kg: kg, ounceDigits: 1)
            poundsText = "\(parts.pounds)"
            ouncesText = number(parts.ounces, digits: 1)
        }
        if let cm = entry.lengthCm {
            lengthText = number(units.fromCm(cm), digits: 2)
        }
        loadedFields = weightFields + [lengthText]
    }

    private func save() {
        let isNew = entry == nil
        let weightChanged = isNew || Array(loadedFields.prefix(3)) != weightFields
        let lengthChanged = isNew || loadedFields.last != lengthText
        let target = entry ?? GrowthEntry.create(in: context)
        target.date = date
        if weightChanged { target.weightKg = parsedWeight.number }
        if lengthChanged { target.lengthCm = parsedLength.number }
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        dismiss()
    }

    /// A number for a text field, in the user's locale, without grouping separators.
    private func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
    }
}
