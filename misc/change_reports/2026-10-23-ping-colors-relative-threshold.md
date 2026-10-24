# Ping Colors Relative to Configured Alert Threshold

## Changes

- Shared ping color policy now takes the configured alert threshold in ms.
  Light green is below 30% of threshold; dark green is from 30% to below
  threshold; yellow is at/above threshold. Failure red and missing-data gray
  are unchanged.
- The 30% split remains a fixed UI ratio; users change the existing Ping Test
  Alert Threshold rather than maintaining separate color settings.
- Dashboard refresh loads router network-monitor settings alongside existing
  optional data and includes the threshold with ping samples. The dashboard
  timeline passes it into the shared policy.
- Network Performance refresh loads that same setting and passes it to both
  its timeline and Ping Test bars. Returning from settings refreshes the page.
- Saving monitoring settings updates the dashboard's threshold immediately and
  notifies listeners. Router configuration remains authoritative on refresh.
- Missing/unreadable/nonpositive threshold values fall back to the existing
  100 ms default, now defined on NetworkMonitorSettings.
- App version 1.0.541+443. No router-script or installer changes.

## Files

- `lib/state/app_state.dart`: threshold load/default and dashboard data updates.
- `lib/screens/dashboard_screen.dart`: pass dashboard threshold into coloring.
- `lib/screens/network_performance_screen.dart`: proportional policy and setting
  refresh/propagation to both panels.
- `test/ping_bar_color_test.dart`: proportion/boundary/fallback tests.
- `test/ping_chart_colors_test.dart`: rendered bars at 100/200 ms thresholds.
- `pubspec.yaml`: version.

## Verification

- 20 focused tests passed, including the exact 60 and 200 ms boundaries for a
  200 ms threshold, lower thresholds, defaults, red/gray states, and rendered
  Ping Test bars at phone width.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built or physical-device/router test performed.
