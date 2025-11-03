
import { Flow } from "@/misc/types/flow";
import { formatBytes } from "@/misc/utils/networkFormatting";

export async function getLast24HoursFlowCount(): Promise<number> {
  try {
    const response = await fetch('/api/flows/count/24h');
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const data = await response.json();
    return data.count || 0;
  } catch (error) {
    console.error('Error fetching flow count:', error);
    return 0;
  }
}

export async function getLast24HoursBlockedFlowCount(): Promise<number> {
  try {
    const response = await fetch('/api/flows/blocked/count/24h');
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const data = await response.json();
    return data.count || 0;
  } catch (error) {
    console.error('Error fetching blocked flow count:', error);
    return 0;
  }
}

export async function getRecentFlows(hours: number = 1): Promise<Flow[]> {
  try {
    const response = await fetch(`/api/flows/recent?hours=${hours}`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Error fetching flows:', error);
    return [];
  }
}

export async function getRecentBlockedFlows(hours: number = 1): Promise<Flow[]> {
  try {
    const response = await fetch(`/api/flows/blocked/recent?hours=${hours}`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Error fetching blocked flows:', error);
    return [];
  }
}

export async function getDeviceFlowCount(mac: string): Promise<number> {
  try {
    const response = await fetch(`/api/flows/count/device/${mac}`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const data = await response.json();
    return data.count || 0;
  } catch (error) {
    console.error('Error fetching device flow count:', error);
    return 0;
  }
}

export async function getDeviceFlows(mac: string, hours: number = 1): Promise<Flow[]> {
  try {
    const response = await fetch(`/api/flows/device/${mac}?hours=${hours}`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Error fetching device flows:', error);
    return [];
  }
}

export interface TopFlowItem {
  fqdn?: string;
  dest_ip?: string;
  detected_app_name?: string;
  count: number;
}

export async function getTopFQDNs(mac: string): Promise<TopFlowItem[]> {
  try {
    const response = await fetch(`/api/flows/device/${mac}/top-fqdn`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  } catch (error) {
    console.error('Error fetching top FQDNs:', error);
    return [];
  }
}

export async function getTopDestIPs(mac: string): Promise<TopFlowItem[]> {
  try {
    const response = await fetch(`/api/flows/device/${mac}/top-dest-ips`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  } catch (error) {
    console.error('Error fetching top destination IPs:', error);
    return [];
  }
}

export async function getTopApplications(mac: string): Promise<TopFlowItem[]> {
  try {
    const response = await fetch(`/api/flows/device/${mac}/top-applications`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  } catch (error) {
    console.error('Error fetching top applications:', error);
    return [];
  }
}

export interface FlowUsageData {
  localBytes: number;
  otherBytes: number;
  totalBytes: number;
  formattedLocalBytes: string;
  formattedOtherBytes: string;
  formattedTotalBytes: string;
}

export async function getFlowUsageByDigest(digest: string): Promise<FlowUsageData | null> {
  try {
    if (!digest) {
      console.error('No digest provided for flow usage lookup');
      return null;
    }
    
    console.log('Fetching flow usage for digest:', digest);
    
    // Use relative URL
    const response = await fetch(`/api/flows/usage/${digest}`);
    
    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Error fetching flow usage (${response.status}):`, errorText);
      return null;
    }
    
    const data = await response.json();
    console.log('Flow usage data received:', data);
    
    // Check if we have any data and create the formatted response
    if (!data || (typeof data.localBytes === 'undefined' && typeof data.otherBytes === 'undefined' && typeof data.totalBytes === 'undefined')) {
      console.log('No flow usage data found for digest:', digest);
      return null;
    }
    
    // Ensure we have numbers for all properties (default to 0 if undefined)
    const localBytes = typeof data.localBytes === 'number' ? data.localBytes : 0;
    const otherBytes = typeof data.otherBytes === 'number' ? data.otherBytes : 0;
    const totalBytes = typeof data.totalBytes === 'number' ? data.totalBytes : 0;
    
    return {
      localBytes,
      otherBytes,
      totalBytes,
      formattedLocalBytes: formatBytes(localBytes),
      formattedOtherBytes: formatBytes(otherBytes),
      formattedTotalBytes: formatBytes(totalBytes)
    };
  } catch (error) {
    console.error('Error fetching flow usage by digest:', error);
    return null;
  }
}

// Add function to get device application usage
export async function getDeviceApplicationUsage(mac: string): Promise<any> {
  try {
    console.log('Fetching application usage for device:', mac);
    const response = await fetch(`/api/application-usage/device/${mac}?unique_digest=true`);
    
    if (!response.ok) {
      console.log('Primary API failed, falling back to database endpoint');
      const fallbackResponse = await fetch(`/api/flows/application-usage/${mac}?unique_digest=true`);
      if (!fallbackResponse.ok) {
        throw new Error('Both primary and fallback API calls failed');
      }
      return fallbackResponse.json();
    }
    
    return response.json();
  } catch (error) {
    console.error('Error fetching device application usage:', error);
    throw new Error('Failed to fetch application usage');
  }
}
