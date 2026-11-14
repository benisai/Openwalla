# Simplify AdBlock UI

## Request

Keep Openwalla's theme and simplify AdBlock to Block Ads, collapsible Feeds, and Safe Search.

## Changes

- Block Ads is now the first section and immediately saves the service setting using the existing AdBlock save path (enable/reload or stop/disable).
- Feeds starts collapsed, shows the selected count, and expands into standard checkbox rows. All existing feed choices and automatic debounced saving remain available.
- Safe Search has its own immediate-save switch below Feeds.
- Removed the service-control panel, runtime action buttons, manual Apply buttons, startup-interface input, and introductory text. Existing hidden settings, including startup interface, DNS backend, reports, and custom feed IDs, are preserved when saving.
- Controls are disabled during saves. Failed saves restore the last saved UI values and show the existing error toast.
- Pending feed changes are included if a switch is used before the debounce fires; saving does not reload the whole page or collapse Feeds.
- Version: `1.0.570+472`.

## Scope

- `lib/screens/adblock_screen.dart`
- `test/adblock_screen_test.dart`
- `pubspec.yaml` and this report
- No backend, installer, ACL, or router script changes.

## Verification

- 10 AdBlock widget tests passed: section order, collapsed feeds, immediate switches, hidden-setting preservation, pending-save locking, failure rollback, debounced feeds, pending-feed/switch interaction, retry, and narrow layouts in both themes with large text.
- Static analysis passed for the changed screen and tests.
- Rendered and visually inspected collapsed and expanded layouts with Openwalla's dark colors.
- No APK built; no live-router testing or configuration changes performed.
