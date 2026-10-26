# Offline Router Snapshots

## Scope
- App-only experiment, version 1.0.543+445. No router scripts or SQLite schemas changed.
- Updated the privacy policy's local-storage and profile-deletion disclosure.
- Cache dashboard, devices, Network (interfaces, firewall and port forwards), Wi-Fi,
  interface usage history, and Network Performance display data as it is fetched.
- Network Performance includes ping history, threshold, speed-test history, and
  network-related recent events. This is not a full notification or flow archive.

## Storage
- One JSON file per saved router UUID under the app's private application-support
  directory: `router_snapshots/<base64url-router-uuid>.json`.
- Versioned sections have individual `savedAt` timestamps. Fingerprints prevent
  loading a snapshot belonging to a different known physical router.
- Serialized, atomic replacement writes avoid partial files or concurrent section
  updates overwriting one another. Each file is limited to 8 MiB and 64 sections.
- Wi-Fi passwords, WEP keys, session tokens and private-key fields are stripped
  recursively. Router profile credentials remain in the existing secure storage,
  never copied to snapshot files. Snapshot display data itself is not encrypted.
- Removing a saved router also removes its snapshot. Logging out retains snapshots.

## Behavior
- Live fetches remain the default; successful display reads update the snapshot.
- Dashboard connection failures retain the last good view and enter read-only mode.
- Failed monitoring reads fall back to the previous successful section rather than
  persisting the error. A banner identifies saved data and provides reconnect.
- After a failed login, an Offline button appears beside Connect when the selected
  saved profile has a dashboard snapshot. Offline entry does not authenticate.
- Choosing another saved router on the login screen selects that profile's cache,
  including when multiple profiles use the same IP address.
- Offline mode blocks RPC commands and SSH connections. Only router identity reads
  are permitted to support checking the physical router during reconnection.
- Wi-Fi sharing is unavailable offline because passwords are intentionally absent.

## Limits
- Open the relevant pages online first to populate their sections. Unvisited pages
  may have no saved data. This does not download every router database on login.
- Online/offline client status, uptime, counters, and charts are historical values
  while offline, not live measurements. Speed tests and Wi-Fi scans cannot run offline.
- Only the listed views are cached. Other management screens still require a router
  connection. No queued writes, synchronization engine, or background offline polling.

## Verification
- Storage and app-state tests cover UUID/fingerprint isolation, same-IP profile
  selection, restart persistence, concurrent writes, corrupt files, size limits,
  secret removal, deletion, live updates, and failed-read fallback.
- Real API and SSH entry points reject commands before connecting in offline mode.
- Widget tests verify the failed-login button row at mobile width and the banner
  at mobile/desktop widths. Existing ping chart mocks include the new offline flag.
- Full suite: 328 tests passed with `flutter test --no-pub --concurrency=2`.
  Static analysis and `git diff --check` passed.
- An unrestricted parallel run hit an existing timing-sensitive repeater reload
  test; the complete lower-concurrency run passed without changing that test.
- No APK built or physical phone/router outage test performed.

## Trial And Rollback
1. Install the new app build, log in online, and visit the desired pages.
2. Make the router unreachable, return to login, and use Offline after login fails.
3. Verify saved views, then reconnect using the banner when the router returns.

Kept as a single feature commit for rollback. Reverting that commit restores the
previous app behavior; leftover private snapshot files are inert. Existing router
data, installation, profiles and credentials are unchanged by the rollback.
