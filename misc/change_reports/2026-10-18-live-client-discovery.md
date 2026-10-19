# Live Client Discovery and SQLite History

## Problem

A nonempty SQLite device inventory bypassed live DHCP discovery. Newly connected
clients could be absent until the collector ran, and cached names and statuses
could hide newer information from standard OpenWrt APIs.

## Behavior

- Read LuCI DHCP leases and dedicated Wi-Fi association lists on each device-list fetch.
- Merge live clients with SQLite history by normalized MAC, never by reused IP address.
- Prefer configured DHCP host names, then live lease names, then LuCI host hints.
- Preserve historical device names when there is no newer identity evidence.
- Keep SQLite vendor, icon, hidden-device metadata, and cached accounting totals.
- Use Wi-Fi associations as evidence that a wireless client is connected.
- Use reachable neighbor states and learned bridge entries for wired connectivity.
- Keep a router-scoped 90-second wired activity grace period to reduce flickering.
- Fall back to the ARP table when neighbor commands are unavailable.
- Preserve cached connectivity when required discovery queries are unavailable.
- Exclude the router's own MAC/IP addresses, hidden devices, and upstream neighbors.
- Preserve access-point LAN discovery when LAN carries the default route.
- Read traffic totals through `/usr/libexec/nlbwmon-action` when available, otherwise
  retain the collector's nlbwmon-derived totals. Wi-Fi station counters are not
  used as historical bandwidth totals.
- Apply live firewall rules after merging history so cached quarantine flags do
  not override current firewall state.
- Use the same per-router discovery process for selected and aggregated lists.
- Correct collector Wi-Fi collection to query actual `iwinfo` associations and
  stop treating complete ARP entries as current activity when NUD data is available.

## Files

- `lib/services/client_discovery_service.dart`: native discovery, optional table
  queries, nlbwmon parsing, and MAC-based history merging.
- `lib/state/app_state.dart`: integrates live discovery, router-scoped history
  reads, Wi-Fi associations, wired activity grace, and firewall reconciliation.
- `openwrt-setup/files/openwalla-devices-collector.sh`: correct wireless discovery
  and ARP fallback behavior.
- `test/client_discovery_test.dart`: live/history merging, identity precedence,
  neighbor and bridge evidence, unavailable APIs, accounting, and AP regression tests.
- `test/device_block_state_test.dart`: shell regression for actual association collection.
- `pubspec.yaml`: app version `1.0.525+427`.
- `pub_script_version.yaml`: router script version `2026.10.18.4`.

## Validation

- Full Flutter suite: 162 tests passed before the final AP-specific regression addition.
- Final focused client/collector tests rerun after the AP safeguard.
- Flutter analysis and shell syntax checks.
- Physical-router behavior remains to be verified on the user's OpenWrt router.

## Deployment

Install the updated app to use live discovery. Update the router's Devices
Collector component through Router Setup to receive the collector fixes as well.
No database reset or deletion of device history is required.
