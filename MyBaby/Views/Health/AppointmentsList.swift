import CoreData
import SwiftUI

struct AppointmentsList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @FetchRequest private var appointments: FetchedResults<Appointment>
    /// Observed for the questions saved while no appointment is scheduled.
    @ObservedObject private var baby: Baby

    @State private var editing: Appointment?
    @State private var addingNew = false
    @State private var summaryFor: Appointment?
    @State private var askingQuestion = false
    @State private var questionDraft = ""
    @State private var toast: Toast?
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: Appointment?
    /// Waiting for "Cancel appointment" from a row's menu.
    @State private var cancelling: Appointment?
    /// "Add to Calendar" from a row's menu.
    @State private var calendarDraft: CalendarEventDraft?
    @ObservedObject private var calendarSync = CalendarSync.shared
    /// "How did it go?" after a visit.
    @State private var recapFor: Appointment?
    @AppStorage(SettingsKey.growthUnits, store: .shared) private var growthUnits: GrowthUnits = .localeDefault

    init(baby: Baby) {
        self.baby = baby
        _appointments = FetchRequest(fetchRequest: baby.entries(Appointment.fetchAll()))
    }

    /// Appointments from an hour ago on still count as upcoming.
    private var upcomingCutoff: Date { Date.now.addingTimeInterval(-3600) }

    /// Where a quick question goes: the next appointment that isn't cancelled, if there is one.
    private var nextAppointment: Appointment? {
        let cutoff = upcomingCutoff
        return appointments.first { $0.date >= cutoff && !$0.isCancelled }
    }

    var body: some View {
        let cutoff = upcomingCutoff
        let upcoming = appointments.filter { $0.date >= cutoff && !$0.isCancelled }
        let past = appointments.filter { $0.date < cutoff && !$0.isCancelled }.reversed()
        // Newest first, like Past. Kept so they can be restored.
        let cancelled = appointments.filter(\.isCancelled).reversed()
        let pending = baby.pendingQuestionList

        List {
            if appointments.isEmpty {
                EmptyStateView(
                    "No appointments",
                    systemImage: "calendar",
                    message: "Add checkups and visits to get a reminder before each one.",
                    actionTitle: "Add appointment",
                    isDisabled: !canEditLog
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    askingQuestion = true
                } label: {
                    Label("Add a question for the next visit", systemImage: "questionmark.bubble")
                }
                .disabled(!canEditLog)
                ForEach(pending) { question in
                    Text(question.text)
                        .deleteDisabled(!canEditLog)
                }
                .onDelete { offsets in
                    var questions = pending
                    questions.remove(atOffsets: offsets)
                    baby.pendingQuestionList = questions
                    context.saveIfChanged()
                }
            } footer: {
                if !pending.isEmpty {
                    Text("Saved for the next visit. They'll be added to the next appointment you add.")
                }
            }

            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { row($0) }
                }
            }
            if !past.isEmpty {
                Section("Past") {
                    ForEach(Array(past)) { appointment in
                        row(appointment)
                        if showsRecapButton(appointment) {
                            recapButton(appointment)
                        }
                    }
                }
            }
            if !cancelled.isEmpty {
                Section {
                    ForEach(Array(cancelled)) { row($0) }
                } header: {
                    Text("Cancelled")
                } footer: {
                    Text("Cancelled appointments have no reminders. Swipe right on one, or open it, to restore it.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add appointment", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $addingNew) {
            AppointmentEditor(appointment: nil)
        }
        .sheet(item: $editing) { appointment in
            AppointmentEditor(appointment: appointment)
        }
        .sheet(item: $summaryFor) { appointment in
            NavigationStack {
                VisitSummaryView(appointment: appointment, showsDoneButton: true)
            }
            .threeAMSheet()
        }
        .alert("Question for the next visit", isPresented: $askingQuestion) {
            TextField("Is this rash normal?", text: $questionDraft)
            Button("Add", action: addQuestion)
            Button("Cancel", role: .cancel) { questionDraft = "" }
        } message: {
            Text(questionDestination)
        }
        .confirmDelete("Delete this appointment?", item: $deleting, message: "Its questions and notes are deleted too.") { appointment in
            NotificationManager.cancel(appointment.notificationID)
            context.delete(appointment)
            context.saveIfChanged()
        }
        .cancelAppointmentDialog(item: $cancelling) { appointment in
            appointment.cancel(in: context)
            toast = Toast(message: String(localized: "Appointment cancelled")) { appointment.restore(in: context) }
        }
        .addToCalendarSheet($calendarDraft) { toast = Toast(message: String(localized: "Added to your calendar")) }
        .sheet(item: $recapFor) { appointment in
            VisitRecapView(appointment: appointment)
        }
        .toast($toast)
    }

    private var questionDestination: String {
        guard let next = nextAppointment else {
            return String(localized: "No appointment is scheduled, so it's kept here until you add one.")
        }
        let when = next.date.formatted(.dateTime.month(.abbreviated).day())
        if next.title.isEmpty {
            return String(localized: "It's added to the appointment on \(when).")
        }
        return String(localized: "It's added to \(next.title) on \(when).", comment: "An appointment's title, then its date")
    }

    private func addQuestion() {
        let question = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        questionDraft = ""
        guard !question.isEmpty else { return }
        if let next = nextAppointment {
            next.questions = VisitQuestions.appending(question, to: next.questions)
            toast = Toast(message: next.title.isEmpty
                ? String(localized: "Added to the next appointment")
                : String(localized: "Added to \(next.title)", comment: "An appointment's title"))
        } else {
            baby.pendingQuestions = VisitQuestions.appending(question, to: baby.pendingQuestions)
            toast = Toast(message: String(localized: "Saved for the next visit"))
        }
        context.saveIfChanged()
    }

    private func row(_ appointment: Appointment) -> some View {
        let isCancelled = appointment.isCancelled
        let tint = isCancelled ? Color.secondary : Palette.appointment
        return Button {
            editing = appointment
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(appointment.date, format: .dateTime.month(.abbreviated))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .textCase(.uppercase)
                    Text(appointment.date, format: .dateTime.day())
                        .font(.title2.weight(.semibold))
                        .strikethrough(isCancelled)
                        .foregroundStyle(isCancelled ? Color.secondary : Color.primary)
                }
                // Grows with the text instead of clipping it.
                .padding(.vertical, Spacing.xs)
                .frame(minWidth: 48, minHeight: 52)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.badge))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(appointment.title.isEmpty ? String(localized: "Appointment") : appointment.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isCancelled)
                        .foregroundStyle(isCancelled ? Color.secondary : Color.primary)
                    Text(appointment.date, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.subheadline)
                        .strikethrough(isCancelled)
                        .foregroundStyle(.secondary)
                    let place = [appointment.provider, appointment.location].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !place.isEmpty {
                        Text(place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // A place picked from the search also has its address.
                    if let address = appointment.addressBelowLocation {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // The strikethrough isn't read out, so this says it in words too.
                    if isCancelled {
                        Label(appointment.cancelledText, systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let toAsk = appointment.questionList.filter { !$0.isAsked }.count
                    if toAsk > 0 && appointment.date >= upcomingCutoff && !isCancelled {
                        Label("\(toAsk) questions to ask", systemImage: "questionmark.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // "Weighed 5.2 kg · 2 shots · notes", once the visit is recapped.
                    if let recap = appointment.recapSummary(units: growthUnits) {
                        Label(recap, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if appointment.reminderMinutes != nil && appointment.date > .now && !isCancelled {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Reminder on")
                }
            }
            // "2-month checkup, Tuesday 9:30 AM, Dr. Lee, 2 questions to ask, reminder on", or
            // "…, Cancelled Oct 20".
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .swipeActions {
            if canEditLog {
                // Not `.destructive`, which would remove the row before the answer.
                Button("Delete", systemImage: "trash") {
                    deleting = appointment
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading) {
            if isCancelled {
                if canEditLog {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        appointment.restore(in: context)
                        toast = Toast(message: String(localized: "Appointment restored"))
                    }
                    .tint(Palette.ok)
                }
            } else {
                Button("Visit summary", systemImage: "doc.text") {
                    summaryFor = appointment
                }
                .tint(.accentColor)
            }
        }
        .contextMenu {
            if isCancelled {
                if canEditLog {
                    Button("Restore appointment", systemImage: "arrow.uturn.backward") {
                        appointment.restore(in: context)
                        toast = Toast(message: String(localized: "Appointment restored"))
                    }
                }
            } else {
                Button("Visit summary", systemImage: "doc.text") {
                    summaryFor = appointment
                }
                if appointment.date < .now, canEditLog || appointment.hasRecap {
                    Button(appointment.hasRecap ? "How it went" : "How did it go?", systemImage: "text.bubble") {
                        recapFor = appointment
                    }
                }
                // With calendar sync on, it's already there.
                if !calendarSync.isEnabled {
                    Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                        calendarDraft = CalendarEventDraft(appointment: appointment)
                    }
                }
                // Not once a recap says how it went.
                if canEditLog, !appointment.hasRecap {
                    Button("Cancel appointment", systemImage: "calendar.badge.minus") {
                        cancelling = appointment
                    }
                }
            }
        }
    }

    /// A gentle "How did it go?" under a visit from the last two weeks that has no recap yet.
    /// Older ones can still be recapped from the appointment or its menu.
    private func showsRecapButton(_ appointment: Appointment) -> Bool {
        canEditLog && !appointment.hasRecap && !appointment.isCancelled
            && appointment.assumedEnd <= .now
            && appointment.assumedEnd > Date.now.addingTimeInterval(-14 * 24 * 3600)
    }

    private func recapButton(_ appointment: Appointment) -> some View {
        Button {
            recapFor = appointment
        } label: {
            Label("How did it go?", systemImage: "text.bubble")
                .font(.subheadline)
        }
        .accessibilityHint("Add notes, measurements or shots from this visit")
    }
}

struct AppointmentEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    let appointment: Appointment?
    /// For "Book the next visit": a new appointment starts with this one's doctor, place and reminder.
    let template: Appointment?

    init(appointment: Appointment?, template: Appointment? = nil) {
        self.appointment = appointment
        self.template = template
    }

    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var provider = ""
    @State private var location = ""
    /// The place picked from the search, or `nil` for a typed one. Typing in the field again makes it
    /// a typed place, so a new name never keeps the old one's map.
    @State private var place: AppointmentPlace?
    /// Suggestions as the parent types. Sends nothing until they do.
    @StateObject private var placeSearch = PlaceSearch()
    /// Places already picked for other appointments and vaccines, for the menu by the field.
    @State private var recentPlaces: [AppointmentPlace] = []
    @State private var notes = ""
    @State private var reminderMinutes: Int? = 60
    @State private var questions: [VisitQuestion] = []
    @State private var newQuestion = ""
    /// A new appointment starts with the questions saved while none was scheduled.
    @State private var tookPendingQuestions = false
    @State private var didLoad = false
    @State private var confirmingDelete = false
    @State private var confirmingCancel = false
    /// Mirrors the appointment's, so restoring it here updates the form at once.
    @State private var isCancelled = false
    @State private var recapping = false

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this appointment, but only the parents can save changes.") }
                }

                if let appointment, isCancelled {
                    Section {
                        NoticeLabel(
                            "\(appointment.cancelledText). It has no reminder until it's restored.",
                            systemImage: "xmark.circle",
                            tint: Palette.inactive
                        )
                        if canEditLog {
                            Button {
                                appointment.restore(in: context)
                                isCancelled = false
                            } label: {
                                Label("Restore appointment", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("What's it for?", text: $title)
                        Menu {
                            ForEach(Appointment.commonTitles, id: \.self) { suggestion in
                                Button(suggestion) { title = suggestion }
                            }
                        } label: {
                            Image(systemName: "text.badge.plus")
                        }
                        .accessibilityLabel("Common appointments")
                    }
                    DateField("Date & time", selection: $date)
                }

                Section {
                    TextField("Doctor or provider", text: $provider)
                        .textContentType(.name)
                    HStack {
                        TextField("Location", text: typedLocation)
                            .textContentType(.location)
                            .submitLabel(.done)
                            // Keeps it as typed.
                            .onSubmit { placeSearch.clear() }
                        if !recentPlaces.isEmpty {
                            RecentPlacesMenu(places: recentPlaces, accessibilityLabel: String(localized: "Places used before"), onPick: use)
                        }
                    }
                    ForEach(placeSearch.suggestions) { suggestion in
                        PlaceSuggestionRow(suggestion: suggestion) { pick(suggestion) }
                    }
                    if placeSearch.isLookingUp {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Finding the place")
                    } else if placeSearch.lookupFailed {
                        NoticeLabel("Couldn't find that place in Maps right now. It's kept as typed.", systemImage: "mappin.slash", tint: Palette.inactive)
                            .font(.subheadline)
                    }
                    if let place {
                        AppointmentPlaceCard(place: place)
                    }
                } footer: {
                    Text(PlaceSearch.privacyNote)
                }

                Section {
                    Picker("Reminder", selection: $reminderMinutes) {
                        ForEach(Appointment.reminderOptions) { option in
                            Text(option.title).tag(option.minutes)
                        }
                    }
                }

                if !isCancelled {
                    AddToCalendarSection(
                        makeDraft: {
                            CalendarEventDraft(
                                title: title,
                                date: date,
                                provider: provider,
                                location: location,
                                babyName: (appointment?.baby ?? Baby.current(in: context))?.displayName,
                                address: place?.address ?? "",
                                coordinate: place?.coordinate
                            )
                        },
                        hasReminder: reminderMinutes != nil
                    )
                }

                questionsSection

                Section("Notes") {
                    TextField("Weight, length, what the doctor said…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                // View-only family can read a recap, but not start one. A cancelled visit has none.
                if let appointment, appointment.date < .now, !isCancelled, canEditLog || appointment.hasRecap {
                    Section {
                        Button {
                            recapping = true
                        } label: {
                            Label(appointment.hasRecap ? "How it went" : "How did it go?", systemImage: "text.bubble")
                        }
                    } footer: {
                        Text(appointment.recapSummary(units: .current)
                             ?? String(localized: "Add what the doctor said, measurements or shots from the visit."))
                    }
                    .sheet(isPresented: $recapping, onDismiss: {
                        // The recap may have checked questions off; Save here shouldn't undo that.
                        questions = appointment.questionList
                    }) {
                        VisitRecapView(appointment: appointment)
                    }
                }

                if let appointment, !isCancelled {
                    Section {
                        NavigationLink {
                            VisitSummaryView(appointment: appointment, questions: allQuestions)
                        } label: {
                            Label("Visit summary", systemImage: "doc.text")
                        }
                    } footer: {
                        Text("What's happened since the last appointment, to share with your pediatrician as a PDF.")
                    }
                }

                // Separate from Delete: cancelling keeps it, struck through, to restore later.
                if let appointment, canEditLog, !isCancelled, !appointment.hasRecap {
                    Section {
                        Button {
                            confirmingCancel = true
                        } label: {
                            Label("Cancel appointment", systemImage: "calendar.badge.minus")
                        }
                        .cancelAppointmentDialog(isPresented: $confirmingCancel) {
                            appointment.cancel(in: context)
                            dismiss()
                        }
                    } footer: {
                        Text("Keeps it in the list, struck through, with no reminder. You can restore it.")
                    }
                }

                if let appointment, canEditLog {
                    Section {
                        Button("Delete appointment", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Delete this appointment?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                NotificationManager.cancel(appointment.notificationID)
                                context.delete(appointment)
                                context.saveIfChanged()
                                dismiss()
                            }
                        } message: {
                            Text("Its questions and notes are deleted too.")
                        }
                    }
                }
            }
            .navigationTitle(appointment == nil ? "New appointment" : "Edit appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canEditLog)
                }
            }
            .onAppear(perform: load)
            .onDisappear { placeSearch.cancel() }
        }
        .threeAMSheet()
    }

    // MARK: Questions

    /// "Questions to ask": check each one off at the visit, swipe to delete.
    private var questionsSection: some View {
        Section {
            ForEach($questions) { $question in
                Button {
                    question.isAsked.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: question.isAsked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(question.isAsked ? Color.accentColor : Color.secondary)
                        Text(question.text)
                            .strikethrough(question.isAsked)
                            .foregroundStyle(question.isAsked ? Color.secondary : Color.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(question.isAsked ? "Asked" : "Not asked yet")
                .accessibilityHint("Checks the question off")
            }
            .onDelete { questions.remove(atOffsets: $0) }

            HStack {
                TextField("Add a question", text: $newQuestion)
                    .submitLabel(.done)
                    .onSubmit(addQuestion)
                Button(action: addQuestion) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(trimmedNewQuestion.isEmpty)
                .accessibilityLabel("Add question")
            }
        } header: {
            Text("Questions to ask")
        } footer: {
            Text(tookPendingQuestions
                 ? "Includes the questions you saved for the next visit."
                 : "Tap a question to check it off at the visit. Swipe left to delete.")
        }
    }

    private var trimmedNewQuestion: String {
        newQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The list, plus a question that's typed but not added yet, so Save doesn't lose it.
    private var allQuestions: [VisitQuestion] {
        trimmedNewQuestion.isEmpty ? questions : questions + [VisitQuestion(text: trimmedNewQuestion)]
    }

    private func addQuestion() {
        guard !trimmedNewQuestion.isEmpty else { return }
        questions.append(VisitQuestion(text: trimmedNewQuestion))
        newQuestion = ""
    }

    // MARK: Place

    /// The location field. Only the parent's own edits search; filling it in here (opening the
    /// appointment, picking a suggestion) never sends anything.
    private var typedLocation: Binding<String> {
        Binding(
            get: { location },
            set: { typed in
                guard typed != location else { return }
                location = typed
                place = nil
                placeSearch.update(query: typed)
            }
        )
    }

    /// Uses a suggestion: its name goes in the field right away, then its address, map and phone
    /// once Apple Maps has them.
    private func pick(_ suggestion: PlaceSearch.Suggestion) {
        location = suggestion.title
        place = nil
        Task {
            guard let found = await placeSearch.place(for: suggestion) else { return }
            // Unless the parent typed something else meanwhile.
            guard location == suggestion.title else { return }
            location = found.name
            place = found
            placeSearch.bias(toward: found.coordinate)
        }
    }

    /// Uses a place picked before, as it was saved; nothing is looked up again.
    private func use(_ recent: AppointmentPlace) {
        placeSearch.clear()
        location = recent.name
        place = recent
        placeSearch.bias(toward: recent.coordinate)
    }

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        recentPlaces = AppointmentPlace.recent(in: context)
        guard let appointment else {
            if let baby = Baby.current(in: context), !baby.pendingQuestionList.isEmpty {
                questions = baby.pendingQuestionList
                tookPendingQuestions = true
            }
            if let template {
                title = Appointment.nextTitle(after: template.title)
                provider = template.provider
                location = template.location
                place = template.place
                reminderMinutes = template.reminderMinutes
            }
            placeSearch.bias(toward: place?.coordinate ?? recentPlaces.first?.coordinate)
            return
        }
        title = appointment.title
        date = appointment.date
        provider = appointment.provider
        location = appointment.location
        place = appointment.place
        placeSearch.bias(toward: place?.coordinate ?? recentPlaces.first?.coordinate)
        notes = appointment.notes
        reminderMinutes = appointment.reminderMinutes
        questions = appointment.questionList
        isCancelled = appointment.isCancelled
    }

    private func save() {
        let target = appointment ?? Appointment.create(in: context)
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.date = date
        target.provider = provider.trimmingCharacters(in: .whitespaces)
        target.location = location.trimmingCharacters(in: .whitespaces)
        target.setPlace(target.location.isEmpty ? nil : place)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.reminderMinutes = reminderMinutes
        target.questionList = allQuestions
        if tookPendingQuestions {
            // They've moved into this appointment.
            target.baby?.pendingQuestions = ""
        }
        context.saveIfChanged()
        NotificationManager.scheduleReminder(for: target)
        dismiss()
    }
}

private extension View {
    /// Asks before cancelling an appointment. The way out says "Keep it" rather than "Cancel", which
    /// would read as the action itself.
    func cancelAppointmentDialog(isPresented: Binding<Bool>, perform: @escaping () -> Void) -> some View {
        confirmationDialog("Cancel this appointment?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Cancel appointment", role: .destructive, action: perform)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(AppointmentEditor.cancelMessage)
        }
    }

    /// The same, for an appointment picked from the list.
    func cancelAppointmentDialog(item: Binding<Appointment?>, perform: @escaping (Appointment) -> Void) -> some View {
        confirmationDialog(
            "Cancel this appointment?",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: item.wrappedValue
        ) { appointment in
            Button("Cancel appointment", role: .destructive) { perform(appointment) }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text(AppointmentEditor.cancelMessage)
        }
    }
}

extension AppointmentEditor {
    static let cancelMessage = String(localized: "Its reminder is turned off, and it's taken out of your calendar if MyBaby added it. It stays in the list, so you can restore it.")
}
