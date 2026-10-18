# Device Name Source and Save

## Bug

Device names cached in SQLite could remain indefinitely even when current DHCP
data no longer supplied that name. A client could therefore appear as
`OpenWrt` instead of `Unknown`. Device-name saves could also report a receive
timeout when the router had already applied the UCI change.

## Source Of Truth

1. A configured OpenWrt DHCP host entry for the device MAC is authoritative.
2. The live DHCP lease hostname is used when no configured name exists.
3. SQLite mirrors the resolved name for fast device-list loading.
4. A device with no usable DHCP name is shown as `Unknown`.

## Resolution

- Prefer configured DHCP host entries over live lease names.
- Ignore live lease names that incorrectly match the router's own hostname.
- Refresh the SQLite hostname from current DHCP data instead of preserving a
  stale non-empty value forever.
- Give native UCI name operations a longer response window.
- Retry the initial DHCP identity lookup after an ambiguous network timeout.
- Verify the DHCP host entry after an interrupted mutation before showing an
  error, avoiding false failures when the router already accepted the change.
- Synchronize the SQLite name cache before reporting a successful save.

## Files Changed

- `openwrt-setup/files/openwalla-devices-collector.sh`
- `lib/state/app_state.dart`
- `lib/utils/device_identity.dart`
- `test/device_block_state_test.dart`
- `test/device_identity_test.dart`
- `pubspec.yaml`
- `pub_script_version.yaml`
- `misc/change_reports/2026-10-18-device-name-source-and-save.md`

## Versions

- `flutter analyze`: no issues.
- `flutter test`: all 141 tests passed.
- App version: `1.0.523+425`
- Router script version: `2026.10.18.3`
