#if DEBUG
import CoreData
import Foundation

/// Two weeks of realistic sample entries for a six-week-old baby named Ava, for App Store
/// screenshots and trying things out. Debug builds only; none of this is in the App Store build.
///
/// Two ways to load it:
/// - Launch with the argument `-MyBabySampleData YES` (Xcode › Product › Scheme › Edit Scheme ›
///   Run › Arguments). The root view checks for it once at startup.
/// - Settings › About (debug builds) › **Load sample data**.
///
/// It adds a new baby (it never touches an existing one's log) and selects it, unless a baby
/// named Ava is already there. It also turns on a night plan for "Maya" and "Sam", replacing the
/// plan on this iPhone. Nothing is scheduled as a notification. See docs/screenshots.md.
@MainActor
enum SampleData {
    /// `-MyBabySampleData YES` puts this key in the launch arguments' defaults domain.
    static let launchArgumentKey = "MyBabySampleData"
    static let babyName = "Ava"

    /// Set after the first check, so the launch argument is acted on once per launch.
    private static var checkedLaunchArgument = false

    /// At startup: loads the sample log when the launch argument asks for it.
    static func loadIfRequested() {
        guard !checkedLaunchArgument else { return }
        checkedLaunchArgument = true
        guard UserDefaults.standard.bool(forKey: launchArgumentKey) else { return }
        load()
    }

    /// Adds Ava and her two weeks, unless she's already there.
    static func load(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        let existing = (try? context.fetch(Baby.fetchAll())) ?? []
        if let ava = existing.first(where: { $0.name == babyName }) {
            Baby.select(ava)
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let birthDate = calendar.date(byAdding: .day, value: -44, to: today) ?? today
        let baby = PersistenceController.shared.createBaby(name: babyName, birthDate: birthDate)
        baby.sex = .female
        // Entries attach to the selected baby.
        Baby.select(baby)

        let plan = nightPlan(startingOn: calendar.date(byAdding: .day, value: -14, to: today) ?? today)
        plan.save()

        var random = SeededRandom(seed: 2026)
        for offset in (0...13).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            addDay(day, plan: plan, random: &random, context: context)
        }

        addGrowth(birthDate: birthDate, context: context)
        addVaccines(birthDate: birthDate, today: today, context: context)
        addAppointments(today: today, context: context)
        addMilestones(today: today, context: context)
        addMilkStash(today: today, context: context)

        context.saveIfChanged()
        SharedPlanSync.push(plan, context: context)
    }

    // MARK: Night plan

    /// Maya and Sam split each night at 2 AM, swapping who goes first.
    private static func nightPlan(startingOn day: Date) -> NightPlan {
        var plan = NightPlan.load()
        plan.isEnabled = true
        plan.mode = .split
        plan.parent1Name = "Maya"
        plan.parent2Name = "Sam"
        plan.nightStartMinutes = 21 * 60
        plan.nightEndMinutes = 7 * 60
        plan.handoffMinutes = 2 * 60
        plan.swapEachNight = true
        plan.anchorDay = day
        plan.anchorParent = .parent1
        return plan
    }

    // MARK: The daily log

    /// About eight feeds, seven diapers, naps and night sleep, and every other day a bath.
    private static func addDay(_ day: Date, plan: NightPlan, random: inout SeededRandom, context: NSManagedObjectContext) {
        let now = Date.now

        func at(_ minutes: Int) -> Date {
            day.addingTimeInterval(TimeInterval((minutes + random.int(-12...12)) * 60))
        }

        func add(_ kind: ActivityKind, _ date: Date, configure: (Activity) -> Void) {
            guard date <= now else { return }
            let activity = Activity.create(kind, startDate: date, in: context)
            configure(activity)
            if kind == .feeding || kind == .diaper {
                activity.caregiver = plan.shift(at: date)?.parent
            }
        }

        // Feeds, roughly every three hours. Night feeds are bottles of pumped milk, so either parent can give them.
        let feedTimes = [1 * 60 + 10, 4 * 60 + 20, 7 * 60 + 30, 10 * 60 + 15, 13 * 60, 15 * 60 + 45, 18 * 60 + 30, 21 * 60 + 15]
        for (index, minutes) in feedTimes.enumerated() {
            let date = at(minutes)
            let isNight = minutes < 7 * 60 || minutes >= 21 * 60
            add(.feeding, date) { feed in
                if isNight {
                    feed.feedingType = index.isMultiple(of: 2) ? .breastMilkBottle : .formula
                    feed.amountML = Double(90 + random.int(0...4) * 10)
                } else {
                    feed.feedingType = .breast
                    feed.leftMinutes = random.int(7...15)
                    feed.rightMinutes = random.int(5...13)
                }
            }
        }

        // Diapers: mostly wet, a few dirty, all a healthy yellow.
        let diaperTimes = [1 * 60 + 30, 4 * 60 + 40, 7 * 60 + 50, 10 * 60 + 40, 13 * 60 + 20, 16 * 60 + 10, 19 * 60]
        for (index, minutes) in diaperTimes.enumerated() {
            add(.diaper, at(minutes)) { diaper in
                let type: DiaperType = index == 2 || index == 5 ? .mixed : (index == 3 && random.chance(0.5) ? .dirty : .wet)
                diaper.diaperType = type
                if type != .wet {
                    diaper.poopColor = .yellow
                    diaper.poopConsistency = random.chance(0.7) ? .seedy : .soft
                }
            }
        }

        // Sleep: night stretches and four naps, each with a start and an end.
        let sleeps: [(start: Int, length: Int)] = [
            (0, 55), (1 * 60 + 40, 150), (4 * 60 + 50, 140),
            (8 * 60 + 15, 90), (11 * 60, 85), (14 * 60, 75), (16 * 60 + 30, 55),
            (21 * 60 + 45, 120),
        ]
        for sleep in sleeps {
            let start = at(sleep.start)
            let end = start.addingTimeInterval(TimeInterval((sleep.length + random.int(-15...20)) * 60))
            guard end <= now else { continue }
            add(.sleep, start) { $0.endDate = end }
        }

        if Calendar.current.component(.day, from: day).isMultiple(of: 2) {
            add(.bath, at(19 * 60 + 30)) { _ in }
        }

        // The vitamin drops the pediatrician recommended, as the parents logged them.
        add(.medication, at(9 * 60)) { dose in
            dose.medicationName = "Vitamin D drops"
            dose.dosage = "1 drop"
        }

        // A pumping session most mornings, to keep night bottles in the fridge.
        if random.chance(0.6) {
            add(.pumping, at(6 * 60)) { session in
                session.pumpLeftML = Double(50 + random.int(0...4) * 5)
                session.pumpRightML = Double(45 + random.int(0...4) * 5)
                session.amountML = (session.pumpLeftML ?? 0) + (session.pumpRightML ?? 0)
                session.durationMinutes = 15 + random.int(0...5)
            }
        }
    }

    // MARK: Health

    /// Birth, the first weeks and the one-month checkup, near the WHO median for girls.
    private static func addGrowth(birthDate: Date, context: NSManagedObjectContext) {
        let points: [(days: Int, kg: Double, cm: Double?, note: String)] = [
            (0, 3.35, 49.8, "Birth"),
            (5, 3.18, nil, "Newborn checkup"),
            (14, 3.52, 51.2, "2-week checkup"),
            (31, 4.24, 53.6, "1-month checkup"),
            (41, 4.58, nil, "Home scale"),
        ]
        for point in points {
            let entry = GrowthEntry.create(in: context)
            entry.date = birthDate.addingTimeInterval(TimeInterval(point.days * 86_400 + 10 * 3600))
            entry.weightKg = point.kg
            entry.lengthCm = point.cm
            entry.notes = point.note
        }
    }

    private static func addVaccines(birthDate: Date, today: Date, context: NSManagedObjectContext) {
        func addVaccine(_ name: String, dose: String, date: Date, given: Bool, lot: String = "") {
            let vaccine = Vaccine.create(in: context)
            vaccine.name = name
            vaccine.doseLabel = dose
            vaccine.date = date
            vaccine.isGiven = given
            vaccine.provider = given ? "Maple Street Pediatrics" : ""
            vaccine.lotNumber = lot
            vaccine.notes = ""
        }
        addVaccine("Hepatitis B (HepB)", dose: "Dose 1 of 3", date: birthDate, given: true, lot: "HB4821A")
        addVaccine("RSV antibody (nirsevimab)", dose: "1 dose", date: birthDate.addingTimeInterval(86_400), given: true, lot: "RS2290K")
        addVaccine("Hepatitis B (HepB)", dose: "Dose 2 of 3", date: birthDate.addingTimeInterval(31 * 86_400), given: true, lot: "HB5530C")
        let twoMonths = Calendar.current.date(byAdding: .day, value: 16, to: today) ?? today
        for name in ["DTaP", "Hib", "Pneumococcal (PCV)", "Polio (IPV)", "Rotavirus (RV)"] {
            addVaccine(name, dose: "Dose 1", date: twoMonths, given: false)
        }
    }

    /// The one-month checkup two weeks ago, and the two-month one coming up with questions to ask.
    private static func addAppointments(today: Date, context: NSManagedObjectContext) {
        let past = Appointment.create(in: context)
        past.title = "1-month checkup"
        past.date = (Calendar.current.date(byAdding: .day, value: -13, to: today) ?? today).addingTimeInterval(10 * 3600)
        past.provider = "Dr. Rivera"
        past.location = "Maple Street Pediatrics"
        past.notes = "Growing well. Keep up the vitamin D drops."
        past.reminderMinutes = nil
        past.questionList = [VisitQuestion(text: "How often should she be feeding at night?", isAsked: true)]

        let next = Appointment.create(in: context)
        next.title = "2-month checkup"
        next.date = (Calendar.current.date(byAdding: .day, value: 16, to: today) ?? today).addingTimeInterval(9.5 * 3600)
        next.provider = "Dr. Rivera"
        next.location = "Maple Street Pediatrics"
        next.notes = ""
        next.reminderMinutes = 1440
        next.questionList = [
            VisitQuestion(text: "Is her spit-up after night bottles normal?"),
            VisitQuestion(text: "How much tummy time should we do each day?"),
            VisitQuestion(text: "What should we expect after the 2-month shots?"),
        ]
    }

    /// Two keepsakes, without photos.
    private static func addMilestones(today: Date, context: NSManagedObjectContext) {
        let smile = Milestone.create(in: context)
        smile.title = "First smile"
        smile.emoji = "😊"
        smile.date = Calendar.current.date(byAdding: .day, value: -5, to: today) ?? today
        smile.notes = "A real one, right after her morning feed. Sam saw it first."

        let bath = Milestone.create(in: context)
        bath.title = "First bath"
        bath.emoji = "🛁"
        bath.date = Calendar.current.date(byAdding: .day, value: -36, to: today) ?? today
        bath.notes = "She didn't mind it at all."
    }

    private static func addMilkStash(today: Date, context: NSManagedObjectContext) {
        let yesterday = (Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today).addingTimeInterval(6 * 3600)
        MilkBag.create(amountML: 100, pumpedDate: yesterday, storage: .fridge, in: context)
        let lastWeek = (Calendar.current.date(byAdding: .day, value: -8, to: today) ?? today).addingTimeInterval(6 * 3600)
        MilkBag.create(amountML: 120, pumpedDate: lastWeek, storage: .freezer, in: context)
        MilkBag.create(amountML: 90, pumpedDate: lastWeek, storage: .freezer, in: context)
    }
}

/// Repeatable "random" numbers, so the sample log is the same every time.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((next() >> 33) % span)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double(next() >> 11) / Double(UInt64(1) << 53) < probability
    }
}
#endif
