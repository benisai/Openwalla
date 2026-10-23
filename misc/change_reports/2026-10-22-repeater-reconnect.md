# Wi-Fi Repeater Reconnection Handling

## Finding

The SSH and command-RPC repeater fallback reloaded Wi-Fi and the network before
printing its confirmation marker. A phone connected through that radio could
lose the response even when the settings had been written. SSH could then fall
through to another configuration attempt; the final command-RPC path propagated
the transport exception or a failing dashboard refresh to the connection sheet.
Native LuCI apply already tolerated some disconnections, but it did not verify
the resulting association and did not cover connect/send timeouts.

## Changes

- Retained LuCI-compatible configuration as the first path; the custom ACL file
  is not required for that path. Existing SSH/RPC fallbacks remain available.
- The fallback now commits configuration and acknowledges a detached,
  HUP-resistant reload scheduled two seconds later, with all descriptors
  redirected. `set -e` prevents a failed configuration command from being
  silently followed by a successful confirmation.
- Reload output is retained at
  `/tmp/openwalla/openwalla-repeater-reload.log`.
- A shared verification service allows a three-second settling period, then
  polls for up to 90 seconds with bounded probes. It requires the WWAN
  interface to be up with an IPv4 address and iwinfo to report the requested
  SSID and selected BSSID, if supplied.
- A transport loss during/after apply waits for verification instead of
  immediately reporting failure or replaying the configuration through another
  fallback. Authentication and HTTP failures are not treated as transport loss.
- A transport failure before native apply is not assumed successful and does
  not blindly repeat configuration through another transport.
- Offline timeout messages explain how to reconnect and check existing
  settings; reachable-but-unconnected results point to credentials/upstream
  connectivity. Neither case is reported as verified success.
- Dashboard refresh after a verified join is best effort and cannot turn the
  successful join into a connection-sheet failure.

## Scope

- `lib/services/repeater_reconnect_service.dart`: verification, disconnect
  classification, user-facing recovery messages, and shared reload command.
- `lib/state/app_state.dart`: repeater-only integration and reload sequencing.
- `test/repeater_reconnect_service_test.dart`: focused transport, status,
  deadline, and delayed-shell-reload regressions.
- `pubspec.yaml`: app version `1.0.530+432`.
- No general Wi-Fi password-edit, installer, firewall, collector, or UI layout
  changes. Router script version is unchanged because this fix is app-side.

## Verification

- Full Flutter suite: 213 tests passed. Flutter analysis and Git whitespace
  checks passed.
- Nine focused tests passed, including recovery after network-unreachable
  errors, identity/DHCP checks, offline/wrong-password outcomes, authorization
  errors, a hard reconnect deadline, and a real shell acknowledgement before
  the simulated delayed reload.
- Physical OpenWrt and phone reconnection testing remains required. No APK
  built. Rebuild/update the app; no Router Components update is necessary.
