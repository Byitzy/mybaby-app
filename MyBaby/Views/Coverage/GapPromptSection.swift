import CoreData
import SwiftUI

/// Today's "Nothing logged since 9:10 AM (5 h)" card, shown while a gap in the log is open (see
/// `Coverage.currentGap(now:)`), with three ways to deal with it: **Catch up** with rough counts, mark
/// it **Not tracked**, or say **Nothing happened**.
///
/// Dismissing it hides it until the next gap (one starting at a different time). It's left out for
/// view-only family, who can't log.
struct GapPromptSection: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage(SettingsKey.dismissedGapStart) private var dismissedGapStart: Double = 0

    let now: Date
    @Binding var toast: Toast?
    let present: (CoverageSheetTarget) -> Void

    /// The latest entries: enough to find when anything was last logged.
    @FetchRequest private var recent: FetchedResults<Activity>
    @FetchRequest private var ongoingSleep: FetchedResults<Activity>
    @FetchRequest private var periods: FetchedResults<TrackingPeriod>

    init(baby: Baby, now: Date, toast: Binding<Toast?>, present: @escaping (CoverageSheetTarget) -> Void) {
        self.now = now
        _toast = toast
        self.present = present
        _recent = FetchRequest(fetchRequest: baby.entries(Activity.fetch(limit: 20)))
        _ongoingSleep = FetchRequest(fetchRequest: baby.entries(Activity.ongoingSleep))
        let latestPeriods = baby.entries(TrackingPeriod.fetchAll())
        latestPeriods.fetchLimit = 10
        _periods = FetchRequest(fetchRequest: latestPeriods)
    }

    var body: some View {
        if canEditLog, let gap = openGap {
            Section {
                card(gap)
            }
        }
    }

    /// The gap still open now, unless it was dismissed or nothing was ever logged.
    private var openGap: Coverage.Gap? {
        guard !recent.isEmpty || !periods.isEmpty else { return nil }
        let coverage = Coverage(
            activities: Array(recent) + Array(ongoingSleep),
            periods: Array(periods),
            now: now,
            plan: NightPlan(data: nightPlanData)
        )
        guard let gap = coverage.currentGap(now: now), gap.hasStart,
              abs(gap.start.timeIntervalSince1970 - dismissedGapStart) > 1
        else { return nil }
        return gap
    }

    private func card(_ gap: Coverage.Gap) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(Palette.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title(gap))
                        .font(.subheadline.weight(.semibold))
                    Text("Catch up with rough numbers, or mark the time, so Reports don't read it as zero.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(spokenTitle(gap)). Catch up with rough numbers, or mark the time, so Reports don't read it as zero.")
                Spacer(minLength: 0)
                Button {
                    dismissedGapStart = gap.start.timeIntervalSince1970
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(Spacing.xs)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
                .accessibilityHint("Hides this until the next time nothing is logged for a while")
            }
            // Side by side, or one under the other when they don't fit (large text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { buttons(gap) }
                VStack(alignment: .leading, spacing: Spacing.s) { buttons(gap) }
            }
            .controlSize(.small)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func buttons(_ gap: Coverage.Gap) -> some View {
        Button("Catch up") {
            present(.catchUp(start: gap.start, end: now))
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Add rough counts of diapers, feeds and naps")
        Button("Not tracked") {
            present(.newPeriod(.notTracked, start: gap.start, end: now))
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Mark this time as not tracked, for example with a caregiver")
        Button("Nothing happened") {
            markNothingHappened(gap)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Mark this time as tracked, with nothing to log")
    }

    /// "Nothing logged since 9:10 AM (5 h)." The day is added when it wasn't today.
    private func title(_ gap: Coverage.Gap) -> String {
        "Nothing logged since \(since(gap)) (\(max(1, Int(gap.duration / 3600))) h)."
    }

    private func spokenTitle(_ gap: Coverage.Gap) -> String {
        "Nothing logged since \(since(gap)), \(Format.spokenDuration(gap.duration))"
    }

    private func since(_ gap: Coverage.Gap) -> String {
        Calendar.current.isDate(gap.start, inSameDayAs: now)
            ? gap.start.formatted(date: .omitted, time: .shortened)
            : gap.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func markNothingHappened(_ gap: Coverage.Gap) {
        let period = TrackingPeriod.create(.nothingHappened, start: gap.start, end: now, in: context)
        context.saveIfChanged()
        toast = Toast(message: "Marked as nothing happened") { [context] in
            context.delete(period)
            context.saveIfChanged()
        }
    }
}
