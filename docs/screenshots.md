# App Store screenshots

How to take MyBaby's App Store screenshots with a realistic, made-up log, which screens to capture, and
what to say under each.

## 1. Load the sample log

Sample data is only in **debug** builds (`MyBaby/Preview Content/SampleData.swift`, wrapped in `#if DEBUG`),
so it never ships in the App Store build. It adds a six-week-old girl named **Ava** with two weeks of
feeds, diapers, naps and night sleep, pumping sessions, vitamin D drops, a milk stash, five growth
measurements (near the WHO median), vaccines given and due, a past and an upcoming checkup with questions
to ask, two milestones (no photos) and a night plan where Maya and Sam split each night at 2 AM.

Either:

- **Launch argument:** Xcode › Product › Scheme › Edit Scheme › Run › Arguments › *Arguments Passed On
  Launch*, add `-MyBabySampleData YES`, and run. The app loads it once at startup, and does nothing if a
  baby named Ava is already there.
- **In the app:** More › Settings, scroll to *About · Debug build* › **Load sample data**.

It never changes another baby's log, but it does replace this device's night plan. Use a simulator or a
test device, then erase it (Device › Erase All Content and Settings) when you're done.

Before capturing:

- Set the simulator's clock to look tidy: `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`.
- Light mode for most shots. Take Night shifts or Cry alerts with **3 AM mode** on (Settings › Display) for
  one night-time shot if you like.
- Leave text at the default size. Check one screen at a large size too; it's a nice accessibility shot.

## 2. Screens to capture (8)

| # | Screen | How to get there | Caption |
|---|--------|------------------|---------|
| 1 | **Today** | Today tab. Scroll so the "time since" cards and the quick log grid show. | *One tap to log feeds, diapers and sleep, even at 3 AM.* |
| 2 | **Reports** | Reports tab, 14 days. | *See the week at a glance, and share a PDF with your pediatrician.* |
| 3 | **Growth percentiles** | Health › Growth. | *Weight and length on the WHO growth charts.* |
| 4 | **Night shifts** | More › Night shifts. Shows the 7-night schedule and each parent's sleep. | *Share the nights fairly, so you both get real sleep.* |
| 5 | **Cry alerts** | More › Cry alerts › Start listening (allow the microphone). | *The phone listens on-device and buzzes only the parent on duty.* |
| 6 | **Milestones** | More › Milestones. Add a photo of your own (not a real child's without permission) to "First smile" for a warmer shot. | *Keep the first smile, the first bath, and every moment in between.* |
| 7 | **Widget and Lock Screen Live Activity** | Add the medium *Baby at a glance* widget to the Home Screen; start a sleep or the breastfeeding timer and lock the phone for the Live Activity. Two shots, or one composited. | *The last feed and diaper at a glance, with a live sleep timer on the Lock Screen.* |
| 8 | **Apple Watch** | Run the MyBabyWatch scheme on a watch simulator paired with the iPhone one. Log a diaper from the wrist. | *Log a feed or a diaper from your wrist.* |

Good extras: the Visit summary (Health › Visits › swipe right on the 2-month checkup), Parent care (titled after the phone's owner, e.g. "Maya's care"), and the
milk stash.

## 3. Sizes App Store Connect needs

iPhone (portrait), PNG or JPEG, no transparency:

| Display | Pixels | Simulator |
|---------|--------|-----------|
| **6.9"** (required) | 1320 × 2868 (also accepted: 1290 × 2796) | iPhone 16 Pro Max |
| **6.5"** | 1242 × 2688 (also accepted: 1284 × 2778) | iPhone 11 Pro Max, or iPhone 14 Plus for 1284 × 2778 |

App Store Connect scales the 6.9" set down for smaller iPhones if you don't upload their own.

Apple Watch (any one size is used for all):

| Watch | Pixels |
|-------|--------|
| Ultra 2 (49 mm) | 410 × 502 |
| Series 10 (46 mm) | 416 × 496 |
| Series 9 (45 mm) | 396 × 484 |

Up to 10 screenshots per size. Apple changes these from time to time, so check the current list in App
Store Connect Help › *Screenshot specifications* before uploading.

## 4. Caption tips

- Keep each caption to one short line; it's read in a second while scrolling.
- Lead with what the parent gets ("both get real sleep"), not the feature name.
- Don't make medical claims: MyBaby tracks and shares, the pediatrician advises.
- Privacy is a feature: one caption, or the last screenshot, can say *No account. No ads. Your data stays
  on your iPhone or in your own iCloud.*
