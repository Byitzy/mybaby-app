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

    /// Where a quick question goes: the next appointment, if there is one.
    private var nextAppointment: Appointment? {
        let cutoff = upcomingCutoff
        return appointments.first { $0.date >= cutoff }
    }

    var body: some View {
        let cutoff = upcomingCutoff
        let upcoming = appointments.filter { $0.date >= cutoff }
        let past = appointments.filter { $0.date < cutoff }.reversed()
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
        .addToCalendarSheet($calendarDraft) { toast = Toast(message: "Added to your calendar") }
        .sheet(item: $recapFor) { appointment in
            VisitRecapView(appointment: appointment)
        }
        .toast($toast)
    }

    private var questionDestination: String {
        guard let next = nextAppointment else {
            return "No appointment is scheduled, so it's kept here until you add one."
        }
        let when = next.date.formatted(.dateTime.month(.abbreviated).day())
        return "It's added to \(next.title.isEmpty ? "the appointment" : next.title) on \(when)."
    }

    private func addQuestion() {
        let question = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        questionDraft = ""
        guard !question.isEmpty else { return }
        if let next = nextAppointment {
            next.questions = VisitQuestions.appending(question, to: next.questions)
            toast = Toast(message: "Added to \(next.title.isEmpty ? "the next appointment" : next.title)")
        } else {
            baby.pendingQuestions = VisitQuestions.appending(question, to: baby.pendingQuestions)
            toast = Toast(message: "Saved for the next visit")
        }
        context.saveIfChanged()
    }

    private func row(_ appointment: Appointment) -> some View {
        Button {
            editing = appointment
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(appointment.date, format: .dateTime.month(.abbreviated))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.appointment)
                        .textCase(.uppercase)
                    Text(appointment.date, format: .dateTime.day())
                        .font(.title2.weight(.semibold))
                }
                // Grows with the text instead of clipping it.
                .padding(.vertical, Spacing.xs)
                .frame(minWidth: 48, minHeight: 52)
                .background(Palette.appointment.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.badge))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(appointment.title.isEmpty ? "Appointment" : appointment.title)
                        .font(.body.weight(.medium))
                    Text(appointment.date, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    let place = [appointment.provider, appointment.location].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !place.isEmpty {
                        Text(place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let toAsk = appointment.questionList.filter { !$0.isAsked }.count
                    if toAsk > 0 && appointment.date >= upcomingCutoff {
                        Label(Format.plural(toAsk, "question") + " to ask", systemImage: "questionmark.bubble")
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
                if appointment.reminderMinutes != nil && appointment.date > .now {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Reminder on")
                }
            }
            // "2-month checkup, Tuesday 9:30 AM, Dr. Lee, 2 questions to ask, reminder on".
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
            Button("Visit summary", systemImage: "doc.text") {
                summaryFor = appointment
            }
            .tint(.accentColor)
        }
        .contextMenu {
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
        }
    }

    /// A gentle "How did it go?" under a visit from the last two weeks that has no recap yet.
    /// Older ones can still be recapped from the appointment or its menu.
    private func showsRecapButton(_ appointment: Appointment) -> Bool {
        canEditLog && !appointment.hasRecap
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
    @State private var notes = ""
    @State private var reminderMinutes: Int? = 60
    @State private var questions: [VisitQuestion] = []
    @State private var newQuestion = ""
    /// A new appointment starts with the questions saved while none was scheduled.
    @State private var tookPendingQuestions = false
    @State private var didLoad = false
    @State private var confirmingDelete = false
    @State private var recapping = false

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this appointment, but only the parents can save changes.") }
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
                    TextField("Location", text: $location)
                        .textContentType(.fullStreetAddress)
                }

                Section {
                    Picker("Reminder", selection: $reminderMinutes) {
                        ForEach(Appointment.reminderOptions) { option in
                            Text(option.title).tag(option.minutes)
                        }
                    }
                }

                AddToCalendarSection(
                    makeDraft: {
                        CalendarEventDraft(
                            title: title,
                            date: date,
                            provider: provider,
                            location: location,
                            babyName: (appointment?.baby ?? Baby.current(in: context))?.displayName
                        )
                    },
                    hasReminder: reminderMinutes != nil
                )

                questionsSection

                Section("Notes") {
                    TextField("Weight, length, what the doctor said…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                // View-only family can read a recap, but not start one.
                if let appointment, appointment.date < .now, canEditLog || appointment.hasRecap {
                    Section {
                        Button {
                            recapping = true
                        } label: {
                            Label(appointment.hasRecap ? "How it went" : "How did it go?", systemImage: "text.bubble")
                        }
                    } footer: {
                        Text(appointment.recapSummary(units: .current)
                             ?? "Add what the doctor said, measurements or shots from the visit.")
                    }
                    .sheet(isPresented: $recapping, onDismiss: {
                        // The recap may have checked questions off; Save here shouldn't undo that.
                        questions = appointment.questionList
                    }) {
                        VisitRecapView(appointment: appointment)
                    }
                }

                if let appointment {
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

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let appointment else {
            if let baby = Baby.current(in: context), !baby.pendingQuestionList.isEmpty {
                questions = baby.pendingQuestionList
                tookPendingQuestions = true
            }
            if let template {
                title = Appointment.nextTitle(after: template.title)
                provider = template.provider
                location = template.location
                reminderMinutes = template.reminderMinutes
            }
            return
        }
        title = appointment.title
        date = appointment.date
        provider = appointment.provider
        location = appointment.location
        notes = appointment.notes
        reminderMinutes = appointment.reminderMinutes
        questions = appointment.questionList
    }

    private func save() {
        let target = appointment ?? Appointment.create(in: context)
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.date = date
        target.provider = provider.trimmingCharacters(in: .whitespaces)
        target.location = location.trimmingCharacters(in: .whitespaces)
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
