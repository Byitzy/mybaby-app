import Foundation

/// MyBaby's Terms of Use, which each person accepts on their own iPhone before using the app, and
/// again whenever they change.
///
/// The same text is on the website (`docs/terms.html`). When it changes, change both (and the
/// French and Spanish translations), set `effectiveDay`, and raise `version`: everyone is then asked
/// to agree again on their next launch. An app update that leaves the terms alone doesn't ask again.
enum TermsOfUse {
    /// Raise by one whenever the text changes.
    static let version = 1

    /// The day the current terms took effect.
    static let effectiveDay: Date = {
        let components = DateComponents(year: 2026, month: 10, day: 25)
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }()

    /// "October 25, 2026", written the way the iPhone's language and region write dates.
    static var effectiveDate: String {
        effectiveDay.formatted(date: .long, time: .omitted)
    }

    /// Kept in `UserDefaults.standard`, so it's per device and per person, never synced: a partner
    /// joining the log accepts on their own phone.
    static let acceptedVersionKey = "termsAcceptedVersion"
    static let acceptedAtKey = "termsAcceptedAt"

    static var acceptedVersion: Int {
        UserDefaults.standard.integer(forKey: acceptedVersionKey)
    }

    /// When the current terms were accepted on this device, for Settings.
    static var acceptedAt: Date? {
        guard acceptedVersion >= version else { return nil }
        return UserDefaults.standard.object(forKey: acceptedAtKey) as? Date
    }

    static func accept() {
        UserDefaults.standard.set(Date.now, forKey: acceptedAtKey)
        UserDefaults.standard.set(version, forKey: acceptedVersionKey)
    }

    struct Section: Identifiable {
        let title: String
        let paragraphs: [String]

        var id: String { title }
    }

    struct KeyPoint: Hashable {
        let systemImage: String
        let text: String
    }

    /// The points shown before the full text on the screen that asks to agree.
    static let keyPoints = [
        KeyPoint(systemImage: "stethoscope", text: String(localized: "MyBaby is a log and a set of tools, not medical advice. Always follow your baby's doctor, and in an emergency call your local emergency number.", comment: "Terms of Use: key point")),
        KeyPoint(systemImage: "waveform.badge.exclamationmark", text: String(localized: "Cry alerts, the nursery monitor and reminders can be late or miss something. They never replace watching your baby.", comment: "Terms of Use: key point")),
        KeyPoint(systemImage: "pills", text: String(localized: "Medicine timing shows what you enter. Check doses with your doctor or pharmacist.", comment: "Terms of Use: key point")),
        KeyPoint(systemImage: "lock", text: String(localized: "Your log stays on your devices and in your own iCloud. We never receive it.", comment: "Terms of Use: key point")),
    ]

    static let sections: [Section] = [
        Section(title: String(localized: "These terms", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "These terms are an agreement between you and the developer of MyBaby (“we”, “us”) for using the MyBaby app on iPhone, iPad and Apple Watch, with its widgets, Live Activities and Siri shortcuts. By tapping Agree, you accept them and the Privacy Policy.", comment: "Terms of Use. “Agree” is the button on the screen that asks to agree."),
            String(localized: "If you got MyBaby from the App Store, Apple's Licensed Application End User License Agreement also applies.", comment: "Terms of Use. Keep Apple's agreement name in English, as Apple publishes it."),
        ]),
        Section(title: String(localized: "MyBaby is not medical advice", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "MyBaby is a log and a set of tools for parents and caregivers. It isn't a medical device, and it doesn't diagnose, treat, monitor or prevent any illness or condition.", comment: "Terms of Use"),
            String(localized: "Growth charts and percentiles, feed and diaper predictions, patterns, medicine timing, temperatures, the allergy tools, the vaccine guide, summaries, reports and everything else in the app are general information, not medical advice. They can be incomplete, wrong or out of date.", comment: "Terms of Use"),
            String(localized: "Always follow the advice of your baby's doctor, nurse or pharmacist, and never delay getting care because of something in the app. If you think your baby or anyone else is in danger, call your local emergency number.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Medicine", comment: "Kind of log entry, or of allergy"), paragraphs: [
            String(localized: "MyBaby shows the medicines, doses and timing that you enter. It doesn't check whether a medicine or dose is right for your baby. Ask your doctor or pharmacist, and follow the label.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Cry alerts, the nursery monitor and reminders", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "Cry alerts and the nursery monitor are conveniences, not safety devices or baby monitors to rely on. They can miss crying, or alert late or not at all: for example during a phone call, with a low battery or a weak connection, in Silent mode or a Focus, or when iOS stops the app.", comment: "Terms of Use"),
            String(localized: "They don't monitor breathing, heart rate or movement, and they can't prevent sudden infant death syndrome (SIDS) or any other harm. Never leave a baby unsupervised because of them, and follow your health authority's safe-sleep advice.", comment: "Terms of Use"),
            String(localized: "Reminders and notifications can also be late or not arrive.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Your data", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "Your log stays on your devices and, if you turn it on, in your own iCloud account. We never receive it; the Privacy Policy explains how it's kept.", comment: "Terms of Use"),
            String(localized: "You're responsible for what you enter, for keeping a copy (Settings › Export all data), and for who you share your log with: anyone you invite can see and change it. Deleting MyBaby, or using Delete all MyBaby data, can't be undone.", comment: "Terms of Use. “Export all data” and “Delete all MyBaby data” are the names of buttons in Settings."),
        ]),
        Section(title: String(localized: "Using MyBaby", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "Use MyBaby lawfully, to care for your own family or the children you look after.", comment: "Terms of Use"),
            String(localized: "MyBaby's source code is published so anyone can see how it works. It isn't licensed for reuse; the license in the repository explains what's allowed.", comment: "Terms of Use"),
            String(localized: "MyBaby is free. We may change, pause or stop offering any feature, or the app, at any time.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "No warranty", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "MyBaby is provided “as is” and “as available”. To the fullest extent the law allows, we make no warranties of any kind, express or implied, including that it will be accurate, reliable, available, secure or free of errors, or fit for a particular purpose.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Limitation of liability", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "To the fullest extent the law allows, we aren't liable for any indirect, incidental, special or consequential damages, or for any loss or harm that comes from using or relying on MyBaby, including missed or late alerts and reminders, wrong or lost information, or decisions made using the app.", comment: "Terms of Use"),
            String(localized: "Where liability can't be excluded, it's limited to what you paid for the app, which is nothing.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Your rights under the law", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "Some places don't allow some of these exclusions or limits, so they may not all apply to you. Nothing in these terms takes away rights you have as a consumer that can't be waived where you live.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Changes to these terms", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "We may update these terms. When we do, MyBaby shows them again and asks you to agree before you keep using it. The date at the top says when they last changed.", comment: "Terms of Use"),
        ]),
        Section(title: String(localized: "Contact", comment: "Terms of Use: section title"), paragraphs: [
            String(localized: "Questions about these terms? Email \(AppLinks.supportEmail).", comment: "Terms of Use: the support email address"),
        ]),
    ]
}
