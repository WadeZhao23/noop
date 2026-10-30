# 9点23 synthetic functional review — 2026-10-30

The Apple Watch edition's core daily-data flows pass this focused review. UI acceptance is partial: navigation and abnormal-data states were exercised, while chart gestures and several settings interactions remain unverified. Physical installation was deferred at the user's request.

## Environment and data

- iPhone 18 Pro Max simulator, iOS 27.2; Chinese UI, Asia/Shanghai timezone.
- Thirty synthetic days (October 1–30 in this run), through the production Apple adapter, repository, metric engine and native screens. Records have `synthetic-` identities and a visible demonstration banner.
- `--nine23-demo-edge-cases` selects the abnormal cases below. Dates move relative to launch day. `--nine23-demo-stale` optionally ages today's update timestamp by eight hours.
- Demo seeding is Debug-only and now also simulator-only. Future samples and unfinished workouts are excluded at the current cutoff; summaries are rebuilt from the retained samples.
- No real HealthKit data was used or uploaded. The signed build-439 package and the installed physical-phone build were not replaced. The final simulator build includes this review's source changes, so it is newer than the previously packaged build 439 despite retaining that build number.

## Native UI checks

| Scenario | Observed result | Status |
|---|---|---|
| Home → recovery | Selected date and recovery 79 agree; underlying SDNN/RHR and baseline explanation are shown | Pass |
| Yesterday: missing RHR | Recovery 94, RHR absent, explicitly marked simplified | Pass |
| Two days ago: missing SDNN | No recovery score; missing-HRV explanation, no false simplified-score claim | Pass |
| Recovery → sleep → back | Linked detail keeps October 28; returning to home keeps its original October 30 date | Pass |
| Three days ago: incomplete sleep | Sleep 6:47; Rest, efficiency and restorative proportion unavailable; 30 unknown minutes and 35 unclassified minutes retained | Pass |
| Four days ago: no records | Empty sleep/session values and empty-state copy; no substitution of today's result | Pass |
| Five days ago: conflicting writer | Apple Watch sleep 6:53; competing writer disclosed and excluded from the total | Pass |
| Six days ago: overlap and nap | 7:41 main sleep + 0:30 nap = 8:11; overlap not counted twice; Rest 92 remains based on the complete main night | Pass |
| Calendar | Future date and future-month navigation disabled; October 23 selection dismisses the sheet and updates home | Pass |
| Seven days ago: missing workout effort | Workout 07:30–08:35, duration 1:05, 273 kcal; effort remains absent; dated heart-rate samples and synthetic identity shown | Pass |
| Sleep plan initial state | 07:00 wake time yields 23:00 bedtime and 8-hour target; no claim to create an alarm | Pass |
| Sleep plan editing/reopening | Time editor opened; setting the value was blocked by the host's locked-screen response | Pending |
| Journal storage | Date/source isolation, upsert, replay and value round-trip covered by automated tests; prior build-439 UI answer persistence was verified | Partial; note editing not rerun |
| Chart selection | Last non-nil selection is retained in code; date/metric/range changes clear it | Compiles; touch/drag still pending |
| Metric-panel settings, accessibility sizes, remaining tab flows | Not fully exercised in this run | Pending |

The Mac interaction tool eventually returned “The Mac is locked and automatic unlock could not unlock it.” Coordinate interactions had also failed earlier while semantic button navigation worked. These tool limitations are not recorded as product passes or product defects.

## Automated checks

All **81 focused tests passed**, with zero failures:

- StrandAnalytics: **39** across `AppleHealthDayTests`, `WatchRecoveryTests`, and `BehaviorInsightsTests`.
- WhoopStore: **25** across `AppleHealthWindowTests` and `JournalWorkoutAppleCacheTests`.
- macOS shared app: **17** across `IntelligenceWatchRecoveryTests` and `WidgetSnapshotTests`.

Coverage includes a 30-day wear gap, dated baselines, recalibration, future-history exclusion, missing inputs, unknown sleep intervals, overlap/source precedence, next-day behavioral associations, widget result consistency, transaction rollback, source isolation, and workout revision/replay/deletion. A failed storage transaction keeps the last good snapshot. This does not simulate an actual HealthKit permission or transport failure.

New assertions verify that an unscored recovery never claims to be a simplified score; main sleep, overlap and nap reconcile to one daily total; daily energy is independent of the workout-energy subtotal; and replaying a revised workout replaces its duration/energy instead of accumulating it. Deleting its window removes it.

The final iOS simulator build succeeded and includes the embedded watch/widget build dependencies. The macOS shared-app test build also succeeded. The previous full foundation suites were not rerun or counted in the 81-test total. Whitespace validation passed.

## Corrections made during this review

1. Recovery explanations now distinguish missing SDNN, insufficient history, stale history, and an actual HRV-only scored fallback. Scoring formulas and weights remain unchanged.
2. Home's sleep summary uses the same rounded-minute formatter as sleep detail, avoiding a one-minute mismatch from truncation.
3. Chart bindings keep the last selected timestamp after touch-up so a dated detail link can remain reachable; changing the chart's date, metric or range clears the selection. Gesture behavior still needs interaction confirmation.
4. Simulator fixtures now exercise seven abnormal days, optional stale data, and the current sampling cutoff; fixture writes cannot run on a physical device.

These changes concern the Apple adapter's presentation and simulator fixtures. Android behavior, database schema, and shared scoring coefficients are unchanged.

## Reproduction

After generating the Xcode project and building `NOOPiOS` for an iOS simulator, install that simulator product and launch it with:

```sh
xcrun simctl launch --terminate-running-process <simulator-id> com.wadezhao23.noop \
  --demo-seed --nine23-demo --nine23-demo-edge-cases \
  -AppleLanguages '(zh-Hans)' -theme.appearance dark
```

Run focused package tests in their package directories:

```sh
# Packages/StrandAnalytics
swift test --filter 'AppleHealthDayTests|WatchRecoveryTests|BehaviorInsightsTests'
# Packages/WhoopStore
swift test --filter 'AppleHealthWindowTests|JournalWorkoutAppleCacheTests'
```

Run the `Strand` macOS scheme with `-only-testing:StrandTests/IntelligenceWatchRecoveryTests` and `-only-testing:StrandTests/WidgetSnapshotTests`.

Local evidence is under ignored `build/nine23-delivery/function-review/`. Device-to-Health reconciliation, Watch synchronization, chart gestures, and the pending UI checks above remain separate acceptance items. Synthetic agreement establishes software behavior, not physiological accuracy or equivalence to WHOOP's official scores.
