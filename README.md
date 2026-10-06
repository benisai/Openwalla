# Openwalla


**Openwalla** is a modern Flutter app for managing and monitoring multiple OpenWrt/LuCI routers. It features an Openwalla-inspired dashboard UI, secure authentication, real-time stats, and seamless multi-router support.

---

## Features

Openwalla can install optional router components from **Manage Device > Router Setup**. Features marked **Built in** only require a normal OpenWrt LuCI/RPC installation.

### Router and Network

- **Multiple Routers** - Saves separate credentials, preferences, and cached data for each router. **Relies on** built-in app functionality.
- **Secure Login** - Connects over HTTP or HTTPS, supports self-signed certificates, securely stores credentials, and refreshes expired LuCI sessions. **Relies on** LuCI RPC (`uhttpd-mod-ubus`, `rpcd-mod-luci`, and `rpcd-mod-iwinfo`).
- **Dashboard** - Shows CPU, memory, load, interfaces, clients, live traffic, and enabled shortcuts. **Relies on** built-in app functionality; richer traffic data uses the monitoring packages below.
- **Network Interfaces** - Views, edits, starts, stops, and restarts LAN, WAN, VPN, and other logical interfaces through UCI and ubus. **Relies on** built-in OpenWrt UCI and ubus functionality.
- **Wi-Fi** - Manages radios, SSIDs, security, channels, and repeater connections. **Relies on** OpenWrt wireless tools and `rpcd-mod-iwinfo`.
- **LAN and DHCP** - Changes the LAN address, subnet, DNS, DHCP pool, and lease time while updating the saved router connection. **Relies on** built-in OpenWrt UCI functionality.
- **Firewall and Routing** - Manages firewall rules, port forwards, static IPv4 routes, and interface routing. **Relies on** OpenWrt firewall4 and UCI.
- **Package Manager** - Detects and uses `apk` on newer OpenWrt releases, with `opkg` as the fallback. **Relies on** the router's installed package manager.
- **SSH Terminal** - Opens a router shell using the saved router credentials. **Relies on** an OpenWrt SSH server, normally Dropbear.
- **Backup and Restore** - Exports or restores Openwalla state and selected router configuration. **Relies on** the Openwalla state-sync helper for scheduled router-side backups.
- **Router Components** - Compares installed Openwalla helper versions with the published script version and redeploys them when needed. **Relies on** Openwalla setup scripts.

### Devices and Monitoring

- **Device Inventory** - Tracks devices by MAC address with hostname, IPv4 address, interface, online state, and traffic totals. **Relies on** Openwalla devices collector, SQLite, and `nlbwmon`.
- **Pause and Block** - Applies device-specific internet access rules immediately or from a schedule. **Relies on** Openwalla internet-blocking helper and firewall4.
- **Quarantine** - Detects new devices and places them in quarantine until they are approved. Hidden devices are exempt from detection. **Relies on** Openwalla devices collector and quarantine support.
- **Parental Controls** - Groups devices and applies recurring access schedules. **Relies on** Openwalla parental-control and scheduler helpers.
- **Live Throughput** - Displays current upload/download rates for the router and devices. **Relies on** interface counters; per-device rates use the Openwalla device-speed helper and `conntrack`.
- **Bandwidth History** - Stores summarized per-device usage for dashboard and device views. **Relies on** Openwalla bandwidth collector, SQLite, and `conntrack`.
- **Statistics** - Shows vnStat interface history, nlbwmon device totals, protocols, and monthly usage. **Relies on** `vnstat`/`vnstat2`, `vnstati`, and `nlbwmon`.
- **Network Performance** - Records latency, outages, Ethernet link state, DNS health, and scheduled speed tests. **Relies on** Openwalla network, DNS, and speed-test monitor helpers.
- **Notifications** - Stores router and Openwalla events in a local router database for the app inbox. **Relies on** Openwalla notifications helper and SQLite.

### Flows

- **Simple Network Flows** - Periodically reads IPv4 conntrack entries and stores a lightweight connection history. **Relies on** Openwalla conntrack collector, `conntrack`, and SQLite.
- **Detailed Network Flows** - Reads Netify flow events with application, protocol, domain, destination, risk, and device details. **Relies on** `netifyd`, the Openwalla Netify collector, and SQLite. Use this instead of Simple Network Flows on routers with enough CPU and memory.
- **Flow Usage Statistics** - Optionally aggregates Netify byte counters at a configurable polling interval. **Relies on** Detailed Network Flows being installed and enabled.

### Security and Traffic Control

- **AdBlock** - Controls OpenWrt domain blocking and service state. **Relies on** `adblock` and optionally `luci-app-adblock`.
- **Smart Queue** - Configures SQM to reduce latency and bufferbloat under load. **Relies on** `sqm-scripts` and optionally `luci-app-sqm`.
- **WireGuard VPN** - Creates and manages WireGuard interfaces, servers, peers, and QR configurations. **Relies on** `wireguard-tools` and `luci-proto-wireguard`.
- **Policy-Based Routing (PBR)** - Routes selected domains or addresses through a VPN or another interface. **Relies on** `pbr` and optionally `luci-app-pbr`.
- **Dynamic DNS** - Keeps a hostname synchronized with a changing public IP address. **Relies on** `ddns-scripts`, service providers, and optionally `luci-app-ddns`.
- **Geo-Blocking** - Uses country IP feeds to block inbound and outbound traffic, with split country sets and NFT reporting counters. **Relies on** `banip` and optionally `luci-app-banip`.
- **Tor Routing** - Routes all traffic or selected devices through Tor, with optional DNS routing. **Relies on** `tor`, `tor-geoip`, and the Openwalla Tor helper.
- **Tailscale** - Manages the Tailscale service, mesh VPN connection, routes, and exit-node options. **Relies on** `tailscale` and the Openwalla Tailscale helper.
- **Multi-WAN** - Configures WAN failover, load balancing, members, policies, and rules. **Relies on** `mwan3`, optionally `luci-app-mwan3`, and nftables compatibility packages when required.

- **Open Source** - GPLv3 licensed and available on [Google Play](https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile) and [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile).

---

## Multiple Router Functionality

- **Add Unlimited Routers:** Each with its own credentials and settings.
- **Quick Switch:** Instantly switch routers from the dashboard dropdown or "Manage Routers" screen.
- **Isolated Data:** Each router’s dashboard, clients, and settings are kept separate.
- **Edit & Remove:** Update credentials, rename, or remove routers at any time.
- **Auto-Connect:** Remembers your last selected router and auto-connects on launch.
- **Secure Storage:** All credentials are stored securely on your device.

---

## Screenshots

| Login | Dashboard | Clients | Interfaces |
|-------|-----------|---------|------------|
| <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_02.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_01.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_03.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/flutter_05.png" width="200"/> |

---

## Installation
```
On Openwrt Router:
wget https://raw.githubusercontent.com/benisai/openwalla-apk/main/openwrt-setup/Setup-Openwrt-WGet-Files.sh
chmod +X Setup-Openwrt-WGet-Files.sh

./Setup-Openwrt-WGet-Files.sh 
```


**Get it on [Google Play](https://play.google.com/store/apps/details?id=com.cogwheel.LuCIMobile)**, **[Apple App Store](https://apps.apple.com/app/luci-mobile/id6749455847)**, or **[IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile)**, or build from source:

```bash
git clone https://github.com/cogwheel0/luci-mobile.git
cd luci-mobile
flutter pub get
flutter run
```

- Requires Flutter 3.32.5+ and Dart 3.8+
- Android: `flutter build apk`  
- iOS: `flutter build ios`

---

## Project Structure

```
lib/
├── config/                 # App configuration
├── models/                 # Data models (client, interface, router)
├── screens/                # UI screens (dashboard, clients, interfaces, login, more, etc.)
├── services/               # Business logic (API, secure storage)
├── state/                  # State management (app_state.dart)
├── widgets/                # Reusable UI components (luci_app_bar.dart)
└── main.dart               # App entry point
```

---

## Development & Contribution

- Run in dev mode: `flutter run`
- Build for release: `flutter build apk --release` or `flutter build ios --release`
- Analyze code: `flutter analyze`

**Contributions welcome!** Please fork, branch, and submit a pull request.

---

## Security & Privacy
- All credentials are stored securely on-device
- HTTPS and self-signed certificate support
- No analytics or tracking

---

## Troubleshooting

- **Connection Failed:** Check router IP, LuCI web interface, firewall, and try both HTTP/HTTPS.
- **Authentication Failed:** Verify credentials and admin privileges.
- **No Data Displayed:** Ensure the router has LuCI RPC support: `opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status`, restart `rpcd` (or reboot), then verify with `ubus list luci-rpc` and `ubus call luci-rpc getNetworkDevices '{}'`.

---

## License

GPL v3.0. See [LICENSE](LICENSE).

---

## Acknowledgments
- OpenWrt community for LuCI
- Flutter team
- [OpenWrtManager](https://github.com/hagaygo/OpenWrtManager) inspiration
- Contributors and testers

---

**Note:** This app requires an OpenWrt router with LuCI web interface enabled. Make sure your router is properly configured before use.
