# Wi-Fi Password Lockout Review

## Status

Read-only review of application behavior and Git history. No app, router script,
version, or router configuration changes were made. The cause of this specific
router's disappearing SSID is not established without runtime logs.

## Findings

### P1: No automatic recovery after an unusable Wi-Fi apply

`lib/state/app_state.dart:9360` explicitly calls UCI apply with `rollback: false`.
If the radio cannot start with the new configuration, the application does not
restore its previous working configuration. The SSH fallback likewise commits
wireless settings directly at line 9411 and reloads without a rollback watchdog.
This explains the absence of a recovery mechanism, not the initial AP failure.

OpenWrt rpcd implements timed rollback and confirmation for apply operations:
https://lxr.openwrt.org/source/rpcd/uci.c

### P1: A write-stage transport failure can be reported as successful apply

The try/catch at `lib/state/app_state.dart:9314` spans interface writes, radio
writes, and apply. The handler at line 9370 treats a connection error anywhere
in that block as `appliedWithLuci = true`. It does not track whether the apply
request was actually reached or verify that the AP returned. The screen then
reports saved settings even if a write was interrupted before apply.

### P2: WPA2 password validation has no upper-length/format check

`lib/state/app_state.dart:9308` and
`lib/screens/interfaces_screen.dart:5459` only reject passwords shorter than
eight characters. They accept overly long non-hex WPA2 passphrases that hostapd
cannot use. WPA2 accepts an 8-63-character passphrase or a 64-digit hex PSK.
This is one possible AP startup failure, not a confirmed diagnosis here.

Reference: https://openwrt.org/docs/guide-user/network/wifi/encryption

## What Changed

- `6bf75e6` (2026-09-24) added the open-network plus nonempty password conversion
  to WPA2 (`psk2`). That conversion remains present in the screen and backend.
- `85bc0b9` (2026-10-07) introduced the current UCI apply call with rollback
  disabled.
- `73f29c5` (2026-10-08) removed the explicit pre-apply wireless commit, expanded
  the disconnect handler to cover the writes as well as apply, and introduced
  the current SSH fallback.
- Recent repeater commits `bca86ec` and `4ea317e` changed the repeater path, not
  `saveWirelessNetworkConfig` or the AP password-edit sheet.

## Next Evidence and Repair

- Confirm whether Ethernet or a second radio still provides router access.
- Without restarting Wi-Fi again, collect recent hostapd/wpad/netifd errors:
  `logread | grep -Ei 'hostapd|wpad|netifd|wlan|phy' | tail -n 100`.
- Confirm whether the SSID is absent on a fresh scan from another device or
  whether an old saved open-network profile simply cannot reconnect.
- Do not request or publish the Wi-Fi password, full unredacted wireless config,
  or generated hostapd configuration.
- Recommended repair: validate WPA2 inputs, restrict expected-disconnect handling
  to the apply phase, and implement safe apply/confirmation with rollback in
  both supported transports before further sole-radio testing.
- No tests or APK build were run because this change is documentation-only.
