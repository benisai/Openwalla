# FWPSE Dashboard

A modern dashboard interface for network monitoring and management built with React, TypeScript, and Tailwind CSS.

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