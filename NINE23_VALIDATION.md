# 9点23 validation — 2026-10-30

## Synthetic functional review after build 439

- At the user's request, physical installation is deferred. The existing signed package has not been replaced.
- The [functional review](NINE23_FUNCTIONAL_REVIEW.md) records 30 days of synthetic input, native navigation/edge-state checks, 81 passing focused tests and the remaining UI limitations.
- Corrected recovery explanations and home/detail minute rounding; retained chart selection after touch-up (gesture confirmation remains pending). Simulator fixtures now cover missing inputs, incomplete sleep, source conflicts, overlap, naps and missing workout effort, and cannot seed a physical device.
- Final simulator build and the macOS shared-app tests succeeded. This development simulator product includes newer source than the previously packaged build 439.

## Reference UI update — build 439

- Expanded native screens and public reference mapping: [NINE23_REFERENCE_UI.md](NINE23_REFERENCE_UI.md).
- Final iOS simulator and development-signed device builds passed, including embedded watchOS and widget targets. macOS shared app build passed.
- AppleHealthDayTests, WatchRecoveryTests and BehaviorInsightsTests: 37 tests passed, zero failures. The additional raw metric test verifies selected date, source, missing values and stale state. Recovery and sleep scoring formulas are unchanged.
- macOS IntelligenceWatchRecoveryTests and WidgetSnapshotTests passed again with the expanded metric output.
- The updated simulator app launched with explicitly labeled synthetic data. Dark and light homepage screenshots were captured; the generated black/white 9:23 icon was visually inspected. Final signature validation and IPA ZIP integrity checks passed.
- Simulator interaction checks passed for sleep detail/back navigation, selected-day switching, source/sample detail and sheet dismissal, recovery detail/week switching, and journal answer persistence after reopening. The behavior-insight empty state correctly reports insufficient explicit control records. These checks used synthetic records only.
- Chart point/drag selection and the expanded screens at accessibility text sizes remain **unverified**. The chart renders and changes period, but the simulator automation did not confirm selection feedback. Build success is not an interaction test.
- Physical installation of **439 is pending**: the previously paired iPhone is currently unavailable. The installed build 438 described below has not been replaced. No uninstall or user-data reset was attempted.
- The new deliverable is `build/nine23-delivery/reference-439/Nine23-reference-439.ipa`, with signed `Payload/NOOP.app`, icon, screenshots and build metadata beside it. The prior build remains available.

## Previous Apple foundation / build 438 validation

- StrandAnalytics: 2,149 tests, zero failures.
- WhoopStore: 634 tests, zero failures; the final focused transaction/source-isolation rerun also passed.
- iOS device build, embedded watchOS app, iOS widgets and Watch complications: built successfully with the existing development team and bundle identifiers.
- iOS simulator build: built and launched on iPhone 18 Pro Max / iOS 27.2.
- macOS shared app: compiled; IntelligenceWatchRecoveryTests and WidgetSnapshotTests passed.
- Local code-signature verification succeeded using `codesign --verify --deep --strict` with normal host keychain access.
- Physical iPhone 17 Pro Max: after replacing the USB cable, the signed build installed successfully over the existing app without uninstalling it. Device inventory confirmed the display name `9点23`, existing bundle identifier, version `12.1.0` and build `438`. Launch succeeded, and a subsequent process query confirmed the main app and widget extension were running. No demonstration launch arguments were used.
- Native UI interactions verified 今日 / 趋势 / 我的, sleep detail and back navigation, historical detail retaining the selected date, and a missing historical date showing empty values instead of today's metrics.
- Light/dark appearance and accessibility text size inspected. An observed crowded date/header row was corrected to a vertical layout at accessibility sizes. Synthetic demonstration records are labeled in the UI.
- Repository diff whitespace check passed. Generated Xcode project, private signing config, local databases, real health data and build products are excluded from commits.

## Local outputs

`build/nine23-delivery/` is ignored by Git and contains the development installation package, screenshots and a patch series after packaging. Install the app as an update with its existing identifier; do not uninstall the current app first.

The primary implementation notes and data/algorithm contracts are in [APPLE_WATCH_EDITION.md](APPLE_WATCH_EDITION.md). The source project remains `Strand.xcodeproj`, generated from `project.yml`; the iPhone scheme remains `NOOPiOS`.

## Pending device and account checks

- Physical phone installation and launch are complete for build 438 only. Build 439 remains pending: after reconnection, CoreDevice still reports the paired phone unavailable and the host USB inventory has no iPhone. The installation attempt failed before transferring the app. Preservation of the user's actual database contents, real HealthKit reconciliation, physical Watch installation and phone-to-Watch synchronization still need verification.
- The connected personal GitHub integration published all seven implementation phases to [WadeZhao23/noop, codex/nine23-apple-watch](https://github.com/WadeZhao23/noop/tree/codex/nine23-apple-watch). Every phase's Git tree hash matches its local source; a fetch and final whole-tree comparison also passed. The build-439 source is published as `e332d0e4c9465209357b4b529a92ed8ed41da2ef` (identical tree to the original local `abd7abe4573ee45394a467963fa490d7e121f543`). Original local commit history is retained on `backup/nine23-local-20261030`; the working branch follows the published history. No direct Git HTTPS credential was installed.
- Simulator/synthetic tests establish software behavior, not physiological accuracy or equivalence to an official WHOOP score.

## Device reconciliation procedure

1. Install the signed build over the existing app; confirm the visible name/icon and the existing records.
2. Allow the new read scopes in Health if prompted, sync 30 days, and compare the same local date/cutoff in both apps.
3. For SDNN, resting HR, sleep, energy and one workout, open the metric detail and compare writers, interval, unit and sample identity. Keep source-priority differences visible rather than summing competing sleep writers.
4. Test a Health sample correction/deletion, repeat sync, then revoke access or cause a query failure; confirm no duplicate totals and that failure retains cached values with a stale state.
5. Confirm phone, Watch and widgets carry the same dated recovery result and activity minutes. Recalibrate only when intentionally testing the baseline reset; raw records must remain available.

No real health records or device diagnostics should be added to the repository during these checks.
