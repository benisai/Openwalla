# Quarantine Firewall Source of Truth

## Bug

After releasing or unblocking a device, it could remain in the blocked device
list even though its Openwalla firewall rules had been removed.

## Root Cause

The app combined live firewall rules with cached `quarantined`, `blocked`, and
scheduled values from the devices SQLite database. A stale database value could
therefore keep a device blocked after the authoritative firewall rule was gone.
The collector also did not clear quarantine flags for devices absent from its
current candidate list.

## Resolution

- Parse current enabled Openwalla firewall rules into blocked, quarantined, and
  paused MAC address sets.
- Use those live rules as the sole source of blocked and quarantine state.
- Continue using the devices database for identity, connection, and traffic
  metadata only.
- Preserve the last known state when the firewall configuration cannot be read.
- Clear cached quarantine flags during each collector pass before rebuilding
  them from current firewall rules.

## Files Changed

- `lib/state/app_state.dart`
- `lib/utils/device_firewall_state.dart`
- `openwrt-setup/files/openwalla-devices-collector.sh`
- `test/device_block_state_test.dart`
- `test/device_firewall_state_test.dart`
- `pubspec.yaml`
- `pub_script_version.yaml`

## Verification

- Firewall parsing tests cover automatic quarantine, manual blocks, scheduled
  blocks, disabled rules, legacy rules, and failed reads.
- Collector regression coverage verifies stale flags are cleared before current
  firewall quarantine rules are restored.
- App version: `1.0.521+423`
- Router script version: `2026.10.18.1`
