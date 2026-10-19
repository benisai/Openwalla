# Shared Device Blocking Engine

## Outcome

Manual blocking and automatic quarantine now execute the same shell engine,
`openwalla-device-access.sh`. The app bundles that source and runs it through
authenticated RPC, falling back to SSH with the saved router credentials when
RPC execution is unavailable. The collector sources the installed copy.

## Rules and State

- Rule identity always uses the normalized MAC address, never the hostname.
- Manual and quarantine restrictions have separate ownership prefixes.
- Both create `family=any` rules for IPv4 and IPv6.
- Manual blocking covers routed forwarding and router input.
- Automatic quarantine covers routed forwarding and preserves router access.
- Releasing quarantine preserves independent manual and parental restrictions.
- General device release determines the current reason from firewall rules.
- Multi-device legacy rules retain their other MAC addresses during release.
- Legacy IPv4-only quarantine rules migrate through the shared engine on the
  collector's next scan, with failures eligible for retry.
- Firewall configuration remains authoritative; SQLite is display metadata.

## Applying Changes

- A shared router-side lock serializes app, collector, and hotplug changes.
- The engine stages a private firewall configuration, checks for competing
  changes, and publishes the completed configuration atomically.
- Firewall reload and active nftables/iptables inspection must succeed before
  the engine emits a success marker. Failed verification restores the previous
  configuration when it is still safe to do so.
- RPC/SSH retries reuse a request UUID and cached result, avoiding a second
  release that could otherwise remove an independent restriction.
- The app no longer inserts separate runtime nftables/iptables block rules.
- When available, conntrack clears the device's existing tracked connections.
  Devices and quarantine installers request this optional package.
- Device views reconcile their optimistic state with firewall state after an
  operation, and the quarantine list reloads after release.

## Detector Fixes

- Failed enforcement does not remember the device as successfully processed or
  send a successful quarantine notification; the next scan retries.
- Router interfaces and hidden devices are excluded before quarantine decisions.
- Toggling quarantine preserves the collector polling setting rather than
  forcing 15 seconds. The quarantine screen reports the actual polling value.
- The component updater installs the new library on existing collector installs.

## Files Changed

- `openwrt-setup/files/openwalla-device-access.sh`: shared engine.
- `lib/services/device_access_service.dart`: app transport and verified replies.
- `lib/state/app_state.dart`: shared operations and polling behavior.
- `lib/screens/clients_screen.dart`: post-operation firewall reconciliation.
- `lib/screens/quarantine_screen.dart`: post-release list reload.
- `openwrt-setup/files/openwalla-devices-collector.sh`: shared enforcement,
  migration, retry, and notification behavior.
- `openwrt-setup/openwalla-components.sh`: dependency-aware library update.
- `openwrt-setup/standalone/install-devices-collector.sh` and
  `openwrt-setup/standalone/install-quarantine.sh`: library and package deployment.
- `lib/utils/quarantine_release.dart`: removed superseded release implementation.
- `test/quarantine_release_test.dart`: replaced by shared-engine coverage.
- `test/device_access_engine_test.dart`, `test/device_access_service_test.dart`,
  and `test/device_block_state_test.dart`: enforcement and detector regressions.
- `README.md`, `pubspec.yaml`, and `pub_script_version.yaml`: documentation,
  asset registration, and versions.

## Verification

- Full Flutter suite: 173 tests passed.
- Final focused engine, transport, collector, and migration suite: 25 tests passed.
- Flutter analysis: no issues.
- Shell syntax and Git whitespace checks passed.
- Shell integration tests use simulated UCI, firewall reload, and nftables
  commands; physical-router behavior has not been tested in this workspace.

UCI flag behavior was checked against the
[OpenWrt UCI CLI source](https://github.com/openwrt/uci/blob/master/cli.c).
Established-flow handling was checked against the
[firewall4 ruleset template](https://github.com/openwrt/firewall4/blob/master/root/usr/share/firewall4/templates/ruleset.uc).

## Deployment and Limits

- App version: `1.0.526+428`; router components: `2026.10.18.5`.
- Install the updated app and update Router Components on the router. The new
  library is added automatically for an existing Devices Collector installation.
- Reinstalling Devices Collector or Quarantine also requests conntrack. Without
  it, an already established session may persist until its connection expires.
- Discovery remains based on IPv4 records/events. Once identified, a quarantined
  device's routed IPv4 and IPv6 traffic is blocked.
- Routed firewall blocking does not provide same-bridge Ethernet/Wi-Fi isolation;
  that requires separate bridge, VLAN, or access-point isolation policy.
- No APK was built and no device inventory reset is required.
