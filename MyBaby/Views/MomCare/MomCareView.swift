import Charts
import CoreData
import SwiftUI
import UIKit

/// The screen's old name, kept so existing references still build. Use `ParentCareView`.
typealias MomCareView = ParentCareView

/// Parent care, titled after whoever this iPhone belongs to ("Sam's care", or "My care"; see
/// `CareTitle`): a daily check-in, your medicines and a 14-day mood chart, with gentle support when
/// things feel hard, for any parent. Birth recovery notes (bleeding, healing) only show when
/// "I gave birth" is on. Pushed from More.
///
/// Private to the parent using this iPhone: entries aren't linked to the baby, so they stay out of
/// the shared log, the baby's exports and the PDF report (see `CareEntry`).
struct ParentCareView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: CareEntry.fetchAll(.mood)) private var checkIns: FetchedResults<CareEntry>
    @FetchRequest(fetchRequest: CareEntry.fetchAll(.medication)) private var medicines: FetchedResults<CareEntry>
    @FetchRequest(fetchRequest: CareEntry.fetchAll(.recovery)) private var recoveryNotes: FetchedResults<CareEntry>
    @AppStorage(SettingsKey.momCheckInReminder) private var reminderOn = false
    @AppStorage(SettingsKey.momCheckInReminderMinutes) private var reminderMinutes = MomCareReminder.defaultMinutes
    /// Not set until the switch is used; see `showsBirthRecovery`.
    @AppStorage(SettingsKey.gaveBirth) private var gaveBirth: Bool?
    /// For the title, which follows the names and who this iPhone belongs to.
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()

    @State private var addingRecoveryNote = false
    @State private var toast: Toast?
    @State private var share: SharePayload?
    @State private var exportError: String?
    @State private var showingPermissionAlert = false

    var body: some View {
        let todaysCheckIn = checkIns.first { Calendar.current.isDateInToday($0.date) }

        List {
            Section {
                MomPrivacyNote()
            } header: {
                Text("Recovery and wellbeing, just for you")
                    .textCase(nil)
            }

            if MomSupport.mostlyLowMood(Array(checkIns)) {
                Section {
                    GentleSupportCard()
                }
            }

            // Starts over from the saved check-in once there is one, and again the next day.
            DailyCheckIn(existing: todaysCheckIn) { message in
                toast = Toast(message: message)
            }
            .id(todaysCheckIn?.objectID)

            Section {
                MoodChart(checkIns: Array(checkIns))
            } header: {
                Text("Mood, last 14 days")
            }

            Section {
                NavigationLink {
                    MomMedicinesView()
                } label: {
                    LabeledContent {
                        Text(medicineSummary)
                    } label: {
                        Label("My medicines", systemImage: "pills")
                    }
                }
                NavigationLink {
                    CareLogList(kind: .mood)
                } label: {
                    LabeledContent {
                        Text("\(checkIns.count)")
                    } label: {
                        Label("Past check-ins", systemImage: "calendar")
                    }
                }
            } header: {
                Text("Your care")
            }

            birthRecoverySections

            Section {
                Toggle("Daily check-in reminder", isOn: $reminderOn)
                if reminderOn {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminder")
            } footer: {
                Text("A gentle nudge once a day. The notification only says it's time to check in, never how you've been feeling.")
            }

            SupportResourcesSections()

            Section {
                Button {
                    exportCareLog()
                } label: {
                    Label("Export my care log (CSV)", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Your check-ins, medicines and any recovery notes as a spreadsheet, to keep or to show your doctor or midwife. It's separate from the baby's export, which never includes them.")
            }

            Section {
                Text("This is a private journal for you, not medical advice. If something doesn't feel right, talk to your doctor or midwife, and call your local emergency number in an emergency.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(CareTitle.title(plan: NightPlan(data: nightPlanData)))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingRecoveryNote) {
            CareEntryEditor(kind: .recovery, entry: nil)
        }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: reminderOn) {
            refreshReminder()
        }
        .onChange(of: reminderMinutes) {
            refreshReminder()
        }
        .alert("Notifications are off", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow notifications for MyBaby in the Settings app to get a daily check-in reminder.")
        }
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .toast($toast)
    }

    /// "I gave birth", and when it's on, recovery after the birth: bleeding, stitches, healing.
    @ViewBuilder
    private var birthRecoverySections: some View {
        Section {
            Toggle("I gave birth", isOn: gaveBirthBinding)
        } footer: {
            Text("Turn this on for a place to note how you're healing after the birth, like pain, bleeding or stitches. It's only on this iPhone.")
        }

        if showsBirthRecovery {
            Section {
                Button {
                    addingRecoveryNote = true
                } label: {
                    Label("Add a recovery note", systemImage: "square.and.pencil")
                }
                NavigationLink {
                    CareLogList(kind: .recovery)
                } label: {
                    LabeledContent {
                        Text("\(recoveryNotes.count)")
                    } label: {
                        Label("Recovery notes", systemImage: "note.text")
                    }
                }
            } header: {
                Text("Birth recovery")
            }
        }
    }

    /// Off for someone new. Before the switch is used, it's on for anyone who already has recovery
    /// notes, so they don't disappear.
    private var showsBirthRecovery: Bool {
        gaveBirth ?? !recoveryNotes.isEmpty
    }

    private var gaveBirthBinding: Binding<Bool> {
        Binding(
            get: { showsBirthRecovery },
            set: { gaveBirth = $0 }
        )
    }

    /// "Ibuprofen 2h ago", or how many there are.
    private var medicineSummary: String {
        guard let latest = medicines.first else { return "None yet" }
        return "\(latest.title) · \(Format.timeAgo(latest.date).lowercased())"
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func refreshReminder() {
        Task {
            if !(await MomCareReminder.refresh()) {
                reminderOn = false
                showingPermissionAlert = true
            }
        }
    }

    private func exportCareLog() {
        do {
            let entries = Array(checkIns) + Array(medicines) + Array(recoveryNotes)
            let title = CareTitle.title(plan: NightPlan(data: nightPlanData))
            share = SharePayload(items: [try CareLogExport.write(entries, title: title)])
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// Today's check-in, right on the screen: a mood face, last night's sleep, pain and a note.
private struct DailyCheckIn: View {
    @Environment(\.managedObjectContext) private var context
    /// Today's check-in once it's saved, to update instead of adding another.
    let existing: CareEntry?
    let onSaved: (String) -> Void

    @State private var mood: Mood?
    @State private var sleepHours: Double?
    @State private var painLevel: Int?
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        Section {
            MoodPicker(selection: $mood)
                .padding(.vertical, 4)
            SleepStepper(title: "Sleep last night", hours: $sleepHours)
            PainPicker(level: $painLevel)
            TextField("Anything on your mind? (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...5)
            Button(existing == nil ? "Save check-in" : "Update check-in", action: save)
                .disabled(!canSave)
        } header: {
            Text("Today's check-in")
        } footer: {
            Text("Just for you. There are no right answers.")
        }
        .onAppear(perform: load)
    }

    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        mood != nil || sleepHours != nil || painLevel != nil || !trimmedNotes.isEmpty
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        mood = existing.mood
        sleepHours = existing.sleepHours
        painLevel = existing.painLevel
        notes = existing.notes
    }

    private func save() {
        let entry = existing ?? CareEntry.create(.mood, in: context)
        entry.mood = mood
        entry.sleepHours = sleepHours
        entry.painLevel = painLevel
        entry.notes = trimmedNotes
        context.saveIfChanged()
        onSaved(existing == nil ? "💛 Check-in saved" : "💛 Check-in updated")
    }
}

/// The mood faces of the last 14 days: one point a day, from that day's latest check-in.
private struct MoodChart: View {
    let checkIns: [CareEntry]

    private struct DayMood: Identifiable {
        let day: Date
        let mood: Mood
        var id: Date { day }
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let points = dailyMoods(from: start, calendar: calendar)

        if points.isEmpty {
            Text("Check in on a few days to see your mood over time here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Mood", point.mood.rawValue)
                )
                .foregroundStyle(Palette.momCare.opacity(0.5))
                .interpolationMethod(.monotone)
                // VoiceOver reads each day once, from its point.
                .accessibilityHidden(true)
                PointMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Mood", point.mood.rawValue)
                )
                .foregroundStyle(Palette.momCare)
                .accessibilityLabel(point.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .accessibilityValue(point.mood.title)
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(position: .leading, values: Mood.allCases.map(\.rawValue)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Int.self), let mood = Mood(rawValue: raw) {
                            Text(mood.emoji)
                                .accessibilityLabel(mood.title)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)
            .padding(.vertical, 8)
        }
    }

    /// The latest check-in of each day since `start`, oldest first.
    private func dailyMoods(from start: Date, calendar: Calendar) -> [DayMood] {
        var byDay: [Date: Mood] = [:]
        // Newest first, so the first one seen for a day is its latest.
        for entry in checkIns where entry.date >= start {
            guard let mood = entry.mood else { continue }
            let day = calendar.startOfDay(for: entry.date)
            if byDay[day] == nil { byDay[day] = mood }
        }
        return byDay
            .map { DayMood(day: $0.key, mood: $0.value) }
            .sorted { $0.day < $1.day }
    }
}
