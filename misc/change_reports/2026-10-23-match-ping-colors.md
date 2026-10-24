# Match Ping Colors Across Dashboard and Performance

## Changes

- Dashboard hourly Network Performance timeline uses the same status-color
  function as the timeline on the Network Performance page.
- Ping Test bars use per-sample status/latency colors rather than uniform green
  with a decorative yellow penultimate bar.
- Shared palette: light green below 30 ms, dark green from 30 ms to below
  100 ms, yellow at 100 ms or above, red for failed samples, and theme gray
  for missing data.
- Failed Ping Test samples retain a short visible bar and are not represented
  as missing data. Failed samples are excluded from latency scaling/statistics.
- Existing hourly averaging, five-minute sample selection, tooltips, chart
  dimensions, and speed-test bar colors remain unchanged.
- App version 1.0.540+442. Router assets/installers are unchanged.

## Files

- `lib/screens/network_performance_screen.dart`: shared status palette and
  explicit per-bar colors for Ping Test; optional chart colors preserve other
  chart behavior.
- `lib/screens/dashboard_screen.dart`: delegate timeline coloring to the
  shared policy.
- `test/ping_bar_color_test.dart`: threshold, failure, missing-data coverage.
- `test/ping_chart_colors_test.dart`: actual panel bar colors and phone-width
  layout check with mocked monitor samples.
- `pubspec.yaml`: version.

## Verification

- 12 focused tests passed, including exact 30/100 ms boundaries and rendered
  Ping Test bars for good/regular/slow/failed/missing samples. The isolated
  Ping Test panel was exercised at 390 logical pixels wide without overflow.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built or physical-device test performed.

## Separate Observation

The full-page test fixture with an empty Speed Test panel showed a pre-existing
Speed Test value/label row overflow at 390 pixels using the default test theme.
The color test isolates Ping Test for phone-width assertions; unrelated Speed
Test header layout was left unchanged.
