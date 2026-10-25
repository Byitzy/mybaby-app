import CoreData
import SwiftUI

/// Which coverage sheet to show: marking a new period, editing one, or catching up on a stretch.
/// Opened from Today's gap card and from History's toolbar.
enum CoverageSheetTarget: Identifiable {
    case newPeriod(TrackingPeriodKind, start: Date, end: Date)
    case editPeriod(TrackingPeriod)
    case catchUp(start: Date, end: Date)

    var id: String {
        switch self {
        case .newPeriod(let kind, let start, let end):
            return "new-\(kind.rawValue)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        case .editPeriod(let period):
            return "edit-\(period.objectID.uriRepresentation().absoluteString)"
        case .catchUp(let start, let end):
            return "catch-up-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        }
    }
}

/// The sheet for a `CoverageSheetTarget`.
struct CoverageSheet: View {
    let target: CoverageSheetTarget
    /// After Catch up saved, with a short summary for a confirmation.
    var onCaughtUp: ((String) -> Void)?

    var body: some View {
        switch target {
        case .newPeriod(let kind, let start, let end):
            TrackingPeriodEditor(kind: kind, start: start, end: end)
        case .editPeriod(let period):
            TrackingPeriodEditor(period: period)
        case .catchUp(let start, let end):
            CatchUpView(start: start, end: end, onSaved: onCaughtUp)
        }
    }
}

/// Marks a stretch of time as *not tracked* (with why) or *nothing happened*, or edits a marked one.
/// Reports then show not-tracked hours as missing rather than as zero (see `Coverage`).
struct TrackingPeriodEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    /// The period being edited, or `nil` for a new one.
    let period: TrackingPeriod?

    @State private var kind: TrackingPeriodKind
    @State private var reason: TrackingPeriodReason?
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String
    @State private var deleting: TrackingPeriod?

    init(kind: TrackingPeriodKind, start: Date, end: Date) {
        period = nil
        _kind = State(initialValue: kind)
        _reason = State(initialValue: nil)
        _start = State(initialValue: min(start, end))
        _end = State(initialValue: max(start, end))
        _notes = State(initialValue: "")
    }

    init(period: TrackingPeriod) {
        self.period = period
        _kind = State(initialValue: period.kind)
        _reason = State(initialValue: period.reason)
        _start = State(initialValue: period.start)
        _end = State(initialValue: period.end)
        _notes = State(initialValue: period.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this, but only the parents can change it.") }
                }

                if kind == .caughtUp {
                    Section {
                        LabeledContent("Marked as", value: kind.title)
                    } footer: {
                        Text("Added with Catch up. Its entries show ≈ in History and count as tracked in Reports.")
                    }
                } else {
                    Section {
                        Picker("This time was", selection: $kind) {
                            Text(TrackingPeriodKind.notTracked.title).tag(TrackingPeriodKind.notTracked)
                            Text(TrackingPeriodKind.nothingHappened.title).tag(TrackingPeriodKind.nothingHappened)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("This time was")
                    } footer: {
                        Text(kind == .notTracked
                            ? "Nobody logged what happened. Reports show these hours as missing, not as zero."
                            : "You were keeping track and there was nothing to log. These hours count as tracked.")
                    }
                }

                if kind == .notTracked {
                    Section("Why") {
                        Picker("Why", selection: $reason) {
                            Text("No reason given").tag(TrackingPeriodReason?.none)
                            ForEach(TrackingPeriodReason.allCases) { reason in
                                Text(reason.title).tag(TrackingPeriodReason?.some(reason))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section("When") {
                    DateField("From", selection: $start)
                    DateField("To", selection: $end, in: start...)
                }

                Section("Notes") {
                    TextField(notesPrompt, text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if period != nil && canEditLog {
                    Section {
                        Button("Delete", role: .destructive) { deleting = period }
                    }
                }
            }
            .navigationTitle(period == nil ? "Mark time" : "Edit marked time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(end <= start || !canEditLog)
                }
            }
            .confirmDelete(
                "Delete this marked time?",
                item: $deleting,
                message: "Entries logged in it stay. Reports go back to working this time out from the log."
            ) { period in
                context.delete(period)
                context.saveIfChanged()
                dismiss()
            }
        }
        .threeAMSheet()
    }

    private var notesPrompt: String {
        if kind == .notTracked && reason == .caregiver { return "Who? e.g. grandma" }
        return "Optional"
    }

    private func save() {
        let target = period ?? TrackingPeriod.create(kind, start: start, end: end, in: context)
        target.kind = kind
        target.start = min(start, end)
        target.end = max(start, end)
        target.reason = kind == .notTracked ? reason : nil
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        dismiss()
    }
}

/// A gray row in History for a marked period: a slashed eye for *not tracked*, so it doesn't rely on
/// color, and "Not tracked · with grandma · 1–5 PM".
struct TrackingPeriodRow: View {
    @ObservedObject var period: TrackingPeriod
    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 40

    var body: some View {
        // Deleted here or on the partner's phone, it can redraw once more before the list drops it.
        if period.isDeleted || period.managedObjectContext == nil {
            EmptyView()
        } else {
            row
        }
    }

    private var side: CGFloat { min(badge, 64) }

    private var row: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: period.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.inactive)
                .frame(width: side, height: side)
                .background(Palette.inactive.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(period.summaryLine)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                if !extraNote.isEmpty {
                    Text(extraNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// The notes, unless the reason already shows them ("with grandma").
    private var extraNote: String {
        period.reasonUsesNotes ? "" : period.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Not tracked, with grandma, from 1:00 PM to 5:00 PM".
    private var spokenLabel: String {
        let interval = period.interval
        var parts = [period.kind.title]
        if !period.reasonPhrase.isEmpty { parts.append(period.reasonPhrase) }
        parts.append("from \(interval.start.formatted(date: .omitted, time: .shortened)) to \(interval.end.formatted(date: .omitted, time: .shortened))")
        if !extraNote.isEmpty { parts.append(extraNote) }
        return parts.joined(separator: ", ")
    }
}
