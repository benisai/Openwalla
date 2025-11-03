
import { Device } from "@/misc/types/device";
import { ApplicationUsage } from "@/misc/types/applicationUsage";

/**
 * Fetches application usage data for a specific device
 * Now with support for unique digest filtering
 */
export async function fetchDeviceApplicationUsage(mac: string): Promise<ApplicationUsage> {
  try {
    console.log('Fetching application usage for device:', mac);
    // Always use unique digest filtering for better data consistency
    const response = await fetch(`/api/application-usage/device/${mac}?unique_digest=true`);
    
    if (!response.ok) {
      console.log('Primary API failed, falling back to database endpoint');
      return fetchDeviceApplicationUsageFromDatabase(mac);
    }
    
    const data = await response.json();
    return processApplicationUsageData(data, mac);
  } catch (error) {
    console.error('Error in primary API, falling back to database endpoint:', error);
    return fetchDeviceApplicationUsageFromDatabase(mac);
  }
}

/**
 * Fallback method that fetches application usage data directly from the database
 * Using unique digest filtering by default
 */
async function fetchDeviceApplicationUsageFromDatabase(mac: string): Promise<ApplicationUsage> {
  try {
    console.log('Fetching application usage from database for device:', mac);
    const dbResponse = await fetch(`/api/flows/application-usage/${mac}?unique_digest=true`);
    
    if (!dbResponse.ok) {
      throw new Error('Failed to fetch from database');
    }
    
    const dbData = await dbResponse.json();
    return processApplicationUsageData(dbData, mac);
  } catch (error) {
    console.error('Error fetching device application usage from database:', error);
    throw new Error('Failed to fetch application usage data');
  }
}

/**
 * Clean application name by removing "netify." prefix
 */
function cleanAppName(name: string): string {
  if (!name) return 'Unknown';
  return name.replace(/^netify\./, '');
}

/**
 * Process application usage data from either API source into the common format
 * Optimized for ISO timestamp format and filters out "Unknown" apps
 */
async function processApplicationUsageData(data: any[], mac: string): Promise<ApplicationUsage> {
  // Ensure data is an array
  if (!Array.isArray(data)) {
    console.error('Received non-array data:', data);
    data = []; // Set to empty array to prevent errors
  }
  
  // Calculate total usage excluding "Unknown" applications
  const totalUsage = data.reduce((sum: number, item: any) => {
    const rawAppName = item.detected_app_name || 'Unknown';
    const appName = cleanAppName(rawAppName);
    
    // Only include in total if not Unknown
    return appName.toLowerCase() !== 'unknown' ? sum + (item.total_bytes || 0) : sum;
  }, 0);
  
  // Aggregate applications
  const appMap = new Map<string, number>();
  data.forEach((item: any) => {
    let rawAppName = item.detected_app_name || 'Unknown';
    let appName = cleanAppName(rawAppName);
    
    // Skip "Unknown" applications
    if (appName.toLowerCase() === 'unknown') {
      return;
    }
    
    const currentBytes = appMap.get(appName) || 0;
    appMap.set(appName, currentBytes + (item.total_bytes || 0));
  });
  
  // Create applications array with percentages
  const applications = Array.from(appMap.entries())
    .map(([name, bytesUsed]) => ({
      name,
      bytesUsed,
      percentage: totalUsage > 0 ? Math.round((bytesUsed / totalUsage) * 100) : 0
    }))
    .sort((a, b) => b.bytesUsed - a.bytesUsed)
    .slice(0, 5); // Get top 5 applications
  
  // Generate timeline data (group by hour)
  const hourMap = new Map<number, number>();
  data.forEach((item: any) => {
    // Get raw app name and clean it
    const rawAppName = item.detected_app_name || 'Unknown';
    const appName = cleanAppName(rawAppName);
    
    // Skip "Unknown" applications for timeline data too
    if (appName.toLowerCase() === 'unknown') {
      return;
    }
    
    // Parse the ISO timestamp and get hour in local time
    try {
      const date = new Date(item.timeperiod);
      const hour = date.getHours();
      const currentUsage = hourMap.get(hour) || 0;
      hourMap.set(hour, currentUsage + (item.total_bytes || 0));
    } catch (error) {
      console.error('Error parsing timeperiod:', item.timeperiod, error);
    }
  });
  
  const timelineData = Array.from(hourMap.entries())
    .map(([hour, usage]) => ({ hour, usage }))
    .sort((a, b) => a.hour - b.hour);
  
  // Get device name
  const devicesResponse = await fetch('/api/devices');
  let deviceName = 'Unknown Device';
  
  if (devicesResponse.ok) {
    const devices: Device[] = await devicesResponse.json();
    const device = devices.find(d => d.mac === mac);
    if (device) {
      deviceName = device.hostname || device.mac;
    }
  }
  
  return {
    deviceMac: mac,
    deviceName,
    totalUsage,
    applications,
    timelineData
  };
}

/**
 * Fetches all devices for application usage display
 */
export async function fetchDevicesForUsage(): Promise<Device[]> {
  try {
    const response = await fetch('/api/devices');
    if (!response.ok) {
      throw new Error('Failed to fetch devices');
    }
    return response.json();
  } catch (error) {
    console.error('Error fetching devices for usage:', error);
    throw error;
  }
}
