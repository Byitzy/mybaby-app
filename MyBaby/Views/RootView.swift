import CoreData
import SwiftUI

struct RootView: View {
    /// Looked up each time: turning sync on or off opens the stores in a new container.
    private var context: NSManagedObjectContext { PersistenceController.shared.viewContext }
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var cloudStatus = CloudStatus.shared
    @AppStorage(SettingsKey.threeAMMode) private var threeAMMode: ThreeAMMode = .off
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    /// Moves on every minute while 3 AM mode follows the night, so it turns on and off by itself.
    @State private var now = Date.now
    /// Kept here rather than in AppContent, which is rebuilt when iCloud is switched on or off.
    /// Plain state rather than `@SceneStorage`: restoring the tab there made the tab bar open the
    /// wrong tab on some iOS versions. A fresh launch starts on Today.
    @State private var selectedTab: AppTab = .today

    var body: some View {
        Group {
            if let message = cloudStatus.reloadingMessage {
                ProgressView(message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Rebuilt from scratch after iCloud is switched on or off, so its fetches see the reopened stores.
                AppContent(selectedTab: $selectedTab)
                    .id(cloudStatus.storeGeneration)
            }
        }
        // The current container's context, so screens rebuilt after the stores reopen use it.
        .environment(\.managedObjectContext, context)
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: RunLoop.main)
        ) { _ in
            // The partner's log, or one being restored, may have just arrived.
            PersistenceController.shared.checkForImportedBaby()
            // The other parent changed something: pick up a new night schedule, and time the
            // feeding reminder from their latest feed too.
            if SharedPlanSync.pull(context: context) {
                Task { await NotificationManager.refreshNightShiftReminders() }
            }
            NotificationManager.refreshFeedingReminder(context: context)
            NotificationManager.refreshAppointmentReminders(context: context)
            // The partner may have given a dose or used a bag from the stash.
            CareReminders.refresh(context: context)
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
                .receive(on: RunLoop.main)
        ) { notification in
            // A download from iCloud finished.
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil
            else { return }
            PersistenceController.shared.checkForImportedBaby()
            DuplicateBabies.shared.check()
        }
        .alert("iCloud", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cloudStatus.lastError ?? "")
        }
        .threeAMLook(threeAMMode.isActive(at: now, plan: NightPlan(data: nightPlanData)))
        // On top of 3 AM mode's tint, so the microphone indicator keeps its own color.
        .overlay {
            ListeningBorder(isDim: threeAMMode.isActive(at: now, plan: NightPlan(data: nightPlanData)))
        }
        // While this device is the nursery monitor (see `NurseryMonitor`).
        .nurseryMonitorCover()
        // A tap on a cry alert opens Today.
        .onReceive(CryAlertTaps.shared.$openToday) { open in
            guard open else { return }
            selectedTab = .today
            CryAlertTaps.shared.openToday = false
        }
        .task(id: threeAMMode) {
            guard threeAMMode == .atNight else { return }
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Timers don't run in the background, so catch up right away when the app opens.
            if phase == .active { now = .now }
        }
        // Checked once per launch, so appearing again is harmless.
        .onAppear { loadSampleDataIfRequested() }
    }

    /// Debug builds launched with `-MyBabySampleData YES` get Ava's sample log, for screenshots.
    private func loadSampleDataIfRequested() {
        #if DEBUG
        SampleData.loadIfRequested()
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { cloudStatus.lastError != nil },
            set: { if !$0 { cloudStatus.lastError = nil } }
        )
    }
}

/// Onboarding until there's a baby, then the tabs. While iCloud brings down a log, a progress screen.
private struct AppContent: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var cloudStatus = CloudStatus.shared
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @AppStorage(SettingsKey.selectedBaby, store: .shared) private var selectedBabyID = ""
    /// Remembered by RootView, so the parent is on the same tab after the rebuild.
    @Binding var selectedTab: AppTab
    @State private var today = Calendar.current.startOfDay(for: .now)
    /// False when the owner invited this iPhone to the log as view only.
    @State private var canEditLog = true

    init(selectedTab: Binding<AppTab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        // One container, so appearing and disappearing are reported once however the content changes.
        ZStack { content }
            // Lets `setSyncEnabled` wait until these screens are gone before it swaps the stores.
            .onAppear { cloudStatus.contentOnScreen += 1 }
            .onDisappear { cloudStatus.contentOnScreen -= 1 }
    }

    @ViewBuilder
    private var content: some View {
        if let message = cloudStatus.awaitingImport,
           !babies.contains(where: { PersistenceController.shared.isJoined($0) }) {
            waiting(message)
        } else if let baby = Baby.preferred(from: Array(babies), selectedID: selectedBabyID) {
            tabs(baby)
        } else {
            OnboardingView()
                // A new or restored log starts on Today, at the top of More.
                .onAppear {
                    selectedTab = .today
                    NavigationMemory.shared.reset()
                }
        }
    }

    /// While iCloud downloads the log, instead of onboarding asking for a new baby.
    private func waiting(_ message: String) -> some View {
        VStack(spacing: 20) {
            ProgressView(message)
            Button("Cancel") {
                Task { await PersistenceController.shared.stopAwaitingImport(timedOut: false) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Each tab is rebuilt when another baby is picked, so its fetches show that baby's log.
    private func tabs(_ baby: Baby) -> some View {
        tabView(baby)
            // A tapped "How did it go?" notification opens that visit's recap.
            .visitRecapRouting()
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    today = Calendar.current.startOfDay(for: .now)
                    SharedPlanSync.pull(context: context)
                    Task { await NotificationManager.refreshNightShiftReminders() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                today = Calendar.current.startOfDay(for: .now)
            }
            // View-only family can look but not log. Checked again when iCloud brings changes, since
            // the owner can change someone's permission at any time.
            .environment(\.canEditLog, canEditLog)
            .task(id: baby.objectID) { canEditLog = PersistenceController.shared.canEdit(baby) }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
                canEditLog = PersistenceController.shared.canEdit(baby)
            }
    }

    /// The five tabs. From iOS 18 each tab is tied to its `AppTab` value with `Tab`, so a tap on the
    /// tab bar always opens that tab; iOS 17 uses `tabItem` and `tag`.
    @ViewBuilder
    private func tabView(_ baby: Baby) -> some View {
        if #available(iOS 18, *) {
            TabView(selection: $selectedTab) {
                Tab("Today", systemImage: "house", value: AppTab.today) { todayTab(baby) }
                Tab("History", systemImage: "list.bullet.rectangle", value: AppTab.history) { historyTab(baby) }
                Tab("Reports", systemImage: "chart.bar.xaxis", value: AppTab.reports) { reportsTab(baby) }
                Tab("Health", systemImage: "cross.case", value: AppTab.health) { healthTab(baby) }
                Tab("More", systemImage: "ellipsis.circle", value: AppTab.more) { moreTab(baby) }
            }
        } else {
            TabView(selection: $selectedTab) {
                todayTab(baby)
                    .tabItem { Label("Today", systemImage: "house") }
                    .tag(AppTab.today)
                historyTab(baby)
                    .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
                    .tag(AppTab.history)
                reportsTab(baby)
                    .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
                    .tag(AppTab.reports)
                healthTab(baby)
                    .tabItem { Label("Health", systemImage: "cross.case") }
                    .tag(AppTab.health)
                moreTab(baby)
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
                    .tag(AppTab.more)
            }
        }
    }

    /// Also rebuilt when the date changes so "today" rolls over at midnight.
    private func todayTab(_ baby: Baby) -> some View {
        TodayView(day: today, baby: baby)
            .id(TodayID(day: today, baby: baby.objectID))
    }

    private func historyTab(_ baby: Baby) -> some View {
        HistoryView(baby: baby)
            .id(baby.objectID)
    }

    private func reportsTab(_ baby: Baby) -> some View {
        ReportsView(baby: baby)
            .id(baby.objectID)
    }

    private func healthTab(_ baby: Baby) -> some View {
        HealthView(baby: baby)
            .id(baby.objectID)
    }

    /// Kept as it is when switching babies, so the Babies list stays open; Settings inside is rebuilt.
    private func moreTab(_ baby: Baby) -> some View {
        MoreView(baby: baby)
    }

    private struct TodayID: Hashable {
        let day: Date
        let baby: NSManagedObjectID
    }
}
