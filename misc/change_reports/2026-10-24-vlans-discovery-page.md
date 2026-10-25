# VLAN Discovery Page

## Scope

Added More -> Manage Device -> VLANs. This first iteration is explicitly
read-only, intended to verify the router's actual topology before introducing
network mutations. Add/edit/delete, VLAN-filtering conversion, subnet/DHCP/
firewall setup, and safe-apply/rollback workflows are not implemented here.
No router network configuration is changed by this page.

## Discovery

- Required: native `uci.get` for network configuration.
- Optional: `luci-rpc.getNetworkDevices` for live device/bridge membership and
  link state; `luci-rpc.getBoardJSON` for legacy switch port/CPU mappings.
- DSA is identified only from runtime devtype=dsa, not inferred from port
  names or the mere presence of bridge configuration.
- Inventory includes bridge-vlan, legacy switch_vlan, explicit 8021q/8021ad
  devices, and dotted VLAN-device references in logical interfaces.
- Tagged/untagged/PVID flags are parsed using LuCI's port-spec conventions.
- Legacy numeric ports remain numeric when board metadata is unavailable.
  CPU connections use the board's device field; no CPU port number is guessed.
- Bridge memberships and discoverable logical interface assignments are shown.
  Legacy switch-to-interface association is marked unresolved rather than
  guessing a CPU device/tag relationship.
- Unknown filtering or link state remains unknown; runtime network devices
  are not presented as a guaranteed count of physical sockets.
- Missing optional metadata produces visible warnings while preserving the
  configured VLAN inventory. Required network-read failures show Retry.

## UI

- VLANs tab with expandable VLAN details.
- Ports & Bridges tab with bridge membership/filtering, port identity/type,
  and available live link state.
- Header refresh, pull-to-refresh, loading, error/retry, and empty states.
- Read-only status is visible. Existing Manage Device styling is preserved.

## Files and Versions

- `lib/screens/vlans_screen.dart`: new discovery page.
- `lib/services/vlan_discovery_service.dart`: topology models and read-only RPCs.
- `lib/screens/manage_device_screen.dart`: VLANs navigation row.
- `lib/state/app_state.dart`: selected-router transport binding.
- `openwrt-setup/rpcd-acl.json`: add only read access to getBoardJSON.
- Focused discovery, screen, and ACL tests.
- App 1.0.542+444; router assets 2026.10.24.1.

Restricted accounts may need the updated RPC ACL and a fresh login for board
mapping. Existing permissions can still provide the VLAN list with a mapping
warning. No packages or collectors are required.

## References

Reviewed official OpenWrt 25.12 LuCI sources:

- https://github.com/openwrt/luci/blob/openwrt-25.12/modules/luci-base/htdocs/luci-static/resources/network.js
- https://github.com/openwrt/luci/blob/openwrt-25.12/modules/luci-mod-network/htdocs/luci-static/resources/tools/network.js

## Verification

- 19 focused tests passed, covering DSA two-LAN/one-WAN topology, legacy CPU
  mapping, missing board data, tagged devices, implicit VLAN references,
  malformed/empty data, configuration errors, navigation, refresh, and a
  360 x 640 logical-pixel dark-theme layout.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: passed.
- No APK built or physical-router discovery verified.
- Pre-existing APK-TEST deletion/addition was left untouched and unstaged.
