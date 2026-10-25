import SwiftUI

/// Where the baby's data is kept, and who can see it.
struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Text("MyBaby has no servers, no analytics and no third-party code. The developers never receive any of your baby's data.")
            }

            Section("Where your log is kept") {
                item(
                    "On this iPhone",
                    systemImage: "iphone",
                    "Until you turn on iCloud sync, the log is only on this iPhone."
                )
                item(
                    "In your iCloud",
                    systemImage: "icloud",
                    "With sync on, the log is also in your own iCloud, end-to-end encrypted. The keys are in your iCloud Keychain, so Apple can't read it. Delete my iCloud copy in Settings removes it from iCloud and keeps the copy on this iPhone."
                )
                item(
                    "Shared with your partner",
                    systemImage: "person.2",
                    "A shared log lives in the iCloud of the parent who created it. Only people you invite can see it, and the invited parent can read and add to it. You can remove someone, or leave a shared log, in Manage sharing."
                )
            }

            Section("Other things to know") {
                item(
                    "Exports and reports",
                    systemImage: "square.and.arrow.up",
                    "CSV exports, the PDF report and the allergy card go wherever you send them. The temporary copies are deleted from the iPhone when the share sheet closes."
                )
                item(
                    "Cry alerts",
                    systemImage: "ear",
                    "Listening happens on this iPhone. The audio never leaves the phone and is never recorded or stored."
                )
                item(
                    "Nursery monitor",
                    systemImage: "dot.radiowaves.left.and.right",
                    "A spare device used as the monitor listens on the device too, and the audio never leaves it. Its alerts travel as small encrypted records in your family's own iCloud, holding only the time and how long the crying has gone on, and are deleted after an hour. Its white noise is made on the device."
                )
                item(
                    "Calendar",
                    systemImage: "calendar",
                    "Appointments you add to your calendar, one at a time or with Keep appointments in my calendar, are stored by your calendar's provider (such as iCloud, Google or Outlook), outside MyBaby's end-to-end encryption. Notes and questions aren't copied."
                )
                item(
                    "Apple Watch",
                    systemImage: "applewatch",
                    "The watch app gets a short summary from this iPhone, and sends your taps back, directly over Apple's WatchConnectivity. No server is involved."
                )
                item(
                    "Feedback",
                    systemImage: "text.bubble",
                    "Send feedback fills in an email from your own account. Only you can send it, after seeing everything in it. The optional technical details never include names, dates or anything from your log. Crash reports from iOS stay on this iPhone unless you attach one, and are deleted after 30 days."
                )
                item(
                    "What Apple sees",
                    systemImage: "eye.slash",
                    "Apple still sees some details that aren't the log itself, such as how much is stored, when your devices sync and the name of a shared log."
                )
                item(
                    "If you reset iCloud Keychain",
                    systemImage: "key",
                    "The encrypted data in iCloud can't be recovered without the keys. The copy on your iPhone is still there."
                )
            }

            Section {
                Link(destination: AppLinks.privacyPolicy) {
                    Label("Full privacy policy", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ title: String, systemImage: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
}
