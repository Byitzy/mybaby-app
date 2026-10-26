import SwiftUI

/// Shown instead of the app until this person agrees to the current Terms of Use: on first launch,
/// and again after the terms change (see `TermsOfUse.version`). The key points first, then the full
/// terms and the privacy policy one tap away, and an explicit checkbox before Agree. Agreeing saves
/// the version, which `RootView` watches to show the app.
struct TermsAcceptanceView: View {
    @State private var hasRead = false
    /// Agreed to an earlier version on this device, so this is "Updated terms".
    private let isUpdate = TermsOfUse.acceptedVersion > 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(isUpdate ? "We've updated our terms" : "Before you start")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(isUpdate
                             ? "Please read and agree to the updated Terms of Use to keep using MyBaby."
                             : "Please read and agree to the Terms of Use to use MyBaby.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(TermsOfUse.keyPoints, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                                Image(systemName: point.systemImage)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                Text(point.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .modifier(CardStyle())

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        NavigationLink {
                            TermsOfUseView()
                        } label: {
                            Label("Read the full Terms of Use", systemImage: "doc.text")
                        }
                        Link(destination: AppLinks.privacyPolicy) {
                            Label("Read the Privacy Policy", systemImage: "hand.raised")
                        }
                    }

                    Button {
                        hasRead.toggle()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                            Image(systemName: hasRead ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(hasRead ? Color.accentColor : .secondary)
                            Text("I've read and agree to the Terms of Use and the Privacy Policy.")
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(hasRead ? .isSelected : [])

                    Button {
                        TermsOfUse.accept()
                    } label: {
                        Text("Agree and continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasRead)

                    Text("Effective \(TermsOfUse.effectiveDate)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.l)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.screenBackground)
        }
    }
}

/// The full Terms of Use: from the screen that asks to agree, and from Settings.
struct TermsOfUseView: View {
    var body: some View {
        List {
            Section {
                Text("Effective \(TermsOfUse.effectiveDate)")
                    .foregroundStyle(.secondary)
                if let acceptedAt = TermsOfUse.acceptedAt {
                    Text("You agreed on \(acceptedAt.formatted(date: .long, time: .shortened)).")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(TermsOfUse.sections) { section in
                Section(section.title) {
                    ForEach(section.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section {
                Link(destination: AppLinks.terms) {
                    Label("Terms of Use on the web", systemImage: "safari")
                }
                Link(destination: AppLinks.privacyPolicy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
