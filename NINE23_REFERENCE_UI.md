# 9:23 reference UI — build 439

This Apple-only iteration replaces the small three-tab shell with a broader native reference experience. It uses WHOOP's public navigation, hierarchy and interaction patterns while retaining the 9:23 identity and NOOP-derived Apple metrics. The implementation contains original SwiftUI views, system symbols and a generated vector wordmark; no WHOOP application code or bundled artwork is included.

## Reference evidence

- [WHOOP mobile navigation](https://support.whoop.com/s/article/Navigating-the-WHOOP-Mobile-App?language=en_US): Home, Health, Community, More; three primary dials and detailed health surfaces.
- [WHOOP home screen](https://www.whoop.com/fo/en/thelocker/the-all-new-whoop-home-screen/): My Day, My Plan and customizable My Dashboard.
- The official support screenshot was visually inspected for the dark blue-grey palette, compact header/date controls, three dials, layered cards and flat four-tab navigation. This is a reconstruction from public references, not a claim of complete pixel parity with every private or subscription screen.

## Screen and component map

| Surface | Working interactions and data |
| --- | --- |
| Home | Date arrows/calendar; sleep/recovery/activity dials; daily interpretation; health monitor; sleep/workout timeline; journal; sleep plan; weekly activity; configurable/reorderable metrics with sparklines; refresh |
| Health | Daily heart-rate samples; five vital metrics; personal observation ranges; VO2 max, weight and steps; capability explanations |
| Community | Local personal statistics, progress and journal links; explicit unconnected team service |
| More | Trends/report, journal/behavior insights, interpretation/optional existing AI coach, sleep plan, device sync, existing advanced settings and upstream credit |
| Sleep | Actual duration and target, existing Rest score, efficiency when known, main sleep/naps, draggable stage timeline, stage totals and provenance |
| Recovery | Existing score, SDNN/RHR versus existing baselines, valid-day maturity, missing-input explanation, related metrics |
| Activity/workout | Recorded minutes, count, energy, steps; individual duration, effort and heart-rate details |
| Metric/trends | Day/week/month/90-day views, bar selection and dated drill-down, gaps retained, summary statistics, source/window/sample sheet |
| Calendar | Monthly recovery colors, historical selection, future-day restriction, return to today |
| Journal | Six yes/no habits, unanswered state, local note, existing NOOP behavior-effect analysis with next-day recovery and explicit control groups |
| Sleep plan | Persistent wake time and bedtime derived from the existing fixed eight-hour sleep goal; no alarm claimed |

`Nine23Style` contains adaptive color, spacing and semantic type tokens. `Nine23Components` supplies cards, dials, charts and explicit metric/date routes. `Nine23RootView`, `Nine23DetailView` and `Nine23LifestyleViews` own the native screens. `Nine23Demo` is an explicitly launched DEBUG fixture used only on the simulator; visible banners label its synthetic records.

## Data and algorithm boundaries

- All existing derived values still come from `Nine23Metrics` / `AppleMetricEngine`. Recovery factor explanations call the same dated `WatchRecovery` calculation with the same rounding and recalibration epochs. No scoring coefficients, thresholds or sleep formulas were changed.
- The activity dial is neutral and displays recorded exercise minutes, not a fabricated WHOOP strain score. VO2 max and weight are existing imported HealthKit values, now exposed through the UI.
- Historical routes retain the metric and day. Charts preserve missing days; selecting a bar opens that date. Sleep gaps and unclassified segments stay distinct. Heart-rate points do not bridge unobserved intervals; workout chart points are explicitly scoped by source and time window.
- Health monitor ranges are observed historical minima/maxima, not medical reference ranges. Journal insights use explicit yes/no answers with the following day's recovery, using the existing `BehaviorInsights` statistics. Native journal writes preserve the established source identifier.
- Community/team services, continuous stress, health age, ECG/BP and cycle analysis have no newly implemented backend/model. Their capability pages state the actual support instead of inventing results. The existing AI coach remains opt-in.
- Bundle IDs, App Group, databases, keychain identifiers and signing team remain unchanged. Build number advances to 439. Android is unchanged; this is the already approved Apple-specific presentation divergence.

## Validation

Build and interaction results are recorded in [NINE23_VALIDATION.md](NINE23_VALIDATION.md). Generated projects, signed apps, screenshots, private health records and local signing files remain outside version control. The icon generator renders the original black/white 9:23 mark into iPhone, Watch and Mac assets.
