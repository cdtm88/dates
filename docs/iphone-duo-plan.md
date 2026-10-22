# iPhone Duo plan

Goal: Dates feels native on iPhone Duo — closed (outer, compact width), open (inner,
regular width), partially folded, and 50/50 split — without changing behaviour on any
other iPhone. Deployment target stays iOS 17; Duo-only API sits behind
`if #available(iOS 27.1, *)`.

Most of the app is standard SwiftUI (NavigationStack, List, sheets, toolbars, alerts),
which Apple says adapts to the fold automatically. The work is one navigation change,
plus verification.

## Phase 0 — Audit on the Duo simulator
- Install the iOS 27.1 simulator runtime (`xcodebuild -downloadPlatform iOS`).
- Run the current app in each pose: closed, open portrait and landscape, book fold,
  tabletop, 50/50 split. Screenshot each, and record what the system already handles.
- Settle the open question below.

## Phase 1 — Inner display: list and detail side by side
- `EventListView`: replace `NavigationStack` + push with `NavigationSplitView`. List
  on the left, `EventDetailView` on the right, which the system splits 50/50 at the
  fold. Compact width collapses to today's push behaviour, so nothing changes on other
  iPhones.
- The notification deep link drives the selection instead of the push path, keeping
  the cold-launch fix from #11.
- Placeholder in the detail column: "Select a date".
- Empty state moves into the list column, so its centred buttons never straddle the fold.
- UI test on the Duo simulator: selecting a row shows its detail beside the list.

## Phase 2 — Verify system adaptation (fix only what's wrong)
- Toolbars move to the vertical side bar on the outer display. Text buttons
  (Cancel/Save) should stay horizontal.
- Sheets (form, Settings, Groups, Import) avoid the fold. Consider keeping the
  single-button Settings sheet's bar horizontal on the outer display.
- Alerts and confirmation dialogs avoid the fold.

## Phase 3 — Release
- Duo App Store screenshots, if App Store Connect asks for them.
- A Duo simulator run in the local verification. CI stays as it is (runner Xcode).

## Skipped on purpose
- `ArrangementView`: NavigationSplitView covers list/detail, and Apple says not to
  nest navigation inside one.
- Manual reserved-region displacement: there are no hand-placed controls.
- Tabletop layout (optional, aimed at media apps), multi-scene, a large widget.

## Open question (resolved)
The app is portrait-only. If Phase 0 shows the inner display letterboxes or
compatibility-modes a portrait-locked app, enable landscape (the list and form already
work in it). Otherwise keep portrait.

Resolved 2026-10-22: the open Duo runs the app full screen across the inner display,
list and detail side by side, with no letterboxing. Portrait-only stays.

## Results (2026-10-22)
- Closed (outer display): toolbars move into the vertical bar; text-button sheets keep
  horizontal bars. All app tests pass.
- Open (inner display): split view fills the screen. All UI tests pass, including
  `testSelectingADateShowsItBesideTheList` (skips on compact iPhones).
- The hinge is driven from DeviceHub's posture buttons (bottom-right of the device
  window); `simctl` cannot change it.
- No Duo screenshot size in App Store Connect yet; the 6.9in set stands.

## Sources
- https://developer.apple.com/videos/play/tech-talks/111466/
- https://developer.apple.com/videos/play/tech-talks/111463/
- https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
