import SwiftUI

/// Settings › Your data › Recent imports: each import made on this iPhone, with Remove this import.
///
/// Hidden until something has been imported. Removing deletes every entry the import added (they carry
/// its `importBatchID`), and nothing else, so entries logged in MyBaby since are kept. Settings gives it
/// a new `id` when the import sheet closes, so a new import shows up.
struct RecentImportsSection: View {
    @State private var records = ImportHistory.load()
    @State private var removing: ImportRecord?
    @State private var busyID: String?
    @State private var errorMessage: String?

    var body: some View {
        if !records.isEmpty {
            Section {
                ForEach(records) { record in
                    HStack(alignment: .center, spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(record.summary)
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: Spacing.s)
                        if busyID == record.id {
                            ProgressView()
                        } else {
                            Button("Remove", role: .destructive) { removing = record }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove this import")
                                .accessibilityHint("Deletes the \(record.added) entries it added.")
                        }
                    }
                }
            } header: {
                Text("Recent imports")
            } footer: {
                Text("Remove this import deletes only what that import added, on every iPhone that shares the log. The files themselves were never kept.")
            }
            .confirmDelete(
                "Remove this import?",
                item: $removing,
                message: "Everything this import added is deleted. Entries logged in MyBaby stay.",
                buttonTitle: "Remove this import"
            ) { record in
                remove(record)
            }
            .alert("Couldn't remove the import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func remove(_ record: ImportRecord) {
        busyID = record.id
        Task {
            do {
                _ = try await ImportWriter.remove(batchID: record.id, container: PersistenceController.shared.container)
                ImportHistory.remove(id: record.id)
                records = ImportHistory.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            busyID = nil
        }
    }
}
