const axios = require('axios');

class NetdataService {
  constructor(config) {
    this.config = config;
    this.netdataUrl = `${config.router_protocol?.toLowerCase() || 'http'}://${config.router_ip || '192.168.1.1'}:19999`;
  }

  async fetchSystemMetrics() {
    try {
      const response = await axios.get(`${this.netdataUrl}/api/v1/allmetrics`, {
        timeout: 5000
      });

      const text = response.data;

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

      // Parse Network throughput from br-lan interface (LAN bridge)
      const receivedMatch = text.match(/NETDATA_NET_BR_LAN_RECEIVED="(\d+(\.\d+)?)"/) || ['0', '0'];
      const sentMatch = text.match(/NETDATA_NET_BR_LAN_SENT="(\d+(\.\d+)?)"/) || ['0', '0'];
      const received = parseFloat(receivedMatch[1]); // Keep as kilobits per second
      const sent = parseFloat(sentMatch[1]); // Keep as kilobits per second

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
    } catch (error) {
      console.error('Error fetching Netdata metrics:', error.message);
      throw new Error(`Failed to fetch Netdata metrics: ${error.message}`);
    }
  }

  async fetchSystemLoad() {
    try {
      const cpuCores = parseInt(this.config.cpu_cores || '4');
      const response = await axios.get(
        `${this.netdataUrl}/api/v1/data?chart=system.load&after=-60&options=seconds&format=json`,
        { timeout: 5000 }
      );

      const data = response.data;
      if (data && data.data && data.data.length > 0) {
        const lastDataPoint = data.data[data.data.length - 1];
        const load15Index = data.labels.indexOf('load15');
        
        if (load15Index !== -1 && lastDataPoint[load15Index] !== null) {
          const load15 = lastDataPoint[load15Index];
          const loadPercentage = (load15 / cpuCores) * 100;
          return Math.min(Math.max(loadPercentage, 0), 100);
        }
      }
      
      return 0;
    } catch (error) {
      console.error('Error fetching system load:', error.message);
      throw new Error(`Failed to fetch system load: ${error.message}`);
    }
  }
}

module.exports = NetdataService;
