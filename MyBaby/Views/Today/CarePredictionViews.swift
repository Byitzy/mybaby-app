import CoreData
import SwiftUI

/// The subtle "Next feed around 2:40" line, with the likely range ("2:20–3:05"), under Today's "Last
/// feed" card, and "Next change around 4:10" under "Last diaper" when diaper checks are on (Settings ›
/// Feed & diaper reminders). Tapping it opens "How MyBaby predicts this" (`CarePredictionSheet`).
///
/// Hidden while the prediction is only a rough guess (`.low`), while breastfeeding, and once the likely
/// range has gone by. It reads the last few days of the log itself, so Today doesn't have to.
struct CarePredictionLine: View {
    let kind: PredictionKind
    @ObservedObject var baby: Baby

    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage(SettingsKey.diaperReminderEnabled, store: .shared) private var diaperChecks = false
    // Read through `CareSettings.load()`; here so the line updates when they change.
    @AppStorage(SettingsKey.feedMaxIntervalHours, store: .shared) private var maxHours = 0.0
    @AppStorage(SettingsKey.feedingReminderHours, store: .shared) private var fixedHours = 3.0
    @AppStorage(SettingsKey.feedReminderMode, store: .shared) private var mode: FeedReminderMode = .off

    @FetchRequest private var recent: FetchedResults<Activity>
    @FetchRequest private var ongoingSleep: FetchedResults<Activity>
    @FetchRequest private var periods: FetchedResults<TrackingPeriod>
    @State private var explaining: CarePrediction?
    private let feedingTimer = FeedingTimer.shared

    init(kind: PredictionKind, baby: Baby) {
        self.kind = kind
        self.baby = baby
        let since = CareLog.fetchStart(now: .now)
        _recent = FetchRequest(fetchRequest: baby.entries(Activity.since(since)))
        _ongoingSleep = FetchRequest(fetchRequest: baby.entries(Activity.ongoingSleep))
        _periods = FetchRequest(fetchRequest: baby.entries(TrackingPeriod.overlapping(since, .distantFuture)))
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            if let prediction = shownPrediction(now: timeline.date) {
                Button {
                    explaining = prediction
                } label: {
                    label(prediction)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(spokenLabel(prediction))
                .accessibilityHint("Shows how MyBaby predicts this")
            }
        }
        .sheet(item: $explaining) { prediction in
            CarePredictionSheet(prediction: prediction, babyName: baby.displayName, plan: NightPlan(data: nightPlanData))
        }
    }

    private func label(_ prediction: CarePrediction) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(headline(prediction))
                Image(systemName: "info.circle")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(detail(prediction))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Next feed around 2:40 AM", "Next change around 4:10 PM" or "Change after the next feed".
    private func headline(_ prediction: CarePrediction) -> String {
        let time = CarePredictions.time(prediction.expected)
        switch kind {
        case .feed: return "Next feed around \(time)"
        case .diaper: return prediction.followsFeeds ? "Change after the next feed" : "Next change around \(time)"
        }
    }

    /// "2:20–3:05 AM", or "Around 4:10 PM" for a change after a feed.
    private func detail(_ prediction: CarePrediction) -> String {
        if kind == .diaper && prediction.followsFeeds {
            return "Around \(CarePredictions.time(prediction.expected))"
        }
        return CarePredictionSheet.range(prediction)
    }

    private func spokenLabel(_ prediction: CarePrediction) -> String {
        let between = "likely between \(CarePredictions.time(prediction.earliest)) and \(CarePredictions.time(prediction.latest))"
        if kind == .diaper && prediction.followsFeeds {
            return "Next diaper change probably after the next feed, around \(CarePredictions.time(prediction.expected)), \(between)"
        }
        return "\(headline(prediction)), \(between)"
    }

    /// The prediction to show now, or `nil` (see the type's notes).
    private func shownPrediction(now: Date) -> CarePrediction? {
        guard kind == .feed || diaperChecks else { return nil }
        let log = CareLog(
            activities: Array(recent) + Array(ongoingSleep),
            periods: Array(periods),
            birthDate: baby.birthDate,
            now: now,
            plan: NightPlan(data: nightPlanData),
            isFeedingNow: CareLog.isFeeding(baby, timer: feedingTimer.state)
        )
        let feed = FeedPredictor.predict(log, settings: .load(), now: now)
        let prediction = kind == .feed ? feed : DiaperPredictor.predict(log, nextFeed: feed, now: now)
        guard let prediction, prediction.confidence > .low, prediction.latest >= now else { return nil }
        return prediction
    }
}

/// "How MyBaby predicts this": the prediction, the explanation in plain words, and the data it used.
struct CarePredictionSheet: View {
    let prediction: CarePrediction
    let babyName: String
    let plan: NightPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                        Text("Likely between \(CarePredictions.time(prediction.earliest)) and \(CarePredictions.time(prediction.latest))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(prediction.confidence.title, systemImage: prediction.confidence.systemImage)
                            .font(.subheadline)
                            .padding(.top, Spacing.xxs)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                }

                Section("How MyBaby predicts this") {
                    Text(prediction.explanation)
                        .accessibilityLabel(CarePredictions.spoken(prediction.explanation))
                    Text(method)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(CarePredictions.spoken(method))
                }

                Section {
                    Text(prediction.dataSummary)
                } header: {
                    Text("Data used")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(prediction.kind == .feed ? "Next feed" : "Next diaper change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "Mavie's next feed around 2:40 AM".
    private var title: String {
        let time = CarePredictions.time(prediction.expected)
        switch prediction.kind {
        case .feed:
            return "\(babyName)'s next feed around \(time)"
        case .diaper:
            return prediction.followsFeeds
                ? "\(babyName)'s next change after the next feed, around \(time)"
                : "\(babyName)'s next change around \(time)"
        }
    }

    /// "2:20–3:05 AM" style, as Today shows it.
    static func range(_ prediction: CarePrediction) -> String {
        "\(CarePredictions.time(prediction.earliest))–\(CarePredictions.time(prediction.latest))"
    }

    private var nightHours: String {
        plan.isEnabled ? "your night shifts' hours" : "7 PM to 7 AM"
    }

    private var method: String {
        switch prediction.kind {
        case .feed:
            return "MyBaby looks at the time from the start of one feed to the start of the next over the last 5 days, with the most recent days counting most. Day and night (\(nightHours)) are worked out separately. Feeds less than \(CarePredictions.describe(FeedPredictor.clusterGap)) apart count as one. Time marked Not tracked, long stretches with nothing logged and caught-up entries are skipped, so a forgotten night doesn't look like a long sleep. It's never later than your \"Never wait longer than\" limit."
        case .diaper:
            return "MyBaby looks at the time between changes over the last 5 days, with the most recent days counting most, day and night (\(nightHours)) separately. When most changes come soon after a feed, it expects the next one after the next feed. Time marked Not tracked, long stretches with nothing logged and caught-up entries are skipped."
        }
    }

    private var footer: String {
        let local = "Worked out on this iPhone from your log. It moves each time you or your partner log something."
        switch prediction.kind {
        case .feed:
            return "\(local) It's a guess from what was logged, not medical advice. Ask your pediatrician how long your baby can go between feeds, especially in the first weeks."
        case .diaper:
            return "\(local) It's a guess from what was logged, not medical advice."
        }
    }
}
