import SwiftUI

/// Help lines for where the person lives, from `support-resources.json`: the emergency number
/// first, then crisis, pregnancy and new-parent, and health lines. Sections for a `List`.
///
/// The region follows the iPhone's Region setting (no location permission), and "Change" picks
/// another one, kept in `UserDefaults.standard` (`supportRegion`). Where a province or state
/// has lines of its own (Canada's 811s), a picker chooses it (`supportSubregion`).
struct SupportResourcesSection: View {
    @AppStorage(SupportDirectory.regionKey) private var regionOverride = ""
    @AppStorage(SupportDirectory.subregionKey) private var subregionCode = ""
    @State private var choosingRegion = false

    private let directory = SupportDirectory.bundled

    var body: some View {
        if let directory {
            let region = directory.resolvedRegion(override: regionOverride)
            let subregion = region.subregion(code: subregionCode)
            let kinds = SupportKind.allCases.filter { !region.lines($0, subregion: subregion).isEmpty }
            let unchosenSubregions = subregion == nil ? (region.subregions ?? []) : []

            Section {
                EmergencyCallout(region: region)
                if let subregions = region.subregions, !subregions.isEmpty {
                    Picker("Province or territory", selection: $subregionCode) {
                        Text("Not set").tag("")
                        ForEach(subregions) { subregion in
                            Text(subregion.name).tag(subregion.code)
                        }
                    }
                }
            } header: {
                SupportRegionHeader(regionName: region.code == SupportDirectory.otherCode ? nil : region.name) {
                    choosingRegion = true
                }
            } footer: {
                if kinds.isEmpty && unchosenSubregions.isEmpty {
                    SupportFootnote(region: region)
                }
            }
            .sheet(isPresented: $choosingRegion) {
                SupportRegionPicker(directory: directory, selection: $regionOverride)
            }

            ForEach(kinds) { kind in
                Section {
                    ForEach(region.lines(kind, subregion: subregion)) { resource in
                        SupportResourceRows(resource: resource)
                    }
                    if kind == .general && region.code == SupportDirectory.otherCode {
                        Text("Your doctor, midwife or health visitor can point you to local support.")
                            .font(.subheadline)
                    }
                } header: {
                    Text(kind.title)
                } footer: {
                    if kind == kinds.last && unchosenSubregions.isEmpty {
                        SupportFootnote(region: region)
                    }
                }
            }

            if !unchosenSubregions.isEmpty {
                Section {
                    Text("Choose your province or territory above to see its lines with the others, or find them here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("Lines in each province and territory") {
                        ForEach(unchosenSubregions) { subregion in
                            ForEach(subregion.resources) { resource in
                                SupportResourceRows(resource: resource, place: subregion.name)
                            }
                        }
                    }
                } header: {
                    Text("By province and territory")
                } footer: {
                    SupportFootnote(region: region)
                }
            }
        } else {
            // Only if the bundled file is missing or broken.
            Section {
                Text("Call your local emergency number if you or your baby are in danger.")
                    .font(.subheadline.weight(.semibold))
                Text("Your doctor, midwife or health visitor can point you to local support.")
                    .font(.subheadline)
            } header: {
                Text("Support")
            }
        }
    }
}

/// "Support for Canada · Change".
private struct SupportRegionHeader: View {
    /// Nil for "Other / not listed".
    let regionName: String?
    let change: () -> Void

    var body: some View {
        let title = regionName.map { "Support for \($0)" } ?? "Support for your region"
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.xs) {
                titleText(title)
                Text("·")
                    .accessibilityHidden(true)
                changeButton
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                titleText(title)
                changeButton
            }
        }
        .textCase(nil)
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
    }

    private var changeButton: some View {
        Button("Change", action: change)
            .buttonStyle(.borderless)
            .accessibilityLabel("Change region")
            .accessibilityHint("Shows support lines for another country or region")
    }
}

/// "If you're thinking about harming yourself or your baby, or anyone is in danger, call 911",
/// with a call button for each emergency number.
private struct EmergencyCallout: View {
    let region: SupportRegion

    var body: some View {
        if let numbers = region.emergencyText {
            Label {
                Text("If you're thinking about harming yourself or your baby, or anyone is in danger, call \(numbers).")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
            }
            .padding(.vertical, Spacing.xs)
            // One row each, so a tap on one row never dials another number.
            ForEach(region.emergency) { number in
                if let url = number.phoneURL {
                    Link(destination: url) {
                        Label("Call \(number.text)", systemImage: "phone.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.danger)
                    .accessibilityLabel(spokenCall(number))
                }
            }
        } else {
            Label {
                Text("Call your local emergency number if you or your baby are in danger.")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    /// "Call 1 0 1 7 7, ambulance", so VoiceOver reads the digits one by one.
    private func spokenCall(_ number: EmergencyNumber) -> String {
        let digits = SupportDirectory.spoken(number.number)
        return number.label.map { "Call \(digits), \($0)" } ?? "Call \(digits)"
    }
}

/// One resource as list rows: what it is, then a row for each way to reach it.
struct SupportResourceRows: View {
    let resource: SupportResource
    /// The province it's in, when it's listed with others' ("Quebec · Info-Santé 811").
    var place: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(place.map { "\($0) · \(resource.name)" } ?? resource.name)
                .font(.subheadline.weight(.semibold))
            Text(resource.details)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let extra = resource.hoursAndLanguages {
                Text(extra)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)

        if let url = resource.phoneURL, let phone = resource.phone {
            Link(destination: url) {
                Label("Call \(phone)", systemImage: "phone")
            }
            .accessibilityLabel("Call \(resource.name), \(SupportDirectory.spoken(phone))")
        }
        if let url = resource.textURL, let sms = resource.sms {
            Link(destination: url) {
                Label(textTitle(sms), systemImage: "message")
            }
            .accessibilityLabel(spokenText(sms))
        }
        if let url = resource.url {
            Link(destination: url) {
                Label(Self.siteName(url), systemImage: "safari")
            }
            .accessibilityLabel("\(resource.name) website")
        }
    }

    /// "Text "SHOUT" to 85258", or "Text 988".
    private func textTitle(_ sms: SupportResource.TextLine) -> String {
        sms.body.map { "Text \"\($0)\" to \(sms.number)" } ?? "Text \(sms.number)"
    }

    private func spokenText(_ sms: SupportResource.TextLine) -> String {
        let digits = SupportDirectory.spoken(sms.number)
        return sms.body.map { "Text \($0) to \(resource.name), \(digits)" } ?? "Text \(resource.name), \(digits)"
    }

    /// "postpartum.net" for https://www.postpartum.net.
    static func siteName(_ url: URL) -> String {
        guard var host = url.host() else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

/// "Numbers checked October 25, 2026. If one doesn't work, call your local emergency number."
private struct SupportFootnote: View {
    let region: SupportRegion

    var body: some View {
        Text("Numbers checked \(SupportDirectory.displayDate(region.lastVerified)). If one doesn't work, call your local emergency number.")
    }
}

/// The list of supported regions, searchable, with "Other / not listed" at the end.
private struct SupportRegionPicker: View {
    let directory: SupportDirectory
    /// A region code, `SupportDirectory.otherCode`, or empty for the iPhone's Region.
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        row(title: automaticTitle, subtitle: "From your iPhone's Region setting", code: "")
                    }
                }
                Section {
                    ForEach(matchingRegions) { region in
                        row(title: region.name, subtitle: nil, code: region.code)
                    }
                    row(title: "Other / not listed", subtitle: "Your local emergency number and an international directory of helplines", code: SupportDirectory.otherCode)
                } footer: {
                    Text("MyBaby uses your iPhone's Region setting (Settings → General → Language & Region), never your location.")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
            .navigationTitle("Where you live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// "Automatic (Canada)", or "Automatic (not listed)" when the iPhone's region isn't one of them.
    private var automaticTitle: String {
        let name = directory.region(code: SupportDirectory.deviceRegionCode)?.name ?? "not listed"
        return "Automatic (\(name))"
    }

    /// Matches a country's name or code, or one of its provinces ("Quebec" finds Canada).
    private var matchingRegions: [SupportRegion] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return directory.sortedRegions }
        return directory.sortedRegions.filter { region in
            region.name.localizedStandardContains(query)
                || region.code.caseInsensitiveCompare(query) == .orderedSame
                || (region.subregions ?? []).contains { $0.name.localizedStandardContains(query) }
        }
    }

    private func row(title: String, subtitle: String?, code: String) -> some View {
        let isSelected = selection == code
        return Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The one call button on the "You're not alone" card: a line that suits the person's region,
/// like the National Maternal Mental Health Hotline in the US or Info-Social 811 in Quebec.
/// Shows nothing when the region has none marked `featured`.
struct RegionalSupportCardButton: View {
    @AppStorage(SupportDirectory.regionKey) private var regionOverride = ""
    @AppStorage(SupportDirectory.subregionKey) private var subregionCode = ""

    var body: some View {
        if let directory = SupportDirectory.bundled {
            let region = directory.resolvedRegion(override: regionOverride)
            if let line = region.featuredLine(subregion: region.subregion(code: subregionCode)),
               let url = line.phoneURL, let phone = line.phone {
                Link(destination: url) {
                    Label("Call \(line.name)", systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.momCare)
                .accessibilityLabel("Call \(line.name), \(SupportDirectory.spoken(phone))")
            }
        }
    }
}
