# 9点23 validation — 2026-10-30

## Reference UI update — build 439

- Expanded native screens and public reference mapping: [NINE23_REFERENCE_UI.md](NINE23_REFERENCE_UI.md).
- Final iOS simulator and development-signed device builds passed, including embedded watchOS and widget targets. macOS shared app build passed.
- AppleHealthDayTests, WatchRecoveryTests and BehaviorInsightsTests: 37 tests passed, zero failures. The additional raw metric test verifies selected date, source, missing values and stale state. Recovery and sleep scoring formulas are unchanged.
- macOS IntelligenceWatchRecoveryTests and WidgetSnapshotTests passed again with the expanded metric output.
- The updated simulator app launched with explicitly labeled synthetic data. Dark and light homepage screenshots were captured; the generated black/white 9:23 icon was visually inspected. Final signature validation and IPA ZIP integrity checks passed.
- Manual navigation, chart gestures, journal persistence and accessibility-size review for the expanded screens are **pending**: computer-use reports that the Mac is locked. Build success is not an interaction test.
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

- Physical phone installation and launch are complete. Preservation of the user's actual database contents, real HealthKit reconciliation, physical Watch installation and phone-to-Watch synchronization still need verification. A successful update installation alone does not establish those results.
- GitHub HTTPS push preflight could not authenticate. Browser sign-in did not provide a Git credential. The implementation is committed on local branch `codex/nine23-apple-watch`; remote upload requires a connected GitHub integration or authenticated Git client. No successful remote push is claimed.
- Simulator/synthetic tests establish software behavior, not physiological accuracy or equivalence to an official WHOOP score.

## Device reconciliation procedure

1. Install the signed build over the existing app; confirm the visible name/icon and the existing records.
2. Allow the new read scopes in Health if prompted, sync 30 days, and compare the same local date/cutoff in both apps.
3. For SDNN, resting HR, sleep, energy and one workout, open the metric detail and compare writers, interval, unit and sample identity. Keep source-priority differences visible rather than summing competing sleep writers.
4. Test a Health sample correction/deletion, repeat sync, then revoke access or cause a query failure; confirm no duplicate totals and that failure retains cached values with a stale state.
5. Confirm phone, Watch and widgets carry the same dated recovery result and activity minutes. Recalibrate only when intentionally testing the baseline reset; raw records must remain available.

No real health records or device diagnostics should be added to the repository during these checks.
