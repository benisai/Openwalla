# Secure Offline Wi-Fi Sharing

- Save AP Wi-Fi sharing passwords in platform secure storage during successful
  wireless-config refreshes. Never write them to display JSON snapshots.
- Scope credentials by router UUID/fingerprint and wireless section; restore only
  when SSID and encryption match. Exclude station/repeater uplink credentials.
- Restore passwords into the in-memory offline Wi-Fi view, enabling the existing
  password display and QR sharing sheet without contacting the router.
- Missing protected-network passwords show a clear message rather than generating
  an invalid QR code. Open networks remain shareable without a password.
- Profile deletion uses the existing router-scoped secure-storage cleanup.
  Snapshot the matching key list before deletion to avoid mutating an active iterator.
- Updated privacy disclosure. App version 1.0.546+448; no router changes or APK build.

## Verification
- Tests cover secure persistence, JSON secret exclusion, matching/scoping, refresh,
  deleted APs, uplink exclusion, open networks, invalid cache, profile deletion,
  and restoring credentials into offline app state without network access.
- All 35 focused Wi-Fi/offline/cache/server-settings tests passed; static analysis
  and diff checks passed. No physical-phone sharing test performed.

## Trial
Log in with the new build and refresh Wi-Fi once while online. Then use Offline
and tap the Wi-Fi password row to display/share its saved QR code. Passwords are
the latest successfully fetched values, not a live guarantee while disconnected.
