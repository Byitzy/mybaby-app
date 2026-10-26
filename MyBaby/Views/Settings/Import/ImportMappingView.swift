import SwiftUI

/// Matching a CSV's columns to what MyBaby needs, for apps it doesn't know.
///
/// The columns are matched from their headers first (`GenericMapping.guess`), and the date format is
/// worked out from the values, so the parent mostly checks: the first rows are shown as they are in
/// the file, and the date line shows how the first one is read.
struct ImportMappingView: View {
    @ObservedObject var flow: ImportFlow

    var body: some View {
        Form {
            if let table = flow.genericTable {
                if flow.tables.count > 1 {
                    Section {
                        Picker("File", selection: $flow.genericTableIndex) {
                            ForEach(flow.tables.indices, id: \.self) { index in
                                Text(flow.tables[index].name).tag(index)
                            }
                        }
                    } footer: {
                        Text("This export has more than one file. Match the columns of each one in turn: import one, then start again for the next.")
                    }
                }

                Section {
                    ImportRowsPreview(table: table)
                        .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l))
                } header: {
                    Text("First rows of \(table.name)")
                } footer: {
                    Text("\(table.rows.count.formatted()) rows in all.")
                }

                Section {
                    columnPicker(.dateTime, table: table)
                    columnPicker(.timeOfDay, table: table)
                    datePatternPicker(table: table)
                } header: {
                    Text("When")
                } footer: {
                    Text(dateFooter(table: table))
                }

                Section {
                    columnPicker(.type, table: table)
                    if flow.mapping[.type] == nil {
                        Picker("Every row is a", selection: $flow.mapping.everyRow) {
                            Text("Choose…").tag(ImportCategory?.none)
                            ForEach(ImportCategory.genericChoices) { category in
                                Text(category.singularTitle).tag(ImportCategory?.some(category))
                            }
                        }
                    }
                } header: {
                    Text("What")
                } footer: {
                    Text(flow.mapping[.type] == nil
                         ? "Without a type column, every row is the same kind, as in an export with one file per kind."
                         : "Rows are recognized from words like bottle, formula, breastfeed, nursing, wet, dirty, nap, pump, bath, temperature or a medicine's name. Rows MyBaby can't tell are skipped and counted.")
                }

                Section {
                    columnPicker(.endTime, table: table)
                    columnPicker(.duration, table: table)
                    Picker("Durations are in", selection: $flow.mapping.durationUnit) {
                        ForEach(DurationUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    columnPicker(.amount, table: table)
                    columnPicker(.unit, table: table)
                    Picker("Amounts without a unit", selection: $flow.mapping.volumeUnit) {
                        ForEach(VolumeUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    columnPicker(.side, table: table)
                    columnPicker(.notes, table: table)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Durations like 1:20 or 1h 20m, and amounts like 4 oz or 120 ml, are read as written. Weights and lengths need their unit (kg, lb, g, cm, in) in the file; temperatures are read as °C or °F from the number.")
                }

                Section {
                    Button("Preview") { flow.continueFromMapping() }
                        .frame(maxWidth: .infinity)
                        .disabled(!canPreview)
                }
            } else {
                EmptyStateView("Nothing to match", systemImage: "tablecells", message: "The file has no rows to import.")
            }
        }
        .navigationTitle("Match the columns")
        .onChange(of: flow.genericTableIndex) {
            flow.guessMapping()
        }
    }

    private var canPreview: Bool {
        flow.mapping[.dateTime] != nil && (flow.mapping[.type] != nil || flow.mapping.everyRow != nil)
    }

    // MARK: Pieces

    private func columnPicker(_ field: GenericField, table: ImportTable) -> some View {
        Picker(field.title, selection: Binding(
            get: { flow.mapping[field] },
            set: { newValue in
                flow.mapping[field] = newValue
                if field == .dateTime || field == .timeOfDay {
                    flow.refreshDateChoices(choosingPattern: true)
                }
            }
        )) {
            Text("None").tag(Int?.none)
            ForEach(table.header.indices, id: \.self) { index in
                Text(table.header[index].isEmpty ? String(localized: "Column \(index + 1)") : table.header[index]).tag(Int?.some(index))
            }
        }
    }

    private func datePatternPicker(table: ImportTable) -> some View {
        let suggested = flow.dateGuess?.pattern
        return Picker("Date format", selection: $flow.mapping.datePattern) {
            if flow.mapping.datePattern == nil {
                Text("Not recognized").tag(DatePattern?.none)
            }
            ForEach(flow.dateChoices) { pattern in
                Text(pattern == suggested ? String(localized: "\(pattern.title) · suggested", comment: "A date format") : pattern.title)
                    .tag(DatePattern?.some(pattern))
            }
        }
        .pickerStyle(.navigationLink)
        .disabled(flow.mapping[.dateTime] == nil)
    }

    private func dateFooter(table: ImportTable) -> String {
        guard flow.mapping[.dateTime] != nil else { return String(localized: "Choose the column with each entry's date and time.") }
        guard let pattern = flow.mapping.datePattern else {
            return String(localized: "MyBaby couldn't read the dates in this column. Check it's the right one, or pick a format.")
        }
        let guess = flow.dateGuess
        let shown = DateGuess(
            pattern: pattern, isAmbiguous: guess?.isAmbiguous ?? false,
            readCount: guess?.readCount ?? 0, sampleCount: guess?.sampleCount ?? 0, example: guess?.example
        )
        var text = ImportDates.describe(shown, timeZone: flow.options.timeZone)
        if shown.isAmbiguous {
            text += " " + String(localized: "These dates could be day first or month first; check the example is right.")
        }
        return text
    }
}

/// The first rows of a file as a small table, scrolling sideways, so the parent can see what each column holds.
struct ImportRowsPreview: View {
    let table: ImportTable
    var rowLimit = 5

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
                GridRow {
                    ForEach(table.header.indices, id: \.self) { index in
                        Text(table.header[index].isEmpty ? String(localized: "Column \(index + 1)") : table.header[index])
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                Divider()
                ForEach(Array(table.rows.prefix(rowLimit).enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(table.header.indices, id: \.self) { index in
                            Text(index < row.count ? row[index] : "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 220, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// The columns and the first row, read as words.
    private var accessibilitySummary: String {
        let columns = table.header.filter { !$0.isEmpty }.joined(separator: ", ")
        guard let first = table.rows.first else { return String(localized: "Columns: \(columns)", comment: "The file's column names") }
        let pairs = table.header.indices.compactMap { index -> String? in
            guard index < first.count, !first[index].isEmpty else { return nil }
            return String(localized: "\(table.header[index]): \(first[index])", comment: "A column's name, then its value")
        }
        let firstRow = pairs.joined(separator: ", ")
        return String(localized: "Columns: \(columns). First row: \(firstRow)", comment: "The file's column names, then the first row's values")
    }
}
