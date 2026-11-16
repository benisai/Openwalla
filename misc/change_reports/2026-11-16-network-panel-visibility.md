# Network Panel Visibility

- Removed Wi-Fi from the shortcut grid and default/saved shortcut ordering. Wi-Fi remains accessible from the Network panel.
- Dashboard Settings now includes Network Panel (hide/show the entire panel) and Wi-Fi in Network Panel (hide/show just its Wi-Fi icon/count). Disabling Wi-Fi removes the divider too, allowing the wired summary to use the space.
- The existing per-router `showWifiShortcut` preference now controls Wi-Fi in the panel, retaining existing hidden choices. Its obsolete shortcut toggle was moved and relabeled. A new `showNetworkPanel` preference defaults on and persists through JSON/copy operations.
- Both portrait and landscape dashboards honor panel visibility. Physical Ethernet indicators, network counts and navigation are unchanged. Wired-only users can hide Wi-Fi without hiding Ethernet; zero active APs do not automatically hide a potentially disabled radio.
- Scope: dashboard/preferences/settings, panel widget, focused tests, version and report. No router/API/ACL changes or APK build. User-owned APK and attachment changes were left untouched.
- Version: `1.0.585+487`.
- Verification: 36 dashboard/preference/quarantine tests passed. Static analysis and whitespace checks passed; narrow-screen Wi-Fi-hidden rendering verified.
