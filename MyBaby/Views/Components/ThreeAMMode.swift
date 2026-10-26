import SwiftUI

/// "3 AM mode": a dim, dark red look for night feeds that's easy on sleepy eyes and doesn't light
/// up the room. Red light is the least likely to wake you (or the baby) up properly.
enum ThreeAMMode: String, CaseIterable, Identifiable {
    case off
    /// During the night plan's hours, or 9 PM–7 AM without a plan.
    case atNight
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off", comment: "3 AM mode setting")
        case .atNight: return String(localized: "At night", comment: "3 AM mode setting: on during the night")
        case .always: return String(localized: "Always", comment: "3 AM mode setting")
        }
    }

    /// Whether the red look is on at `date`.
    func isActive(at date: Date, plan: NightPlan) -> Bool {
        switch self {
        case .off:
            return false
        case .always:
            return true
        case .atNight:
            if plan.isEnabled {
                return plan.shift(at: date) != nil
            }
            let minutes = date.minutesIntoDay
            return minutes >= 21 * 60 || minutes < 7 * 60
        }
    }
}

private enum ThreeAMStyle {
    /// Buttons and links: a deep red instead of the usual accent color.
    static let tint = Color(red: 0.78, green: 0.12, blue: 0.09)
    /// Multiplied over the dark screen, so white text turns a dim red and colors lose their blue and green.
    /// Bright enough in red that primary text stays readable (about 5:1 against the black
    /// background); secondary text is dimmer by design, so key information uses primary text.
    static let filter = Color(red: 0.95, green: 0.25, blue: 0.14)
}

private struct ThreeAMModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether 3 AM mode is on right now, so sheets can match.
    var isThreeAMMode: Bool {
        get { self[ThreeAMModeKey.self] }
        set { self[ThreeAMModeKey.self] = newValue }
    }
}

private struct ThreeAMLook: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(isOn ? .dark : nil)
            .tint(isOn ? ThreeAMStyle.tint : nil)
            .overlay {
                if isOn {
                    ThreeAMStyle.filter
                        .blendMode(.multiply)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .environment(\.isThreeAMMode, isOn)
    }
}

/// Sheets are drawn above the root view's red filter, so each one adds it again.
///
/// Every editor sheet already has this, so it also gives them their iPad size: a form sheet in the
/// middle of the screen, never full screen (see `formSheetSizing`).
private struct ThreeAMSheet: ViewModifier {
    @Environment(\.isThreeAMMode) private var isOn

    func body(content: Content) -> some View {
        content
            .modifier(ThreeAMLook(isOn: isOn))
            .formSheetSizing()
    }
}

extension View {
    /// The 3 AM look for the whole app, from the root view.
    func threeAMLook(_ isOn: Bool) -> some View {
        modifier(ThreeAMLook(isOn: isOn))
    }

    /// The same look inside a sheet, while 3 AM mode is on.
    func threeAMSheet() -> some View {
        modifier(ThreeAMSheet())
    }
}
