# Openwalla Dashboard

# The project is on hold, I have not had time to fix things 😭

Openwalla is a modern dashboard interface for monitoring OpenWRT, built using React, TypeScript, and Tailwind CSS. Inspired by the Firewalla app, Openwalla provides a user-friendly way to visualize network activity and system performance. Inspiration came from the Firewalla app, thus the name 'Openwalla'.

This project was initially created for personal use, but I am sharing it in hopes that others find it useful. **Please note:** The software is currently in **alpha**—some features may be incomplete or non-functional. Contributions via pull requests are welcome as I work toward refining and expanding the project.

## Background
Openwalla was developed to store and analyze Netify data, allowing me to monitor IoT devices and track network traffic using the NetifyD deep packet inspection tool on OpenWRT. A custom script exports data to the router’s `/www/` folder, which Openwalla scrapes every 60 seconds for analysis.

## Features
- **Internet Monitoring:** Periodically pings `1.1.1.1` and notifies the user of packet loss or connectivity issues.
- **New Device Detection:** Tracks devices by scraping `/www/clientlist.html` from the router every 60 seconds.
- **OpenWRT System Resource Monitoring:** Displays system statistics using the Netdata API.
- **Bandwidth Monitoring:** Hourly, daily, and monthly statistics collected via `vnstat2` and stored in SQLite.
- **Device Usage Tracking:** Uses `nlbwmon` to collect device bandwidth data, storing results in SQLite.

---

## Router Setup

### Automatic Installation
Download and execute the setup script:
```bash
wget https://raw.githubusercontent.com/benisai/Openwalla/main/Router/router-setup.sh
chmod +x router-setup.sh
sh ./router-setup.sh
```

### Manual Installation
If you prefer manual setup, follow these steps:
1. **Install required packages** (`netify`, `nlbwmon`, `vnstat2`, `netdata`) via LuCI.
2. **Configure vnstat:** Ensure it monitors `br-lan` (via LuCI settings).
3. **Modify Nlbw refresh interval:** Update `/etc/config/nlbwmon`, changing `refresh_interval` from `30s` to `10s`.
4. **Configure Netify:** Modify its config file to listen on the router’s IP (`10.0.5.1` as an example). See [OpenWRT Forum](https://forum.openwrt.org/t/open-source-dpi-and-network-intelligence-engine-beta/52994) for details.
5. **Set up periodic scripts:**
   - Download `1-minute.sh`, place it in `/usr/bin/`, set execution permissions, and configure a crontab entry to run it every minute.
   - Download `nlbw-compare-rate-service.sh` (place in `/etc/init.d/`), enable it, and ensure execution permissions.
   - Download `nlbw-compare-rate.sh` (place in `/usr/bin/`), ensure execution permissions.

---

## Deployment Options

### Docker Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/benisai/Openwalla.git
   cd Openwalla
   ```
2. Configure environment variables in `docker-compose.yml` (`Router_IP` and `TZ`).
3. Start the project:
   ```bash
   sudo docker-compose up -d
   ```
   - The backend initializes first to fetch and store configurations in SQLite.
   - The frontend starts afterward; allow 20-30 seconds for full initialization.

### Local Setup
1. Install [Node.js](https://nodejs.org/en/download).
2. Clone/download the repository and navigate to the project directory:
   ```bash
   git clone https://github.com/benisai/Openwalla.git
   cd Openwalla
   ```
3. Update the router IP in `Openwalla/openwalla/configs.cjs`
4. Start the project (I created a bash script to do the npm install and npm start) :
   ```bash
   chmod +x ./manage-server.sh
   ./manage-server.sh install
   ./manage-server.sh start
   

6. Access the dashboard at `http://<server-ip>:8080`.
   
7. To Stop the project, run `./manage-server.sh force_kill_all`

8. To Restart the project, run `./manage-server.sh restart`
---

## Screenshots
### Dashboard Overview
Displays system resources and bandwidth statistics.
![Dashboard](https://github.com/user-attachments/assets/bacc4e74-aa46-4d18-bda6-a72bb1107620)

### Network Flows
Netify flow analysis.
![Flows](https://github.com/user-attachments/assets/b4356288-4364-464d-8a91-fce4e2931217)

### Device Management
Tracks active devices and their traffic.
![Devices](https://github.com/user-attachments/assets/6ce0e54b-258d-42db-a52d-d1c3307f2479)

### Usage Statistics
Aggregated monthly/daily usage from `vnstat2`.
![Usage](https://github.com/user-attachments/assets/90322cfd-4dea-4f01-a634-42dd09cefe2c)

---

## Backend Services & Database

### Core Services
- **NetifyService**: Processes network flow data.
- **InternetMonitorService**: Monitors internet connectivity.
- **PingStatsService**: Tracks network latency.
- **DeviceService**: Manages device tracking.
- **VnstatService**: Collects bandwidth usage data.

### Database Structure
Openwalla uses SQLite databases for structured data storage:
- **Configs.db** - Core configuration and state.
- **OpenWRT.db** - Router-specific device tracking.
- **Flows.db** - Network flow logs.
- **Notifications.db** - System alerts and history.
- **Vnstat.db** - Bandwidth usage statistics.
- **devices.db** - Device(s) information.

---

## Technology Stack
- **Frontend**: React, TypeScript, Tailwind CSS, shadcn/ui, Lucide React, Recharts
- **Backend**: Express.js, SQLite
- **Networking**: NetifyD, Netdata, vnstat2, nlbwmon

---

## Development Guide
1. **Install dependencies:**
   ```bash
   npm install
   ```
2. **Start the development server:**
   ```bash
   npm run dev
   ```
3. **Run the backend:**
   ```bash
   cd backend
   npm install
   node server.js
   ```

### Best Practices
- Keep components modular and maintainable.
- Use TypeScript interfaces for type safety.
- Follow existing styling and component structure.
- Ensure API requests handle errors gracefully.
- Test new features before submitting PRs.

---

## Contributing
Contributions are welcome! If you’d like to help:
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature-name`).
3. Commit changes (`git commit -m "Add new feature"`).
4. Push to your branch (`git push origin feature-name`).
5. Open a pull request.

Thank you for your interest in Openwalla!

