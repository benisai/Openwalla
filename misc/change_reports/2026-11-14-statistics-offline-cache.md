# Statistics Offline Cache

## Findings

Statistics checked installed tools through a live router command, even when viewing an offline snapshot. A failed check displayed the installation card. vnStat graph samples were already cached, but monthly settings and nlbwmon breakdowns were not.

## Changes

- Statistics skips the live installation gate in explicit Offline mode, including when no Statistics cache exists yet.
- Offline usage-settings editing is disabled. Panels without saved breakdown data show empty states rather than installation prompts.
- Successful tool detection is saved. A connection failure can reuse that saved detection result; a successful live probe confirming missing tools still fails the installation check.
- Monthly usage settings, named Top Devices rows, and Activity Analysis protocol rows now use the existing router JSON snapshot mechanism.
- Successful reads save those sections; offline reads require no router authentication or requests. Failed live reads fall back to saved settings/breakdowns without replacing successful data with errors.
- Saved monthly settings are also updated after a settings save. Existing vnStat graph caching is retained.
- Snapshots remain separated by router UUID and fingerprint, not IP address. No new storage service or cache format was introduced.
- Version: `1.0.577+479`.

## Scope

- `lib/screens/statistics_screen.dart`
- Statistics methods in `lib/state/app_state.dart`
- Existing Statistics header/UI tests and new Statistics snapshot tests
- Version and this report
- No router scripts, installers, ACL, or login-flow changes.

## Verification

- 45 focused Statistics and shared offline-cache tests passed.
- Covered offline UI with/without saved samples, transition from a failed live gate into Offline mode, disabled settings editing, live-to-offline cache reuse with zero RPC calls, disconnected fallback, confirmed missing tools, router-profile isolation at a shared IP, and existing usage-header layout behavior.
- Shared offline state, snapshot cache, and background-save regressions passed.
- Static analysis and whitespace checks passed.
- No APK built or live-router settings changed. Existing user APK changes were left untouched.

## Testing Note

Open Statistics once while connected to populate the newly cached monthly settings and nlbwmon breakdowns. Existing graph snapshots remain usable. No router reinstall is required.
