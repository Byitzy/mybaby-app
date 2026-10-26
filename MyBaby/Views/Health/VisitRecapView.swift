import CoreData
import SwiftUI

/// "How did it go?": a short, optional recap after a visit. Every part can be left empty.
///
/// - **What the doctor said** is saved on the appointment (`visitNotes`).
/// - **Measurements** become a `GrowthEntry` dated at the appointment (or update the one already
///   there), in the app's units, head circumference included. It's also still copied to the
///   appointment, where recaps kept it before, for a partner's phone on an earlier version.
/// - **Shots** mark upcoming `Vaccine`s as given at the visit, or add new ones.
/// - **Questions** from visit prep can be checked off as answered, with an optional answer.
/// - **Book the next visit** opens a new appointment with the same doctor and place.
///
/// Saving marks the recap done (`recapDoneAt`), which ends the nudges on both phones. View-only
/// family can read it but not change it.
struct VisitRecapView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var units: GrowthUnits = .localeDefault

    @ObservedObject var appointment: Appointment

    @State private var visitNotes = ""
    /// Kilograms, when metric.
    @State private var weightText = ""
    /// Pounds and ounces, when imperial.
    @State private var poundsText = ""
    @State private var ouncesText = ""
    /// Centimeters or inches.
    @State private var lengthText = ""
    @State private var headText = ""
    @State private var shots: [ShotChoice] = []
    @State private var questions: [VisitQuestion] = []
    /// By question id.
    @State private var answers: [UUID: String] = [:]
    @State private var bookingNext = false
    @State private var didLoad = false

    init(appointment: Appointment) {
        self.appointment = appointment
    }

    /// Read from `CloudStatus`, which keeps it up to date, rather than asked of the store each time:
    /// the form checks it several times per render, and renders on every keystroke.
    @ObservedObject private var cloudStatus = CloudStatus.shared

    private var canEdit: Bool {
        guard let baby = appointment.baby else { return false }
        return cloudStatus.canEdit(baby)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEdit {
                    Section { ViewOnlyBanner(message: "You can see how the visit went, but only the parents can change it.") }
                }

                Section {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(VisitFollowUp.question(for: appointment))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(appointment.date.formatted(date: .complete, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.xxs)
                } footer: {
                    Text("Add whatever you like and skip the rest.")
                }

                Section("What the doctor said") {
                    TextField("Advice, next steps, anything to remember", text: $visitNotes, axis: .vertical)
                        .lineLimit(3...10)
                }

                measurementsSection

                shotsSection

                if !questions.isEmpty {
                    questionsSection
                }

                if canEdit {
                    Section {
                        Button {
                            bookingNext = true
                        } label: {
                            Label("Book the next visit", systemImage: "calendar.badge.plus")
                        }
                    } footer: {
                        Text(appointment.provider.isEmpty
                             ? "Starts a new appointment at the same place."
                             : "Starts a new appointment with \(appointment.provider).")
                    }
                }
            }
            .disabled(!canEdit)
            .navigationTitle("How did it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(canEdit ? "Cancel" : "Done") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(hasInvalidNumber)
                    }
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $bookingNext) {
                AppointmentEditor(appointment: nil, template: appointment)
            }
        }
        .threeAMSheet()
    }

    // MARK: Measurements

    private var measurementsSection: some View {
        Section {
            switch units {
            case .metric:
                numberField(String(localized: "Weight"), text: $weightText, unit: String(localized: "kg", comment: "Kilograms"))
            case .imperial:
                numberField(String(localized: "Weight"), text: $poundsText, unit: String(localized: "lb", comment: "Pounds"))
                numberField("", text: $ouncesText, unit: String(localized: "oz", comment: "Ounces"))
            }
            numberField(String(localized: "Length"), text: $lengthText, unit: units.lengthUnit)
            numberField(String(localized: "Head", comment: "Short for head circumference"), text: $headText, unit: units.lengthUnit)
        } header: {
            Text("Measurements")
        } footer: {
            if hasInvalidNumber {
                NoticeLabel(
                    "Check the numbers. Use digits with one decimal point, and more than zero.",
                    systemImage: "exclamationmark.circle.fill",
                    tint: Palette.danger
                )
            } else {
                Text("Weight, length and head size are added to Growth, dated at the visit.")
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                // "Weight, in kg"; the ounces field has no title of its own.
                .accessibilityLabel(title.isEmpty ? "Ounces" : "\(title), in \(unit)")
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var parsedWeightKg: MeasurementText.Parsed {
        switch units {
        case .metric:
            return MeasurementText.parse(weightText).positive
        case .imperial:
            let pounds = MeasurementText.parse(poundsText)
            let ounces = MeasurementText.parse(ouncesText)
            switch (pounds, ounces) {
            case (.empty, .empty): return .empty
            case (.invalid, _), (_, .invalid): return .invalid
            default:
                return MeasurementText.Parsed
                    .value(GrowthUnits.kg(pounds: pounds.number ?? 0, ounces: ounces.number ?? 0))
                    .positive
            }
        }
    }

    private var parsedLengthCm: MeasurementText.Parsed {
        MeasurementText.parse(lengthText).positive.map(units.toCm)
    }

    private var parsedHeadCm: MeasurementText.Parsed {
        MeasurementText.parse(headText).positive.map(units.toCm)
    }

    private var hasInvalidNumber: Bool {
        parsedWeightKg.isInvalid || parsedLengthCm.isInvalid || parsedHeadCm.isInvalid
    }

    // MARK: Shots

    /// A vaccine that may have been given at the visit: an upcoming one, or one added here.
    struct ShotChoice: Identifiable {
        let id = UUID()
        var name: String
        var doseLabel = ""
        /// The upcoming `Vaccine` it marks as given; `nil` adds a new one.
        var vaccineID: NSManagedObjectID?
        var isGiven = false
    }

    private var shotsSection: some View {
        Section {
            ForEach(appointment.vaccinesGivenAtVisit) { vaccine in
                Label {
                    Text(vaccine.doseLabel.isEmpty ? vaccine.name : "\(vaccine.name) · \(vaccine.doseLabel)")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.vaccineGiven)
                }
                .accessibilityValue("Given at this visit")
            }
            ForEach($shots) { $shot in
                Toggle(isOn: $shot.isGiven) {
                    Text(shot.doseLabel.isEmpty ? shot.name : "\(shot.name) · \(shot.doseLabel)")
                }
            }
            Menu {
                ForEach(Vaccine.commonNames, id: \.self) { name in
                    Button(name) { addShot(named: name) }
                }
            } label: {
                Label("Add a shot", systemImage: "plus.circle")
            }
        } header: {
            Text("Shots")
        } footer: {
            Text("Turn on the ones given today. Upcoming vaccines are marked as given at the visit; others are added to Vaccines.")
        }
    }

    /// Picks the matching upcoming vaccine if there is one, or adds a new shot. An upcoming one saved
    /// under another name for the same vaccine ("DTaP" for "DTaP (diphtheria, tetanus, whooping
    /// cough)") counts as matching.
    private func addShot(named name: String) {
        if let index = shots.firstIndex(where: { sameVaccine($0.name, name) && !$0.isGiven }) {
            shots[index].isGiven = true
            return
        }
        let listed = Set(shots.compactMap(\.vaccineID))
        if let upcoming = upcomingVaccines.first(where: { sameVaccine($0.name, name) && !listed.contains($0.objectID) }) {
            shots.append(ShotChoice(name: upcoming.name, doseLabel: upcoming.doseLabel, vaccineID: upcoming.objectID, isGiven: true))
        } else {
            shots.append(ShotChoice(name: name, isGiven: true))
        }
    }

    private func sameVaccine(_ saved: String, _ picked: String) -> Bool {
        if saved == picked { return true }
        guard let pickedEntry = VaccineGuide.entry(matching: picked) else { return false }
        return VaccineGuide.entry(matching: saved)?.id == pickedEntry.id
    }

    private var upcomingVaccines: [Vaccine] {
        let vaccines = (appointment.baby?.vaccines as? Set<Vaccine>) ?? []
        return vaccines.filter { !$0.isGiven }.sorted { $0.date < $1.date }
    }

    // MARK: Questions

    private var questionsSection: some View {
        Section {
            ForEach($questions) { $question in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Toggle(isOn: $question.isAsked) {
                        Text(question.text)
                    }
                    .accessibilityHint("Marks the question as answered")
                    TextField("Answer (optional)", text: answerBinding(for: question.id), axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(1...4)
                }
                .padding(.vertical, Spacing.xxs)
            }
        } header: {
            Text("Your questions")
        } footer: {
            Text("Turn on the ones that were answered.")
        }
    }

    private func answerBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { answers[id] = $0 }
        )
    }

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        visitNotes = appointment.visitNotes ?? ""
        questions = appointment.questionList
        let saved = appointment.answers
        for question in questions {
            if let answer = saved[question.text] { answers[question.id] = answer }
        }
        if let entry = appointment.measurementAtVisit {
            if let kg = entry.weightKg {
                weightText = number(kg, digits: 3)
                let parts = GrowthUnits.poundsAndOunces(kg: kg, ounceDigits: 1)
                poundsText = "\(parts.pounds)"
                ouncesText = number(parts.ounces, digits: 1)
            }
            if let cm = entry.lengthCm { lengthText = number(units.fromCm(cm), digits: 2) }
        }
        // On the entry since head circumference joined Growth; on the appointment for older recaps.
        if let cm = appointment.measurementAtVisit?.headCircumferenceCm ?? appointment.headCircumferenceCm {
            headText = number(units.fromCm(cm), digits: 2)
        }
        // Upcoming vaccines due by a month after the visit, ready to switch on.
        let soon = appointment.date.addingTimeInterval(31 * 24 * 3600)
        shots = upcomingVaccines
            .filter { $0.date <= soon }
            .map { ShotChoice(name: $0.name, doseLabel: $0.doseLabel, vaccineID: $0.objectID) }
    }

    private func save() {
        guard canEdit, let baby = appointment.baby else { return }
        let visitDate = appointment.date

        appointment.visitNotes = visitNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        appointment.questionList = questions
        var byText: [String: String] = [:]
        for question in questions {
            if let answer = answers[question.id] { byText[question.text] = answer.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        appointment.answers = byText

        // Measurements: update the entry saved from this recap before, or add one.
        let weight = parsedWeightKg.number
        let length = parsedLengthCm.number
        let head = parsedHeadCm.number
        // Still copied here, where recaps kept it before Growth had head circumference, so a
        // partner's phone on an earlier version of MyBaby shows the same recap.
        appointment.headCircumferenceCm = head
        if let entry = appointment.measurementAtVisit {
            entry.weightKg = weight
            entry.lengthCm = length
            entry.headCircumferenceCm = head
            if weight == nil && length == nil && head == nil { context.delete(entry) }
        } else if weight != nil || length != nil || head != nil {
            let entry = GrowthEntry(context: context)
            attach(entry, to: baby)
            entry.uuid = UUID()
            entry.date = visitDate
            entry.weightKg = weight
            entry.lengthCm = length
            entry.headCircumferenceCm = head
            entry.notes = appointment.title.isEmpty
                ? String(localized: "Measured at the appointment")
                : String(localized: "Measured at \(appointment.title)", comment: "An appointment's title: Measured at 2-month checkup")
            entry.baby = baby
        }

        // Shots given today.
        for shot in shots where shot.isGiven {
            if let id = shot.vaccineID, let vaccine = try? context.existingObject(with: id) as? Vaccine {
                vaccine.isGiven = true
                vaccine.date = visitDate
                if vaccine.provider.isEmpty { vaccine.provider = appointment.provider }
            } else {
                let vaccine = Vaccine(context: context)
                attach(vaccine, to: baby)
                vaccine.uuid = UUID()
                vaccine.name = shot.name
                vaccine.date = visitDate
                vaccine.isGiven = true
                vaccine.provider = appointment.provider
                vaccine.baby = baby
            }
        }

        appointment.recapDoneAt = .now
        context.saveIfChanged()
        dismiss()
    }

    /// New entries go in the baby's own store, like `Baby.attach`, but for this appointment's baby,
    /// who may not be the one the app is showing.
    private func attach(_ object: NSManagedObject, to baby: Baby) {
        if let store = baby.objectID.persistentStore {
            context.assign(object, to: store)
        }
    }

    /// A number for a text field, in the user's locale, without grouping separators.
    private func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
    }
}

/// Reads a measurement typed with either the user's decimal separator or a period, like the growth editor.
enum MeasurementText {
    enum Parsed {
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

        /// Zero isn't a measurement.
        var positive: Parsed {
            if case .value(let value) = self, value <= 0 { return .invalid }
            return self
        }

        func map(_ transform: (Double) -> Double) -> Parsed {
            if case .value(let value) = self { return .value(transform(value)) }
            return self
        }
    }

    /// For keyboards that type the locale's own digits, e.g. Arabic.
    private static let localeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter
    }()

    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = trimmed
            .replacingOccurrences(of: separator, with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) ?? localeFormatter.number(from: trimmed)?.doubleValue,
              value.isFinite, value >= 0
        else { return .invalid }
        return .value(value)
    }
}

// MARK: - Nudges

/// Today's "How did the 2-month checkup go?" card, for the latest appointment that ended in the last
/// 3 days without a recap. Dismissing it hides it for that appointment on this phone. It's gone on
/// both phones once either parent saves a recap. Left out for view-only family, who can't add one.
struct VisitRecapPromptSection: View {
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.dismissedVisitRecaps) private var dismissedIDs = ""
    @FetchRequest private var recent: FetchedResults<Appointment>
    let now: Date

    @State private var recapping: Appointment?

    init(baby: Baby, now: Date) {
        self.now = now
        let request = Appointment.fetchAll()
        request.predicate = NSPredicate(
            format: "date >= %@ AND recapDoneAt == nil",
            now.addingTimeInterval(-Self.window - 3600) as NSDate
        )
        _recent = FetchRequest(fetchRequest: baby.entries(request))
    }

    /// How long after a visit the card is offered.
    private static let window: TimeInterval = 3 * 24 * 3600

    var body: some View {
        if canEditLog, let appointment {
            Section {
                card(appointment)
            }
            .sheet(item: $recapping) { appointment in
                VisitRecapView(appointment: appointment)
            }
        }
    }

    /// The latest one that has ended, isn't recapped, cancelled or dismissed.
    private var appointment: Appointment? {
        let dismissed = Set(dismissedIDs.split(separator: ",").map(String.init))
        return recent.last { appointment in
            let end = appointment.assumedEnd
            return end <= now && end >= now.addingTimeInterval(-Self.window) && !appointment.hasRecap
                && !appointment.isCancelled
                && !dismissed.contains(appointment.uuid?.uuidString ?? "")
        }
    }

    private func card(_ appointment: Appointment) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "stethoscope")
                .font(.title3)
                .foregroundStyle(Palette.appointment)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(VisitFollowUp.question(for: appointment))
                        .font(.subheadline.weight(.semibold))
                    Text("Add what the doctor said, measurements or shots, if you like.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Button("Add notes") { recapping = appointment }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Opens a short recap of the visit")
            }
            Spacer(minLength: 0)
            Button {
                dismiss(appointment)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(Spacing.xs)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Hides this for this appointment")
        }
        .padding(.vertical, Spacing.xs)
    }

    private func dismiss(_ appointment: Appointment) {
        guard let id = appointment.uuid?.uuidString else { return }
        // Only recent ones matter, so the list stays short.
        let kept = dismissedIDs.split(separator: ",").map(String.init).suffix(19)
        dismissedIDs = (kept + [id]).joined(separator: ",")
    }
}

extension SettingsKey {
    // In `UserDefaults.standard`:
    /// `uuid`s of appointments whose "How did it go?" card was dismissed on Today, comma-separated.
    static let dismissedVisitRecaps = "dismissedVisitRecaps"
}

extension View {
    /// Shows the recap a tapped "How did it go?" notification asked for (`VisitRecapRouter`).
    func visitRecapRouting() -> some View {
        modifier(VisitRecapRouting())
    }
}

private struct VisitRecapRouting: ViewModifier {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject private var router = VisitRecapRouter.shared

    func body(content: Content) -> some View {
        content.sheet(item: appointment) { appointment in
            VisitRecapView(appointment: appointment)
        }
    }

    private var appointment: Binding<Appointment?> {
        Binding(
            get: {
                guard let id = router.appointmentID else { return nil }
                let request = Appointment.fetchAll()
                request.predicate = NSPredicate(format: "uuid == %@", id as NSUUID)
                request.fetchLimit = 1
                return try? context.fetch(request).first
            },
            set: { if $0 == nil { router.appointmentID = nil } }
        )
    }
}
