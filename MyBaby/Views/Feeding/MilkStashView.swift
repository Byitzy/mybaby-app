import CoreData
import SwiftUI

/// The pumped milk on hand: totals by where it's stored, and each bag oldest first with its
/// use-by date from the CDC's storage guidelines. Pushed from the More tab.
struct MilkStashView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.milkStashReminder, store: .shared) private var reminderEnabled = false
    @FetchRequest private var bags: FetchedResults<MilkBag>

    @State private var editing: MilkBag?
    @State private var addingNew = false
    /// The bag waiting for "log a bottle?" after tapping Use.
    @State private var using: MilkBag?
    @State private var toast: Toast?
    @State private var showingPermissionAlert = false

    init(baby: Baby) {
        _bags = FetchRequest(fetchRequest: baby.entries(MilkBag.inStash()))
    }

    var body: some View {
        List {
            if bags.isEmpty {
                EmptyStateView(
                    "No milk in the stash",
                    systemImage: "refrigerator",
                    message: "Log a pumping session and turn on Add to milk stash, or add a bag here.",
                    actionTitle: "Add a bag",
                    isDisabled: !canEditLog
                ) {
                    addingNew = true
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    totals
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach(MilkStorage.allCases) { storage in
                    let inStorage = bags.filter { $0.storage == storage }
                    if !inStorage.isEmpty {
                        Section {
                            ForEach(inStorage) { bag in
                                MilkBagRow(bag: bag, unit: unit, onEdit: { editing = bag }, onUse: { using = bag })
                                    .swipeActions(edge: .trailing) {
                                        if canEditLog {
                                            Button("Discard", systemImage: "trash", role: .destructive) { discard(bag) }
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if canEditLog {
                                            ForEach(bag.possibleMoves) { destination in
                                                Button(moveTitle(bag, to: destination), systemImage: destination.systemImage) {
                                                    move(bag, to: destination)
                                                }
                                                .tint(destination == .freezer ? Palette.frozenMilk : Palette.milkStash)
                                            }
                                        }
                                    }
                            }
                        } header: {
                            Text("\(storage.title) · oldest first")
                        }
                    }
                }
            }

            Section {
                Toggle("Remind me on the use-by day", isOn: $reminderEnabled)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A notification at 8 AM on the day milk in the fridge or freezer reaches its use-by date.")
                    Text(MilkStorageGuide.summary)
                }
            }
        }
        .navigationTitle("Milk stash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingNew = true } label: {
                    Label("Add a bag", systemImage: "plus")
                }
                .disabled(!canEditLog)
            }
        }
        .sheet(isPresented: $addingNew) {
            MilkBagEditor(bag: nil)
        }
        .sheet(item: $editing) { bag in
            MilkBagEditor(bag: bag)
        }
        .confirmationDialog("Use this bag?", isPresented: usingBinding, titleVisibility: .visible, presenting: using) { bag in
            Button(logTitle(bag)) { use(bag, logFeeding: true) }
            Button("Use without logging") { use(bag, logFeeding: false) }
        } message: { _ in
            Text("It's taken out of the stash. You can log it as a bottle of breast milk too.")
        }
        .alert("Notifications are off", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow notifications for MyBaby in the iPhone Settings app to get this reminder.")
        }
        .onChange(of: reminderEnabled) { _, enabled in
            guard enabled else {
                CareReminders.refreshMilkStash(context: context)
                return
            }
            Task {
                if await NotificationManager.requestAuthorization() {
                    CareReminders.refreshMilkStash(context: context)
                } else {
                    reminderEnabled = false
                    showingPermissionAlert = true
                }
            }
        }
        .toast($toast)
    }

    // MARK: Totals

    private var totals: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            AdaptiveStack(spacing: 10) {
                ForEach(MilkStorage.allCases) { storage in
                    StatTile(
                        title: storage.shortTitle,
                        value: unit.format(ml: total(in: bags.filter { $0.storage == storage })),
                        tint: storage == .freezer ? Palette.frozenMilk : Palette.milkStash
                    )
                }
            }
            Text("\(Format.plural(bags.count, "bag")) · \(unit.format(ml: total(in: Array(bags)))) in all")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xs)
        }
    }

    private func total(in bags: [MilkBag]) -> Double {
        bags.compactMap(\.amountML).reduce(0, +)
    }

    // MARK: Actions

    private var usingBinding: Binding<Bool> {
        Binding(get: { using != nil }, set: { if !$0 { using = nil } })
    }

    /// "Use and log a 120 ml bottle".
    private func logTitle(_ bag: MilkBag) -> String {
        guard let ml = bag.amountML, ml > 0 else { return "Use and log a bottle" }
        return "Use and log a \(unit.format(ml: ml)) bottle"
    }

    private func use(_ bag: MilkBag, logFeeding: Bool) {
        bag.usedDate = .now
        let feeding = logFeeding ? logBottle(from: bag) : nil
        context.saveIfChanged()
        if logFeeding {
            NotificationManager.refreshFeedingReminder(context: context)
        }
        CareReminders.refreshMilkStash(context: context)

        let message = logFeeding ? "🍼 Bottle logged from the stash" : "🫙 Bag used"
        toast = Toast(message: message) { [context] in
            bag.usedDate = nil
            if let feeding { context.delete(feeding) }
            context.saveIfChanged()
            Task { @MainActor in
                NotificationManager.refreshFeedingReminder(context: context)
                CareReminders.refreshMilkStash(context: context)
            }
        }
    }

    /// A bottle of breast milk with the bag's amount, given now.
    private func logBottle(from bag: MilkBag) -> Activity {
        let bottle = Activity.create(.feeding, in: context)
        bottle.feedingType = .breastMilkBottle
        bottle.amountML = bag.amountML
        bottle.caregiver = NightPlan.load().shift(at: bottle.startDate)?.parent
        return bottle
    }

    private func discard(_ bag: MilkBag) {
        bag.discarded = true
        context.saveIfChanged()
        CareReminders.refreshMilkStash(context: context)
        toast = Toast(message: "🗑️ Bag discarded") { [context] in
            bag.discarded = false
            context.saveIfChanged()
            Task { @MainActor in CareReminders.refreshMilkStash(context: context) }
        }
    }

    private func moveTitle(_ bag: MilkBag, to destination: MilkStorage) -> String {
        switch destination {
        case .freezer: return "Freeze"
        case .fridge: return bag.storage == .freezer ? "Thaw" : "To fridge"
        case .room: return "To room"
        }
    }

    private func move(_ bag: MilkBag, to destination: MilkStorage) {
        let before = (storage: bag.storage, frozen: bag.frozenDate, thawed: bag.thawedDate)
        let title = moveTitle(bag, to: destination)
        bag.move(to: destination)
        context.saveIfChanged()
        CareReminders.refreshMilkStash(context: context)
        let message = title == "Thaw" ? "Thawing in the fridge · use within 24 hours" : "Moved to the \(destination.shortTitle.lowercased())"
        toast = Toast(message: message) { [context] in
            bag.storage = before.storage
            bag.frozenDate = before.frozen
            bag.thawedDate = before.thawed
            context.saveIfChanged()
            Task { @MainActor in CareReminders.refreshMilkStash(context: context) }
        }
    }
}

/// One bag: how much, when it was pumped, and when to use it by, with a warning when it's close or past.
private struct MilkBagRow: View {
    @ObservedObject var bag: MilkBag
    let unit: VolumeUnit
    let onEdit: () -> Void
    let onUse: () -> Void
    @Environment(\.canEditLog) private var canEditLog

    var body: some View {
        // A bag deleted here or on the partner's phone can redraw once more before the list drops it.
        if bag.isDeleted || bag.managedObjectContext == nil {
            EmptyView()
        } else {
            row
        }
    }

    private var row: some View {
        TimelineView(.everyMinute) { timeline in
            HStack(spacing: Spacing.m) {
                Button(action: onEdit) {
                    HStack(spacing: Spacing.m) {
                        EmojiBadge(emoji: "🫙", tint: Palette.milkStash)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(bag.amountML.map { unit.format(ml: $0) } ?? "Amount not set")
                                .font(.body.weight(.medium))
                            Text(pumpedText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            freshnessLabel(now: timeline.date)
                            if !bag.notes.isEmpty {
                                Text(bag.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit this bag")

                Button("Use", action: onUse)
                    .buttonStyle(.bordered)
                    .tint(Palette.milkStash)
                    .disabled(!canEditLog)
                    .accessibilityLabel("Use this bag")
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    /// "Pumped Oct 24, 9:14 AM", plus when it was frozen or thawed.
    private var pumpedText: String {
        var text = "Pumped \(bag.pumpedDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        if let thawed = bag.thawedDate {
            text += " · thawed \(thawed.formatted(.dateTime.month(.abbreviated).day().hour().minute())), don't refreeze"
        } else if bag.storage == .freezer, let frozen = bag.frozenDate {
            text += " · frozen \(frozen.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return text
    }

    private func freshnessLabel(now: Date) -> some View {
        let freshness = bag.freshness(now: now)
        let icon: String
        let color: Color
        switch freshness {
        case .fresh:
            icon = "calendar"
            color = .secondary
        case .useSoon:
            icon = "exclamationmark.circle.fill"
            color = Palette.warning
        case .pastBest:
            icon = "exclamationmark.triangle"
            color = Palette.warning
        case .expired:
            icon = "exclamationmark.triangle.fill"
            color = Palette.danger
        }
        // The words ("Use soon", "Past its use-by date") and the icon say it, not only the color;
        // the text stays readable while the icon carries the tint.
        return Label {
            Text(bag.useByText(now: now))
                .foregroundStyle(freshness == .fresh ? Color.secondary : Color.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .font(.caption.weight(freshness == .fresh ? .regular : .semibold))
    }
}

/// Adds a bag by hand, or edits one.
struct MilkBagEditor: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml

    let bag: MilkBag?

    @State private var amount: Double = 0
    @State private var pumpedDate = Date.now
    @State private var storage: MilkStorage = .fridge
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    Stepper(value: $amount, in: 0...unit.maxValue, step: unit.step) {
                        LabeledContent("Amount", value: unit.format(value: amount))
                            .monospacedDigit()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unit.presets, id: \.self) { preset in
                                Button(unit.format(value: preset)) { amount = preset }
                                    .buttonStyle(.bordered)
                                    .tint(amount == preset ? Color.accentColor : Color.secondary)
                                    .accessibilityAddTraits(amount == preset ? .isSelected : [])
                            }
                        }
                    }
                }

                Section {
                    DateField("Pumped", selection: $pumpedDate, in: ...Date.now)
                    if let bag, let thawed = bag.thawedDate {
                        LabeledContent("Thawed", value: thawed.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Picker("Stored in", selection: $storage) {
                            ForEach(storageOptions) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                } footer: {
                    Text(storageFooter)
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if bag != nil && canEditLog {
                    Section {
                        Button("Delete bag", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("To take it out of the stash, use Use or Discard instead. Delete is for a bag added by mistake.")
                    }
                }
            }
            .navigationTitle(bag == nil ? "Add a bag" : "Edit bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(amount <= 0 || !canEditLog)
                }
            }
            .confirmationDialog("Delete this bag?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
        }
        .threeAMSheet()
    }

    /// Any place for a new bag. An existing one can stay, or go where `MilkBag.possibleMoves` allows.
    private var storageOptions: [MilkStorage] {
        guard let bag else { return MilkStorage.allCases }
        let allowed = Set([bag.storage] + bag.possibleMoves)
        return MilkStorage.allCases.filter { allowed.contains($0) }
    }

    private var storageFooter: String {
        if bag?.isThawed == true {
            return "Thawed milk keeps up to 24 hours in the fridge. Never refreeze it (CDC)."
        }
        if bag?.storage == .freezer && storage == .fridge {
            return "Moving frozen milk to the fridge thaws it: use it within 24 hours, and don't refreeze it (CDC)."
        }
        return MilkStorageGuide.summary
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let bag else { return }
        amount = bag.amountML.map(unit.fromML) ?? 0
        pumpedDate = bag.pumpedDate
        storage = bag.storage
        notes = bag.notes
    }

    private func save() {
        let target = bag ?? MilkBag.create(amountML: nil, pumpedDate: pumpedDate, storage: storage, in: context)
        target.amountML = amount > 0 ? unit.toML(amount) : nil
        target.pumpedDate = pumpedDate
        target.move(to: storage)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        CareReminders.refreshMilkStash(context: context)
        dismiss()
    }

    private func delete() {
        guard let bag else { return }
        context.delete(bag)
        context.saveIfChanged()
        CareReminders.refreshMilkStash(context: context)
        dismiss()
    }
}
