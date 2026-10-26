import SwiftUI

/// Every vaccine in `VaccineGuide`, searchable by name or brand, with the official schedule for the
/// parents' region and what's normal after any vaccine.
///
/// From the Vaccines list it's for reading. From the vaccine editor (`onPick`), tapping a vaccine
/// picks it, and the info button shows its notes first.
struct VaccineGuideView: View {
    var onPick: ((VaccineGuide.Entry) -> Void)?

    @AppStorage(SupportDirectory.regionKey) private var regionOverride = ""
    @AppStorage(SupportDirectory.subregionKey) private var subregionCode = ""
    @State private var query = ""
    /// The vaccine whose notes are shown, when picking.
    @State private var showing: VaccineGuide.Entry?
    @State private var choosingRegion = false

    var body: some View {
        let groups = VaccineGuide.Group.allCases
            .map { GuideGroup(group: $0, entries: matches(in: $0)) }
            .filter { !$0.entries.isEmpty }

        List {
            if query.isEmpty {
                scheduleSection
            }
            ForEach(groups) { found in
                Section(found.group.title) {
                    ForEach(found.entries) { row($0) }
                }
            }
            if query.isEmpty {
                Section {
                    NavigationLink {
                        AfterVaccineView()
                    } label: {
                        Label("After any vaccine", systemImage: "heart.text.square")
                    }
                } footer: {
                    Text("General information, not medical advice. Reviewed \(VaccineGuide.reviewed).")
                }
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
        .searchable(text: $query, prompt: "Vaccine or brand name")
        .sheet(isPresented: $choosingRegion) {
            if let directory = SupportDirectory.bundled {
                SupportRegionPicker(directory: directory, selection: $regionOverride)
            }
        }
        .navigationTitle(onPick == nil ? "Vaccine guide" : "Choose a vaccine")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $showing) { entry in
            VaccineInfoView(entry: entry, onPick: onPick.map { pick -> () -> Void in { pick(entry) } })
        }
    }

    private func matches(in group: VaccineGuide.Group) -> [VaccineGuide.Entry] {
        let entries = VaccineGuide.entries(in: group)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { entry in
            ([entry.name, entry.protectsAgainst] + entry.otherNames).contains { $0.localizedStandardContains(trimmed) }
        }
    }

    @ViewBuilder
    private func row(_ entry: VaccineGuide.Entry) -> some View {
        if let onPick {
            HStack(spacing: Spacing.m) {
                Button {
                    onPick(entry)
                } label: {
                    VaccineGuideRowLabel(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Uses this vaccine")

                Button {
                    showing = entry
                } label: {
                    Image(systemName: "info.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("About \(entry.name)")
            }
        } else {
            NavigationLink {
                VaccineInfoView(entry: entry)
            } label: {
                VaccineGuideRowLabel(entry: entry)
            }
        }
    }

    private var scheduleSection: some View {
        let region = SupportDirectory.bundled?.resolvedRegion(override: regionOverride)
        let code = region?.code ?? SupportDirectory.otherCode
        return Section {
            if let subregions = region?.subregions, !subregions.isEmpty {
                Picker("Province or territory", selection: $subregionCode) {
                    Text("Not set").tag("")
                    ForEach(subregions) { subregion in
                        Text(subregion.name).tag(subregion.code)
                    }
                }
            }
            ForEach(VaccineGuide.scheduleLinks(regionCode: code, subregionCode: subregionCode)) { link in
                Link(destination: link.url) {
                    HStack(spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(link.title)
                                .foregroundStyle(.primary)
                            Text(link.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHint("Opens in Safari")
            }
        } header: {
            HStack(spacing: Spacing.xs) {
                Group {
                    if code == SupportDirectory.otherCode {
                        Text("Your schedule")
                    } else if let name = region?.name {
                        Text("Schedule for \(name)", comment: "A country or region")
                    } else {
                        Text("Schedule for your region")
                    }
                }
                .accessibilityAddTraits(.isHeader)
                if SupportDirectory.bundled != nil {
                    Text("·")
                        .accessibilityHidden(true)
                    Button("Change") { choosingRegion = true }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Change region")
                        .accessibilityHint("Shows the vaccine schedule for where you live")
                }
            }
            .textCase(nil)
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Which vaccines are offered, and when, differs between countries and changes over time. Your clinic's schedule is the one to follow. This is where you live, from your iPhone's Region setting unless you change it here or in Parent care; it's shared with the support lines there.")
                if code.uppercased() == "US" {
                    Text(VaccineGuide.unitedStatesNote)
                }
            }
        }
    }
}

/// One group's vaccines that match the search.
private struct GuideGroup: Identifiable {
    let group: VaccineGuide.Group
    let entries: [VaccineGuide.Entry]

    var id: VaccineGuide.Group { group }
}

/// The name, and what it protects against.
private struct VaccineGuideRowLabel: View {
    let entry: VaccineGuide.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(entry.name)
                .foregroundStyle(.primary)
            Text(entry.protectsAgainst)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One vaccine's notes: what it protects against and why, roughly when, what's normal after, and
/// the rare reactions to know about.
struct VaccineInfoView: View {
    let entry: VaccineGuide.Entry
    /// From the editor's guide: "Use this vaccine".
    var onPick: (() -> Void)?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(entry.protectsAgainst)
                        .font(.headline)
                    Text(entry.about)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text("Protects against")
            }

            Section {
                Text(entry.usuallyGiven)
            } header: {
                Text("Usually given")
            } footer: {
                Text("Your clinic's schedule decides the exact timing.")
            }

            Section {
                ForEach(entry.commonReactions, id: \.self) { reaction in
                    Label(reaction, systemImage: "checkmark.circle")
                        .labelStyle(GuideBulletStyle(tint: Palette.vaccineGiven))
                }
            } header: {
                Text("Common after this vaccine")
            } footer: {
                Text("These are normal and usually pass in a day or two.")
            }

            if !entry.watchFor.isEmpty {
                Section("Rare, but good to know") {
                    ForEach(entry.watchFor, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                            .labelStyle(GuideBulletStyle(tint: Palette.warning))
                    }
                }
            }

            Section {
                NavigationLink {
                    AfterVaccineView()
                } label: {
                    Label("Comfort, and when to call", systemImage: "heart.text.square")
                }
            } footer: {
                Text("General information, not medical advice. Reviewed \(VaccineGuide.reviewed).")
            }

            if let onPick {
                Section {
                    Button(action: onPick) {
                        Text("Use this vaccine")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What's normal after any vaccine, how to comfort a baby, when to call the doctor (with the
/// region's nurse line), and the signs of an emergency (with its emergency number).
struct AfterVaccineView: View {
    @AppStorage(SupportDirectory.regionKey) private var regionOverride = ""
    @AppStorage(SupportDirectory.subregionKey) private var subregionCode = ""

    var body: some View {
        let region = SupportDirectory.bundled?.resolvedRegion(override: regionOverride)
        let healthLines = (region?.lines(.healthLine, subregion: region?.subregion(code: subregionCode)) ?? [])
            .filter { $0.phoneURL != nil }
            .prefix(2)

        List {
            Section {
                ForEach(VaccineGuide.comfort, id: \.self) { tip in
                    Label(tip, systemImage: "heart")
                        .labelStyle(GuideBulletStyle(tint: Palette.baby))
                }
            } header: {
                Text("Comfort")
            } footer: {
                Text("Soreness, a low fever, fussiness and extra sleep are common for a day or two after shots.")
            }

            Section("Call your doctor or nurse line for") {
                ForEach(VaccineGuide.callTheDoctor, id: \.self) { reason in
                    Label(reason, systemImage: "phone")
                        .labelStyle(GuideBulletStyle(tint: Palette.warning))
                }
                ForEach(Array(healthLines)) { line in
                    if let url = line.phoneURL, let phone = line.phone {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Label("Call \(line.name) · \(phone)", systemImage: "phone.fill")
                                    .font(.body.weight(.semibold))
                                Text(line.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Call \(line.name), \(SupportDirectory.spoken(phone))")
                    }
                }
            }

            Section {
                Text(VaccineGuide.emergencySigns)
                ForEach(region?.emergency ?? []) { number in
                    if let url = number.phoneURL {
                        Link(destination: url) {
                            Label("Call \(number.text)", systemImage: "phone.fill")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.danger)
                        .accessibilityLabel("Call \(SupportDirectory.spoken(number.number))")
                    }
                }
            } header: {
                Group {
                    if let numbers = region?.emergencyText {
                        Label("Call \(numbers) right away for", systemImage: "exclamationmark.triangle.fill")
                    } else {
                        Label("Call your local emergency number right away for", systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .foregroundStyle(Palette.danger)
            } footer: {
                Text("Serious reactions are very rare. That's why clinics ask you to wait a little while after the shots. General information, not medical advice. Reviewed \(VaccineGuide.reviewed).")
            }
        }
        .navigationTitle("After a vaccine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A bullet with a small tinted icon at the first line, and text that wraps under itself.
private struct GuideBulletStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            configuration.icon
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
