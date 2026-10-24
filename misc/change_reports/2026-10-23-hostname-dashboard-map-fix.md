# Hostname Dashboard Map Type Fix

## Cause

After successfully saving the router hostname, the local dashboard boardInfo
update spread an untyped Map into an untyped map literal. This produced a
Map<dynamic, dynamic>, while dashboard consumers cast boardInfo to
Map<String, dynamic>. Returning to the dashboard raised the reported type error
until a fresh router response replaced the cached map.

## Change

- Preserve Map<String, dynamic> when copying boardInfo and replacing hostname.
- Retain other board fields without mutating the original map.
- Add a regression test that uses the same runtime cast as the dashboard.
- App version: 1.0.534+436.

Only the local hostname cache update changed. Router UCI writes, timezone,
Wi-Fi behavior, and router assets are unchanged.

## Verification

- Focused system-settings service, screen, and ACL tests passed (22 tests).
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built; not tested on a physical phone/router.
