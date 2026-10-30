# 9点23 validation — 2026-10-30

## Passed

- StrandAnalytics: 2,149 tests, zero failures.
- WhoopStore: 634 tests, zero failures; the final focused transaction/source-isolation rerun also passed.
- iOS device build, embedded watchOS app, iOS widgets and Watch complications: built successfully with the existing development team and bundle identifiers.
- iOS simulator build: built and launched on iPhone 18 Pro Max / iOS 27.2.
- macOS shared app: compiled; IntelligenceWatchRecoveryTests and WidgetSnapshotTests passed.
- Local code-signature verification succeeded using `codesign --verify --deep --strict` with normal host keychain access.
- Native UI interactions verified 今日 / 趋势 / 我的, sleep detail and back navigation, historical detail retaining the selected date, and a missing historical date showing empty values instead of today's metrics.
- Light/dark appearance and accessibility text size inspected. An observed crowded date/header row was corrected to a vertical layout at accessibility sizes. Synthetic demonstration records are labeled in the UI.
- Repository diff whitespace check passed. Generated Xcode project, private signing config, local databases, real health data and build products are excluded from commits.

## Local outputs

`build/nine23-delivery/` is ignored by Git and contains the development installation package, screenshots and a patch series after packaging. Install the app as an update with its existing identifier; do not uninstall the current app first.

The primary implementation notes and data/algorithm contracts are in [APPLE_WATCH_EDITION.md](APPLE_WATCH_EDITION.md). The source project remains `Strand.xcodeproj`, generated from `project.yml`; the iPhone scheme remains `NOOPiOS`.

## Pending device and account checks

- The physical iPhone was discovered but reported **unavailable**. This run has not installed the update on the physical phone or Watch, verified preservation of the user's actual database, or compared real HealthKit samples with the Health app. Those checks need the connected/unlocked phone and paired Watch.
- GitHub HTTPS push preflight could not authenticate. Browser sign-in did not provide a Git credential. The implementation is committed on local branch `codex/nine23-apple-watch`; remote upload requires a connected GitHub integration or authenticated Git client. No successful remote push is claimed.
- Simulator/synthetic tests establish software behavior, not physiological accuracy or equivalence to an official WHOOP score.

## Device reconciliation procedure

1. Install the signed build over the existing app; confirm the visible name/icon and the existing records.
2. Allow the new read scopes in Health if prompted, sync 30 days, and compare the same local date/cutoff in both apps.
3. For SDNN, resting HR, sleep, energy and one workout, open the metric detail and compare writers, interval, unit and sample identity. Keep source-priority differences visible rather than summing competing sleep writers.
4. Test a Health sample correction/deletion, repeat sync, then revoke access or cause a query failure; confirm no duplicate totals and that failure retains cached values with a stale state.
5. Confirm phone, Watch and widgets carry the same dated recovery result and activity minutes. Recalibrate only when intentionally testing the baseline reset; raw records must remain available.

No real health records or device diagnostics should be added to the repository during these checks.
