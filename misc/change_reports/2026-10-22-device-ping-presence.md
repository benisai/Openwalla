# Device Ping Presence Checks

## Scope

- Added `openwrt-setup/files/openwalla-devices-ping.sh`, installed as
  `/usr/bin/openwalla-devices-ping`.
- Added `openwrt-setup/files/Openwalla-1min-run.sh`, installed at the same name
  under `/usr/bin`. There was no existing one-minute runner in the repository.
- Devices Collector and Quarantine installers deploy both helpers and register
  one cron entry, running every minute. Existing installs receive the helpers
  through Router Components updates when the Devices Collector is present.
- Device component removal also removes these helpers and their cron entry.
- Updated the Device Inventory README bullet, regression tests, and versions.
- No app UI, firewall engine, discovery collector, or database schema changes.

## Behavior

- Reads the configured devices SQLite database, excluding hidden or invalid
  clients and router-owned IPv4/MAC addresses.
- Sends one ICMP echo per client, with a two-second timeout, at most five
  clients concurrently. An overlapping invocation skips the active scan.
- A reply refreshes `last_seen` and online status, preserving manual blocks,
  quarantine, and scheduled-block metadata. No firewall rules are changed.
- Missed replies do not immediately declare a client offline: some devices
  ignore ICMP. Existing discovery evidence and offline expiry remain in charge.
- Neighbor MAC mismatches reject stale-IP replies. Writes also check that the
  database still assigns the same IP to the same visible client.
- Collects successful results and applies one SQLite transaction rather than
  making concurrent database writes from the five workers.
- Missing databases and disabled device collection are skipped. No new device
  rows are created, and names, vendors, and traffic totals are untouched.
- IPv4 only, matching the current device inventory address field.

## Deployment

- App version: `1.0.527+429`; router scripts: `2026.10.22.1`.
- Update Router Components or rerun the Devices Collector/Quarantine installer.
- Manual router check: `/usr/bin/openwalla-devices-ping`.
- Cron output: `/tmp/openwalla/openwalla-1min-run.last.log`.
- Runtime scan state stays under `/tmp/openwalla` and is removed after each run.
- No APK was built. Real-router ICMP behavior needs testing on the router.

## Verification

- Focused ping, collector-state, and blocking-engine suite: 30 tests passed.
- Tests use a real SQLite database and simulated ping, network, and UCI tools.
- Coverage includes five-worker batches, partial batches, reachability, missed
  replies, changed neighbor MACs, protected access states, hidden/router/invalid
  targets, disabled collection, missing databases, overlapping scans, and cron
  idempotency/runner dispatch.
- Focused Flutter analysis, shell syntax, and Git whitespace checks passed.
