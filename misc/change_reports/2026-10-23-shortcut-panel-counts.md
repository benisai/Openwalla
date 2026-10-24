# Shortcut Panel Counts

## Changes

- Dashboard settings now offer 3, 6, or 9 icons per shortcut page.
- Existing 3/6 settings remain supported; default stays 6.
- Nine-icon preference survives copying and JSON persistence, including
  numeric strings. Unsupported or missing counts fall back to 6.
- Dashboard keeps three columns and swipe navigation. Panel height uses
  one, two, or three fixed-height rows, including spacing, so the nine-icon
  page fits without a nested scrolling grid or clipped bottom row.
- Shortcut visibility and ordering are unchanged.
- App version 1.0.537+439. Router scripts/installers are unchanged.

## Files

- `lib/models/dashboard_preferences.dart`
- `lib/screens/dashboard_screen.dart`
- `lib/screens/router_dashboard_settings_screen.dart`
- `test/dashboard_shortcut_visibility_test.dart`
- `pubspec.yaml`

## Verification

- Eight focused dashboard preference tests passed, including 3/6/9 round-trip
  persistence, unrelated updates, and legacy defaults.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built or physical-device layout test performed.
