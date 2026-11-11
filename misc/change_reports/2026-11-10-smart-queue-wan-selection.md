# Smart Queue WAN Selection

- Version: 1.0.565+467.
- Removed the Diagnostics section (Debug Logging and Log Verbosity). Existing router values are preserved on save rather than silently reset.
- Replaced the vnStat-derived device list and hardcoded `eth1`/`wan` fallback with named OpenWrt WAN networks. Discovery combines WAN-zone membership, non-LAN default-route interfaces, and configured WAN/WWAN names. Custom-named uplinks in the WAN zone or with a default route are included; vnStat is no longer needed for this selector.
- The dropdown displays WAN, WWAN, and other logical names, while SQM still receives the actual kernel device. Runtime `l3_device` is preferred, including PPPoE and Wi-Fi station devices. Virtual protocols without a resolved L3 device do not fall back to an unrelated Ethernet parent. Disconnected basic WANs can use their configured single device/legacy ifname.
- Unknown/unresolved choices are marked unavailable. No arbitrary Ethernet interface is fabricated; unmatched existing settings require an explicit valid selection before saving.
- Device mapping is refreshed immediately before save to handle a changed WWAN device. Fixed the save-progress flag so editing remains available after a successful save.
- Wrapped the enable toggle in Material to satisfy Flutter's ink/ListTile rendering requirements, and constrained dropdown labels for narrow screens/large text.

## Verification

- WAN discovery tests cover WAN/WWAN/custom names, LAN exclusion, IPv4/IPv6 default routes, PPPoE L3 mapping, disconnected interfaces, and no fake fallback.
- Screen tests select WWAN, change its runtime device before saving, verify the saved device and preserved diagnostic settings, verify save remains enabled afterward, and prevent an unresolved save.
- Smart Queue layout tests pass at widths 320, 430, and 1024 with 2x text scaling.
- Combined with the dashboard quarantine work, 59 focused tests passed. Focused analyzer and `git diff --check` passed.
- No SQM installation/enforcement scripts changed. No APK built or live-router configuration modified.
