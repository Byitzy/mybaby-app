import CoreData
import SwiftUI

struct VaccinesList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @FetchRequest private var vaccines: FetchedResults<Vaccine>

    @State private var editing: Vaccine?
    @State private var addingNew = false
    /// Waiting for "Delete" after a swipe.
    @State private var deleting: Vaccine?

    init(baby: Baby) {
        _vaccines = FetchRequest(fetchRequest: baby.entries(Vaccine.fetchAll()))
    }

    var body: some View {
        let upcoming = vaccines.filter { !$0.isGiven }
        let given = vaccines.filter(\.isGiven).reversed()

        List {
            if given.contains(where: { Date.now.timeIntervalSince($0.date) < 2 * 24 * 60 * 60 && $0.date <= .now }) {
                Section {
                    NavigationLink {
                        AfterVaccineView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Shots in the last two days")
                                    .font(.body.weight(.medium))
                                Text("What's normal after, how to comfort, and when to call")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(Palette.baby)
                        }
                    }
                }
            }

            if vaccines.isEmpty {
                EmptyStateView(
                    "No vaccines yet",
                    systemImage: "syringe",
                    message: "Record each shot with its date and lot number, and add upcoming ones from your pediatrician's schedule.",
                    actionTitle: "Add vaccine",
                    isDisabled: !canEditLog
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            }

            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { vaccine in
                        row(vaccine)
                            .swipeActions(edge: .leading) {
                                if canEditLog {
                                    Button("Given today", systemImage: "checkmark") {
                                        vaccine.isGiven = true
                                        vaccine.date = .now
                                        context.saveIfChanged()
                                    }
                                    .tint(Palette.vaccineGiven)
                                }
                            }
                    }
                }
            }
            if !given.isEmpty {
                Section("Given") {
                    ForEach(Array(given)) { row($0) }
                }
            }

            Section {
                NavigationLink {
                    VaccineGuideView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Vaccine guide")
                                .font(.body.weight(.medium))
                            Text("What each vaccine is for, what's normal after, and your official schedule")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(Palette.vaccineGiven)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add vaccine", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $addingNew) {
            VaccineEditor(vaccine: nil)
        }
        .sheet(item: $editing) { vaccine in
            VaccineEditor(vaccine: vaccine)
        }
        .confirmDelete("Delete this vaccine?", item: $deleting) { vaccine in
            context.delete(vaccine)
            context.saveIfChanged()
        }
    }

    private func row(_ vaccine: Vaccine) -> some View {
        Button {
            editing = vaccine
        } label: {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "💉", tint: vaccine.isGiven ? Palette.vaccineGiven : Palette.vaccineDue)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(vaccine.name.isEmpty ? String(localized: "Vaccine") : vaccine.name)
                        .font(.body.weight(.medium))
                    let details = [vaccine.product, vaccine.doseLabel, vaccine.provider].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    // Said in words with an icon, not only in green or orange.
                    NoticeLabel(
                        vaccine.isGiven ? "Given" : "Due",
                        systemImage: vaccine.isGiven ? "checkmark.circle.fill" : "clock",
                        tint: vaccine.isGiven ? Palette.vaccineGiven : Palette.vaccineDue
                    )
                    .font(.caption.weight(.semibold))
                    Text(vaccine.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .swipeActions {
            if canEditLog {
                // Not `.destructive`, which would remove the row before the answer.
                Button("Delete", systemImage: "trash") {
                    deleting = vaccine
                }
                .tint(.red)
            }
        }
    }
}

struct VaccineEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog

    let vaccine: Vaccine?

    @State private var name = ""
    @State private var date = Date.now
    @State private var isGiven = true
    @State private var doseLabel = ""
    @State private var provider = ""
    /// The clinic picked from the search, or `nil` for a typed one. Typing in the field again makes
    /// it a typed one, so a new name never keeps the old one's map.
    @State private var place: AppointmentPlace?
    /// Clinics already picked for other vaccines and appointments, for the menu by the field.
    @State private var recentPlaces: [AppointmentPlace] = []
    @StateObject private var placeSearch = PlaceSearch()
    @State private var lotNumber = ""
    @State private var productName = ""
    /// As typed, so "0," can become "0,5".
    @State private var doseAmountText = ""
    @State private var doseUnit = VaccineDoseUnit.milliliters
    @State private var hasExpiry = false
    @State private var expiryDate = Date.now
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmingDelete = false
    /// The vaccine guide, opened to choose a vaccine.
    @State private var choosingFromGuide = false

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this vaccine, but only the parents can save changes.") }
                }

                Section {
                    HStack {
                        TextField("Vaccine name", text: $name)
                        Button {
                            choosingFromGuide = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Choose from the vaccine guide")
                    }
                    TextField("Dose (e.g. Dose 1 of 3)", text: $doseLabel)
                }

                productSection

                if let entry = VaccineGuide.entry(matching: name) {
                    Section("About this vaccine") {
                        NavigationLink {
                            VaccineInfoView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(entry.protectsAgainst)
                                Text("What it's for, and what's normal after")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Already given", isOn: $isGiven)
                    DateField(isGiven ? "Date given" : "Due date", selection: $date, includesTime: false)
                }

                Section {
                    HStack {
                        TextField("Clinic or provider", text: typedProvider)
                            .textContentType(.organizationName)
                            .submitLabel(.done)
                            // Keeps it as typed.
                            .onSubmit { placeSearch.clear() }
                        if !recentPlaces.isEmpty {
                            RecentPlacesMenu(places: recentPlaces, accessibilityLabel: String(localized: "Clinics used before"), onPick: use)
                        }
                    }
                    ForEach(placeSearch.suggestions) { suggestion in
                        PlaceSuggestionRow(suggestion: suggestion, hint: String(localized: "Uses this clinic for the vaccine")) { pick(suggestion) }
                    }
                    if placeSearch.isLookingUp {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Finding the clinic")
                    } else if placeSearch.lookupFailed {
                        NoticeLabel("Couldn't find that place in Maps right now. It's kept as typed.", systemImage: "mappin.slash", tint: Palette.inactive)
                            .font(.subheadline)
                    }
                    if let place {
                        AppointmentPlaceCard(place: place)
                    }
                } footer: {
                    Text(PlaceSearch.privacyNote)
                }

                Section {
                    TextField("Lot number", text: $lotNumber)
                        .textInputAutocapitalization(.characters)
                } footer: {
                    Text("The lot number is on the vaccine record your clinic gives you.")
                }

                Section("Notes") {
                    TextField("Reactions, fever, fussiness…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let vaccine, canEditLog {
                    Section {
                        Button("Delete vaccine", role: .destructive) {
                            confirmingDelete = true
                        }
                        .confirmationDialog("Delete this vaccine?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                context.delete(vaccine)
                                context.saveIfChanged()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(vaccine == nil ? "New vaccine" : "Edit vaccine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !canEditLog)
                }
            }
            .navigationDestination(isPresented: $choosingFromGuide) {
                VaccineGuideView { entry in
                    name = entry.name
                    choosingFromGuide = false
                }
            }
            .onAppear(perform: load)
            .onDisappear { placeSearch.cancel() }
        }
        .threeAMSheet()
    }

    // MARK: Product

    /// The brand, the amount given and the expiry date, from the vaccine record or the box.
    private var productSection: some View {
        Section {
            HStack {
                TextField("Brand or product", text: $productName)
                    .textInputAutocapitalization(.words)
                if let entry = VaccineGuide.entry(matching: name), let brands = VaccineGuide.brands[entry.id], !brands.isEmpty {
                    Menu {
                        ForEach(brands, id: \.self) { brand in
                            // Brand names as printed on the box, the same in every language.
                            Button(brand) { productName = brand }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Brands of this vaccine")
                }
            }
            HStack {
                TextField("Amount given", text: $doseAmountText)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $doseUnit) {
                    ForEach(VaccineDoseUnit.allCases) { unit in
                        Text(verbatim: unit.symbol).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Unit")
            }
            Toggle("Expiry date", isOn: $hasExpiry)
            if hasExpiry {
                DateField("Expires", selection: $expiryDate, includesTime: false)
            }
        } header: {
            Text("Product")
        } footer: {
            Text("From the vaccine record or the box. All optional.")
        }
    }

    /// "0.5" or "0,5", whichever the keyboard gives. Nil when empty or not a number.
    private var parsedDoseAmount: Double? {
        let text = doseAmountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(text), amount > 0 else { return nil }
        return amount
    }

    // MARK: Place

    /// The clinic field. Only the parent's own edits search; filling it in here (opening the
    /// vaccine, picking a suggestion or a clinic used before) never sends anything.
    private var typedProvider: Binding<String> {
        Binding(
            get: { provider },
            set: { typed in
                guard typed != provider else { return }
                provider = typed
                place = nil
                placeSearch.update(query: typed)
            }
        )
    }

    /// Uses a suggestion: its name goes in the field right away, then its address, map and phone
    /// once Apple Maps has them.
    private func pick(_ suggestion: PlaceSearch.Suggestion) {
        provider = suggestion.title
        place = nil
        Task {
            guard let found = await placeSearch.place(for: suggestion) else { return }
            // Unless the parent typed something else meanwhile.
            guard provider == suggestion.title else { return }
            provider = found.name
            place = found
            placeSearch.bias(toward: found.coordinate)
        }
    }

    /// Uses a clinic picked before, as it was saved; nothing is looked up again.
    private func use(_ recent: AppointmentPlace) {
        placeSearch.clear()
        provider = recent.name
        place = recent
        placeSearch.bias(toward: recent.coordinate)
    }

    // MARK: Load & save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        recentPlaces = AppointmentPlace.recent(in: context)
        defer { placeSearch.bias(toward: place?.coordinate ?? recentPlaces.first?.coordinate) }
        guard let vaccine else { return }
        name = vaccine.name
        date = vaccine.date
        isGiven = vaccine.isGiven
        doseLabel = vaccine.doseLabel
        provider = vaccine.provider
        place = vaccine.place
        lotNumber = vaccine.lotNumber
        notes = vaccine.notes
        productName = vaccine.product
        doseUnit = vaccine.amountUnit
        doseAmountText = vaccine.doseAmount.map { $0.formatted(.number.precision(.fractionLength(0...3)).grouping(.never)) } ?? ""
        if let expiry = vaccine.expiryDate {
            hasExpiry = true
            expiryDate = expiry
        }
    }

    private func save() {
        let target = vaccine ?? Vaccine.create(in: context)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.date = date
        target.isGiven = isGiven
        target.doseLabel = doseLabel.trimmingCharacters(in: .whitespaces)
        target.provider = provider.trimmingCharacters(in: .whitespaces)
        target.setPlace(target.provider.isEmpty ? nil : place)
        target.lotNumber = lotNumber.trimmingCharacters(in: .whitespaces)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = productName.trimmingCharacters(in: .whitespaces)
        target.productName = product.isEmpty ? nil : product
        target.doseAmount = parsedDoseAmount
        target.doseUnit = parsedDoseAmount == nil ? nil : doseUnit.rawValue
        target.expiryDate = hasExpiry ? Calendar.current.startOfDay(for: expiryDate) : nil
        context.saveIfChanged()
        dismiss()
    }
}
