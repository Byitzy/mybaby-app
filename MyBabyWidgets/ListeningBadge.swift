import SwiftUI
import WidgetKit

/// The mic badge on the widgets while cry alerts listen on this iPhone (`WidgetSnapshot.Listening`):
/// "Listening", turning orange, "Crying", during a cry. It shows the app's state, whichever baby the
/// widget is set to.
///
/// The timeline stops showing it at the stop time (`WidgetSnapshot.activeListening(at:)`), so it goes
/// away on time even when the app can't reload the widgets.
struct ListeningBadge: View {
    enum Style {
        /// The mic alone, for the Lock Screen's small spaces. A waveform during a cry, since the Lock
        /// Screen usually shows it without color.
        case glyph
        /// The mic in a small capsule, for the small widget.
        case compact
        /// The mic and "Listening" or "Crying" in a capsule, for the medium and large widgets.
        case full
    }

    let listening: WidgetSnapshot.Listening
    var style: Style = .full

    var body: some View {
        content
            .widgetAccentable()
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.voiceOver(listening))
    }

    @ViewBuilder
    private var content: some View {
        let color = ListeningStyle.color(isCrying: listening.isCrying)
        switch style {
        case .glyph:
            Image(systemName: listening.isCrying ? "waveform" : "mic.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        case .compact, .full:
            HStack(spacing: 3) {
                Image(systemName: "mic.fill")
                if style == .full {
                    listening.isCrying
                        ? Text("Crying", comment: "Widget badge and Live Activity: cry alerts hear the baby crying now")
                        : Text("Listening", comment: "Widget badge and Live Activity: cry alerts are listening on this iPhone")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, style == .full ? 6 : 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
        }
    }

    /// What VoiceOver reads for the badge, also added to the Lock Screen widgets' own label.
    static func voiceOver(_ listening: WidgetSnapshot.Listening) -> String {
        listening.isCrying
            ? String(localized: "Cry alerts hear crying now", comment: "VoiceOver, widget: the mic badge during a cry")
            : String(localized: "Cry alerts are listening", comment: "VoiceOver, widget: the mic badge while cry alerts listen on this iPhone")
    }
}

/// The colors of cry alerts outside the app: the app's listening green and cry orange
/// (`Palette.listening`, `Palette.cryAlerts`), a little muted, because they're seen at night.
enum ListeningStyle {
    static let listening = Color.green.opacity(0.8)
    static let crying = Color.orange.opacity(0.9)
    /// Text on the Live Activity's dark background: soft rather than bright white.
    static let text = Color.white.opacity(0.8)
    static let dimText = Color.white.opacity(0.55)

    static func color(isCrying: Bool) -> Color {
        isCrying ? crying : listening
    }
}
