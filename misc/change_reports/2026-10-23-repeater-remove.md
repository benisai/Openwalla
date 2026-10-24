# Repeater Remove

## Scope

Added Remove beside Connect/Disconnect in expanded repeater details. A
confirmation warns that removal disconnects the uplink and may interrupt Wi-Fi.
The selected wireless station is deleted, including its saved SSID and key.
APs, radio devices, network interfaces, and firewall configuration are preserved.

## LuCI Reference

Reviewed the official OpenWrt 25.12 LuCI sources online:

- https://github.com/openwrt/luci/blob/openwrt-25.12/modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js
- https://github.com/openwrt/luci/blob/openwrt-25.12/modules/luci-base/htdocs/luci-static/resources/form.js

Wireless Remove delegates to TypedSection.handleRemove, which removes just the
selected UCI section and saves pending changes. It does not remove its network
interface or firewall zone. LuCI applies those changes through Save & Apply.
Openwalla combines removal and apply after confirmation rather than requiring a
separate pending-changes screen.

## Implementation

- `lib/services/repeater_removal_service.dart`: fetch current wireless config;
  require the exact section to be a wifi-iface in sta mode; invoke native UCI
  delete and apply. Do not commit before apply. Verify section absence and no
  remaining wireless changes, retrying read-only probes for up to 30 seconds.
  Only an apply-stage transport disconnect is treated as an uncertain outcome;
  deletion is never replayed. Authentication/rejection/write errors still fail.
- `lib/state/app_state.dart`: connect the service to the selected router's
  existing authenticated RPC transport and refresh dashboard data afterward.
- `lib/screens/interfaces_screen.dart`: confirmation, busy-state protection,
  destructive action, and existing standard success/error toasts.
- `test/repeater_removal_service_test.dart`: focused behavior and failure tests.
- `pubspec.yaml`: app version 1.0.532+434.

No AP password-save behavior, router scripts, or installer logic was changed.
No SSH fallback or new router package is required for this action.

## Verification

- 23 focused tests passed across removal and existing repeater reconnection.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built. Physical router/mobile UI verification remains to be performed.

## Existing Router Limitation

The user reproduced disappearing AP broadcasts after changing AP security while
using a same-radio station, through both Openwalla and LuCI; reboot restored
the broadcast with the saved password. Removal also applies wireless changes
and does not claim to fix that separate OpenWrt runtime/reload issue. Keep
Ethernet access available for the first physical-router test.
