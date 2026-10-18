# Quarantine Router Identity and Release

## Bug

Openwalla could identify a router-owned wireless or repeater interface as a new
client and quarantine it. Releasing a device could also show `Router could not
apply the device access change` even when its firewall rules were removed.

## Root Cause

Router identity filtering depended mainly on MAC addresses currently exposed in
`/sys/class/net`. Repeater interfaces may use configured or temporary MACs and
router-owned IPv4 addresses that are discovered through the normal client data
sources. The release flow also waited for a firewall reload, which can briefly
interrupt the RPC response and create a false failure.

## Resolution

- Discover router MAC addresses from sysfs, live links, UCI network settings,
  UCI wireless settings, and ubus network device status.
- Discover all router-owned IPv4 addresses from live interfaces and ubus.
- Exclude candidates matching either a router MAC or router IPv4 address.
- Remove existing device records and quarantine rules associated with those
  router identities during collector reconciliation.
- Commit rule deletion synchronously, then queue the disruptive firewall reload
  after returning a confirmation marker to the app.

## Files Changed

- `openwrt-setup/files/openwalla-devices-collector.sh`
- `lib/state/app_state.dart`
- `lib/utils/quarantine_release.dart`
- `test/device_block_state_test.dart`
- `test/quarantine_release_test.dart`
- `pubspec.yaml`
- `pub_script_version.yaml`
- `misc/change_reports/2026-10-18-quarantine-router-identity-and-release.md`

## Verification

- Router identity tests cover configured network MACs, wireless MACs, live link
  MACs, LAN addresses, and repeater/WWAN addresses.
- Release coverage verifies firewall reload is queued after confirmation.
- Collector shell syntax is validated.
- `flutter analyze`: no issues.
- `flutter test`: all 137 tests passed.
- App version: `1.0.522+424`
- Router script version: `2026.10.18.2`
