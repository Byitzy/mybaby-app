import CoreData
import SwiftUI

/// Settings › Your data › Import from another app: bring a log over from Huckleberry, Glow Baby,
/// Nara Baby, another iPhone's MyBaby export, or any CSV, so switching apps doesn't mean starting over.
///
/// Pick the file, where it's from and which baby it's for, check the preview, then import. Everything
/// happens on this iPhone: the file is read where it is, never uploaded and never kept (`ImportFlow`).
struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow: ImportFlow

    init(baby: Baby) {
        _flow = StateObject(wrappedValue: ImportFlow(baby: baby))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch flow.step {
                case .choose: ImportChooseStep(flow: flow)
                case .mapping: ImportMappingView(flow: flow)
                case .preview: ImportPreviewView(flow: flow)
                case .importing: ImportProgressStep(flow: flow)
                case .finished: ImportFinishedStep(flow: flow) { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    switch flow.step {
                    case .choose:
                        Button("Cancel") { dismiss() }
                    case .mapping, .preview:
                        Button {
                            flow.goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                                .labelStyle(.titleAndIcon)
                        }
                    case .importing, .finished:
                        EmptyView()
                    }
                }
            }
            .alert(
                "Import",
                isPresented: Binding(get: { flow.errorMessage != nil }, set: { if !$0 { flow.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(flow.errorMessage ?? "")
            }
        }
        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
        // An import in progress finishes or is stopped with its own button, not by swiping the sheet away.
        .interactiveDismissDisabled(flow.isImporting)
        .threeAMSheet()
    }
}

// MARK: - Choosing the file

private struct ImportChooseStep: View {
    @ObservedObject var flow: ImportFlow
    @ObservedObject private var cloudStatus = CloudStatus.shared
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @State private var pickingFile = false

    var body: some View {
        Form {
            Section {
                Button {
                    pickingFile = true
                } label: {
                    HStack {
                        Label(flow.fileNames.isEmpty ? "Choose a file" : "Choose another file", systemImage: "doc.badge.plus")
                        if flow.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(flow.isWorking)
                ForEach(flow.fileNames, id: \.self) { name in
                    Label(name, systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Chosen file, \(name)")
                }
            } header: {
                Text("File")
            } footer: {
                Text("A CSV, TXT or ZIP file exported from the other app. It's read on this iPhone, never uploaded, and not kept after the import.")
            }

            Section {
                Picker("From", selection: $flow.source) {
                    Text(autoTitle).tag(ImportSource?.none)
                    ForEach(ImportSource.allCases) { source in
                        Text(source.title).tag(ImportSource?.some(source))
                    }
                }
            } header: {
                Text("Exported from")
            } footer: {
                Text(flow.effectiveSource.howToExport)
            }

            Section {
                Picker("Baby", selection: $flow.target) {
                    ForEach(editableBabies) { baby in
                        Text(baby.displayName).tag(ImportFlow.Target.existing(baby.objectID))
                    }
                    if cloudStatus.canAddBabies {
                        Text("A new baby").tag(ImportFlow.Target.newBaby)
                    }
                }
                if flow.target == .newBaby {
                    TextField("Baby's name", text: $flow.newBabyName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                    Toggle("Add a birthday", isOn: $flow.newBabyHasBirthday)
                    if flow.newBabyHasBirthday {
                        DateField("Birthday", selection: $flow.newBabyBirthday, in: ...Date.now, includesTime: false)
                    }
                }
            } header: {
                Text("Import into")
            } footer: {
                Text("Entries already in MyBaby aren't added twice, so importing the same file again is safe.")
            }

            Section {
                NavigationLink {
                    TimeZonePicker(selection: $flow.timeZoneID)
                } label: {
                    LabeledContent("Time zone", value: Self.zoneTitle(flow.timeZoneID))
                }
            } footer: {
                Text("Most apps export times without a time zone. They're read as times in this zone: choose the one you were in when they were logged.")
            }

            Section {
                Button("Continue") { flow.continueFromChoose() }
                    .frame(maxWidth: .infinity)
                    .disabled(!flow.canContinue)
            }
        }
        .navigationTitle("Import from another app")
        .fileImporter(
            isPresented: $pickingFile,
            allowedContentTypes: ImportFiles.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            flow.filesPicked(result)
        }
    }

    private var editableBabies: [Baby] {
        babies.filter { cloudStatus.canEdit($0) }
    }

    private var autoTitle: String {
        if let detected = flow.detected { return String(localized: "Auto-detect (\(detected.title))", comment: "The app the file looks to be from") }
        return String(localized: "Auto-detect")
    }

    static func zoneTitle(_ identifier: String) -> String {
        let zone = TimeZone(identifier: identifier) ?? .current
        let name = zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
        return zone.identifier == TimeZone.current.identifier ? String(localized: "\(name) (this iPhone)", comment: "A time zone") : name
    }
}

/// Every time zone, searchable, with this iPhone's first.
private struct TimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            ForEach(zones, id: \.self) { identifier in
                Button {
                    selection = identifier
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(title(identifier))
                                .foregroundStyle(.primary)
                            Text(identifier.replacingOccurrences(of: "_", with: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if identifier == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(identifier == selection ? .isSelected : [])
            }
        }
        .searchable(text: $search, prompt: "City or region")
        .navigationTitle("Time zone")
    }

    private var zones: [String] {
        let current = TimeZone.current.identifier
        let all = [current] + TimeZone.knownTimeZoneIdentifiers.filter { $0 != current }
        guard !search.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: "_")) || title($0).localizedCaseInsensitiveContains(search) }
    }

    private func title(_ identifier: String) -> String {
        let zone = TimeZone(identifier: identifier)
        let name = zone?.localizedName(for: .generic, locale: .current) ?? identifier
        return identifier == TimeZone.current.identifier ? String(localized: "\(name) (this iPhone)", comment: "A time zone") : name
    }
}

// MARK: - Importing

private struct ImportProgressStep: View {
    @ObservedObject var flow: ImportFlow
    @State private var stopping = false

    var body: some View {
        let total = max(flow.plan?.entries.count ?? 1, 1)
        VStack(spacing: Spacing.l) {
            Spacer()
            ProgressView(value: Double(min(flow.progress, total)), total: Double(total)) {
                Text(stopping ? "Stopping…" : "Importing")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(flow.progress.formatted()) of \(total.formatted()) entries")
            }
            .accessibilityElement(children: .combine)
            Text("You can keep MyBaby open while this finishes. Stopping keeps what's already added, and you can remove it afterwards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Stop importing", role: .destructive) {
                stopping = true
                flow.cancelImport()
            }
            .buttonStyle(.bordered)
            .disabled(stopping)
            Spacer()
        }
        .padding(Spacing.xl)
        .navigationTitle("Importing")
    }
}

private struct ImportFinishedStep: View {
    @ObservedObject var flow: ImportFlow
    let done: () -> Void
    @State private var confirmingRemove = false

    var body: some View {
        let summary = flow.summary ?? ImportSummary()
        Form {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label(headline(summary), systemImage: summary.wasStopped ? "pause.circle" : "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if summary.duplicates > 0 {
                        Text("\(summary.duplicates.formatted()) were already in MyBaby and weren't added again.")
                    }
                    if let skipped = flow.plan?.skippedCount, skipped > 0 {
                        Text("\(skipped.formatted()) rows from the file weren't imported, as the preview showed.")
                    }
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)
            } footer: {
                if summary.added > 0, flow.removedCount == nil {
                    Text("To undo it later, go to Settings › Your data › Recent imports and tap Remove this import. The file wasn't kept.")
                }
            }

            if summary.added > 0, flow.record != nil {
                Section {
                    Button(summary.wasStopped ? "Remove what was added" : "Remove this import", role: .destructive) {
                        confirmingRemove = true
                    }
                    .disabled(flow.isWorking)
                }
            }

            Section {
                Button("Done", action: done)
                    .frame(maxWidth: .infinity)
                    .disabled(flow.isWorking)
            }
        }
        .navigationTitle(summary.wasStopped ? "Import stopped" : "Import finished")
        .confirmationDialog("Remove this import?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove \(summary.added.formatted()) entries", role: .destructive) {
                Task { await flow.removeImported() }
            }
        } message: {
            Text("Everything this import added to \(flow.importedBabyName)'s log is deleted. Entries you logged in MyBaby stay.")
        }
    }

    private func headline(_ summary: ImportSummary) -> String {
        if let removed = flow.removedCount {
            return removed == 1
                ? String(localized: "Removed the 1 imported entry")
                : String(localized: "Removed the \(removed.formatted()) imported entries")
        }
        let added = summary.added.formatted()
        let name = flow.importedBabyName
        if summary.wasStopped {
            switch summary.added {
            case 0: return String(localized: "Stopped before anything was added")
            case 1: return String(localized: "Stopped after adding 1 entry")
            default: return String(localized: "Stopped after adding \(added) entries")
            }
        }
        if summary.added == 0 {
            return flow.record == nil && summary.duplicates == 0
                ? String(localized: "Nothing to add")
                : String(localized: "Everything was already in MyBaby")
        }
        return summary.added == 1
            ? String(localized: "Added 1 entry to \(name)'s log")
            : String(localized: "Added \(added) entries to \(name)'s log", comment: "A number, then the baby's name")
    }
}
