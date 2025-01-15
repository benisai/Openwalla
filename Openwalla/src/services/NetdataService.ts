import axios from 'axios';

export interface SystemMetrics {
  cpu: number;
  memory: number;
  load: number;
  received: number;
  sent: number;
  connections: number;
}

async function getServerConfig() {
  const response = await fetch('/api/config');
  if (!response.ok) {
    throw new Error('Failed to fetch config');
  }
  return response.json();
}

export const fetchSystemMetrics = async (): Promise<SystemMetrics> => {
  const config = await getServerConfig();
  const netdataUrl = config.netdata_url || 'http://192.168.1.1:19999';
  
  const response = await fetch(`${netdataUrl}/api/v1/allmetrics`);
    
  if (!response.ok) {
    throw new Error('Failed to fetch metrics');
  }

  const text = await response.text();
    
  // Parse CPU usage
  const cpuMatch = text.match(/NETDATA_SYSTEM_CPU_VISIBLETOTAL="(\d+(\.\d+)?)"/) || ['0', '0'];
  const cpu = parseFloat(cpuMatch[1]);

  // Parse Memory metrics - Calculate actual used memory
  const memUsedMatch = text.match(/NETDATA_SYSTEM_RAM_USED="(\d+(\.\d+)?)"/) || ['0', '0'];
  const memTotalMatch = text.match(/NETDATA_SYSTEM_RAM_VISIBLETOTAL="(\d+(\.\d+)?)"/) || ['0', '0'];
  
  const memUsed = parseFloat(memUsedMatch[1]);
  const memTotal = parseFloat(memTotalMatch[1]);
  
  // Calculate memory percentage (used/total * 100)
  const memory = memTotal > 0 ? (memUsed / memTotal) * 100 : 0;

  // Parse Load15 metric
  const loadMatch = text.match(/NETDATA_SYSTEM_LOAD_LOAD15="(\d+(\.\d+)?)"/) || ['0', '0'];
  const load = parseFloat(loadMatch[1]) * 100; // Convert to percentage (0-100 range)

  // Parse Network throughput
  const receivedMatch = text.match(/NETDATA_SYSTEM_IP_RECEIVED="(\d+(\.\d+)?)"/) || ['0', '0'];
  const sentMatch = text.match(/NETDATA_SYSTEM_IP_SENT="(\d+(\.\d+)?)"/) || ['0', '0'];
  const received = parseFloat(receivedMatch[1]);
  const sent = parseFloat(sentMatch[1]);

  // Parse Conntrack connections
  const connectionsMatch = text.match(/NETDATA_NETFILTER_CONNTRACK_SOCKETS_CONNECTIONS="(\d+(\.\d+)?)"/) || ['0', '0'];
  const connections = parseFloat(connectionsMatch[1]);

  return {
    cpu: Math.min(Math.max(cpu, 0), 100),
    memory: Math.min(Math.max(memory, 0), 100),
    load: Math.min(Math.max(load, 0), 100),
    received,
    sent,
    connections
  };
};