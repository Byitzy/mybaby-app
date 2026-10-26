import Charts
import CoreData
import SwiftUI

/// Weight, length and head circumference over time, with the latest of each up top. With the
/// baby's sex and birthday set, each is placed on the WHO growth charts.
struct GrowthList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var units: GrowthUnits = .localeDefault
    @FetchRequest private var entries: FetchedResults<GrowthEntry>
    /// For the head circumference older "How did it go?" recaps kept on the appointment.
    @FetchRequest private var appointments: FetchedResults<Appointment>
    /// Observed so setting the sex or birthday shows the percentiles right away.
    @ObservedObject private var baby: Baby

    @State private var editing: GrowthEntry?
    @State private var addingNew = false
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: GrowthEntry?
    /// An older recap's head circumference, which is changed in its recap.
    @State private var recapping: Appointment?

    init(baby: Baby) {
        self.baby = baby
        _entries = FetchRequest(fetchRequest: baby.entries(GrowthEntry.fetchAll()))
        _appointments = FetchRequest(fetchRequest: baby.entries(Appointment.fetchAll()))
    }

    var body: some View {
        let readings = GrowthReading.all(entries: Array(entries), appointments: Array(appointments))
        let weights = points(readings, .weight)
        let lengths = points(readings, .length)
        let heads = points(readings, .headCircumference)
        let showsPercentiles = baby.canShowGrowthPercentiles
        // With reference curves to compare with, one measurement is already worth a chart.
        let pointsForChart = showsPercentiles ? 1 : 2

        List {
            if readings.isEmpty {
                EmptyStateView(
                    "No measurements yet",
                    systemImage: "ruler",
                    message: "Add your baby's weight, length and head size from each checkup to see how they're growing.",
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
                            title: String(localized: "Weight"),
                            emoji: "⚖️",
                            value: weights.last.map { units.formatWeight(kg: $0.value) },
                            change: changeText(weights, format: units.formatWeightChange(kg:)),
                            percentile: weights.last.flatMap { percentile(.weight, $0) }
                        )
                        GrowthStat(
                            title: String(localized: "Length"),
                            emoji: "📏",
                            value: lengths.last.map { units.formatLength(cm: $0.value) },
                            change: changeText(lengths, format: units.formatLengthChange(cm:)),
                            percentile: lengths.last.flatMap { percentile(.length, $0) }
                        )
                        // Only once there's one, so the row stays roomy for families who don't measure it.
                        if !heads.isEmpty {
                            GrowthStat(
                                title: String(localized: "Head", comment: "Short for head circumference"),
                                emoji: "👶",
                                value: heads.last.map { units.formatLength(cm: $0.value) },
                                change: changeText(heads, format: units.formatLengthChange(cm:)),
                                percentile: heads.last.flatMap { percentile(.headCircumference, $0) },
                                spokenTitle: String(localized: "Head circumference")
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if showsPercentiles {
                        if baby.isPreterm, let born = baby.gestationText {
                            Text("Born at \(born), so the percentiles use corrected age, counted from the due date, until \(baby.displayName)'s second birthday. \(Self.whoSource)")
                        } else {
                            Text(Self.whoFooter)
                        }
                    }
                }

                if !showsPercentiles && GrowthStandards.who != nil {
                    percentileHint
                }

                if weights.count >= pointsForChart {
                    Section("Weight (\(units.weightUnit))") {
                        chart(weights, measure: .weight, label: String(localized: "Weight"), color: Palette.weight, convert: units.fromKg, format: units.formatWeight(kg:))
                    }
                }
                if lengths.count >= pointsForChart {
                    Section("Length (\(units.lengthUnit))") {
                        chart(lengths, measure: .length, label: String(localized: "Length"), color: Palette.length, convert: units.fromCm, format: units.formatLength(cm:))
                    }
                }
                if heads.count >= pointsForChart {
                    Section("Head circumference (\(units.lengthUnit))") {
                        chart(heads, measure: .headCircumference, label: String(localized: "Head circumference"), color: Palette.headCircumference, convert: units.fromCm, format: units.formatLength(cm:))
                    }
                }

                Section("Measurements") {
                    // Newest first, each with the change since the measurement before it.
                    ForEach(Array(readings.enumerated()).reversed(), id: \.element.id) { index, reading in
                        row(reading, earlier: Array(readings[..<index]))
                    }
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
        .sheet(item: $recapping) { appointment in
            VisitRecapView(appointment: appointment)
        }
        .confirmDelete("Delete this measurement?", item: $deleting) { entry in
            entry.deleteIncludingRecapHead(in: context)
            context.saveIfChanged()
        }
    }

    /// The readings that have `measure`, for its tile and chart.
    private func points(_ readings: [GrowthReading], _ measure: GrowthMeasure) -> [GrowthPoint] {
        readings.compactMap { reading in
            reading.value(measure).map { GrowthPoint(id: reading.id, date: reading.date, value: $0) }
        }
    }

    /// "+180 g since Oct 12", or when it was measured if there's nothing to compare with.
    private func changeText(_ points: [GrowthPoint], format: (Double) -> String) -> String? {
        guard let latest = points.last else { return nil }
        guard points.count >= 2 else {
            return String(localized: "Measured \(latest.date.formatted(.dateTime.month(.abbreviated).day()))")
        }
        let previous = points[points.count - 2]
        return String(localized: "\(format(latest.value - previous.value)) since \(previous.date.formatted(.dateTime.month(.abbreviated).day()))", comment: "A change, then a date: +180 g since Oct 12")
    }

    static let whoSource = String(localized: "WHO Child Growth Standards. Your pediatrician can explain what these mean for your baby.")
    static let whoFooter = whoSource + " " + String(localized: "Percentiles use age from the birthday. For a baby born early, add the weeks of pregnancy in the baby's profile to use corrected age.")

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
        // For a baby born early, the curves start from the due date while corrected age applies.
        guard let sex = baby.sex, let first = points.first?.date, let last = points.last?.date,
              let birthDate = baby.growthAgeStart(on: first), let standards = GrowthStandards.who
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
        GrowthChart(
            points: points,
            curves: referenceCurves(points, measure: measure),
            label: label,
            color: color,
            convert: convert,
            format: format,
            percentile: { percentile(measure, $0) },
            spokenValue: { spokenValue(measure, $0, format: format) }
        )
    }

    /// "4.2 kg, 48th percentile", for a point on the chart.
    private func spokenValue(_ measure: GrowthMeasure, _ point: GrowthPoint, format: (Double) -> String) -> String {
        let value = format(point.value)
        guard let percentile = percentile(measure, point) else { return value }
        return "\(value), \(percentile.spokenText)"
    }

    /// "Weight 48th · Length 62nd · Head 55th percentile" for a row, when the WHO charts apply.
    private func percentileLine(_ reading: GrowthReading) -> String? {
        var parts: [String] = []
        if let kg = reading.weightKg, let p = baby.growthPercentile(.weight, value: kg, on: reading.date) {
            parts.append(String(localized: "Weight \(p.shortText)", comment: "A weight percentile: Weight 48th"))
        }
        if let cm = reading.lengthCm, let p = baby.growthPercentile(.length, value: cm, on: reading.date) {
            parts.append(String(localized: "Length \(p.shortText)", comment: "A length percentile: Length 62nd"))
        }
        if let cm = reading.headCm, let p = baby.growthPercentile(.headCircumference, value: cm, on: reading.date) {
            parts.append(String(localized: "Head \(p.shortText)", comment: "Head circumference, short: Head 38 cm, or its percentile, Head 55th"))
        }
        guard !parts.isEmpty else { return nil }
        // Its own sentence, apart from "48th percentile", which other languages word differently.
        return String(localized: "Percentiles: \(parts.joined(separator: " · "))", comment: "Percentiles of each measure: Percentiles: Weight 48th · Length 62nd")
    }

    /// "4.2 kg · 55 cm · Head 38 cm".
    private func valuesLine(_ reading: GrowthReading) -> String {
        [
            reading.weightKg.map { units.formatWeight(kg: $0) },
            reading.lengthCm.map { units.formatLength(cm: $0) },
            reading.headCm.map { String(localized: "Head \(units.formatLength(cm: $0))", comment: "Head circumference, short: Head 38 cm, or its percentile, Head 55th") },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Weight +180 g (+4.5%) in 6 days, 30 g a day · Length +1.2 cm in 14 days, 0.6 cm a week",
    /// against the latest earlier measurement of each. Weight is per day, like pediatricians count it;
    /// length and head per week, since a day's growth rounds to nothing.
    private func changeLine(_ reading: GrowthReading, earlier: [GrowthReading]) -> String? {
        var parts: [String] = []
        for measure in [GrowthMeasure.weight, .length, .headCircumference] {
            guard let value = reading.value(measure),
                  let previous = earlier.last(where: { $0.value(measure) != nil }),
                  let before = previous.value(measure), before > 0
            else { continue }
            let change = value - before
            let days = max(1, Calendar.current.dateComponents([.day], from: previous.date, to: reading.date).day ?? 1)
            let percent = change / before * 100
            let percentText = (percent >= 0 ? "+" : "−") + abs(percent / 100).formatted(.percent.precision(.fractionLength(0...1)))
            let span = days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
            switch measure {
            case .weight:
                parts.append(String(localized: "Weight \(units.formatWeightChange(kg: change)) (\(percentText)) in \(span), \(perDayWeight(change / Double(days))) a day", comment: "Weight +180 g (+4.5%) in 6 days, 30 g a day"))
            case .length:
                parts.append(String(localized: "Length \(units.formatLengthChange(cm: change)) (\(percentText)) in \(span), \(units.formatLengthChange(cm: change / Double(days) * 7)) a week", comment: "Length +1.2 cm (+2%) in 14 days, 0.6 cm a week"))
            case .headCircumference:
                parts.append(String(localized: "Head \(units.formatLengthChange(cm: change)) (\(percentText)) in \(span), \(units.formatLengthChange(cm: change / Double(days) * 7)) a week", comment: "Head circumference: Head +0.8 cm (+2%) in 14 days, 0.4 cm a week"))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A day's weight change: "+30 g" or "+1.1 oz", since pounds a day round to nothing.
    private func perDayWeight(_ kg: Double) -> String {
        switch units {
        case .metric:
            return units.formatWeightChange(kg: kg)
        case .imperial:
            let ounces = kg * 35.27396
            let magnitude = abs(ounces).formatted(.number.precision(.fractionLength(0...1)))
            return (ounces >= 0 ? "+" : "−") + String(localized: "\(magnitude) oz", comment: "Ounces")
        }
    }

    private func row(_ reading: GrowthReading, earlier: [GrowthReading]) -> some View {
        Button {
            if let entry = reading.entry {
                editing = entry
            } else {
                recapping = reading.recap
            }
        } label: {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "📏", tint: Palette.growth)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    let values = valuesLine(reading)
                    Text(values.isEmpty ? String(localized: "Measurement") : values)
                        .font(.body.weight(.medium))
                    if let percentiles = percentileLine(reading) {
                        Text(percentiles)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let change = changeLine(reading, earlier: earlier) {
                        Text(change)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !reading.notes.isEmpty {
                        Text(reading.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(reading.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        // A head circumference from an older recap is changed in that recap.
        .accessibilityHint(reading.entry == nil ? Text("Opens the visit recap it was noted in") : Text(""))
        .swipeActions {
            if canEditLog, let entry = reading.entry {
                // Not `.destructive`, which would remove the row before the answer.
                Button("Delete", systemImage: "trash") {
                    deleting = entry
                }
                .tint(.red)
            }
        }
    }
}

/// A measure's chart: the baby's measurements over the WHO percentile curves. The row above it shows
/// the latest measurement's value, percentile and date; tapping the chart shows the nearest
/// measurement's instead, and tapping it again goes back to the latest. The row sits outside the
/// chart, so nothing in it can be clipped by the chart's edges.
private struct GrowthChart: View {
    let points: [GrowthPoint]
    let curves: [GrowthCurve]
    let label: String
    let color: Color
    let convert: (Double) -> Double
    let format: (Double) -> String
    let percentile: (GrowthPoint) -> GrowthPercentile?
    let spokenValue: (GrowthPoint) -> String

    @State private var selectedID: NSManagedObjectID?

    private var selected: GrowthPoint? {
        points.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let shown = selected ?? points.max(by: { $0.date < $1.date }) {
                reading(shown, isSelected: selected != nil)
            }
            Chart {
                // Faint reference lines behind the baby's own, the median solid and the rest dashed.
                ForEach(curves) { curve in
                    ForEach(curve.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(label, convert(point.value)),
                            series: .value("Line", curve.label)
                        )
                        .foregroundStyle(Color.gray.opacity(curve.percentile == 50 ? 0.5 : 0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: curve.percentile == 50 ? [] : [4, 3]))
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
                    .symbolSize(point.id == selectedID ? 140 : 50)
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(spokenValue(point))
                }
                if let selected {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(color.opacity(0.35))
                        .accessibilityHidden(true)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        // A tap, not a drag, so the list still scrolls past the chart.
                        .onTapGesture { location in
                            select(at: location, proxy: proxy, geometry: geometry)
                        }
                }
            }
            .frame(height: 200)

            Text(curves.isEmpty
                 ? "Tap the chart to see a measurement."
                 : "Gray lines: WHO 3rd, 15th, 50th (solid), 85th and 97th percentiles. Tap the chart to see where a measurement falls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    /// "3.02 kg · 15th percentile", with the date and whether it's the latest or the tapped one.
    private func reading(_ point: GrowthPoint, isSelected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(format(point.value))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color)
                    if let percentile = percentile(point) {
                        Text(percentile.text)
                            .font(.subheadline.weight(.medium))
                    }
                }
                Text(point.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(isSelected ? "Selected" : "Latest")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xxs)
                .background(Palette.chipBackground, in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    /// The measurement nearest the tapped date; the same one again hides the callout.
    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let x = location.x - geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x),
              let nearest = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        else { return }
        selectedID = nearest.id == selectedID ? nil : nearest.id
    }
}

/// One weight, length or head circumference reading, in storage units (kg or cm).
private struct GrowthPoint: Identifiable {
    let id: NSManagedObjectID
    let date: Date
    let value: Double
}

/// The latest weight, length or head circumference, with the change since the measurement before it.
private struct GrowthStat: View {
    let title: String
    let emoji: String
    let value: String?
    let change: String?
    /// On the WHO chart, when the baby's sex and birthday are set.
    var percentile: GrowthPercentile?
    /// What VoiceOver reads for a short `title`: "Head circumference" for "Head".
    var spokenTitle: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(emoji)
                    .accessibilityHidden(true)
                Text(title)
                    .accessibilityLabel(spokenTitle ?? title)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text(value ?? "–")
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(value ?? String(localized: "Not measured yet"))

            if let percentile {
                Text(percentile.text)
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel(percentile.spokenText)
            }

            Text(change ?? String(localized: "Not measured yet"))
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
    /// Head circumference, in centimeters or inches.
    @State private var headText = ""
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
                        numberField(String(localized: "Weight"), text: $weightText, unit: String(localized: "kg", comment: "Kilograms"))
                    case .imperial:
                        numberField(String(localized: "Pounds"), text: $poundsText, unit: String(localized: "lb", comment: "Pounds"))
                        numberField(String(localized: "Ounces"), text: $ouncesText, unit: String(localized: "oz", comment: "Ounces"))
                    }
                }

                Section("Length") {
                    numberField(String(localized: "Length"), text: $lengthText, unit: units.lengthUnit)
                }

                Section {
                    numberField(
                        String(localized: "Head", comment: "Short for head circumference"),
                        text: $headText, unit: units.lengthUnit, spokenTitle: String(localized: "Head circumference")
                    )
                } header: {
                    Text("Head circumference")
                } footer: {
                    if hasInvalidNumber {
                        NoticeLabel(
                            "Check the numbers. Use digits with one decimal point, and more than zero.",
                            systemImage: "exclamationmark.circle.fill",
                            tint: Palette.danger
                        )
                    } else {
                        Text("Add any of weight, length and head circumference. Head size is measured around the widest part, just above the eyebrows and ears.")
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
                                entry.deleteIncludingRecapHead(in: context)
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

    private func numberField(_ title: String, text: Binding<String>, unit: String, spokenTitle: String? = nil) -> some View {
        HStack {
            Text(title)
                .accessibilityLabel(spokenTitle ?? title)
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

    /// The head circumference in centimeters.
    private var parsedHead: Parsed {
        guard case .value(let value) = parse(headText) else { return parse(headText) }
        return value > 0 ? .value(units.toCm(value)) : .invalid
    }

    private var hasInvalidNumber: Bool {
        parsedWeight.isInvalid || parsedLength.isInvalid || parsedHead.isInvalid
    }

    /// At least one measurement, and nothing unreadable.
    private var canSave: Bool {
        !hasInvalidNumber && (parsedWeight.number != nil || parsedLength.number != nil || parsedHead.number != nil)
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
        // Including one an older recap kept on the appointment, so it can be changed here too.
        if let cm = entry.headCmIncludingRecap {
            headText = number(units.fromCm(cm), digits: 2)
        }
        loadedFields = weightFields + [lengthText, headText]
    }

    private func save() {
        let isNew = entry == nil
        let weightChanged = isNew || Array(loadedFields.prefix(3)) != weightFields
        let lengthChanged = isNew || loadedFields.count < 5 || loadedFields[3] != lengthText
        let headChanged = isNew || loadedFields.count < 5 || loadedFields[4] != headText
        let target = entry ?? GrowthEntry.create(in: context)
        // Found before the date changes, while it still matches the recap's appointment.
        let visit = target.recapAppointment
        let head = headChanged ? parsedHead.number : target.headCmIncludingRecap
        if headChanged { target.setHeadCircumference(head) }
        target.date = date
        if let visit, visit.headCircumferenceCm != nil, abs(date.timeIntervalSince(visit.date)) >= 60 {
            // Moved off the visit: the entry keeps the head size, so it isn't shown twice.
            target.headCircumferenceCm = head
            visit.headCircumferenceCm = nil
        }
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
