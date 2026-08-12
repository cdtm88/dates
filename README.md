# Dates

Birthday, anniversary and key-date reminders for iOS. Native, offline-first, no backend.

This repository implements **Milestone 1 of the PRD — phases 01 to 04**: the data model, groups
and offsets, the chronological list and detail views, and the rolling-window notification
engine. That is the point the PRD calls the first TestFlight-worthy build.

## Layout

```
DatesKit/            Foundation-only Swift package. Every rule the app can get wrong.
  Sources/DatesKit/  AnnualDate, offsets, ordering, notification planner.
  Tests/             70 tests, runnable on any Swift toolchain — no Xcode needed.
Dates/               The iOS app: SwiftData models, notification scheduler, SwiftUI views.
DatesTests/          Tests that need SwiftData or UserNotifications. Xcode only.
project.yml          XcodeGen spec — the source of truth for the project.
Dates.xcodeproj/     Generated from project.yml and committed so the repo opens directly.
docs/verification.md Requirement-by-requirement status.
```

### Why the split

`DatesKit` depends on Foundation and nothing else. Leap-day resolution, the day-rollover
boundary, age calculation, offset inheritance, list ordering, and the whole notification plan
live there as value types, so they are tested directly rather than through a simulator. The
SwiftUI and SwiftData layer stays thin: it stores components, maps models to snapshots, and
hands the resulting plan to `UNUserNotificationCenter`.

That split is also what made it possible to develop this on a machine without Xcode. The
domain suite has been run and is green; the app layer has been syntax-checked but **not
compiled**, because SwiftUI, SwiftData, EventKit and UserNotifications only build on Apple
platforms. Expect to fix small compile errors on the first Xcode build.

## Building

Requires Xcode 15 or newer (iOS 17 deployment target, D-01).

```sh
open Dates.xcodeproj      # then select an iPhone simulator and run
```

To regenerate the project after adding files — [XcodeGen](https://github.com/yonaskolb/XcodeGen),
`brew install xcodegen`:

```sh
xcodegen generate
```

Adding a source file under `Dates/` does not need a project edit; the target globs the
directory. Regenerate only when targets, settings, or Info.plist keys change.

### Signing

`CODE_SIGN_STYLE` is Automatic with no team set, so the project opens without a paid account.
Set your team in *Signing & Capabilities* to run on a physical device. The Apple Developer
Program membership is still a hard blocker for Phase 08 and for testing notifications on
device; the simulator covers most of Phase 04.

## Tests

The domain suite, with no Xcode involved:

```sh
cd DatesKit && swift test
```

The SwiftData and scheduler suite, which needs Xcode:

```sh
xcodebuild test -project Dates.xcodeproj -scheme Dates \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Current state: **70 of 70 DatesKit tests pass.** The 15 tests in `DatesTests/` have never been
executed — they were written against APIs that cannot run here.

## Decisions worth knowing

Beyond the PRD's locked decisions, three judgement calls were made where the PRD left room.
All three are described with their reasoning in `docs/verification.md`:

- **The scheduler fills by event, not by fire date.** The nearest events get *all* of their
  offsets or none. Filling strictly by fire date would let the queue end on a 7-day gift
  warning whose day-of reminder did not fit, which is worse than no warning at all.
- **The rolling window is 400 days, not the 60 the PRD assumed.** The 60-request ceiling is
  the binding constraint for a large dataset, so a long window costs nothing there — and for
  a small dataset it means the queue covers everything for over a year, which is the real
  defence against the queue draining while the app goes unopened.
- **Seeded groups get different default offsets.** Only Close family gets the full 7/3/day-of
  set. The PRD's Job 2 is explicit that advance alerts must stay meaningful rather than
  becoming noise, and every group defaulting to all three would do the opposite.

## Not in this milestone

Phases 05 to 08 are untouched: calendar and CSV import/export, iCloud sync, the Light/Dark
appearance setting, and release readiness. The empty state shows the two import routes as
disabled buttons rather than hiding them, so that screen does not need redesigning when
Phase 05 lands.
