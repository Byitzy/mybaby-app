import CoreData
import SwiftUI

/// Today's calm card after a vaccine: "After Tuesday's shots" or "MMR was 9 days ago", two or three
/// short lines on what to look out for now, **Comfort, and when to call** (`AfterVaccineView`) and
/// each vaccine's notes (`VaccineInfoView`). When and what come from `VaccineGuide.watchWindows`, put
/// together by `VaccineFollowUp.cards`; one card per visit, for shots marked given only.
///
/// Dismissing it is remembered on this iPhone, per vaccine and window, so it comes back when the next
/// window starts and not before. It's only reading, so view-only family see it too: it has nothing
/// that changes the log. In 3 AM mode the lines are in primary text, which the red filter keeps
/// readable.
struct VaccineFollowUpSection: View {
    @Environment(\.isThreeAMMode) private var isThreeAMMode
    @AppStorage(SettingsKey.dismissedVaccineFollowUps) private var dismissed = ""
    @FetchRequest private var recent: FetchedResults<Vaccine>
    let now: Date

    init(baby: Baby, now: Date) {
        self.now = now
        let request = Vaccine.fetchAll()
        let since = Calendar.current.date(byAdding: .day, value: -VaccineFollowUp.lookBackDays, to: Calendar.current.startOfDay(for: now)) ?? now
        request.predicate = NSPredicate(format: "isGiven == YES AND date >= %@", since as NSDate)
        _recent = FetchRequest(fetchRequest: baby.entries(request))
    }

    var body: some View {
        ForEach(VaccineFollowUp.cards(for: Array(recent), now: now, dismissed: dismissedKeys)) { card in
            Section {
                summary(card)
                NavigationLink {
                    AfterVaccineView()
                        .readableContentWidth()
                } label: {
                    Label {
                        Text("Comfort, and when to call")
                    } icon: {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(Palette.baby)
                    }
                }
                ForEach(card.entries) { entry in
                    NavigationLink {
                        VaccineInfoView(entry: entry)
                            .readableContentWidth()
                    } label: {
                        Label {
                            Text(entry.name)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Palette.vaccineGiven)
                        }
                    }
                    .accessibilityLabel("About \(entry.name)")
                }
            }
        }
    }

    private func summary(_ card: VaccineFollowUp.Card) -> some View {
        let lines = card.lines
        return HStack(alignment: .top, spacing: Spacing.m) {
            EmojiBadge(emoji: "💉", tint: Palette.vaccineGiven, size: 40)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                ForEach(lines, id: \.self) { line in
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(isThreeAMMode ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                dismiss(card)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(Spacing.xs)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Hides this until the next time there's something to look out for after these shots")
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var dismissedKeys: Set<String> {
        Set(dismissed.split(separator: "\n").map(String.init))
    }

    private func dismiss(_ card: VaccineFollowUp.Card) {
        var keys = dismissed.split(separator: "\n").map(String.init)
        keys.append(contentsOf: card.dismissKeys.filter { !keys.contains($0) })
        // Only recent shots matter; older windows are long over.
        dismissed = keys.suffix(60).joined(separator: "\n")
    }
}
