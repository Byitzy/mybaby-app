import SwiftUI

/// What the import would add, before anything is saved: how many of each kind, the dates it covers,
/// what's already in MyBaby, the rows left out and why, and a few entries as they'll appear.
struct ImportPreviewView: View {
    @ObservedObject var flow: ImportFlow
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var growthUnits: GrowthUnits = .localeDefault
    @AppStorage(SettingsKey.temperatureUnit, store: .shared) private var temperatureUnit: TemperatureUnit = .localeDefault

    var body: some View {
        Form {
            if let plan = flow.plan, !flow.isWorking {
                content(plan)
            } else {
                Section {
                    HStack(spacing: Spacing.m) {
                        ProgressView()
                        Text("Reading the file…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Preview")
    }

    @ViewBuilder
    private func content(_ plan: ImportPlan) -> some View {
        if let babies = flow.fullPlan?.babyNames, babies.count > 1 {
            Section {
                Picker("Baby in the file", selection: Binding(
                    get: { flow.fileBaby ?? babies[0] },
                    set: { flow.fileBaby = $0; flow.fileBabyChanged() }
                )) {
                    ForEach(babies, id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                Text("This file has more than one baby. Only the one chosen here is imported.")
            }
        }

        if flow.target == .newBaby {
            Section {
                TextField("Baby's name", text: $flow.newBabyName)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                Toggle("Add a birthday", isOn: $flow.newBabyHasBirthday)
                if flow.newBabyHasBirthday {
                    DateField("Birthday", selection: $flow.newBabyBirthday, in: ...Date.now, includesTime: false)
                }
            } header: {
                Text("New baby")
            } footer: {
                Text("The baby is added when you tap Import, with everything from the file.")
            }
        }

        if plan.entries.isEmpty {
            Section {
                EmptyStateView(
                    "Nothing to import",
                    systemImage: "tray",
                    message: plan.skippedCount > 0
                        ? "None of the rows could be read. The reasons are below."
                        : "This file has no entries MyBaby can read."
                )
            }
        } else {
            Section {
                ForEach(plan.counts) { item in
                    HStack {
                        EmojiTitle(item.category.emoji, item.category.title)
                        Spacer()
                        Text(item.count.formatted())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                if let range = plan.dateRange {
                    LabeledContent("Dates", value: Self.rangeText(range, timeZone: flow.options.timeZone))
                }
            } header: {
                Text("\(plan.entries.count.formatted()) entries to import")
            } footer: {
                Text("Times that weren't logged in the other app stay unlogged in MyBaby. They're not counted as nothing happening.")
            }

            Section {
                duplicatesRow(plan)
            } footer: {
                Text("An entry of the same kind within a minute of one already in MyBaby is treated as the same one and skipped.")
            }
        }

        if plan.dateDescription != nil || plan.datesAreAmbiguous {
            Section {
                if let description = plan.dateDescription {
                    Text(description)
                }
                if plan.datesAreAmbiguous && flow.effectiveSource != .generic {
                    Picker("Date order", selection: Binding(
                        get: { flow.dateOrder },
                        set: { flow.dateOrder = $0; flow.rebuildPlan() }
                    )) {
                        ForEach(DateOrder.allCases) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Dates")
            } footer: {
                if plan.datesAreAmbiguous {
                    Text("No day in the file is after the 12th, so the dates could be day first or month first. Check the example above.")
                }
            }
        }

        if !plan.entries.isEmpty {
            Section("A few entries") {
                ForEach(samples(plan)) { entry in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(alignment: .firstTextBaseline) {
                            EmojiTitle(entry.category.emoji, entry.title)
                            Spacer()
                            Text(Self.timeText(entry.start, timeZone: flow.options.timeZone))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        let detail = entry.detail(unit: unit, growthUnits: growthUnits, temperatureUnit: temperatureUnit)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !entry.notes.isEmpty {
                            Text(entry.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }

        if plan.skippedCount > 0 {
            Section {
                ForEach(plan.skippedReasons) { skip in
                    HStack(alignment: .firstTextBaseline) {
                        Text(skip.reason)
                        Spacer()
                        Text(skip.count.formatted())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("\(plan.skippedCount.formatted()) rows won't be imported")
            } footer: {
                Text("These rows stay in the file. Nothing is guessed.")
            }
        }

        if !plan.notes.isEmpty {
            Section {
                ForEach(plan.notes, id: \.self) { Text($0).font(.footnote) }
            }
        }

        Section {
            Button {
                flow.startImport()
            } label: {
                Text(importTitle(plan))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!flow.canImport)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Imported entries can be removed again in Settings › Your data › Recent imports.")
        }
    }

    @ViewBuilder
    private func duplicatesRow(_ plan: ImportPlan) -> some View {
        if let duplicates = flow.duplicateCount {
            if duplicates == 0 {
                NoticeLabel("None of these are in MyBaby yet", systemImage: "checkmark.circle", tint: Palette.ok)
            } else {
                NoticeLabel(
                    duplicates == plan.entries.count
                        ? "All of these are already in MyBaby and will be skipped"
                        : "\(duplicates.formatted()) are already in MyBaby and will be skipped",
                    systemImage: "square.on.square",
                    tint: Palette.inactive
                )
            }
        } else {
            HStack(spacing: Spacing.m) {
                ProgressView()
                Text("Checking what's already in MyBaby…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importTitle(_ plan: ImportPlan) -> String {
        let count = max(0, plan.entries.count - (flow.duplicateCount ?? 0))
        return count == 1 ? String(localized: "Import 1 entry") : String(localized: "Import \(count.formatted()) entries")
    }

    /// Up to five entries, spread over the file from its first to its last.
    private func samples(_ plan: ImportPlan) -> [ImportEntry] {
        let sorted = plan.entries.sorted { $0.start < $1.start }
        guard sorted.count > 5 else { return sorted }
        return (0..<5).map { sorted[$0 * (sorted.count - 1) / 4] }
    }

    static func rangeText(_ range: ClosedRange<Date>, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = timeZone
        let first = range.lowerBound.formatted(style), last = range.upperBound.formatted(style)
        return first == last ? first : "\(first) – \(last)"
    }

    static func timeText(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
