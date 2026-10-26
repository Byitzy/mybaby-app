import CoreData
import SwiftUI

/// "Make a keepsake PDF": picks what goes in (one month, the first year or everything), whether the
/// letters for later are printed too, and hands the PDF to the share sheet to save, print or send.
struct KeepsakeView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var growthUnits: GrowthUnits = .localeDefault
    @ObservedObject var baby: Baby

    @State private var choice: Choice = .everything
    /// Which month, for "One month".
    @State private var monthIndex = 1
    @State private var includesLetters = false
    @State private var isMaking = false
    @State private var share: SharePayload?
    @State private var failed = false
    @State private var didLoad = false

    enum Choice: String, CaseIterable, Identifiable {
        case month, firstYear, everything

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: return String(localized: "One month", comment: "What goes in the keepsake PDF")
            case .firstYear: return String(localized: "The first year", comment: "What goes in the keepsake PDF")
            case .everything: return String(localized: "Everything", comment: "What goes in the keepsake PDF")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if months.isEmpty {
                        LabeledContent("What to include", value: String(localized: "Everything", comment: "What goes in the keepsake PDF"))
                    } else {
                        Picker("What to include", selection: $choice) {
                            ForEach(Choice.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        if choice == .month {
                            Picker("Month", selection: $monthIndex) {
                                ForEach(months) { month in
                                    Text(month.fullTitle()).tag(month.index)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(contentsFooter)
                }

                if canEditLog {
                    Section {
                        Toggle("Include letters for later", isOn: $includesLetters)
                    } footer: {
                        Text("Off unless you turn it on, so the letters stay sealed for \(baby.displayName). Turned on, they're printed in full.")
                    }
                }

                Section {
                    Button(action: make) {
                        HStack(spacing: Spacing.s) {
                            if isMaking {
                                ProgressView()
                                Text("Making your keepsake…")
                            } else {
                                Label("Make keepsake PDF", systemImage: "doc.richtext")
                            }
                        }
                    }
                    .disabled(isMaking)
                } footer: {
                    Text("The PDF goes only where you send it. The copy on this iPhone is deleted when the share sheet closes.")
                }
            }
            .navigationTitle("Keepsake PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .sheet(item: $share) { payload in
                ShareSheet(items: payload.items)
                    .presentationDetents([.medium, .large])
            }
            .alert("Couldn't make the PDF", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again. If it keeps happening, try a shorter range.")
            }
        }
        .threeAMSheet()
    }

    /// The baby's months so far, newest first. Empty before a birthday is set.
    private var months: [DiaryPeriod] {
        guard let birthDate = baby.birthDate else { return [] }
        return DiaryPeriod.months(birthDate: birthDate)
    }

    private var contentsFooter: String {
        let base = String(localized: "The diary entries with their photos, each month's summary and your notes about it.")
        if baby.birthDate == nil {
            let name = baby.displayName
            let addBirthday = DiaryText.bySex(
                baby,
                female: String(localized: "Add her birthday to have it arranged by month of life, with summaries."),
                male: String(localized: "Add his birthday to have it arranged by month of life, with summaries."),
                unknown: String(localized: "Add \(name)'s birthday to have it arranged by month of life, with summaries.")
            )
            return "\(base) \(addBirthday)"
        }
        return base
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        // The month that just finished, or the first one.
        let finished = months.first { $0.isFinished() }
        monthIndex = finished?.index ?? months.last?.index ?? 1
    }

    private var range: KeepsakeExporter.Scope {
        guard !months.isEmpty else { return .everything }
        switch choice {
        case .month: return .month(monthIndex)
        case .firstYear: return .firstYear
        case .everything: return .everything
        }
    }

    private func make() {
        isMaking = true
        let range = self.range
        let letters = canEditLog && includesLetters
        Task {
            let url = await KeepsakeExporter.make(
                baby: baby, range: range, includesLetters: letters, growthUnits: growthUnits, context: context
            )
            isMaking = false
            if let url {
                share = SharePayload(items: [url])
            } else {
                failed = true
            }
        }
    }
}
