# Dashboard Offline Status Placement

- Moved the offline/saved-data status from the global app builder into the
  dashboard, immediately above the hostname/router selector.
- Match its background to the dashboard instead of a separate gray app-wide band.
- Preserve the saved timestamp, read-only label, reconnect control, and status-bar
  safe-area handling. The banner now uses the route's normal Navigator overlay.
- Remove the extra global overlay wrapper. No cache or router behavior changes.
- Allow the Live Traffic placeholder icon to shrink in constrained space, avoiding
  a small vertical overflow exposed by the mobile viewport check.
- App version: 1.0.545+447. No APK built.

## Verification
- Update the real-app widget regression to check that the banner is absent on
  splash, appears above the dashboard selector on mobile/desktop, supports
  tooltips, and is removed on logout. Focused offline/cache/ping rendering tests
  and static analysis passed.
