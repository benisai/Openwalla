# Exclude WAN Interface From Netify History

- Version: 1.0.564+466.
- Added `openwalla.collector.exclude_wan_interface`, default `1`, to the collector, packaged config, and standalone Netify installer. Installer defaults preserve an explicit user setting of `0`.
- Insertion uses the same resolved interface stored in the row and displayed as Outbound Interface: event `interface`, then flow `interface`, then flow `local_interface`.
- With the option enabled, an exact `wan` match (case insensitive, surrounding whitespace trimmed) prevents insertion into `flow_raw`. `wan6`, `pppoe-wan`, unknown interfaces, and LAN flows are not excluded by this option.
- Existing rows are not deleted. HTTP/HTTP-S filtering, flow labels, five-minute accounting, traffic totals, backup/reboot, and the external server remain unchanged.

## CLI Control

Deploy the updated router collector first. To include WAN rows again:

```sh
uci set openwalla.collector.exclude_wan_interface='0'
uci commit openwalla
/etc/init.d/openwalla-netify-collector restart
```

Set the value to `1` and restart again to restore WAN exclusion. Missing settings default to enabled.

## Verification

- 18 tests passed across column storage/insertion, protocol/UCI filtering, and flow accounting. Coverage includes default skip, disabled insertion, existing-row preservation, exact matching, nested interface fallbacks, and root-interface precedence.
- Focused analyzer, both edited shell syntax checks, and `git diff --check` passed.
- No APK built and no live-router changes made.
