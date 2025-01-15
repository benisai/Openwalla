# Openwalla Dashboard

A modern dashboard interface for monitoring OpenWRT using React, TypeScript, and Tailwind CSS. 

Inspiration came from the Firewalla app, thus the name 'Openwalla'. 

This software was created for my personal use, but I'm sharing it with others in hopes they find it useful. 

SOFTWARE IS ALPHA at this point. Things are broken, and some things dont work. :) 
I will update/fix things as I have time but PR's are welcomed. Hoping to make this into a nicer / polished project. (Maybe even add some small router functionality like reboots, etc)

## Router Setup
* Install Software (netify, nlbwnon, vnstat2, netdata)

* Configure vnstat to monitor br-lan
* Configure netify config file to listen on thr router ip (10.0.3.1 is my router as an example)

* Download this shell script and run it every minute via a crontab on the Openwrt Router
*https://github.com/benisai/Openwalla/blob/main/Router/1-minute.sh

## Docker Setup 
* Download Repo and run Docker-Compose up -d to start the project. Make sure to update env vars router IPs. 

## Local Setup 
* To run locally, without docker, modify this file (https://github.com/benisai/Openwalla/blob/main/Openwalla/backend/utils/config.js) with the router IPs and 
* cd into backend folder and run 'run install', then run 'node server.js'
* cd into src folder, and run 'npm install', then run 'npm run dev'
* browse ip:8080




# Screenshots

## Dashboard 
* System Resouces from Netdata
* Monthly Usage from vnstat2 (br-lan as selection)
![Dashboard](https://github.com/user-attachments/assets/bacc4e74-aa46-4d18-bda6-a72bb1107620)

## Flows 
* Netify
![flows](https://github.com/user-attachments/assets/b4356288-4364-464d-8a91-fce4e2931217)

## Devices Page
![devices](https://github.com/user-attachments/assets/6ce0e54b-258d-42db-a52d-d1c3307f2479)

## Device Details 
* Data usage from NLBWMON - http://router-ip/nlbw.html
![device-details](https://github.com/user-attachments/assets/df83fab2-90ca-4276-8def-59af12c7505d)

## Device Top Flow Count 
* Netify Sqlite DB
![devices-top](https://github.com/user-attachments/assets/7a568a0f-f4ed-4024-a92f-a9644541e2ae)

## Device Flows 
* MAC Based from Netify SQLITE
![device-flows](https://github.com/user-attachments/assets/eeaa6526-a352-4913-9a70-47374133dcb9)

## Monthly / Daily Usage 
* vnstat2 - http://router-ip/vnstat.txt
![data-usage](https://github.com/user-attachments/assets/90322cfd-4dea-4f01-a634-42dd09cefe2c)





## Components Structure

### Dashboard Cards
The dashboard consists of several card components:

1. **Network Performance Card**
   - Location: `src/components/dashboard/NetworkPerformanceCard.tsx`
   - Displays current WAN performance metrics

2. **Flow Statistics Cards**
   - Flows24 (`src/components/dashboard/Flows24.tsx`): Shows flow statistics for last 24 hours
   - Blocked24 (`src/components/dashboard/Blocked24.tsx`): Displays blocked traffic

3. **Monthly Usage Card**
   - Location: `src/components/dashboard/MonthlyUsageCard.tsx`
   - Shows data usage with progress tracking

4. **Status Cards**
   - DevicesCard (`src/components/dashboard/DevicesCard.tsx`): Connected devices count
   - AlarmsCard (`src/components/dashboard/AlarmsCard.tsx`): Active alarms count
   - RulesCard (`src/components/dashboard/RulesCard.tsx`): Active rules count

## Backend Services

### Core Services
1. **NetifyService**
   - Location: `backend/services/NetifyService.js`
   - Handles network flow monitoring and analysis
   - Connects to Netify agent for real-time flow data
   - Maintains device cache for efficient lookups

2. **InternetMonitorService**
   - Location: `backend/services/InternetMonitorService.js`
   - Monitors internet connectivity
   - Tracks latency and connection status

3. **PingStatsService**
   - Location: `backend/services/PingStatsService.js`
   - Collects and stores ping statistics
   - Monitors network latency to specified targets

4. **DeviceService**
   - Location: `backend/services/DeviceService.js`
   - Manages connected device information
   - Handles device discovery and tracking

5. **VnstatService**
   - Location: `backend/services/VnstatService.js`
   - Interfaces with vnstat for bandwidth monitoring
   - Tracks daily, monthly, and hourly usage

### Database Structure
Located in `backend/database.js`, manages multiple SQLite databases:

1. **Openwalla Database**
   - Core system configuration
   - System state information

2. **OpenWRT Database**
   - Router-specific information
   - Device tracking data

3. **Flows Database**
   - Network flow records
   - Traffic analysis data

4. **Notifications Database**
   - System notifications
   - Alert history

5. **Hourly WAN Usage Database**
   - Bandwidth usage tracking
   - Historical usage data

6. **Ping Stats Database**
   - Network latency measurements
   - Connection quality metrics

7. **Devices Database**
   - Connected device records
   - Device metadata and statistics

8. **VnStat Database**
   - Bandwidth statistics
   - Usage tracking (hourly, daily, monthly)

9. **OUI Vendor Database**
   - MAC address vendor lookups
   - Device manufacturer information

## Technology Stack

- React with TypeScript
- Tailwind CSS for styling
- shadcn/ui for UI components
- Lucide React for icons
- Recharts for data visualization
- SQLite for data storage
- Express.js for backend API

## Project Structure

```
src/
├── components/
│   ├── dashboard/     # Dashboard-specific components
│   ├── ui/           # Reusable UI components
├── pages/
│   └── Index.tsx     # Main dashboard page
backend/
├── services/         # Backend services
├── database.js       # Database initialization
├── server.js         # Express server setup
```

## Development

1. Install dependencies:
```bash
npm install
```

2. Start development server:
```bash
npm run dev
```

3. Start backend server:
```bash
cd backend
node server.js
```

## Service Initialization Order

The services are initialized in a specific order to ensure proper data loading:

1. Database initialization
2. Internet Monitor Service
3. Ping Stats Service
4. Device Service
5. VnStat Service
6. Netify Service (started last to ensure all other services are ready)

## Component Guidelines

- Each card is a separate component for maintainability
- Components use shadcn/ui base components where possible
- Icons from lucide-react package
- Charts implemented using Recharts library

## Adding New Features

1. Create new components in appropriate directories
2. Follow existing naming conventions
3. Use Tailwind CSS for styling
4. Import and use shadcn/ui components when needed
5. Add new routes in App.tsx if required

## Best Practices

- Keep components small and focused
- Use TypeScript types/interfaces
- Follow existing styling patterns
- Maintain responsive design
- Use shadcn/ui components when possible
- Ensure proper error handling in services
- Follow the established service initialization order
