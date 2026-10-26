# MyBaby 👶

A simple iPhone app (it runs on iPad too) that makes it easy for new parents to track their newborn's care
and share clear reports with their pediatrician.

Everything is designed for one-handed, half-asleep use at 3 a.m.: big buttons, one tap
to log the common things, and an **Undo** on every quick log.

## Why we made MyBaby

We made MyBaby as new parents. In those first weeks we wanted to really understand what our baby
needed: when they last ate, how they were sleeping, whether we were changing enough diapers, and what
to tell the pediatrician. We also wanted to take turns at night without one of us running on empty.

So we built the app we wished we had, with one rule: **a baby's information belongs to their parents,
and nobody else.**

- **Your data stays with you.** The log is kept on your iPhone and, if you choose, in your own iCloud,
  end-to-end encrypted. There are no MyBaby servers, accounts, ads, tracking or analytics. We never see
  your data.
- **No AI.** There are no AI tools in MyBaby: no chatbot, no AI suggestions, nothing that sends your
  baby's log to be analyzed, and nothing trained on it. The one exception is cry alerts, which use Apple's
  built-in sound recognition to tell crying from other sounds, entirely on the iPhone. Smart reminders are
  plain arithmetic on your own log.
- **Always free.** We won't ask for money: no subscriptions, no in-app purchases, no premium tier, not
  even donations.
- **Honest feedback is all we ask.** Tell us what works, what doesn't and how we can make MyBaby better,
  from Settings › *Send feedback* in the app, or by email at mybaby@manhattin.com.
- **Open for transparency.** The code is public so anyone can check these promises for themselves. It's
  licensed under the [PolyForm Strict License 1.0.0](LICENSE.md): you're welcome to read and review it,
  but it isn't open source. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Features

| Tab | What it does |
| --- | --- |
| **Today** | Baby's name and age (tap it to switch babies or add one), "time since" cards (last feed, last diaper, awake/asleep for), one-tap quick log, and today's timeline. |
| **History** | Every entry grouped by day with a daily summary (the last 30 days, then *Show earlier*), filter by type, tap to edit, swipe to delete. **Mark time** marks a stretch as not tracked or nothing happened, or catches up on it. |
| **Reports** | 7 / 14 / 30-day charts for feedings, bottle amounts, breastfeeding minutes, wet & dirty diapers and sleep, plus daily averages. **Share PDF** creates a one-page report to bring to checkups. **Patterns** finds the baby's rhythms. |
| **Health** | Appointments (with reminders, questions to ask, a visit summary, an after-visit recap, Add to Calendar, and cancel or restore), vaccines (given and upcoming, with lot numbers, the clinic, and a guide to what each one is for and what's normal after), medicine (history, one-tap "Give now" and dose timing), allergies (a reactions log, introducing foods and an allergy card for caregivers), and growth (weight, length and head circumference charts with WHO percentiles). |
| **More** | **Babies** (switch or add), **Night shifts**, **Cry alerts**, **Milestones**, **Diary**, **Parent care** and **Settings**: baby profile, parents (names and whose iPhone this is), iCloud & sharing, ml/oz, 3 AM mode, feed & diaper reminders (every few hours, or smart ones that learn from the log), CSV export, import from another app, privacy. |

What you can log:

- 🍼 **Feeding** — breastfeeding (a live left/right timer, or minutes on each side), bottle of breast milk or formula (amount), or solids (what baby ate).
- 🧷 **Diapers** — pee, poop, both or dry, with optional poop color and consistency (the app flags colors worth calling the pediatrician about).
- 😴 **Sleep** — start a live sleep timer and tap "Woke up", or add a past sleep.
- 🛁 **Baths** — one tap.
- 💊 **Medicine** — name and dose, with recent medicines one tap away.
- 💉 **Vaccines** and 🩺 **appointments** — under the Health tab.
- 📏 **Growth** — weight, length and head circumference from each checkup or a home scale, in kg/cm or lb/oz/in. Health → Growth
  shows the latest of each with the change since the last measurement and a chart over time. Measurements
  are included in the PDF report.
- 🫙 **Pumping** — how much from each side (ml or oz) and how long, with the total. Tap *Pump* on Today.
- 🌡️ **Temperature** — the reading (°C or °F, Settings → *Units*), how it was taken and any symptoms.

### 🫙 Pumping and the milk stash

Tap **Pump** on Today to log a session: the amount from the left and right side, the total, and how long
it took. Turn on **Add to milk stash** to put the milk in the fridge, freezer or at room temperature, as one
bag or split evenly into several. Reports shows a **Pumped per day** chart once you've logged some, the PDF
has a pumping table, and the CSV export has the left, right and duration columns.

More → **Milk stash** shows what's on hand: the total in the fridge, the freezer and at room temperature, and
every bag oldest first with its **use-by date**. A bag close to its date says *Use soon*, and one past it says
so in words as well as in color.

- **Use** takes the bag out of the stash and offers to log a bottle of breast milk with that amount.
- Swipe left to **Discard**. Swipe right to **Freeze** a bag from the fridge, or **Thaw** a frozen one in the
  fridge. Thawed milk can't go back in the freezer.
- **+** adds a bag by hand. Tap a bag to change it.
- *Remind me on the use-by day* sends a notification at 8 AM the day a bag in the fridge or freezer reaches
  its date (room-temperature milk only keeps for hours, so it isn't included).

Use-by dates follow the CDC's breast milk storage guidelines for healthy, full-term babies: room temperature
up to 4 hours, fridge up to 4 days, freezer best within 6 months and acceptable up to 12 months (counted from
when it was pumped), and thawed milk within 24 hours in the fridge, never refrozen. The stash is shared with
your partner like the rest of the log.

### 🌡️ Fever and sickness log

Tap **Temp** on Today to log a temperature: pick the reading on the wheel, how it was taken (rectal, armpit,
ear, forehead or oral) and any symptoms (cough, runny nose, vomiting, diarrhea, rash, fussy, poor feeding).
Temperatures are stored in °C and shown in °C or °F (Settings → *Units*; °F by default in the US).

When a reading is a fever, the editor says so calmly, following the American Academy of Pediatrics (AAP):

- A fever is 100.4 °F (38 °C) or higher taken rectally, in the ear or on the forehead, 100 °F (37.8 °C) by
  mouth, or 99 °F (37.2 °C) under the arm.
- **Under 3 months** (from the baby's birthday): *Call your pediatrician right away, or seek care now.*
- **Older babies:** *Keep an eye on it, and call your pediatrician if you're worried.*
- Always: call emergency services if your baby is struggling to breathe, is unusually hard to wake or floppy,
  has blue or gray lips, or has a seizure.

Readings show up in History and the CSV export, and the PDF report lists them under *Temperatures*.

### 💊 Safe medicine timing

Health → Medicine → **Dose timing** (on each *Give again* row, or in the medicine editor) is where you enter the
timing your pediatrician gave you for a medicine: the least time between doses, and optionally the most doses
in 24 hours. MyBaby never suggests a dose or an interval; the fields start empty.

With timing set, each *Give again* row shows **Next dose allowed at 4:10 AM** or **OK to give now**, worked out
from the last doses either parent logged. Logging a dose sooner than that, or over the daily limit, shows a
warning (in the editor, and a *Give anyway* check on *Give now*), but never stops you. *Notify me when the
next dose is allowed* sends a reminder at that time, on this iPhone only. Medicines are matched by name,
ignoring capitals.

### ⚠️ Allergies

Health → **Allergies** keeps the baby's allergies and reactions in one place, calmly and in your own words.
MyBaby never decides whether something is an allergy, and gives no medical advice beyond the emergency line
below.

- **The allergy list.** Each allergy has the allergen, a type (*Food*, *Medicine*, *Environment*, *Skin
  contact*, *Other*), a status (*Suspected*, *Confirmed*, *Outgrown*), a severity (*Mild*, *Moderate*,
  *Severe*), the reactions seen, who diagnosed it and when (optional), whether there's an **epinephrine
  auto-injector** and where it's kept, and notes. The common food allergens (milk, egg, peanut, tree nuts,
  soy, wheat, fish, shellfish, sesame) and common medicines (amoxicillin, penicillin), plus pollen, dust
  mites, pet dander and latex, are one tap away. Outgrown allergies stay on the list but don't warn. The
  baby's profile starts with a summary, "Allergies: Peanut (confirmed, severe)".
- **Reactions log.** Log a reaction with the time, what the baby had (filled in from the last solids log
  when it was in the last day), a symptoms checklist (hives or rash, swelling, vomiting, diarrhea, coughing or
  wheezing, trouble breathing, unusual sleepiness, fussiness, eczema flare, other), how bad it was, what you
  did (antihistamine, epinephrine, called the doctor, went to the ER), notes and an optional photo of a rash.
  The photo is handled exactly like milestone photos: a small JPEG inside the record, end-to-end encrypted,
  without its location. One tap adds the food as a **suspected allergy**, links the reaction to an allergy
  already listed, marks an outgrown one as suspected again, or raises an allergy's severity, when you save.
- **Emergency banner.** Ticking *trouble breathing* or *swelling* pins a banner to the top of the reaction
  editor: "Trouble breathing, or swelling of the face, lips or tongue, can be an emergency. Call 911 now.",
  with a call button. The number is the emergency number for your region from `support-resources.json` (the
  same one the support lines use, from the iPhone's Region setting or the region you picked). VoiceOver
  reads it out when it appears.
- **Introducing foods.** In the solids editor, tag the common allergens the food had (*Contains*, optional
  chips). Allergies → **Introducing foods** lists the nine food allergens: *Not tried yet*, or *Tried 4 times ·
  first Oct 2* and *Last given 9 days ago*, with any reaction logged within a day after it (or linked to an
  allergy to it). It doesn't say when or how often to give a food; the footer points to the pediatrician.
  When a solids log has a confirmed or suspected allergen (tagged, or named in what baby ate, as a whole
  word: "eggs" but not "eggplant"), the editor says so gently before saving: "Mavie has a suspected egg
  allergy."
- **Medicine warning.** Logging a medicine, or setting its dose timing, whose name matches a medicine allergy
  (ignoring case, either name containing the other) shows "Mavie's list says she's allergic to amoxicillin.
  Check with your doctor or pharmacist before giving it." ("Mavie's allergy list includes amoxicillin." until
  the baby's sex is set). *Give now* asks first. You can always save. The matching is
  `AllergyMatch.medicineMatches` in `MyBaby/Services/AllergyMatch.swift`, a pure function.
- **Siri and the widget check too.** Siri's *Log Medicine* asks first when the medicine matches: "Mavie's
  allergy list includes amoxicillin. Log it anyway?" Saying no logs nothing. The widget's **Medicine** button
  never logs a match: it shows **Check allergy list** instead and opens the app, where the warning says more
  and you can still log it. The button checks again when tapped, in case an allergy was added since the widget
  was drawn. The Bottle button has no check: a bottle is formula or breast milk, with no food name to compare,
  and MyBaby never decides that a formula and a milk allergy are related.
- **Allergy card.** Allergies → **Allergy card for caregivers** is a one-page summary for daycare,
  grandparents or a babysitter: name and age, the emergency line with your region's number, the auto-injector
  and where it's kept, confirmed and suspected allergies with severity and reactions, recent reactions (last
  90 days) and an optional note (kept on this iPhone only). Share it as a PDF or as text; it goes only where
  you send it.
- **Reports.** The visit summary and its PDF, and the PDF report, list the allergies and the reactions in
  their period. The CSV export adds `MyBaby-allergies.csv` and `MyBaby-reactions.csv`, and the log's CSV has an
  *Allergens* column for tagged solids.

Allergies and reactions belong to the baby like everything else, so they sync and are shared with your
partner; view-only family can read them but not change them. Removing a baby removes them too, and merging
two copies of a baby keeps one allergy per allergen (filling in what's missing and keeping every reaction).

### 📈 WHO growth percentiles

Set the baby's sex (Settings → *Baby* → **Sex (for growth charts)**, or when adding the baby) and Health →
Growth shows where each weight, length and head circumference falls on the **WHO Child Growth Standards**, e.g.
"4.2 kg · 48th percentile". The charts draw the WHO 3rd, 15th, 50th, 85th and 97th percentile curves as
faint gray lines behind the baby's own, and the PDF report adds percentile columns to the growth table.
Very low or high values show as "<1st" or ">99th". Without a sex and birthday, Growth asks for them
instead of guessing.

Percentiles use age from the birthday (the WHO charts are for babies born at term; your pediatrician may
use a corrected age for a baby born early). They're there to help you follow along, not to diagnose:
your pediatrician can explain what they mean for your baby.

> The numbers are the WHO's own LMS values, bundled in `MyBaby/Resources/who-growth.json`: the daily
> "expanded tables" for weight-for-age, length/height-for-age and head circumference-for-age, girls and boys,
> birth to 1856 days, from https://www.who.int/tools/child-growth-standards/standards (files
> `wfa-boys/girls-zscore-expanded-tables.xlsx`, `lhfa-boys/girls-zscore-expanded-tables.xlsx` and
> `hcfa-boys/girls-zscore-expanded-tables.xlsx`), downloaded on 2026-10-25 and checked against the
> CDC's copies of the WHO monthly tables (https://www.cdc.gov/growthcharts/who-data-files.htm). From
> day 731 the length table is standing height, as in the WHO standard. Percentiles come from
> z = ((X/M)^L − 1) / (L·S) and the normal distribution (`MyBaby/Services/GrowthStandards.swift`).

### ❔ Missing data isn't zero

In a tracking app, a time nobody used the app looks just like a time nothing happened. "No wet diapers" isn't
the same as "nobody wrote the wet diapers down", so MyBaby works out how much of each day was actually
tracked and never counts missing time as zeros.

- **Coverage.** Every entry shows someone was looking after the baby for a while: 2.5 hours either side of
  it, and a sleep for its whole length. A stretch with nothing logged is **untracked** when more than 5 of
  its hours fall in the day (7 AM–9 PM, or outside your night shifts' hours), or when it's longer than
  8 hours at all; shorter quiet stretches at night are fine, since babies sleep without anyone logging it.
  A finished day is **fully tracked** when at least 85% of its waking hours were covered, **partly tracked**
  below that, and has **no data** when none of it was. Today is still in progress. The rules and their
  numbers are in `MyBaby/Services/Coverage.swift`, as pure functions that can be tested without Core Data.
- **Nothing logged since 9:10 AM (5 h).** When a gap is open, Today shows a card with three answers:
  **Catch up**, **Not tracked** or **Nothing happened**. ✕ hides it until the next gap. Settings →
  *Reminders* → **Haven't logged in a while** (off by default) also sends a notification when a gap
  begins, but never while you're off duty on a night shift (and, without a night plan, not before 7 AM).
- **Not tracked / Nothing happened.** From the card, or History → **Mark time**: mark a stretch as *not
  tracked* (*With a caregiver*, *At daycare*, *Forgot to log* or *Other*, with a note like "grandma"), or as
  *nothing happened* (you were tracking and there was nothing to log). History shows them as gray rows,
  "Not tracked · with grandma · 1–5 PM". Tap one to change it, swipe to delete it (it asks first). They
  belong to the baby like everything else, so your partner sees them too. Marked times always win over
  what the app works out.
- **Catch up.** For a gap, or any stretch you pick: how many wet and dirty diapers, bottles (about how much
  each, in ml or oz), breastfeeds and naps (about how long each), plus a note. MyBaby adds that many
  **approximate** entries spread evenly over the stretch, marks it *caught up* (tracked), and shows them
  with "≈" before the time ("approx." for VoiceOver). They count in totals like any other entry, and the CSV
  has an *Approximate* column.
- **Reports** show a light gray **No data** column on days nobody tracked instead of a zero bar, and draw
  partly tracked days lighter, with a legend under the chart. Daily averages use only fully tracked days
  ("Based on 5 fully tracked days (2 partly tracked days not counted)"), or partly tracked ones when there
  are none, and say so.
- **The PDF report** has a *Tracked* column (Full, Partial or None), shows "–" rather than 0 on days nobody
  tracked, and notes that days not fully tracked may undercount, so low numbers on them may not be real.
  The visit summary says the same.
- **Patterns** skip untracked time, so a gap in the log isn't read as a long time between feeds or a long
  awake stretch.
- **A forgotten sleep timer** doesn't become a 14-hour sleep unnoticed: after 12 hours, Today's sleeping
  banner asks *Still asleep? Over 12 hours — set the wake-up time*, which opens the sleep to fix it.

The CSV export (Settings → *Your data*) includes `MyBaby-tracking.csv` with the marked times.

### 🔍 Patterns

Reports → **Patterns** looks at the last 7 or 14 days and puts the baby's rhythms into plain sentences
and small charts:

- **Night wake-ups**: the times the baby usually wakes at night ("around 2:30 AM, 5 of 7 nights"), from
  night feeds and the ends of night sleeps. Night is 9 PM to 7 AM.
- **Time between feeds**: the average gap, during the day and at night.
- **Longest sleep**: the longest stretch, the longest each day, and whether it's getting longer.
- **Awake between sleeps**: how long the baby usually stays awake between daytime sleeps.
- **Busiest diaper times**: changes by hour of the day.

It only describes what was logged. It doesn't say what's normal for a baby's age; that's a question for
your pediatrician. The math is in `MyBaby/Services/PatternFinder.swift`, as pure functions that can be
tested without Core Data.

### ⏰ Smart reminders

Settings → **Feed & diaper reminders** (on each phone) reminds you when the baby will probably want to eat,
or need a change, from your own log, and keeps moving the reminder as the log changes.

- **Feeding reminder:** *Off*, *Every few hours* (a fixed time after the last feed began, as before), or
  **Smart (learns from your log)**, which goes off *Remind me* 0, 5, 10 (the default) or 15 minutes before
  the predicted time: "Mavie will probably be hungry around 2:40 (usually every 2 h 50 min)".
- **Never wait longer than…** (Smart): the longest it will ever wait between feeds, day or night. It starts
  at your *Every few hours* time, or 3 hours.
- **Diaper check** (off by default) is gentler: "Diaper check for Mavie? It's been 3 h", never while the
  baby is asleep. If one came due during a sleep, it comes 5 minutes after the baby wakes.
- **Let baby sleep** (off by default): no feed reminders while a sleep is going on. By default they come as
  usual, since young babies may need waking for feeds. Ask your pediatrician how long your baby can go
  between feeds, especially in the first weeks.
- **Snooze 15 min** on the notification brings it back in 15 minutes, until something new is logged.
- Nothing while the breastfeeding timer is running. During a night shift only the parent on duty is
  reminded, with their alert style (vibrate only or sound), the same way as the wake-ups; outside shifts,
  and without a night plan, both phones are.

**How it predicts.** `MyBaby/Services/CarePredictions.swift` has the rules as pure functions (in debug builds,
`po CarePredictions.checkSampleScenarios()` runs a set of sample logs through them), and
`MyBaby/Services/SmartReminders.swift` schedules the notifications:

- Feeds are measured from the **start** of one feed to the **start** of the next, over the last **5 days**,
  and each gap counts half as much for every **1.5 days** it's older, so recent days dominate.
- Day and night are learned separately: night is your night shifts' hours, or 7 PM to 7 AM.
- Feeds less than **40 minutes** after the previous one ended are one feed (a top-up bottle, a second side
  later), as long as the whole session is under 90 minutes. Solids aren't counted.
- The prediction is the weighted **median** of the gaps, and the likely range is the middle half (25th to
  75th percentile), so one odd gap doesn't move it.
- **Missing data isn't learned:** a gap that crosses time marked *Not tracked*, or a long stretch with nothing
  logged (see *Missing data isn't zero*), is skipped, as is one that touches a caught-up entry or is longer
  than 8 hours. A forgotten night doesn't teach it that the baby sleeps 9 hours.
- With fewer than **8** usable gaps it's a rough guess: your *Every few hours* time, or a common gap for the
  baby's age (2.5 h in the first 4 weeks, 3 h to 3 months, 3.5 h to 6 months, then 4 h). Today doesn't show
  rough guesses, but the reminder still uses them.
- Diapers work the same way from the changes. When at least 60% of changes come within 30 minutes after a
  feed, the next change is expected after the next feed.
- Predictions never go past *Never wait longer than*.

**On Today**, the *Last feed* card adds a subtle "Next feed around 2:40" with the likely range ("2:20–3:05"),
and the *Last diaper* card does the same when diaper checks are on. They're hidden while it's only a rough
guess. Tap one for **How MyBaby predicts this**: the explanation ("Usually every 2 h 50 min in the daytime,
about 3 h 30 min at night, from the last 3 days") and the data it used ("From 24 feeds in the last 3 days;
2 missing stretches skipped"). The large *Baby at a glance* widget shows "Next feed around 2:40" under the
last feed.

**Keeping up with your partner.** Reminders are worked out again after every save, when your partner's
changes arrive from iCloud, when the app opens, and when the night plan or a setting changes. iCloud wakes
the app in the background with a silent push when your partner logs (the `remote-notification` background
mode), so a reminder is usually moved before it goes off. If your phone couldn't sync in time (no
connection, Low Power Mode, or iOS holding back background work), a reminder can still go off after your
partner already fed the baby; it's moved as soon as their feed arrives.

It's all worked out on the iPhone; nothing new leaves it. Predictions describe what was logged and aren't
medical advice.

### 🩺 Pediatrician visit prep

- **Questions to ask**: each appointment has a checklist. Add questions as they come up, check them off
  at the visit, swipe to delete. Health → Appointments → **Add a question for the next visit** adds one
  in a tap: it goes to the next upcoming appointment, or, with none scheduled, waits in a list that moves
  into the next appointment you add.
- **Visit summary**: open an appointment (or swipe right on it) for what's happened since the previous
  appointment, or the last 30 days if there wasn't one: feeds, diapers (with any poop colors worth
  mentioning), sleep, growth with percentiles, temperatures, medicine given, vaccines, and your questions.
  **Share PDF** turns it into a one-page summary to hand to the pediatrician. It includes what the doctor
  said at the previous visit, if you noted it.
- **How did it go?** After a visit, a short, optional recap: what the doctor said, the weight, length and
  head circumference measured (all three go to Growth, dated at the visit), shots given (upcoming
  vaccines are marked as given, or new ones added) and answers to your questions, plus **Book the next
  visit** with the same doctor (after "2-month checkup" it suggests "4-month checkup"). Every part can be
  skipped. It's offered by a notification an hour after the visit ends (appointments count as an hour long;
  only for appointments with a reminder, and only the next 3 are scheduled), a dismissible card on Today for
  3 days, and a row under recent past appointments. Once saved, the appointment shows a summary like
  "Weighed 5.2 kg · 2 shots · notes". The recap is in the shared log, so the other parent's nudges go away
  too; view-only family can read it. (`Views/Health/VisitRecapView.swift`, `Services/VisitFollowUp.swift`.)
  Recaps saved before Growth had head circumference kept it on the appointment; Growth, the reports and the
  export still show it, and editing it in Growth or the recap moves it along.
- **Cancel, not delete**: open an appointment (or long-press it) and tap **Cancel appointment**, separate from
  Delete. After you confirm, it moves to a **Cancelled** group, struck through, with its questions and notes
  kept. Its reminder, the "How did it go?" follow-up and Today card go away, and with *Keep appointments in my
  calendar* on, so does its calendar event. **Restore** (swipe right on it, or open it) brings them all back.
  The visit summary doesn't count a cancelled visit as the previous appointment, the diary leaves it out, and
  the appointments CSV marks it (*Cancelled*, *Cancelled on*). It's in the shared log, so it's cancelled on
  your partner's phone too. (`Models/Appointment+Cancel.swift`.)
- **Places**: type in an appointment's *Location* and MyBaby suggests clinics, hospitals and addresses from
  Apple Maps as you type (name, with the address below). Pick one to save its address, coordinates and
  phone number with the appointment; the list shows the address under the place, and the appointment shows
  a small map (tap it to open Maps), **Directions** (driving, in Apple Maps) and **Call** when Maps has a
  number. You can still type any place and just save it, and older appointments keep their text. Suggestions
  lean toward the last place you picked, or your iPhone's Region setting; MyBaby never asks for your location.
  Only what you type in the field is sent to Apple Maps, never before you type, after a short pause in typing
  (`Services/PlaceSearch.swift`, `Models/Appointment+Place.swift`). The visit summary and its PDF include the
  address, and the appointments CSV adds *Address*, *Latitude*, *Longitude* and *Phone* at the end.
- **Vaccine clinics**: a vaccine's *Clinic or provider* field searches Apple Maps the same way, and a picked
  clinic shows its address, map, **Directions** and **Call**. The clock button by this field, and by an
  appointment's *Location*, lists places already picked for vaccines and appointments, so the usual clinic is
  one tap, with nothing searched. The vaccines CSV adds *Provider address*, *Latitude*, *Longitude* and
  *Phone* at the end (`Models/Vaccine+Place.swift`).
- **Vaccine guide** (Health › Vaccines, and the list button in the vaccine editor): 21 vaccines and combination
  shots (routine ones, 6-in-1 and 5-in-1 shots, MMRV, and MenB, MenC, MenACWY and BCG where they're offered),
  searchable by name or brand, including the names on French-language records (DCaT-HB-VPI-Hib, RRO-Var).
  Each has what it protects against and why, roughly when it's given (never exact ages, which differ by
  country), what's common after it, and the rare reactions to watch for. A vaccine typed or saved by any of
  its names shows *About this vaccine* in the editor. **After a vaccine** covers comfort, when to call the
  doctor (with the region's nurse line, like 811 or NHS 111) and the signs of an emergency (with the region's
  emergency number), and the list links it for two days after a shot. The guide links the official schedule
  for the region picked for support lines (AAP and CDC in the US, Québec and Canada, the NHS, or the WHO
  elsewhere). It's bundled and works offline; the notes carry a *Reviewed* date to check yearly
  (`Models/VaccineGuide.swift`, `Views/Health/VaccineGuideView.swift`).
- **After the shots, on Today**: once a vaccine is marked given, Today shows one calm card for the visit
  while there's something to look out for, timed to each vaccine: "After Tuesday's shots" for the first two
  days after most vaccines (soreness, a low fever, fussiness, extra sleep), then, where it applies, "MMR was 9
  days ago" (MMR and MMRV again about days 6 to 14: fever, a mild rash, swollen glands and the rare febrile
  seizure), chickenpox spots up to about 4 weeks (keep them covered around newborns, pregnant people and
  anyone with a weak immune system), rotavirus's first week (the rare signs of intussusception to get care
  for right away), BCG's bump and blister from about 2 to 12 weeks, MenB's more common fever (follow the
  clinic's advice on infant paracetamol) and the RSV antibody's mild first days. Each card has two or three
  short lines, **Comfort, and when to call** and each vaccine's notes. Shots given the same day are one card,
  and it's never shown for a vaccine that's only due. Dismissing it hides it until that visit's next window
  starts, remembered on this iPhone. View-only family see it too (it changes nothing in the log), and in
  3 AM mode its lines stay in readable primary text. Settings › **After vaccines** (off by default, on each
  phone) adds a notification at 9 AM the day a later window starts (MMR and MMRV on day 6, BCG at 2 weeks):
  "MMR was 6 days ago: a fever or mild rash can show up around now. Here's what's normal." Tapping it opens
  Today. Only the next one is pending, and it's moved whenever vaccines change, here or on the partner's
  phone (`Models/VaccineGuide+Watch.swift`, `Services/VaccineFollowUp.swift`,
  `Views/Today/VaccineFollowUpSection.swift`).

### 📅 Appointments in your calendar

- **Add to Calendar**: open an appointment (or long-press it in the list) for iOS's new-event sheet, filled in
  with "Mavie: 2-month checkup", the time (an hour long), the doctor and place, and an alert an hour before.
  A place picked from the suggestions comes with its address and map location, so Calendar shows the map and
  can offer a time-to-leave alert (both here and with *Keep appointments in my calendar*).
  You see exactly what's added and pick the calendar. It needs no calendar permission (on iOS 17 the sheet
  runs outside the app).
- **Keep appointments in my calendar** (Settings › *Calendar*, per phone, off by default) asks for full
  calendar access, then adds every upcoming appointment (all babies, from 24 hours ago on) to the default
  calendar or one you pick, such as a shared Family calendar. Edits update the event, deleting or cancelling
  an appointment removes it (restoring adds it back), and changes your partner makes show up too. Events get
  no alerts, since MyBaby already sends the reminder chosen on each appointment. If the picked calendar is
  deleted, appointments go to the default one.
  Turning it off asks whether to keep or remove the events.
- **Two phones, one family calendar**: before adding an event, MyBaby looks for one with the same title at the
  same time in that calendar and adopts it, so turning it on on both phones doesn't make duplicates. It's still
  best to turn it on on one phone only.
- Which event belongs to which appointment is kept on the phone (`CalendarEvents.json` in Application
  Support, keyed by the appointment's `uuid`), never in the shared log (`Services/CalendarSync.swift`).
  Events added with *Add to Calendar* are remembered next to it (`CalendarAddedEvents.json`: the event's
  identifier when MyBaby has calendar access, otherwise the title and time), so *Delete all MyBaby data* can
  remove them too.

### 🤱 Breastfeeding timer

Tap **Feed** on Today → *Breastfeed · start timer*, then tap the side you're starting on. Tap the other side
(or **Switch**) to change sides, **Pause** if baby takes a break, and **Done** to save the feed with the
minutes on each side (rounded, and at least 1 minute for a side you used). **Discard** throws it away.

- Before you start, MyBaby suggests which side to start on: the one that had less time last feed (or wasn't
  used at all), or, if both had the same, the one the last feed didn't end on. Go with what your lactation
  consultant or pediatrician recommends.
- You can close the app. The timer keeps going, shows as a card on Today, and appears on the Lock Screen and
  in the Dynamic Island with **Switch**, **Pause** and **Done** buttons.
- It's kept in the App Group on the iPhone, so it survives the app being closed or restarted.

### 📲 Widgets, Live Activities and Siri

**Home Screen widgets** (small, medium and large) show how long ago the last feed was (and what it was), the
last diaper, and how long baby has been asleep or awake, plus who's on night duty when you use Night shifts.
The medium and large widgets have buttons to log a **Wet** or **Dirty** diaper and to start or end a
**Sleep**, without opening the app. **Lock Screen widgets** show the time since the last feed (round and
inline) and the last feed and diaper (rectangular).

**Make each widget your own.** Touch and hold a widget, then **Edit Widget** (on the Lock Screen: touch and
hold the Lock Screen, **Customize**, then tap the widget):

- **Baby:** *Follow the app* (the default: whichever baby you're viewing in MyBaby) or a particular baby.
  With twins, put one widget for each side by side; each shows its baby's name and its buttons log for that
  baby, whoever is shown in the app.
- **Show** (Home Screen): pick the details and their order, from the last feed, last diaper, asleep or awake,
  who's on night duty (shown at the top during a night shift), the next medicine dose (when the dose timing
  you entered allows it, in the same words as the app), the last pumping, the milk stash, and feeds and
  diapers today. A small widget fits 3 lines, a medium 4 and a large 6; the first ones you pick are shown.
- **Buttons** (medium and large, up to 4): **Wet**, **Dirty**, **Both**, **Sleep** / **Woke up**,
  **Bottle** (the same bottle as last time, which the button shows), **Breastfeed** (starts the timer on the
  side MyBaby suggests; **Switch** while it runs) and **Medicine** (the medicine given last, recorded with the
  dose you logged last time; it never suggests a dose). While the dose timing you entered doesn't allow
  another dose yet, the Medicine button shows the time it will instead, and opens the app. When the medicine
  matches one on the baby's allergy list, it shows **Check allergy list** and opens the app (see *Allergies*).
- **Show** (Lock Screen): one of the last feed, last diaper, asleep or awake, next medicine dose, or who's
  on night duty.

Left as they are, widgets look and work as they always did. These settings are kept by iOS on each iPhone,
for each widget: they aren't synced, so you and your partner each set up your own.

**Live Activities:** the breastfeeding timer and a running sleep ("Sleeping 0:42", with **Woke up**) appear on
the Lock Screen and in the Dynamic Island, counting by themselves. A sleep your partner starts shows up on
your phone too, the next time MyBaby opens or syncs. Swipe one away and it stays away for that sleep.
While cry alerts listen, there's one for that too, and every widget shows a small mic (see *Cry alerts*).

**Siri and Shortcuts** work without any setup, also from the Shortcuts app, the Action button, Spotlight and
Siri on Apple Watch. Say "in MyBaby" (or "in My Baby") so Siri knows which app you mean. These are the
phrases Siri knows; each has a few ways to say it:

| # | Shortcut | Say | Siri answers |
|---|---|---|---|
| 1 | Log Diaper | "Log a wet diaper in MyBaby" (wet, dirty, wet and dirty, also "pee" or "poopy"), "Log a diaper in MyBaby", "Log a diaper change in MyBaby", "Log a diaper for Mavie in MyBaby", "MyBaby, dirty diaper" | "Logged a wet diaper for Mavie." |
| 2 | Log Bottle | "Log a formula bottle in MyBaby", "Log a bottle in MyBaby", "Log breast milk in MyBaby", "Log a bottle for Noah in MyBaby", "The baby had a bottle in MyBaby" | "Logged a bottle of formula for Mavie." (with an amount in ml or oz from Shortcuts: "Logged 120 ml of formula…"; without a type, the same as the last bottle) |
| 3 | Start Breastfeeding | "Start breastfeeding in MyBaby", "Start breastfeeding on the left in MyBaby", "Start nursing in MyBaby", "Start breastfeeding Noah in MyBaby" | "Started the timer on the right side for Mavie." (the side MyBaby suggests, unless you say one) |
| 4 | Stop Breastfeeding | "Stop breastfeeding in MyBaby", "Finish breastfeeding in MyBaby", "Stop nursing in MyBaby", "Stop the feeding timer in MyBaby" | "Saved Mavie's feed: left 10 minutes, right 5 minutes." |
| 5 | Asleep or Awake | "MyBaby, the baby's asleep", "The baby woke up in MyBaby", "The baby is awake in MyBaby", "Baby fell asleep in MyBaby", "Log sleep for Noah in MyBaby" | "Sleep timer started for Mavie. Sweet dreams." / "Got it. Mavie slept 1 hour, 20 minutes." |
| 6 | Ask MyBaby | "Ask MyBaby when the baby last ate", "When did the baby last eat in MyBaby?", "When did Noah last eat in MyBaby?", "Ask MyBaby about the last diaper", "…how long the baby has slept", "…about today", "…about the next medicine dose", "…who's on duty" | See below |
| 7 | Cry Alerts | "Start cry alerts in MyBaby", "Stop listening in MyBaby", "MyBaby, turn off cry alerts", "Listen for crying in MyBaby" | "Listening for crying. Keep your iPhone near the baby, and plugged in." Starting opens MyBaby: iPhone only lets the microphone start while the app is on screen. Stopping works in the background. |
| 8 | Log Pumping | "Log pumping in MyBaby", "Log pumping on the left in MyBaby", "I just pumped in MyBaby" | Asks "How much did you pump?", then "Logged 120 ml pumped for Mavie." In Shortcuts it can also add the milk to the stash (fridge, freezer or room temperature). |
| 9 | Bath or Temperature | "Log a bath in MyBaby", "Log a temperature in MyBaby", "Log the baby's temperature in MyBaby" | "Logged a bath for Mavie." / asks "What was the temperature?", then "Logged 38.4 °C for Mavie. Fever. Keep an eye on it, and call your pediatrician if you're worried." |
| 10 | Add Diary Note | "Add a note in MyBaby", "Write in MyBaby's diary", "Write a letter in MyBaby", "Add a note for Noah in MyBaby" | Asks "What would you like to write?", then "Saved to Mavie's diary." (a letter for later: "Sealed a letter for Mavie, to open at 18.") |

**Ask MyBaby** answers, briefly:

- **When the baby last ate:** "Mavie's last feed was 2 hours, 10 minutes ago, a bottle of formula, 120 ml."
  (or how long breastfeeding has been going, while the timer runs)
- **The last diaper:** "Mavie's last diaper was 40 minutes ago, wet."
- **Sleep:** "Mavie has been asleep for 1 hour, 20 minutes, since 9:10 PM." or "Mavie is awake. The last sleep
  ended 2 hours ago, after 45 minutes."
- **Today so far:** "So far today, Mavie has had 6 feeds and 7 diapers, 5 wet and 3 dirty, and has slept 9 hours,
  10 minutes." When part of today wasn't logged (the same coverage as Reports), it starts "From what's logged
  so far today" and says there may have been more.
- **The next medicine dose:** "By the dose timing you entered for Mavie: Tylenol, next dose allowed at 4:10 AM.
  Vitamin D, OK to give now." Only from the dose timing you entered; it never suggests a dose.
- **Who's on duty:** "Maya is on duty now, until 2:00 AM. Then Sam until 7:00 AM."

**Choosing the baby.** Every action has an optional **Baby**. Left out, it's the baby shown in the app. With
twins, say the name ("Log a diaper for Noah in MyBaby"); Siri learns the babies' names when MyBaby opens and
whenever a baby is added, renamed or removed. Replies use the baby's name once it's set.

**In Shortcuts and Spotlight only** (Apple allows an app 10 Siri phrases; add any of these to Siri from the
Shortcuts app if you like): **Switch Breastfeeding Side**, **Start Sleep**, **End Sleep**, **Log Medicine**
(pick from medicines given before; it records the dose you logged last time, never suggests one, says
when the dose timing you entered didn't allow one yet, and asks first when the medicine is on the baby's
allergy list), **When Did Baby Last Eat?** (kept for shortcuts made with it; the same answer as Ask MyBaby) and **Start or Stop White Noise** (white, pink or brown, on the
nursery monitor, at the volume set there).

Everything logged this way counts for the parent on night duty, like Today's quick log. On a log that's view
only on this iPhone, logging says "This log is view only on this iPhone"; questions still work. Siri never
reads the diary back, not even the note just added, and nothing from the care page is available to Siri.

> How it works: the actions are App Intents in `MyBaby/Intents/`, and the 10 phrases are in
> `MyBabyShortcuts.swift` (each names the app once, with at most one choice in it, such as wet or dirty). "My
> Baby" is accepted as the app's name through `INAlternativeAppNames` in `MyBaby-Info.plist`. The baby choice
> is the widgets' `BabyEntity` (`Shared/BabyEntity.swift`); in the app it lists the babies from the log,
> without the widgets' *Follow the app*. Logging goes through the same `QuickLog` as the widget buttons.

> How the buttons work: widgets and Live Activities are drawn by a separate extension (`MyBabyWidgets`), which
> never opens the database. The app writes a small summary of what they show (`WidgetSnapshot.json`, with a
> part for each baby) to the App Group whenever the log changes, and their buttons run inside the app
> (`LiveActivityIntent`), which logs the entry for the widget's baby and redraws everything. The summary
> stays on the iPhone, isn't synced, and holds only what the widgets show. The Edit Widget options are App
> Intents (`MyBabyWidgets/WidgetConfigurationIntents.swift`), and the baby list comes from that same summary
> (`Shared/BabyEntity.swift`).

### 📱 iPad

MyBaby runs on iPad as an iPad app, not a stretched iPhone one, which suits the nursery monitor and a
tablet on the changing table. The iPhone layout doesn't change.

- **Sidebar** (iPadOS 18 and later): the five tabs can show as a sidebar, or as the tab bar along the top.
  iPadOS 17 keeps the tab bar.
- **Wider screens, laid out for them.** Today puts the "time since" cards and the quick log side by side.
  Reports shows the charts two by two, with all six averages in one row. History, Health, More and Settings
  keep to a readable column in the middle of the screen.
- **Sheets** open as form-sized cards in the middle of the screen (iPadOS 18), never full screen.
- **Keyboard:** ⌘1 to ⌘5 open Today, History, Reports, Health and More; ⌘N on Today or History asks what to
  log and opens it. Hold ⌘ to see them.
- **Pointer:** the quick log buttons and History's filter chips light up under the pointer.
- **Every orientation, Split View and Slide Over.** In a narrow window the iPhone layout comes back.
- **Nursery monitor:** a big, dim clock above the status. In landscape the status is centered on the left
  and the controls sit beside it; the night light's glow fills the whole screen.
- **Widgets:** the same small, medium and large Home Screen widgets, and the Lock Screen ones.

The layout pieces live in `MyBaby/Views/Components/RegularWidth.swift`: `readableContentWidth()`, the
`CardColumns` layout, `formSheetSizing()` and the keyboard shortcuts. They only do something in a regular
width (`horizontalSizeClass`), so iPhone screens stay exactly as they were.

### ⌚ Apple Watch

Log from your wrist without reaching for the phone in the dark. The watch app shows the baby you're viewing on
the iPhone:

- **At a glance:** who's on night duty, how long since the last feed (and what it was) and the last diaper,
  and how long baby has been asleep or awake. The times count up by themselves.
- **Big buttons:** **Wet**, **Dirty**, **Both**, **Sleep** / **Woke up**, **Bottle** (formula or breast milk,
  then an amount in your ml or oz setting) and **Medicine** (medicines you've logged before, recorded with the
  dose you logged last time, which the button shows; it never suggests a dose). A medicine on the baby's
  allergy list shows **⚠︎** and isn't logged from the watch. Tapping it says why instead: "Mavie's list
  includes amoxicillin. Log it on the iPhone after checking with your doctor or pharmacist." The iPhone
  checks too, so a medicine added to the allergy list while the watch was away isn't logged either, and the
  watch says so when it next hears from the iPhone.
- **Breastfeeding timer:** **Start left** or **Start right** (with MyBaby's suggested side starred), then a live
  clock with each side's time, **Switch** and **Stop & save**. It's the same timer as on the iPhone, its Live
  Activity and Siri.
- Every tap buzzes and shows a short confirmation, with **Undo** for 5 seconds.
- After 9 PM, before 7 AM and during a night shift, the buttons turn a dim red.
- **Complications** for the watch face (round, rectangular, inline and corner): the last feed, the last
  diaper, asleep or awake, the next medicine dose (from the dose timing you entered) or who's on night duty.
  Each one follows the baby shown on the iPhone, or a particular baby: with twins, put one for each side by
  side, and each shows its baby's name.

**Choosing what a complication shows.** Touch and hold the watch face, tap **Edit**, swipe to the
complications and tap one, then pick from MyBaby's list: each detail for the baby on the iPhone (*Last
feed* first), then each baby by name ("Mavie: last feed"; with twins also their last diaper and sleep).
Complications already on your watch face, and ones you add without choosing, look as they always did: the
last feed, for the baby on the iPhone. The choices are kept on each watch, so you and your partner each set
up your own.

**No phone nearby?** Taps still work. They're queued on the watch ("Will sync to iPhone") and logged at the time
you tapped as soon as the iPhone is back in range, even if you closed the app. The home screen says how many
are waiting, and "Last synced 3 min ago" when what it shows may be out of date. The complications keep showing
the last summary for every baby, with your taps on the watch added.

> How it works: the watch has no database and never talks to a server. It talks only to your own iPhone, over
> Apple's WatchConnectivity, directly between the two devices. The iPhone sends a small summary (the same one
> the widgets use, with each baby's part trimmed to what the complications show, plus your bottle amounts,
> recent medicine names with any allergy-list matches, and the suggested side) whenever it changes, and each
> tap on the watch is sent back as a small command that the iPhone logs through the same code as Siri and the
> widgets (`MyBaby/Services/WatchBridge.swift`). Before logging a medicine from the watch, the iPhone checks
> the baby's allergy list with the same name matching as the app's warnings (`AllergyMatch.medicineMatches`).
> The watch keeps the last summary in its own App Group, for the complications. Their options are an App
> Intent (`MyBabyWatchWidgets/ComplicationIntent.swift`) with the widgets' baby choice (`Shared/BabyEntity.swift`,
> which reads that summary on the watch); watchOS shows them as the ready-made list above
> (`recommendations()`).

### 👶👶 Twins and siblings

Track more than one baby. Tap the baby's name on Today (or go to More → **Babies**) to switch between them
or **Add a baby**. Each baby has their own log, history, reports, health records, reminders and export; the
app shows one baby at a time. Settings → *Babies* lists every baby; tap one (or ⓘ in More → Babies) for
their profile: name, birthday, sex for the growth charts, and, while there's more than one, **Remove from
MyBaby**, which removes them and everything logged for them. Feed and diaper reminders are per baby, so twins each
get theirs. Widgets can each be set to a baby (Edit Widget → **Baby**), so twins can sit side by side on
the Home Screen or Lock Screen, each with their own buttons.

If you share the log with your partner, a baby you add joins the same share, so it shows up on their phone
too. New babies are added on the phone of the parent who created the log: a parent who joined their
partner's log sees every baby, but can't add one themselves (Core Data can't put a brand-new baby into
someone else's share from the invited phone).

### 🌙 Night shifts — so both parents get equal sleep

More → **Night shifts** lets two parents share the nights:

- **Split each night** — e.g. Maya 9 PM–2 AM, Sam 2 AM–7 AM. Turn on *Swap who goes first each night*
  so you each get the first half and the second half equally often. *Split the night evenly* puts the
  handoff in the middle.
- **Take turns by night** — one parent covers the whole night while the other sleeps through, switching
  every night (or every 2–7 nights).

The plan shows a 7-night schedule and each parent's average sleep per night, and warns you if one parent
is getting less. The person taking over gets a **wake-up reminder at the handoff** (and optionally a
bedtime heads-up). The rotation is calculated from the plan itself, so both phones agree on who's on
duty, and with Family sharing the plan syncs to your partner's phone by itself.

**Parents and whose iPhone this is.** The parents' names live in Settings → **Parents**: two fields,
*Parent 1* and *Parent 2*, with quick suggestions (Mom, Dad, Mama, Papa, Mommy, Daddy) under an empty one.
Any two parents work, including two moms or two dads; until you add names, the app says "Parent 1" and
"Parent 2". Below them, **This iPhone belongs to** picks either parent, or *Shared iPhone (both of us)*.
Night-shift wake-ups and cry alerts only buzz the person the phone belongs to. Night shifts shows the
names with an *Edit names in Settings* link, and the same *This iPhone belongs to* choice under
*Reminders on this iPhone*; both screens read and change the same setting. The names are shared with your
partner's phone as part of the plan; whose iPhone it is stays on each phone.

Onboarding asks for *Your name* and *Your partner's name* (optional), and makes the phone yours. A phone
that joined a partner's log, or one still on the old "both of us" default, gets a one-time **Who's using
this iPhone?** card on Today once both names are known: tap a name or *Both of us*, or ✕ to dismiss it.

The Today screen shows who's on duty right now. Feeds and diapers logged during a shift are credited to
the parent on duty (you can change it under *Handled by*), and **Reports → Night duty** shows how many
each of you handled.

**Vibrate-only wake-ups** (the default) buzz without any sound, so the other parent and the baby keep
sleeping. The wake-up repeats every 30 seconds, up to 5 times, until you tap **I'm up**. With an Apple
Watch, the buzz is a tap on your wrist. Prefer a sound? Switch *Alert style* to *Sound*.

**Apple Watch:** iOS picks where an alert goes. If you're wearing your watch and your iPhone is locked, it
taps your wrist (and you can tap *I'm up* there). If the watch is on its charger, the iPhone buzzes
instead. There's no setup. With MyBaby's watch app installed, *I'm up* on the watch tells the iPhone (over
WatchConnectivity, queued if the phone is out of reach), which stops the rest of that wake-up's buzzes. If you use a Sleep Focus or Do Not Disturb at night,
add MyBaby to its allowed apps.

### 👂 Cry alerts — buzz the right parent when the baby cries

Today (or More) → **Cry alerts** → *Start listening* turns the iPhone into a baby monitor for the night. Apple's
built-in sound classifier (SoundAnalysis) listens for crying **on the device**. Audio is never recorded,
saved or sent anywhere.

- **Both parents' phones can listen.** With the baby in your room, both phones hear the cry, but each one
  buzzes only when **its owner is on duty**, so the off-duty parent keeps sleeping. No pairing or network
  is needed.
- The on-duty parent is buzzed again every minute while the crying continues. If it goes on for longer than
  you choose (2, 5 or 10 minutes), **the other parent's phone buzzes too**.
- Alerts use the alert style from Night shifts, so they can be vibrate only.
- While it's listening, a soft **teal border pulses around the whole app**, so it's obvious the microphone is on.
  It turns orange and pulses faster while the baby is crying. It stays still with Reduce Motion and dims in 3 AM mode.
- Sensitivity is Low, Medium or High. **Stop listening** is set on each iPhone: when you stop it (the default),
  when the night shifts end, at a time you pick, or after a number of hours (1 to 12). A nursery monitor always
  listens until it's stopped.
- Keep the phone close to the baby, plugged in, and leave MyBaby running in the background. Swiping the
  app away stops listening.
- **Outside the app, too.** While this iPhone listens, a **Live Activity** shows on the Lock Screen: a mic,
  "Listening for crying", since when, and "until 7:00 AM" when it stops by itself, with a **Stop** button
  that really stops listening. In the Dynamic Island it's a small green mic (tap and hold for Stop). During
  a cry it turns orange: "Crying for 1:20", counting up. It's dark, dim and still, whatever the 3 AM mode
  setting, so it doesn't light up the room. It ends when listening stops, however that happens: Stop, the
  time you chose, a call that ends listening, or swiping MyBaby away. If iOS closes MyBaby without saying so,
  it's marked out of date at the stop time and removed the next time MyBaby opens (or with Stop). Swipe it
  away and it stays away until you start listening again; it isn't shown when Live Activities are off for
  MyBaby (iPhone Settings › MyBaby), and iOS ends any Live Activity after about 8 hours, while listening
  goes on. When listening starts again by itself after a call, it appears the next time you open MyBaby.
- **Widgets** show it as well, whichever baby they're set to: a small mic capsule, "Listening", at the top
  of the medium and large Home Screen widgets (just the mic on the small one), and a tiny mic on the Lock
  Screen widgets. It turns orange, "Crying", during a cry (a small waveform on the Lock Screen, which
  usually shows without color). The widgets stop showing it at the stop time even if the app can't redraw
  them. A cry starting or ending redraws them at most once a minute.
- A nursery monitor shows neither: it has its own dim full-screen view by the crib, its **Stop monitor**
  asks first (a Lock Screen button wouldn't), and the parents' phones already show whether it's listening.
- Without a night plan, the phone simply buzzes whenever it hears crying.
- **Battery.** Listening is built to sip power. A cheap loudness check looks at the sound all the time
  (an RMS level, against a slowly adapting "how loud is the room" floor, so a fan or white noise counts as
  quiet), and Apple's classifier only wakes for a few seconds when something stays about 10 dB louder than
  the room for half a second. The second before is kept and classified too, so the start of a cry isn't
  lost. Audio is taken at 16 kHz in large chunks, the classifier hears 1.5 s windows with little overlap,
  and the screen isn't kept awake. In Low Power Mode the check is a little less eager (Cry alerts says
  so); listening never stops because of it. Keep the phone or the monitor plugged in overnight anyway.
  Debug builds show how much the classifier ran in Cry alerts' footer (`CryGate`).

> How it shows outside the app: `CryMonitor.listeningSummary` goes into the widgets' snapshot
> (`WidgetSnapshot.listening`, optional, so a snapshot written before it reads as not listening) and into
> the Live Activity (`ListeningActivityAttributes`, started, updated and ended in
> `Services/LiveActivities.swift`, drawn in `MyBabyWidgets/ListeningLiveActivity.swift`). Stop is
> `StopListeningIntent` in `Shared/ButtonIntents.swift`, which runs in the app like the other buttons.

> Cry alerts help you rest; they aren't a medical or safety monitor.

> How vibrate-only works: iOS doesn't let apps vibrate a notification without a sound, so MyBaby plays a
> silent sound file (`MyBaby/Sounds/silence.wav`), and iPhone vibrates for it. This needs haptics turned on
> in iPhone Settings › Sounds & Haptics. Reminders are notifications, not system alarms, so allow
> notifications from MyBaby.

### 📡 Nursery monitor — an old iPhone or iPad by the crib

A spare device can stay by the crib and alert the parent on duty's phone, with no server.

**Setting it up**

1. Install MyBaby on the spare iPhone or iPad. On an iPad the monitor works in either orientation, with a
   big clock (see *iPad*).
2. Sign in to iCloud on it with a parent's Apple ID, or with another Apple ID you invite to the log with
   permission to make changes. Turn on iCloud sync (or open the invitation link).
3. Open MyBaby once on each parent's iPhone with iCloud on, and pick *This iPhone belongs to* in Night
   shifts. That sets up the phone to receive the monitor's alerts (Cry alerts says when it's ready).
4. On the spare device: Cry alerts → **Use this device as the baby monitor**. It's offered when iCloud
   sync is on, the device can change the log and there's a baby; otherwise it says why.
5. Keep it plugged in and on Wi-Fi, with MyBaby open. Tap **Test alert** to check both phones get it.

The monitor's screen is dark and dim and stays on while it's open. It shows "Listening for Noah" (or
"Noah is crying · 1:20"), who's on duty, **white noise** (Off, White, Pink or Brown, with a volume and a
sleep timer of 30 min, 1 h, 2 h or all night), a **night light** (a warm, dim glow), a hint to keep it
plugged in, Test alert, and **Stop monitor**, which asks first. The parents' phones show it on Today and in
Cry alerts: "Nursery monitor (Noah's iPad) · Listening · checked 3 min ago". If a listening monitor hasn't
checked in for 15 minutes, they warn: "The monitor hasn't checked in since 2:10 AM. Is it plugged in and on
Wi-Fi?" That warning comes from data already on the phone, not from another notification.

**How alerts reach the phones** (`Services/AlertInboxes.swift`, `Services/RemoteCryAlerts.swift`)

- Each parent's phone keeps a private **alert inbox**: a record zone in its own iCloud private
  database, with a subscription that makes iCloud show "👶 Your baby is crying" whenever a record is added.
  (iCloud only shows visible notifications for subscriptions in a database you own, so the shared log
  itself can't do this.)
- The phone shares the inbox with the people the log is shared with who can make changes, and publishes
  where to deliver as an `AlertInbox` entry in the log: which parent the phone is for, its name ("Sam's
  iPhone") and the inbox's private link. The monitor and the family's devices join each inbox from that.
- When it hears crying, the monitor saves a small `CryAlert` record into the inbox of **the parent on duty**
  (from the night plan), plus phones set to both parents; with no shift going on, every phone. "Still
  crying" follows at most every 2 minutes, and after your *Wake the other parent after* time the other
  parent's inbox gets one too. Records hold only the time, the kind and how long the crying has gone on,
  all encrypted, and are deleted after an hour. Offline, it keeps trying with a growing wait for up to 10
  minutes.
- Detection is the same as on a phone (`CryMonitor` in its `.monitorDevice` mode), but the monitor never
  buzzes itself. White noise is generated on the device and played through the same audio engine, with
  Apple's echo cancellation turned on while it plays, so the device's own noise is taken back out of what
  the microphone hears. Its volume is capped, and the screen reminds you to keep it at least 7 feet (2 m)
  from the crib and quiet (the AAP's advice for sound machines).
- A tap on the alert opens MyBaby on Today. These pushes don't count toward iOS's 64 pending local
  notifications.

**Limitations, plainly**

- How fast a push arrives is up to Apple. It's usually a few seconds, but it isn't guaranteed.
- iCloud's pushes can't be marked time-sensitive, so a Sleep Focus or Do Not Disturb may hold them. Add
  MyBaby to the Focus's allowed apps.
- Routing to the parent on duty needs each parent on their own Apple ID. With one shared Apple ID, every
  phone on it gets every alert (and so does a monitor on that Apple ID, which hides them while it runs).
- How well echo cancellation removes white noise depends on the device; test it with your own.
- It's not a medical or safety device. It helps you rest.

Before the App Store release, deploy the CloudKit schema (see *Running it*) after a monitor has sent a test
alert in development, so the `CryAlert` and `CryAlertTest` record types are in it.

### ⭐ Milestones — a keepsake timeline

More → **Milestones** keeps the moments you want to remember: a first smile, rolling over, a first bath.
Each one has a title, a date, an emoji, a note and as many photos as you like, and the timeline shows them
newest first with the baby's age on that day.

- **Add a milestone** with **+**. Pick one of the suggestions (first smile, first laugh, holds head up, rolls
  over, sits up, first tooth, crawls, first word, first steps, first bath, first outing, first food) or write
  your own.
- **Photos** come from your library (no permission needed: iOS only hands over the photos you pick) or
  **Take photo** with the camera. Tap a photo to see it full screen and swipe between them.
- **Share** sends the photos with a caption ("😊 First smile · Ava · Oct 12 · 6 weeks old") to Messages,
  Mail or anywhere else.
- Milestones belong to the baby, so a shared log shares them, photos included.

It's a keepsake, not a development checklist: there are no "should happen by" ages. Every baby has their own
pace, and your pediatrician is the one to ask about development.

Photos are kept small so they sync quickly: each is scaled down to 1,600 pixels on its long side and saved as
a JPEG under about 600 KB (well inside a CloudKit record), without its location. They're stored inside the
record rather than as separate iCloud files, so they're end-to-end encrypted like everything else.

### 📖 Diary — things to read one day

More → **Diary** is where parents write things down for the baby: what made you smile, something new they
learned, a first, a funny moment, or a letter for them to read when they're older. It has three tabs:
**Diary**, **Summaries** and **Letters**.

- **Writing is one tap**: the pencil button opens a big text area with a few gentle prompts ("What made you
  smile this week?", "What did Mavie learn?"). Prompts use the baby's name, and "she" or "he" only once the
  baby's sex is set in the profile. Each entry has a date, an optional title, a kind (*Moment*, *Learned
  something new*, *A first*, *Funny*, *Letter for later*), who wrote it and optional photos (handled exactly
  like milestone photos: small JPEGs inside the record, end-to-end encrypted, without their location).
- **Written by** starts with this iPhone's parent (Night shifts › *This iPhone belongs to*), or the name last
  used here, with both parents' names one tap away. Every entry shows who wrote it.
- **The diary** is grouped by the baby's months, "Month 3 · 12 Jan – 11 Feb" (by calendar month until a
  birthday is set, and "Before Mavie was born" for anything written earlier), with search and a filter by kind.
  It shows the last 3 months, with *Show earlier* for more; search always looks through the whole diary.
- **Letters for later** can have an *open when*: a birthday (say the 18th) or a date. Until then a letter is
  a sealed envelope, "For Mavie, to open at 18", everywhere in the app, and search never matches its words.
  A parent can always tap **Read anyway** (it's sealed again next time), so nothing is ever locked away.
- **Week and month summaries** are worked out on the fly from the log, never stored: week by week for the
  first 3 months ("Week 6" is the sixth week from the birthday), then month by month ("Month 3" runs from the
  2-month birthday to the day before the 3-month one). Each shows feeds (count and a day), sleep (total and
  longest stretch), diapers, growth with the change and WHO percentile when measured, milestones, vaccines
  and checkups, and the diary entries and photos from those days. Days nobody logged are said honestly,
  "Logged 5 of 7 days", using the same coverage as Reports, so they never read as zero.
- **A note from you** sits at the top of each summary: *Write about this month*. It's a diary entry linked to
  that week or month, so it shows in the diary too, and both parents can add one.
- **On Today**, a small card appears when a summary is ready, the day after the week or month ends: "Mavie is
  3 months old today 🎉 · See her month and write something for her." It can be dismissed (or swiped away)
  and goes by itself after a few days.
- **Month birthday reminder** (off by default, in the diary's ⋯ menu › *Diary settings*): "Mavie is 3 months
  today. Write something she'll love to read one day?" at 10 AM. Only the next one is ever pending.
- **Make a keepsake PDF** (⋯ menu): one month, the first year or everything, with the diary entries and their
  photos, each month's summary and your notes. Letters for later are left out unless you turn them on. It's
  shared through the share sheet, and the temporary copy is deleted when it closes.

Entries belong to the baby like everything else, so a shared log shares the diary, and deleting or merging a
baby takes their diary along. Family invited as view only can read the diary but not write, and don't get
*Read anyway*. The diary isn't locked: it's the baby's, and belongs to everyone the log
is shared with. (The parent care page is the private, locked one.) The diary is part of the CSV export (`MyBaby-diary.csv`).

### 💛 Parent care — recovery and wellbeing, just for you

More → **Parent care** (shown as *Your name's care* on your iPhone, e.g. "Sam's care", after the person
the phone belongs to in Settings → *Parents*, or *My care* on a shared iPhone or before there's a name) is
a private space for any parent to look after themselves.

- **Daily check-in**: how you feel (five faces), last night's sleep, pain from 0 to 10, and a note.
- **My medicines**, with **Took it now** for another dose of anything you've taken before.
- **I gave birth** (off for someone new, and only on this iPhone) adds a **Birth recovery** section with
  **recovery notes**: pain, bleeding and how you're healing, to remember or to ask your doctor or midwife
  about. If you already have recovery notes, it starts on.
- **Mood, last 14 days**: a chart of your check-ins.
- An optional **daily check-in reminder** (off until you turn it on). The notification never says how you've
  been feeling.
- **Export my care log (CSV)**, separate from the baby's export.

**It's private.** Your entries aren't linked to the baby, so they're never shared with your partner, and
they're never in the baby's CSV export or PDF report. They stay on your iPhone, or in your own iCloud,
end-to-end encrypted, if sync is on. (If you and your partner use the same Apple ID, iCloud would show them
on their devices too.)

**It's always locked.** The page opens only after Face ID (or Touch ID, or the iPhone's passcode), and nothing
in it is loaded before. There's no switch to turn the lock off. It locks again every time you leave it, and
as soon as MyBaby stops being active (another app, the app switcher, Control Center, the Lock Screen), so
coming back always asks again. An iPhone without a passcode can't open it at all until one is set. The page
and the screens it opens (My medicines, past check-ins, recovery notes, the note editor) are left out of
screenshots, covered while the screen is recorded, mirrored or sent with AirPlay, and blurred in the app
switcher (`privateScreen()` in `Views/Components/ScreenCaptureShield.swift`). Nothing from the care page
appears in the widgets, on the Apple Watch or in Siri. The lock is `PrivateContentLock` in `MyBaby/Views/Components/PrivacyLock.swift`.

**Gentle support.** If most of your check-ins over the last two weeks were one of the two lowest faces, a
card says that many new parents feel this way and help works, and suggests talking to your doctor or
midwife, with a call button for a line in your region when there's a suitable one. MyBaby doesn't diagnose
anything and doesn't use a screening questionnaire; the check-in is just a mood face.

**Support where you live.** The bottom of the screen always lists help for your region: the emergency
number first, then crisis lines, pregnancy and new-parent support, and nurse or health lines, with hours
and languages when known. The region comes from the iPhone's Region setting (Settings → General → Language
& Region), never from your location, and **Change** next to "Support for …" picks another one (or *Other /
not listed*, which shows your local emergency number and the Find A Helpline directory). In Canada, choose
your province or territory to see its own lines, like Quebec's Info-Santé and Info-Social 811 and
1 866 APPELLE. Covered so far: the US, Canada (every province and territory), the UK, Ireland, Australia,
New Zealand, Israel, France, Germany, the Netherlands, Belgium, Switzerland, Spain, Italy, Sweden, Norway,
Denmark, India, South Africa, Mexico, Brazil, Singapore, Hong Kong and Japan.

The numbers live in `MyBaby/Resources/support-resources.json`. Every resource lists the official pages
(the organization's own site or a government health site) where its number was checked, each region
lists all of them, and the file says when it was last checked (`lastVerified`) and when to check it all
again (`reverifyBy`, six months later). Re-verify every number against those pages by then, and before
adding a region; if a number can't be confirmed, remove it rather than guess. A wrong crisis number is
worse than none.

### 🔴 3 AM mode

Settings → *Display* → **3 AM mode** turns the whole app dark with a dim, warm red tint, so a night feed
doesn't light up the room or wake you up properly. Choose *Off*, *At night* (during your night shifts' hours,
or 9 PM–7 AM without a night plan; it switches on and off by itself) or *Always*.

### ♿ Design & accessibility

The look is plain iOS: grouped lists, soft category tints, emoji badges and a rose accent. It lives in one
file, `MyBaby/Views/Components/DesignSystem.swift`: the spacing scale (`Spacing`), corner radii (`Radius`),
named colors for everything that isn't an activity (`Palette`; activity colors stay on `ActivityKind.color`),
`.cardStyle()` and `.tileStyle()`, a standard `EmptyStateView` with one clear action, `SummaryHeader` for list
headers with a summary, `NoticeLabel` for warnings and statuses, and `confirmDelete` for asking before
deleting. New screens should use these instead of their own values.

What's supported:

- **VoiceOver.** Every button, tile, chip and badge reads words, not emoji names. Rows and cards are one
  stop each ("Last feed, 2 hours, 10 minutes ago, Formula, 120 ml"). Charts have a label and value on every
  bar and point. Headers are marked as headers, decorative emoji are hidden, chips and pickers say which one
  is selected, and running timers are read in words ("Sleeping for 42 minutes") rather than ticking every
  second. Quick-log confirmations are announced, and stay on screen longer so there's time to reach Undo.
- **Dynamic Type.** Text never clips: no fixed heights on text, badges and icons grow with `@ScaledMetric`,
  and at the accessibility sizes the Today quick log and the Reports tiles go from three columns to two,
  rows of cards stack, and buttons move under the text they belong to. Widgets grow up to the largest size
  their fixed space allows.
- **Contrast.** Tints are for backgrounds and icons; numbers and words stay `.primary` or `.secondary`.
  3 AM mode keeps primary text at about 5:1.
- **Never color alone.** Who's on duty shows the name, the diaper chart puts wet and dirty side by side
  with a legend that names them, fevers and medicine timing say so in words with an icon, and milk
  freshness reads *Use soon* or *Past its use-by date*.
- **Reduce Motion.** The confirmation toast fades instead of sliding, and buttons dim instead of shrinking
  when pressed.
- **Deleting asks first** for appointments, vaccines, measurements, milestones and dose timing.

App Store screenshots: `docs/screenshots.md` lists the screens, sizes and captions. Debug builds can load a
sample log for a baby named Ava with the launch argument `-MyBabySampleData YES`, or Settings › *About ·
Debug build* › **Load sample data** (`MyBaby/Preview Content/SampleData.swift`).

### 👨‍👩‍👧 Family sharing — both parents, one log

More → Settings → **Invite partner** sends your partner an iCloud link (by Messages, Mail or anything else).
Once they open it, you both see and add to the **same log**: a feed your partner logs at 3 AM shows up on
your phone a few seconds later. The night schedule syncs as well, with the parents' names from Settings →
*Parents*. Each phone keeps its own *This iPhone belongs to* (Settings → *Parents*), alert style and cry
alert settings. After joining, Today asks once **Who's using this iPhone?**, so the new phone buzzes the
right person. If each of you typed your own name first, the phone still follows its owner by name.

- Your partner should open the link instead of setting up a new baby. If they already started an empty
  one, it's removed when they join.
- Reminders follow the shared data: feed and diaper reminders count from the latest feed or change either
  of you logged (see *Smart reminders*), and appointment reminders appear on both phones.

**Grandparents and nannies, view only.** The parent who created the log can invite more people and choose
what each one can do. In Settings → *Invite partner* (or *Manage sharing* once the log is shared), add the
person, then under *Share Options* set **Permission** to **View only**. They see the log, history, reports, health records and milestones, but the quick log buttons,
Save and swipe-to-delete are turned off, with a "View only" note. You can change someone's permission, or
remove them, from *Manage sharing* at any time. Parent care is never shared with anyone.

**Where the data lives:** you choose.

- **On this iPhone only** (the default). Nothing leaves the phone.
- **Sync with iCloud**, chosen in onboarding or in Settings → *iCloud & sharing*. Your log is backed up to
  your iCloud and synced to your own devices signed in to the same Apple ID.
- **Shared with your partner.** Tapping *Invite partner* (or opening a partner's link) turns on iCloud,
  after asking. The log lives in the iCloud account of the parent who created the baby and is shared with
  the other through iCloud.

Switching only changes whether the same database is mirrored to iCloud, so nothing is copied or
converted. There's no MyBaby server, and only people you invite can see the log. You can remove someone,
or leave a shared log, from Settings → *Manage sharing*. iCloud can't be turned off while the log is
shared.

**Delete my iCloud copy** (Settings → *iCloud & sharing*, while sync is on and the log isn't shared) deletes
the log from your iCloud and keeps the copy on the iPhone. It turns sync off first, deletes MyBaby's iCloud
zones, then copies the log into a fresh database file so that turning sync back on later starts over and
uploads a new copy, instead of reacting to the deleted zone (which can make iCloud clear the phone). If it's
interrupted, for example offline, Settings shows *Finish deleting iCloud copy*, and turning sync on finishes
it first. Other devices signed in to the same Apple ID stop syncing and may remove their copy.

**Delete all MyBaby data** (Settings → *Your data*) is the "delete my account" button. MyBaby has no account
or server, so the account is everything it keeps on the iPhone and in the parent's own iCloud. A sheet lists
what goes (every baby's log with photos, diary, milestones, allergies and reports; the iCloud copy; the
private Parent care page; settings, widgets and reminders; the Apple Watch summary), offers the CSV export
and a keepsake PDF first, and says what happens to sharing: a log you created and shared disappears from
your partner's iPhone too, since its share is deleted with your iCloud copy (named when iCloud knows the
partner's name); a log you joined is left, and the partner's own log stays. It can also remove the
appointments *Keep appointments in my calendar* added and the ones added with *Add to Calendar* on this
iPhone; that needs full calendar access, which is asked for only then, and if it's not given the summary
names the events that stayed. The parent types DELETE (any case), then confirms
with Face ID, Touch ID or the passcode when the iPhone has one. `Services/DataWipe.swift` then takes the
screens down (like switching iCloud) behind a "Deleting your data…" progress screen and, carrying on past
any step that fails: stops cry alerts, monitor mode, white noise, the breastfeeding timer, Live Activities
and all notifications; leaves joined logs (Core Data's purge), turns sync off, deletes Core Data's zones and
the `MyBabyAlertInbox` zone from the private database, leaves other parents' logs and inboxes in the shared
database and deletes every CloudKit subscription; removes the calendar events; destroys both stores and
everything next to them, the widget snapshot, Application Support (calendar links, crash reports) and
temporary exports; clears both `UserDefaults` domains (MyBaby keeps nothing in the Keychain); tells the
widgets and the watch there's no baby; and opens new, empty stores with sync off, back on the welcome
screen. Offline or signed out, the iPhone is still wiped and only `iCloudDeletionPending` is kept, the same
flag as *Delete my iCloud copy*: the iCloud part finishes by itself the next time the app opens online with
no log, from *Finish deleting iCloud copy*, or before sync is turned back on. Deleting the app alone never
deletes the iCloud copy.

**Before sync turns on**, every way of turning it on (the Settings switch, *Invite partner*, onboarding's
*Back up to iCloud*, *Restore from iCloud* and opening a partner's link) checks the iCloud account first. If
the iPhone isn't signed in, iCloud is restricted (Screen Time, a work profile) or can't be reached, sync stays
off and an alert says what to do. While sync is on, Settings shows a status row under the switch: *Syncing…*,
*Up to date · synced 2 minutes ago*, *Waiting for a connection*, or what's wrong (iCloud storage full, signed
out or into a different account, iCloud busy), with *Try again* for account problems
(`Services/SyncStatus.swift`, `Services/CloudErrors.swift`). Nothing is deleted when the account changes.
If the database can't be opened with iCloud, the app turns sync off and opens the same files without it,
so the log is still there; only if they can't be opened even then does the app stop.

Switching sync on or off opens the database files in a new `NSPersistentCloudKitContainer` each time (a
container's CloudKit mirroring can't be restarted), and the screens are rebuilt with its context. Sharing
and joining wait until iCloud has finished setting up the store ("Connecting to iCloud…").

**Change history is kept for a week.** Both stores have persistent history tracking on, which
`NSPersistentCloudKitContainer` uses to find what to upload; it adds a little to the database with every
save. Once a day, 10 seconds after launch, the app deletes history older than 7 days from both stores on a
background context (`PersistenceController.purgeOldHistoryIfDue`), so the database doesn't keep growing.
The container keeps its own place in the history and only needs what it hasn't uploaded yet, so a week is a
wide margin even for a phone that was offline for days; if it ever found its place purged, it would set
sync up again from the store, losing nothing. The app itself never reads the history. The database isn't
vacuumed: the space freed inside the files is reused by later saves.

Turning iCloud on or off rebuilds the app's screens with the database reopened, but you stay where you
were: on the same tab, and in More › Settings if that's where you flipped the switch (the tab is kept in
`RootView`, the More tab's path in `NavigationMemory`).

**The same baby twice.** If you used MyBaby on two devices with the same Apple ID before turning on sync (or
restored from iCloud on a phone that already had a log), each device made its own baby and iCloud brings
both together, each with part of the log. When two babies in your own log have the same name and birthday,
Settings › Babies asks "Mavie appears twice, probably from another iPhone or iPad. Merge them into one?"
**Merge** keeps the baby created first and moves everything logged for the other into it (feeds, sleep,
growth, vaccines, appointments, milestones and their photos, diary entries, the milk stash, medicine
schedules and not-tracked periods), fills in a missing birthday, sex or night plan, and adds the other's checkup
questions. Entries aren't de-duplicated, since two devices logging the same hour are two events; only
medicine schedules with the same name become one. **Not now** isn't asked again for that pair, and the
baby's profile still offers *Merge with the other Mavie*. A baby your partner shared with you is never
merged: it lives in their iCloud, and entries can't link across the two. The check runs after sync is
turned on, after a restore and when an iCloud download finishes (`Services/BabyMerge.swift`).

### 📥 Import from another app

Switching to MyBaby doesn't mean starting over. Settings › *Your data* › **Import from another app** brings
a log over from another baby tracker, or from MyBaby on another iPhone without iCloud.

1. **Choose a file**: a CSV, TXT or ZIP exported from the other app (several at once for MyBaby's own set
   of CSVs).
2. **Exported from**: *Auto-detect* (it says what it found) or the app, with how to export from it.
3. **Import into**: a baby already in MyBaby, or *A new baby* (named, and with a birthday, from the file
   when it has them).
4. **Time zone**: most apps write times without one, so they're read in the zone you pick, this iPhone's
   by default.
5. **Preview**: how many of each kind, the dates covered, how many are already in MyBaby, the rows left out
   with the reason for each, and a few entries as they'll appear. Nothing is saved until you tap
   **Import**.

What each reader understands, and where its format comes from (none of these apps documents its export, so
each reader was written against real exports people have published, cited in its source file):

| From | File | What comes over |
| --- | --- | --- |
| **MyBaby** | The CSVs from *Export all data* | The log, growth, vaccines and marked times (not tracked, nothing happened, caught up), exactly as exported. Appointments, the diary and allergies aren't brought back yet. |
| **Huckleberry** | Child profile › *Export tracking data as CSV* | Breastfeeds with each side's minutes, bottles (formula or breast milk, ml or oz), solids, diapers (pee, poo, both, dry, with the color and consistency MyBaby knows), sleep, pumping (left and right), medicine with the dose, baths, weight and length. `Services/Import/HuckleberryImporter.swift` |
| **Glow Baby** | *Export Report* › CSV (a ZIP of CSVs) | Diapers with color and texture, bottles, solids, sleep, weight and length. `GlowBabyImporter.swift` |
| **Nara Baby** | Activity › the child › *Export Data* | Breastfeeds with each side's time, bottles, diapers, sleep, pumping and growth, at the exact moment Nara recorded. With more than one child in the file, you pick which one. `NaraBabyImporter.swift` |
| **Another app** | Any CSV | You match the columns (date and time, end, type, amount, unit, duration, side, notes) on a screen that shows the first rows; MyBaby suggests a match from the headers and the date format from the values, for you to confirm. Each row's kind comes from words like *bottle*, *formula*, *nursing*, *wet*, *nap*, *pump* or a medicine's name, or *Every row is a…* for a file with one kind per file. |

Baby Tracker (Nighp), Baby Connect, Sprout Baby and Baby Daybook don't document their CSV exports and no
published example could be found, so they go through *Another app* rather than a reader built on guesses.

- **Units** are converted to MyBaby's: oz to ml, lb (and lb + oz) to kg, inches and feet to cm, °F to °C.
  Weights and lengths need their unit in the file, a temperature without one is read as °C or °F from the
  number (36.8 or 98.2), and amounts without one use the unit you pick.
- **Nothing is guessed.** A row MyBaby can't read (an unknown type, a sleep with no end, a diaper that
  doesn't say wet or dirty) is skipped and counted, with the reason shown in the preview. Breastfeeds with
  only a total time are split evenly between the sides, and the note says so; a bottle that doesn't say what
  was in it is saved as formula with a note.
- **Duplicates.** An entry of the same kind within a minute of one already in MyBaby is skipped, so
  importing the same file twice adds nothing the second time.
- **Gaps stay gaps.** Imported entries count as logged time for coverage like any other, and nothing else
  is added: a stretch nobody logged in the other app is untracked in MyBaby too, never a run of zeros.
- **In the background, with Stop.** Entries are saved in batches of 400 on a background context, with
  progress. Stopping keeps what's added so far, which can be removed.
- **Undo.** Every entry an import adds carries its id (`importBatchID` on `Activity`, `GrowthEntry`,
  `Vaccine` and `TrackingPeriod`). Settings › *Your data* › **Recent imports** lists the last 10 imports made
  on this iPhone, and **Remove this import** deletes exactly what it added, on every iPhone that shares the
  log, and nothing logged in MyBaby.
- **Private.** The file is read on the iPhone, from where it is, into memory, and let go when the import
  closes: it's never uploaded, copied into MyBaby or kept. Only the entries you import are saved, like any
  others. The list of recent imports (app, file name, baby, count) stays on this iPhone.

The readers are pure functions from text to an `ImportPlan` (`MyBaby/Services/Import/`), with their own CSV
reader (quotes, line breaks in fields, commas, semicolons or tabs, UTF-8 or UTF-16) and a small ZIP reader
on Apple's Compression framework, so they can be tried on sample files without Core Data.
`ImportWriter.swift` saves a plan and removes an import.

### 📜 Terms of Use

On first launch, and again whenever the terms change, each person sees the key points (not medical advice;
cry alerts and reminders can miss something; check medicine doses; the log stays theirs), can read the full
terms and the privacy policy, and ticks a box before **Agree and continue**. It's kept per device, so a
partner agrees on their own phone. An app update that doesn't change the terms doesn't ask again; raising
`TermsOfUse.version` does. The full text is in Settings › Privacy › *Terms of Use* and at `docs/terms.html`
(`Models/TermsOfUse.swift`, `Views/Settings/TermsViews.swift`).

### 🔒 Privacy

The developers never receive any of your baby's data. MyBaby has no server, no analytics and no
third-party code. Settings → *Privacy* explains this in the app.

- **Without iCloud**, the log is only on your iPhone.
- **With iCloud**, the log is in your own iCloud, end-to-end encrypted. The keys are in your iCloud
  Keychain, so Apple can't read the contents.
- **A shared log** lives in the iCloud of the parent who created it. The invited parent can read and edit it;
  family invited as view only can read it.
- **Parent care** is private to the phone: it's kept in your own private store, not in the baby's log, and never shared with your partner.
- **Milestone, diary and reaction photos** are stored inside the log, end-to-end encrypted, without their location.
- **Allergies and reactions** are part of the baby's log, stored and shared the same way. The allergy card goes only
  where you share it, and its note for caregivers stays on the iPhone.
- **The diary** (entries, letters for later, your notes about each month) is part of the baby's log and is
  stored and shared the same way. Summaries are worked out on the phone and never stored.
- **Apple still sees some metadata** that isn't the content itself, such as record sizes, when your devices
  sync and the share's title.
- **If you lose access to iCloud Keychain** (for example, you reset it), the encrypted data can't be recovered
  from iCloud. The copy on your iPhone is still there.
- **Imports** read the other app's file on the iPhone, from where it is. It's never uploaded, copied or
  kept; only the entries you choose to import are saved.
- **CSV exports and the PDF report** go wherever you send them. The temporary copies are deleted from the
  phone when the share sheet closes.
- **Calendar events** (Add to Calendar, or Keep appointments in my calendar) leave the encrypted log: they're
  stored by the calendar's provider (iCloud, Google, Outlook…). They hold the title, baby's name, time, doctor
  and place (with its address and map location when it was picked from the suggestions), never the
  appointment's notes or questions.
- **Places**: searching for an appointment's place or a vaccine's clinic sends what's typed in that field to Apple Maps, the
  same as typing in Maps, and only once you start typing. The small map of a picked place is loaded from Apple
  Maps too. Nothing else from the log is sent, and MyBaby doesn't ask for or use the iPhone's location.
- **Cry alerts** listen on the phone only. The audio never leaves the phone and is never stored. While they
  listen, their Live Activity shows on the Lock Screen, without unlocking, that they're listening, since and
  until when, and whether crying is heard now; the widgets show a small mic. The Live Activity shows nothing
  from the log, not even the baby's name, and none of it is sent anywhere (the Apple Watch's summary leaves
  it out).
- **The nursery monitor** listens on the device too, and its white noise is generated there. Its alerts
  travel as small encrypted records (a time, a kind, how long the crying went on, no names) in the family's
  own iCloud, in each parent's private inbox, and are deleted after an hour. The notification's wording is
  fixed and generic.
- **Widgets and Live Activities** read a small summary for each baby (last feed, diaper, sleep, pumping, the
  stash total, today's counts, the last medicine and when its next dose is allowed, when the next feed is
  probably due, who's on duty), plus whether cry alerts are listening on this iPhone, that the
  app keeps in its App Group on the iPhone. It's never synced or sent anywhere. Widget settings stay on the
  iPhone too.
- **The Apple Watch app** gets that summary (each baby's part trimmed to what the complications show, plus your bottle amounts,
  recent medicine names and, for those, any matching names on the allergy list) straight from
  your iPhone over Apple's WatchConnectivity, and sends taps back the same way. No server is involved.
- **Deleting everything** (Settings → *Your data* → *Delete all MyBaby data*) removes everything MyBaby keeps
  on the iPhone and in your iCloud; there's no account to close besides. Uninstalling the app alone leaves
  the iCloud copy in place.
- **Feedback** (Settings → *Help & support* → *Send feedback*) is an email from the parent's own account,
  filled in by the app and sent only by the parent, who sees and can change all of it first. If Mail isn't
  set up, it opens a `mailto:` link or copies the message instead. The optional technical details (app and
  iOS versions, device model, language and region, sync on/off and shared or not, how many babies, whether
  cry alerts or a nursery monitor are used, Low Power Mode and thermal state) can be read exactly before
  sending, and never include names, dates, log entries, photos, the Apple ID or a lasting identifier
  (`Services/FeedbackDiagnostics.swift`). MetricKit crash and hang reports stay on the phone, in the app's
  own Application Support folder (the newest 3, about 200 KB in all, deleted after 30 days), unless the
  parent attaches the latest one (`Services/CrashReports.swift`).

The app's privacy manifest (`MyBaby/PrivacyInfo.xcprivacy`) declares no tracking and no collected data,
so the App Store listing shows "Data Not Collected". Feedback doesn't change that: the parent sends it
themselves, from their own email account, outside the app.

## Running it

Requirements: a Mac with **Xcode 16 or newer** and a **paid Apple Developer Program membership**
($99/year). iCloud sharing, push and time-sensitive notifications aren't available to free accounts. The app targets
**iOS 17+**.

1. Open `MyBaby.xcodeproj` in Xcode.
2. Select the **MyBaby** target → **Signing & Capabilities**. Choose your team, and change the bundle
   identifier from `com.example.mybaby` to something unique, like `com.yourname.mybaby`.
   Then select the **MyBabyWidgets** target: choose the same team, and under **Build Settings** →
   *User-Defined* set `MYBABY_APP_BUNDLE_IDENTIFIER` to the app's new bundle identifier. The widgets'
   identifier (`<app id>.widgets`) and App Group follow from it. Keep the two in step; if they differ,
   the widgets can't read the app's data.
   Do the same for the **MyBabyWatch** and **MyBabyWatchWidgets** targets (the Apple Watch app and its
   complications): same team, and the same `MYBABY_APP_BUNDLE_IDENTIFIER`. Their identifiers become
   `<app id>.watchkitapp` and `<app id>.watchkitapp.widgets`, and the watch app names the iPhone app as its
   companion from it. All four targets must change together, or the watch app won't install with the
   iPhone app.
3. Under **iCloud**, check that CloudKit is on and the container `iCloud.<your bundle id>` is selected.
   If the container shows red, click **+** and add that exact name (it's derived from the bundle
   identifier in `MyBaby.entitlements` and `MyBaby-Info.plist`).
4. Under **App Groups**, check that `group.<your bundle id>` is selected (click **+** to add it if it shows
   red), on both the **MyBaby** and **MyBabyWidgets** targets. The database, the widgets' summary and the
   breastfeeding timer live in this group's shared folder. Without it the app still runs and keeps
   everything in its own folder, but the widgets stay empty.
   The **MyBabyWatch** and **MyBabyWatchWidgets** targets use a group of the same name on the watch, for
   the complications. Without it the watch app still works, but the complications stay empty.
5. Pick a device and press **⌘R**. To try sharing, sign in to two iPhones with *different* Apple IDs.
   The watch app is built and embedded with the iPhone app (*Embed Watch Content*) and installs on the paired
   Apple Watch (watchOS 10+). To run it from Xcode, pick the **MyBabyWatch** scheme and the watch.

> Only have a free Apple ID? You can still try the app on your own iPhone: delete the
> `CODE_SIGN_ENTITLEMENTS` line from the target's build settings. Everything works except syncing,
> sharing and time-sensitive alerts.

### TestFlight & App Store checklist

TestFlight and App Store builds use CloudKit's **Production** environment; builds run from Xcode use
**Development**. Debug builds keep their own database files (`MyBaby-private-development.sqlite`), so running
one from Xcode on a phone that also has the TestFlight build never mixes the two: a debug build starts with
an empty log of its own. Production only knows the record types that were deployed to it, and until they are,
syncing and sharing fail (the app says "iCloud isn't set up for this version of MyBaby yet").

1. Run a **Debug** build from Xcode on an iPhone signed in to iCloud, turn on **Sync with iCloud**, and tap
   More → Settings → *About · Debug build* → **Create iCloud schema**. That creates every record type and
   field in Development: the Core Data ones (`initializeCloudKitSchema`) and the nursery monitor's
   `CryAlert` and `CryAlertTest`, which are plain CloudKit records. The button only exists in debug builds.
   Until they're deployed, a TestFlight phone shows "Alerts from a nursery monitor aren't available in this
   version yet" under Cry alerts.
2. In the [CloudKit Console](https://icloud.developer.apple.com), open the container `iCloud.<bundle id>`
   (now `iCloud.com.mybaby.ios`), then **Schema → Deploy Schema Changes…** to Production.
3. **Redeploy after any change to the data model** (`MyBaby.xcdatamodeld`), before uploading a build that
   uses it. Repeat steps 1 and 2.
4. In the developer account (Certificates, Identifiers & Profiles), check that the iCloud container exists and
   is enabled for the App ID, with CloudKit, and that the App Group `group.<bundle id>` exists and is enabled
   for the app and widget App IDs.
5. MyBaby supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`, for the app and the widgets), so App
   Store Connect needs iPad screenshots too (see `docs/screenshots.md`). Once a version with iPad support
   is on the App Store, later versions can't drop it.

## Website and App Store links

App Store Connect needs a Privacy Policy URL and a Support URL. `docs/` holds those pages as plain
static HTML: `index.html` (landing page), `privacy.html`, `terms.html`, `support.html`, a shared
`style.css` and `icon.png`. The links between them are relative, so they work from any folder or domain. The App Store listing text (name,
subtitle, promotional text, description and keywords, within Apple's limits) is in `docs/app-store.md`.

The pages are also in French (`docs/fr/`) and Spanish (`docs/es/`); the English ones keep their URLs. Each page
has an English · Français · Español switcher, and `lang.js` remembers the choice. The English home page sends a
French or Spanish browser to its language until a language is picked. The terms match the app's own French and
Spanish text, and the app opens the pages in the language it's showing.

The site is published with **GitHub Pages** from the public repository (`byitzy/mybaby-app`, branch `main`,
folder `/docs`):

| Page | URL |
| --- | --- |
| Home | https://byitzy.github.io/mybaby-app/ |
| Privacy policy | https://byitzy.github.io/mybaby-app/privacy.html |
| Support | https://byitzy.github.io/mybaby-app/support.html |

1. In the repository on GitHub: Settings → Pages → Build and deployment → *Deploy from a branch*, branch
   `main`, folder `/docs`. The pages go live a minute or two later.
2. The app links to these URLs from Settings and the Privacy screen (`MyBaby/Utilities/AppLinks.swift`). If
   the repository is ever renamed or moved, update them there and in App Store Connect together.
3. Enter the same URLs in App Store Connect: Privacy Policy URL and Support URL.
4. In App Store Connect → App Privacy, answer **Data Not Collected**. This matches the privacy manifest
   and the policy: the developer never receives any data.

If the app's data handling changes, update `docs/privacy.html` and its French and Spanish copies (and their
effective dates), `PrivacyView.swift` and `PrivacyInfo.xcprivacy` together.

## Project layout

```
MyBaby/
  MyBabyApp.swift          App entry point, notification + share-invitation delegates
  MyBaby.xcdatamodeld      Core Data model (synced with CloudKit)
  Models/                  Baby, Activity (feed/diaper/sleep/bath/medicine/pumping/temperature), Vaccine, Appointment,
                           GrowthEntry, MilkBag, MedicineSchedule, NightPlan, Milestone + MilestonePhoto,
                           Allergy + AllergyReaction + AllergyReactionPhoto,
                           CareEntry (Parent care), TrackingPeriod (not tracked / nothing happened),
                           DiaryEntry + DiaryPhoto (the diary and letters for later)
  Services/                iCloud persistence & sharing, reminders, cry monitor, report math, coverage, patterns,
                           WHO growth percentiles, visit summaries, export, breastfeeding timer, help lines by region,
                           Live Activities, the widget snapshot writer, the Apple Watch bridge,
                           Delete all MyBaby data (DataWipe), Import/ (reading other apps' exports)
  Intents/                 Siri & Shortcuts actions and phrases
  Resources/               who-growth.json (WHO growth standards, bundled), support-resources.json
                           (help lines by region, with their sources)
  Utilities/               Settings keys, App Group, units (ml/oz, kg/lb, cm/in), formatting
  Views/
    Today/                 Home screen, quick log and baby switcher
    Feeding/               Breastfeeding timer and its card on Today
    Log/                   The add/edit form used for every activity
    Coverage/              Today's "Nothing logged since" card, marking time as not tracked, Catch up
    Feeding/               The milk stash
    More/                  The More tab, babies list and "Add a baby"
    Milestones/            Milestone timeline, editor (photos and camera), photo viewer, image downscaling
    Diary/                 The diary, its editor, week and month summaries, letters, Today's card, keepsake PDF
    MomCare/               Parent care: check-ins, medicines, birth recovery notes, mood chart and support
    Components/            Shared pieces and the design system (DesignSystem.swift), iPad layout (RegularWidth.swift)
    History/  Reports/  Health/  Settings/  Onboarding/
  Preview Content/         Debug-only sample data for screenshots
Shared/                    Built into the app, the widgets and the watch: App Group, WidgetSnapshot, the
                           timer's state, Live Activity types, the widget/Live Activity button intents,
                           and what the iPhone and the watch send each other (WatchContext, WatchCommand)
MyBabyWidgets/             Widget extension: Home & Lock Screen widgets, their Edit Widget options, Live Activity views
MyBabyWatch/               Apple Watch app: status, quick-log buttons, breastfeeding timer, offline queue
MyBabyWatchWidgets/        Watch face complications and their options
```

The Xcode project uses synchronized folders, so any `.swift` file you add under `MyBaby/` is
included in the app automatically, under `MyBabyWidgets/` in the widgets, and under `Shared/` in both.
Code in `Shared/` that only the app can run (it uses Core Data) goes inside `#if !WIDGET_EXTENSION`.
The watch targets build `Shared/` too, except `ButtonIntents.swift` and `LiveActivityAttributes.swift`
(Live Activities aren't on watchOS), and the watch app also leaves out `BabyEntity.swift` (the widgets' and
complications' baby picker), which the project excludes for them. The complications set `WIDGET_EXTENSION`
like the iPhone widgets. So a new file in `Shared/` must
build on watchOS, or be added to those exclusions (in Xcode: the file's Target Membership).

## Ideas for next steps

- Weight-for-length (the WHO tables have it too)

> MyBaby is a tracking tool, not medical advice. Always contact your pediatrician with questions or concerns.
