import { Flow } from "@/misc/types/flow";

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
