# Repeater Reconnect Budget

- Changed verification from a 90-second budget to two 15-second windows.
- Both windows share one elapsed-time clock, including the initial settling
  delay, probe timeouts, and polling pauses: at most 30 seconds total.
- The second window retries status verification only. It does not reapply
  Wi-Fi configuration or trigger another radio restart.
- SSID/BSSID, DHCP, transport-error handling, and recovery messages are unchanged.
- Added coverage for the default 15 + 15 second budget and successful recovery
  in the second window after the first expires.
- App version: `1.0.531+433`. No router script changes or APK build.
- Verification: 11 focused repeater tests passed; Flutter analysis and Git
  whitespace checks passed.
