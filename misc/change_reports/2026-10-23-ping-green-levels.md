# Ping Bar Green Levels

## Changes

- Hourly ping bars use light green (#86EFAC) for successful average latency
  below 30 ms, and dark green (#168A48) for 30 ms to below 100 ms.
- The 30 ms excellent cutoff is a UI choice, not a universal network standard.
- Yellow remains 100 ms and above. Red (only failures) and gray (no data)
  are unchanged. Bucketing, tooltips, and alert thresholds are unchanged.
- Other green charts and resolved-event colors are not affected.
- App version: 1.0.535+437. Router assets are unchanged.

## Verification

- Eight color tests cover both green levels and exact 30/100 ms boundaries.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built or physical-device visual test performed.
