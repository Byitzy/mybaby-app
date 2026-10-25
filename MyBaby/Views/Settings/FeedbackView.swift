import MessageUI
import PhotosUI
import StoreKit
import SwiftUI
import UIKit

/// Send feedback: what it's about, a message, an optional screenshot, and optional technical
/// details, sent as an email from the parent's own account.
///
/// There's no server: the app only fills in an email, which the parent reads, can change, and sends
/// themselves (or doesn't). Nothing is sent from the app by itself. When Mail isn't set up, it
/// opens a `mailto:` link in another email app instead, or copies the message.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    /// The app version the parent was last asked to rate, so it's asked at most once per version.
    @AppStorage(FeedbackView.ratedVersionKey) private var ratedVersion = ""

    @State private var kind: FeedbackKind?
    @State private var message = ""
    @State private var includeDetails = true
    @State private var showingDetails = false
    @State private var diagnostics: FeedbackDiagnostics?
    @State private var screenshotItem: PhotosPickerItem?
    @State private var screenshot: Screenshot?
    @State private var isLoadingScreenshot = false
    @State private var crashReports: [CrashReports.Report] = []
    @State private var attachCrashReport = false
    /// Asked for a rating on this screen, for the thank-you in its place.
    @State private var askedForRating = false
    @State private var composing = false
    /// What to say once Mail has closed: thanks, or why it couldn't send.
    @State private var afterMail: FeedbackAlert?
    @State private var copied = false
    @State private var alert: FeedbackAlert?
    @FocusState private var messageFocused: Bool

    static let ratedVersionKey = "feedbackRatedVersion"

    init(kind: FeedbackKind? = nil) {
        _kind = State(initialValue: kind)
    }

    /// The screenshot the parent picked, already smaller and without its location.
    private struct Screenshot {
        let jpeg: Data
        let thumbnail: UIImage
    }

    private struct FeedbackAlert {
        let title: String
        let message: String
        /// Closes Send feedback on OK, after the email was sent.
        var closesScreen = false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Feedback goes by email from your own account, so you'll see exactly what's sent. Nothing is sent from the app by itself.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "envelope")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                kindSection

                if kind == .love, ratedVersion != appVersion || askedForRating {
                    ratingSection
                }

                Section {
                    TextField(kind?.placeholder ?? "Tell us what's on your mind.", text: $message, axis: .vertical)
                        .lineLimit(5...12)
                        .textInputAutocapitalization(.sentences)
                        .focused($messageFocused)
                } header: {
                    Text("Your message")
                } footer: {
                    Text("Please leave out your baby's name and any health details you'd rather keep private. We don't need them to help.")
                }

                screenshotSection

                if kind == .problem, let latest = crashReports.first {
                    crashReportSection(latest: latest)
                }

                detailsSection

                sendSection
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { messageFocused = false }
                }
            }
            .interactiveDismissDisabled(!message.isEmpty || screenshot != nil)
            .onAppear {
                if diagnostics == nil { diagnostics = FeedbackDiagnostics.current() }
                crashReports = CrashReports.shared.reports
            }
            .onChange(of: screenshotItem) { _, item in
                guard let item else { return }
                Task { await loadScreenshot(item) }
            }
            .onChange(of: message) { copied = false }
            .onChange(of: includeDetails) { copied = false }
            // An alert can't show while Mail is still closing, so it waits until Mail has gone.
            .sheet(isPresented: $composing, onDismiss: {
                alert = afterMail
                afterMail = nil
            }) {
                MailComposeView(email: email, attachments: attachments) { result, error in
                    switch result {
                    case .sent:
                        afterMail = FeedbackAlert(
                            title: "Thank you",
                            message: "Your feedback is on its way. It helps make MyBaby better for every family.",
                            closesScreen: true
                        )
                    case .failed:
                        afterMail = FeedbackAlert(
                            title: "Couldn't send",
                            message: error?.localizedDescription ?? "Mail couldn't send the email. Please try again."
                        )
                    default:
                        // Cancelled, or saved as a draft in Mail: the message stays here too.
                        afterMail = nil
                    }
                    composing = false
                }
                .ignoresSafeArea()
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
                presenting: alert
            ) { shown in
                Button("OK", role: .cancel) {
                    if shown.closesScreen { dismiss() }
                }
            } message: { shown in
                Text(shown.message)
            }
        }
        .threeAMSheet()
    }

    // MARK: Sections

    private var kindSection: some View {
        Section("What's it about?") {
            ForEach(FeedbackKind.allCases) { option in
                let isSelected = kind == option
                Button {
                    kind = option
                } label: {
                    HStack {
                        Label(option.title, systemImage: option.systemImage)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var ratingSection: some View {
        Section {
            if askedForRating {
                Label("Thank you for thinking of us!", systemImage: "star.fill")
            } else {
                Text("Would you rate MyBaby on the App Store?")
                Button {
                    ratedVersion = appVersion
                    askedForRating = true
                    requestReview()
                } label: {
                    Label("Rate MyBaby", systemImage: "star")
                }
            }
        } footer: {
            Text("Ratings help other parents find MyBaby. You can also tell us what you love below.")
        }
    }

    private var screenshotSection: some View {
        Section {
            if let screenshot {
                Image(uiImage: screenshot.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityLabel("Your screenshot")
                Button(role: .destructive) {
                    self.screenshot = nil
                } label: {
                    Label("Remove screenshot", systemImage: "trash")
                }
            }
            if isLoadingScreenshot {
                HStack(spacing: Spacing.m) {
                    ProgressView()
                    Text("Adding screenshot…")
                        .foregroundStyle(.secondary)
                }
            } else {
                PhotosPicker(selection: $screenshotItem, matching: .images) {
                    Label(screenshot == nil ? "Add a screenshot" : "Choose a different screenshot", systemImage: "photo")
                }
            }
        } header: {
            Text("Screenshot (optional)")
        } footer: {
            Text("Only the picture you choose is added, a little smaller and without its location.")
        }
    }

    private func crashReportSection(latest: CrashReports.Report) -> some View {
        let count = crashReports.count
        let date = latest.receivedAt.formatted(date: .abbreviated, time: .omitted)
        return Section {
            Toggle("Attach the latest crash report (\(count))", isOn: $attachCrashReport)
        } footer: {
            Text("MyBaby stopped or froze \(count == 1 ? "once" : "\(count) times") recently, the latest on \(date). The report holds technical details about where the app stopped, and nothing from your log. It's attached as a file you can open before sending.")
        }
    }

    private var detailsSection: some View {
        Section {
            Toggle("Include technical details", isOn: $includeDetails)
            DisclosureGroup("See what's included", isExpanded: $showingDetails) {
                Text(diagnostics?.text ?? "")
                    .font(.footnote.monospaced())
                    .foregroundStyle(includeDetails ? Color.primary : Color.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            Text("Versions, the iPhone model, language and region, and which features are on help us find problems. Never names, birthdays, anything you've logged, photos or your Apple ID.")
        }
    }

    private var sendSection: some View {
        Section {
            Button(action: send) {
                Label(canUseMail ? "Write email" : "Open in email app", systemImage: "paperplane")
            }
            .disabled(!canSend)
            if !canUseMail {
                Button {
                    UIPasteboard.general.string = email.plainText
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy message", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(!canSend)
            }
        } footer: {
            Text(sendFooter)
        }
    }

    // MARK: The email

    private var appVersion: String { FeedbackDiagnostics.currentAppVersion }

    private var canUseMail: Bool { MailComposeView.canSendMail }

    private var canSend: Bool {
        kind != nil && !isLoadingScreenshot && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendFooter: String {
        if kind == nil {
            return "Pick what it's about and write your message to continue."
        }
        if canUseMail {
            return "Mail opens with everything filled in, to \(AppLinks.feedbackEmail). You can change anything there before you tap Send."
        }
        var footer = "Mail isn't set up on this iPhone. Open in email app starts the message in another email app, or copy it and send it to \(AppLinks.feedbackEmail) from any email app."
        if screenshot != nil || (kind == .problem && attachCrashReport) {
            footer += " Attachments can't be added this way, so attach the screenshot yourself if you'd like."
        }
        return footer
    }

    private var email: FeedbackEmail {
        FeedbackEmail.make(
            kind: kind ?? .question,
            message: message,
            diagnostics: includeDetails ? diagnostics : nil,
            version: FeedbackDiagnostics.currentAppVersion,
            build: FeedbackDiagnostics.currentAppBuild
        )
    }

    private var attachments: [MailComposeView.Attachment] {
        var attachments: [MailComposeView.Attachment] = []
        if let screenshot {
            attachments.append(.init(data: screenshot.jpeg, mimeType: "image/jpeg", fileName: "Screenshot.jpg"))
        }
        if kind == .problem, attachCrashReport, let latest = crashReports.first {
            attachments.append(.init(data: latest.json, mimeType: "application/json", fileName: "MyBaby-crash-report.json"))
        }
        return attachments
    }

    private func send() {
        messageFocused = false
        // The details as they are now, in case something changed while the parent was writing.
        diagnostics = FeedbackDiagnostics.current()
        if canUseMail {
            afterMail = nil
            composing = true
        } else if let url = email.mailtoURL {
            openURL(url) { accepted in
                if !accepted {
                    alert = FeedbackAlert(
                        title: "No email app found",
                        message: "Tap Copy message, then send it to \(AppLinks.feedbackEmail) from any email app or website."
                    )
                }
            }
        }
    }

    // MARK: Screenshot

    private func loadScreenshot(_ item: PhotosPickerItem) async {
        isLoadingScreenshot = true
        let data = try? await item.loadTransferable(type: Data.self)
        let prepared = await Task.detached(priority: .userInitiated) { () -> Screenshot? in
            guard let data,
                  let jpeg = MilestoneImages.storableJPEG(from: data),
                  let thumbnail = MilestoneImages.downsample(jpeg, maxPixelSize: 600)
            else { return nil }
            return Screenshot(jpeg: jpeg, thumbnail: UIImage(cgImage: thumbnail))
        }.value
        if let prepared {
            screenshot = prepared
        } else {
            alert = FeedbackAlert(
                title: "Couldn't add the screenshot",
                message: "It couldn't be read. If it's in iCloud Photos, check that you're online and try again."
            )
        }
        isLoadingScreenshot = false
        screenshotItem = nil
    }
}

/// The "Send feedback" row in Settings › Help & support, which opens `FeedbackView`.
struct FeedbackRow: View {
    @State private var showingFeedback = false

    var body: some View {
        Button {
            showingFeedback = true
        } label: {
            Label("Send feedback", systemImage: "text.bubble")
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackView()
        }
    }
}

// MARK: - Mail

/// Apple's Mail compose screen, filled in with a feedback email the parent can change before sending.
struct MailComposeView: UIViewControllerRepresentable {
    struct Attachment {
        let data: Data
        let mimeType: String
        let fileName: String
    }

    let email: FeedbackEmail
    let attachments: [Attachment]
    /// Called once Mail is done: sent, saved as a draft, cancelled or failed.
    let onFinish: (MFMailComposeResult, Error?) -> Void

    /// False when no Mail account is set up on this iPhone.
    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([email.recipient])
        controller.setSubject(email.subject)
        controller.setMessageBody(email.body, isHTML: false)
        for attachment in attachments {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Error?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result, error)
        }
    }
}

#Preview {
    FeedbackView(kind: .love)
}
