# Dashboard Physical Ethernet Ports

## Changes

- Removed Network from the shortcut grid and default shortcut order. Older saved orders discard the retired entry without changing the relative order of remaining shortcuts. The Network panel remains the entry point.
- Small icons now represent physical LAN/WAN Ethernet ports, not logical network interfaces. All discovered ports are shown, wrapping when needed; there is no four-icon cap or `+N` placeholder.
- Use optional LuCI `getBuiltinEthernetPorts` inventory and `getBoardJSON` hardware mapping, merged with the dashboard's existing `getNetworkDevices` carrier state. Both inventory reads start alongside existing dashboard requests and failures do not block dashboard availability.
- De-duplicate ports. Exclude bridges, tagged VLAN devices, Wi-Fi, tunnels, and switch CPU/conduit connections. Legacy switches use labeled non-CPU LAN/WAN PHY ports from board metadata; their link state stays unknown when individual PHY status is unavailable, rather than borrowing the CPU link.
- Existing runtime DSA devices provide a fallback. Generic Ethernet device types or names alone are not proof of a physical jack. Missing inventory shows `Ports unavailable`, not invented icons.
- Network-interface and active Wi-Fi counts and navigation are unchanged. Port status uses actual carrier where available, not administrative interface-up state.
- Normalized inventory is included in the per-router dashboard snapshot, so offline viewing retains the physical-port indicators. Older snapshots only use confirmed DSA fallback until refreshed online.
- Added read permission for `luci.getBuiltinEthernetPorts` to the bundled ACL. Existing board mapping permission remains a fallback when that method is unavailable/denied. No helper scripts or packages added.
- Version: `1.0.583+485`.

## Verification

- 47 focused tests passed, including the 2-LAN/1-WAN case, DSA and independent NICs, legacy switch CPU/VLAN exclusion, unknown carrier versus admin-up, unchanged network/Wi-Fi totals, all-port rendering, shortcut migration, cached inventory, optional-RPC failure, ACL and wired-only regressions.
- Static analysis and whitespace checks passed. Narrow light/dark panel layouts remain covered; real-font screenshot verified. No APK built or live router accessed. User-owned APK and attachment changes were left untouched.

## References

- [LuCI Ethernet port status panel](https://github.com/openwrt/luci/blob/master/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js) uses native inventory with board-network fallback.
- [LuCI inventory RPC](https://github.com/openwrt/luci/blob/master/modules/luci-base/root/usr/share/rpcd/ucode/luci) supplies built-in Ethernet devices, including its x86 enumeration workaround.
- [LuCI network-device RPC](https://github.com/openwrt/luci/blob/master/libs/rpcd-mod-luci/src/luci.c) reports carrier separately from administrative state.
