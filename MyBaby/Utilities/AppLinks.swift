import Foundation

/// The app's public web pages and support email, in one place.
///
/// The pages are the static site in `docs/`, published with GitHub Pages from the public repository's
/// `main` branch. The same URLs go in App Store Connect (Privacy Policy URL and Support URL).
enum AppLinks {
    static let website = URL(string: "https://byitzy.github.io/mybaby-app/")!
    static let privacyPolicy = URL(string: "https://byitzy.github.io/mybaby-app/privacy.html")!
    static let support = URL(string: "https://byitzy.github.io/mybaby-app/support.html")!

    static let supportEmail = "mybaby@manhattin.com"

    /// Opens a new email to `supportEmail` in the Mail app.
    static let supportEmailURL = URL(string: "mailto:\(supportEmail)")!

    /// Where Send feedback addresses its email (see `FeedbackView`).
    static let feedbackEmail = "mybaby@manhattin.com"
}
