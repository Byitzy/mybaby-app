import CoreData
import SwiftUI
import UIKit

/// Settings › *After vaccines*, on each phone: the optional heads-up the morning a later reaction can
/// start after a vaccine (`VaccineFollowUp.refresh`). Off by default. Today's card after the shots
/// shows either way.
struct VaccineFollowUpReminderSection: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.vaccineFollowUpReminder) private var enabled = false
    @State private var showingPermissionAlert = false

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("After vaccines")
                    Text("A heads-up when a later reaction can start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("At \(reminderTime) on the day a fever or rash can start after MMR (about a week after), or the bump after BCG (about 2 weeks after), with what's normal. Today shows what to look out for after any vaccine either way.", comment: "Settings footer; a time of day, like 9:00 AM")
        }
        .onChange(of: enabled) { _, isOn in
            guard isOn else {
                VaccineFollowUp.refresh(context: context)
                return
            }
            Task {
                if await NotificationManager.requestAuthorization() {
                    VaccineFollowUp.refresh(context: context)
                } else {
                    enabled = false
                    showingPermissionAlert = true
                }
            }
        }
        .alert("Notifications are off", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow notifications for MyBaby in the Settings app to get reminders.")
        }
    }

    /// "9:00 AM", or "09:00", as the iPhone writes times.
    private var reminderTime: String {
        let calendar = Calendar.current
        let time = calendar.date(bySettingHour: VaccineFollowUp.reminderHour, minute: 0, second: 0, of: .now) ?? .now
        return time.formatted(date: .omitted, time: .shortened)
    }
}
