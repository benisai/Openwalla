# Dashboard Network Panel

## Changes

- Added a compact Network panel above the shortcut grid in portrait and landscape dashboard layouts, inspired by the provided reference while retaining Openwalla's surface, border, typography and cyan accents.
- Globe and Network heading on the left, with up to four interface-status indicators and an overflow count. Green means up, orange means down, and gray means unknown; tooltips and accessibility labels identify each logical interface and status.
- Right side shows logical network-interface count and active Wi-Fi access-point count with icons and a divider. Loopback and duplicate interfaces are excluded. Repeater/client uplinks, disabled APs and down radios do not inflate the Wi-Fi count. The same SSID on two active radios counts as two AP interfaces.
- Network/title taps open Network; the Wi-Fi count opens Wi-Fi. Existing shortcuts remain unchanged.
- Uses only the existing dashboard payload, including offline snapshots. No extra router calls, collectors, packages, scripts or permissions. Counts describe reported logical interfaces, not inferred physical switch ports or connected client totals. Missing data shows unavailable rather than zero; explicitly empty data shows zero.
- Narrow layouts scale labels to fit and keep the panel intrinsically compact with bounded indicator counts.
- Version: `1.0.582+484`.

## Verification

- 29 dashboard tests passed, including interface/AP counting, repeater/disabled exclusions, missing/malformed data, independent navigation callbacks, light/dark themes, and 320/430/1000px layouts with 1.5x text.
- Rendered and inspected the narrow dark-theme panel with real fonts. Static analysis and whitespace checks passed.
- Scope: dashboard insertion, one reusable panel widget, focused tests, version and this report. No APK built or live router accessed. Existing user APK and attachment changes were left untouched.
