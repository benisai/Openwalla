# Openwalla Privacy Policy

Last updated: October 12, 2026

Openwalla is an open-source mobile application for managing OpenWrt routers. This policy explains what information the app handles, where it is stored, and the choices available to you.

## 1. Information Openwalla Handles

### Router connection information

- Openwalla uses the router address, username, password, and connection preferences that you provide to connect to your router.
- Saved credentials and API tokens are stored on your device using platform-provided secure storage through `flutter_secure_storage`.
- The Openwalla project does not operate a service that receives or stores your router credentials.

### Router and network data

- Openwalla reads router status, interfaces, connected devices, traffic information, logs, and configuration data to provide the features you request.
- This information normally travels directly between your device and your OpenWrt router.
- Some optional Openwalla components store monitoring data on your router, including SQLite databases created by the router helper scripts.

### Optional self-hosted Openwalla Server

- You may configure the app to connect to an Openwalla Server that you or your administrator operates, including a server hosted on a LAN or VPS.
- When enabled, the app sends requests to the server address you configure. The server may process or store network-flow and tunnel-status data according to that deployment's configuration.
- Openwalla does not provide or control that server. The server operator is responsible for its security, retention, access, and deletion policies.

### Internet requests

- Openwalla may request public files from the project's GitHub repository to check published app or router-component versions, open documentation, or install router components that you select.
- Router setup may download packages from OpenWrt or package-provider repositories selected by the router.
- These providers may receive ordinary connection metadata, such as an IP address, under their own privacy policies. Openwalla does not include router credentials or router data in its GitHub version and documentation requests.
- Openwalla does not include advertising, analytics SDKs, or third-party tracking.

## 2. How Information Is Used

Openwalla uses this information only to:

- authenticate with and manage routers you configure;
- display router, device, traffic, and system information;
- run actions that you request, such as changing settings or installing components;
- connect to an optional self-hosted Openwalla Server; and
- save your app preferences and connection profiles.

## 3. Sharing and Sale of Data

- The Openwalla project does not sell personal information.
- The Openwalla project does not receive or share your router credentials, router data, or network-flow data.
- Data may be handled by a router, server, VPN, proxy, or other infrastructure that you or your administrator configures. Those systems are outside the Openwalla project's control.

## 4. Data Retention and Deletion

- Removing a router profile deletes that profile's locally stored app credentials and settings.
- Openwalla does not create an Openwalla cloud account, so there is no developer-hosted account to delete.
- Uninstalling Openwalla removes app data according to the mobile operating system's normal behavior.
- Data stored by router helper components remains on the router until you remove it or uninstall those components.
- Data stored by an optional Openwalla Server must be deleted from that self-hosted deployment by its operator.

## 5. Security

- Sensitive saved values use platform secure storage where supported.
- Openwalla supports HTTPS and SSH connections. HTTP may also be used for local routers when you configure it.
- You are responsible for securing your router, mobile device, and any optional Openwalla Server. Strong passwords, current OpenWrt software, HTTPS, and restricted network access are recommended.
- No method of storage or transmission can be guaranteed to be completely secure.

## 6. Children's Privacy

Openwalla is not directed to children under 13, and the project does not knowingly collect personal information from children.

## 7. Changes to This Policy

This policy may be updated when Openwalla's functionality or data practices change. The current version will be published in the project repository and linked from the app.

## 8. Contact

Questions or concerns may be submitted through the [Openwalla issue tracker](https://github.com/benisai/Openwalla/issues).
