# Offline Banner Logout Fix

## Cause
- The app-level cache banner was a sibling of the Navigator, so its reconnect
  tooltip had no ancestor Overlay. The original banner test only covered a banner
  inside a page and did not reproduce the real app hierarchy.
- A pending failed read could also mark a section stale after logout completed.

## Changes
- Wrap the app-level layout in Flutter's `Overlay.wrap`, preserving the existing
  Navigator and banner layout while supporting tooltips above both.
- Only show stale-section status for authenticated sessions or explicit offline
  viewing. Failed reads finishing after logout no longer restore that status.
- App version 1.0.544+446; no router changes or APK build.

## Verification
- Added an actual LuCIApp widget test that displays the banner, opens its tooltip,
  logs out, and verifies clean removal without a missing-Overlay error.
- Added a delayed-read/logout regression test.
- All 21 focused offline/cache tests passed; static analysis and diff checks passed.
