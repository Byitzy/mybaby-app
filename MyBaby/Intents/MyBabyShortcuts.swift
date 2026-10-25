import AppIntents

/// The phrases Siri knows without any setup, also shown in the Shortcuts app and Spotlight.
///
/// Apple's rules, checked for every phrase below:
/// - each phrase names the app exactly once (`\(.applicationName)`: "MyBaby", or "My Baby" from
///   `INAlternativeAppNames` in MyBaby-Info.plist);
/// - at most one parameter per phrase, and only `AppEnum` or `AppEntity` parameters (never a number or
///   text, which Siri asks for instead);
/// - at most 10 `AppShortcut`s per app.
///
/// The 10, in order: diaper, bottle, start breastfeeding, stop breastfeeding, asleep or awake, ask,
/// cry alerts, pumping, bath or temperature, diary note. Everything else (Switch Breastfeeding Side, Start
/// Sleep, End Sleep, Log Medicine, When Did Baby Last Eat?, Start or Stop White Noise) is in the Shortcuts
/// app and Spotlight, and can be added to Siri from there. The README has the full list.
///
/// Phrases with `\(\.$baby)` use the babies' names, which `SiriBabyNames` keeps up to date
/// (`updateAppShortcutParameters()`).
struct MyBabyShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .pink

    static var appShortcuts: [AppShortcut] {
        // 1
        AppShortcut(
            intent: LogDiaperIntent(),
            phrases: [
                "Log a \(\.$type) diaper in \(.applicationName)",
                "Log a diaper in \(.applicationName)",
                "Log a diaper change in \(.applicationName)",
                "Log a diaper for \(\.$baby) in \(.applicationName)",
                "Add a \(\.$type) diaper in \(.applicationName)",
                "\(.applicationName), \(\.$type) diaper",
            ],
            shortTitle: "Log Diaper",
            systemImageName: "drop"
        )
        // 2
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Log a \(\.$type) bottle in \(.applicationName)",
                "Log a bottle in \(.applicationName)",
                "Log \(\.$type) in \(.applicationName)",
                "Log a bottle for \(\.$baby) in \(.applicationName)",
                "The baby had a bottle in \(.applicationName)",
                "\(.applicationName), the baby had a \(\.$type) bottle",
            ],
            shortTitle: "Log Bottle",
            systemImageName: "waterbottle"
        )
        // 3
        AppShortcut(
            intent: StartBreastfeedingIntent(),
            phrases: [
                "Start breastfeeding in \(.applicationName)",
                "Start breastfeeding on the \(\.$side) in \(.applicationName)",
                "Start nursing in \(.applicationName)",
                "Start nursing on the \(\.$side) in \(.applicationName)",
                "Start breastfeeding \(\.$baby) in \(.applicationName)",
                "\(.applicationName), start breastfeeding",
            ],
            shortTitle: "Start Breastfeeding",
            systemImageName: "timer"
        )
        // 4
        AppShortcut(
            intent: StopBreastfeedingIntent(),
            phrases: [
                "Stop breastfeeding in \(.applicationName)",
                "Finish breastfeeding in \(.applicationName)",
                "Stop nursing in \(.applicationName)",
                "Done breastfeeding in \(.applicationName)",
                "Stop the feeding timer in \(.applicationName)",
                "\(.applicationName), stop breastfeeding",
            ],
            shortTitle: "Stop Breastfeeding",
            systemImageName: "stop.circle"
        )
        // 5
        AppShortcut(
            intent: SleepOrWakeIntent(),
            phrases: [
                "\(.applicationName), the baby's \(\.$change)",
                "\(.applicationName), the baby is \(\.$change)",
                "The baby is \(\.$change) in \(.applicationName)",
                "The baby \(\.$change) in \(.applicationName)",
                "Baby \(\.$change) in \(.applicationName)",
                "Log sleep for \(\.$baby) in \(.applicationName)",
            ],
            shortTitle: "Asleep or Awake",
            systemImageName: "moon.zzz"
        )
        // 6
        AppShortcut(
            intent: AskMyBabyIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$question)",
                "Ask \(.applicationName) about \(\.$question)",
                "Check \(\.$question) in \(.applicationName)",
                "When did the baby last eat in \(.applicationName)",
                "When did my baby last eat in \(.applicationName)",
                "When was the last feed in \(.applicationName)",
                "When did \(\.$baby) last eat in \(.applicationName)",
            ],
            shortTitle: "Ask MyBaby",
            systemImageName: "questionmark.bubble"
        )
        // 7
        AppShortcut(
            intent: CryAlertsIntent(),
            phrases: [
                "\(\.$action) cry alerts in \(.applicationName)",
                "\(\.$action) listening in \(.applicationName)",
                "\(.applicationName), \(\.$action) cry alerts",
                "\(.applicationName), \(\.$action) listening",
                "Listen for crying in \(.applicationName)",
            ],
            shortTitle: "Cry Alerts",
            systemImageName: "ear"
        )
        // 8
        AppShortcut(
            intent: LogPumpingIntent(),
            phrases: [
                "Log pumping in \(.applicationName)",
                "Log a pumping session in \(.applicationName)",
                "Log pumping on the \(\.$side) in \(.applicationName)",
                "Log pumping for \(\.$baby) in \(.applicationName)",
                "I just pumped in \(.applicationName)",
                "\(.applicationName), log pumping",
            ],
            shortTitle: "Log Pumping",
            systemImageName: "drop.circle"
        )
        // 9
        AppShortcut(
            intent: LogBathOrTemperatureIntent(),
            phrases: [
                "Log a \(\.$entry) in \(.applicationName)",
                "Add a \(\.$entry) in \(.applicationName)",
                "Log the baby's \(\.$entry) in \(.applicationName)",
                "\(.applicationName), log a \(\.$entry)",
            ],
            shortTitle: "Bath or Temperature",
            systemImageName: "thermometer.medium"
        )
        // 10
        AppShortcut(
            intent: AddDiaryNoteIntent(),
            phrases: [
                "Add a note in \(.applicationName)",
                "Add a diary note in \(.applicationName)",
                "Write in \(.applicationName)'s diary",
                "Write \(\.$kind) in \(.applicationName)",
                "Add a note for \(\.$baby) in \(.applicationName)",
                "\(.applicationName), add a note",
            ],
            shortTitle: "Add Diary Note",
            systemImageName: "book"
        )
    }
}
