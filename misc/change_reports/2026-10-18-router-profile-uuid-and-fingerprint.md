# Router Profile UUID and Fingerprint

## Summary

- Replaced address-and-username profile IDs with random UUID v4 identifiers.
- Added a physical-router fingerprint discovered after LuCI authentication.
- Prefer the router serial number when OpenWrt exposes one; otherwise use the LAN device MAC address.
- Reuse an existing UUID when its fingerprint is found at a new address.
- Keep routers sharing an address, such as `192.168.1.1`, in separate profiles when their fingerprints differ.
- Reject a saved-profile connection when the address answers with a different known fingerprint.
- Automatically migrate existing profiles and router-scoped secure-storage values to UUID keys.
- Updated router profile backups to identity format version 2.

## Files Changed

- `lib/models/router.dart` - stores the fingerprint and identity schema version.
- `lib/services/router_service.dart` - creates UUID profiles, migrates legacy profiles, and matches fingerprints.
- `lib/services/secure_storage_service.dart` - moves router-scoped settings from legacy IDs to UUIDs.
- `lib/state/app_state.dart` - discovers and validates the physical router after login.
- `lib/utils/router_identity.dart` - UUID generation and OpenWrt fingerprint parsing helpers.
- `test/router_identity_test.dart` - fingerprint parsing coverage.
- `test/router_profile_backup_test.dart` - UUID, matching, and migration coverage.
- `pubspec.yaml` - bumps the app to `1.0.524+426`.

## Verification

- `flutter test test/router_profile_backup_test.dart test/router_identity_test.dart`
- `flutter analyze`
