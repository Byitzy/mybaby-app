import Foundation

/// The app's public web pages and support email, in one place.
///
/// The pages are the static site in `docs/`, published with GitHub Pages from the public repository's
/// `main` branch. The same URLs go in App Store Connect (Privacy Policy URL and Support URL), with the
/// French and Spanish ones in those localizations (`docs/app-store.md`).
enum AppLinks {
    static let website = URL(string: "https://byitzy.github.io/mybaby-app/")!

    /// The privacy policy, terms and support pages open in the language MyBaby is showing.
    static var privacyPolicy: URL { page("privacy.html") }
    static var terms: URL { page("terms.html") }
    static var support: URL { page("support.html") }

    static let supportEmail = "mybaby@manhattin.com"

    /// Opens a new email to `supportEmail` in the Mail app.
    static let supportEmailURL = URL(string: "mailto:\(supportEmail)")!

    /// Where Send feedback addresses its email (see `FeedbackView`).
    static let feedbackEmail = "mybaby@manhattin.com"

    /// French and Spanish have their own copies of each page under `fr/` and `es/`. Every other language gets
    /// the English pages, which keep their original URLs.
    ///
    /// The language comes from `Bundle.main.preferredLocalizations`, the one the app's text is actually in. It
    /// can differ from the iPhone's first language: a German iPhone with French as its second language shows
    /// MyBaby in French, and iPhone Settings › MyBaby › Language can set one for MyBaby alone.
    private static func page(_ name: String) -> URL {
        let language = Bundle.main.preferredLocalizations.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        let folder: String
        switch language {
        case "fr": folder = "fr/"
        case "es": folder = "es/"
        default: folder = ""
        }
        return URL(string: "https://byitzy.github.io/mybaby-app/\(folder)\(name)")!
    }
}
