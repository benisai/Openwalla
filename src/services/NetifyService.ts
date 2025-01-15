import { databases } from '../database/init';
import net from 'net';
import { v4 as uuidv4 } from 'uuid';
import { toast } from '@/components/ui/use-toast';

interface NetifyFlow {
  established: boolean;
  flow: {
    detected_protocol_name: string;
    local_ip: string;
    local_mac: string;
    local_port: number;
    other_ip: string;
    other_mac: string;
    other_port: number;
    host_server_name?: string;
    detected_application_name?: string;
    interface: string;
    first_seen_at: number;
    last_seen_at: number;
  };
  interface: string;
  internal: boolean;
  type: string;
}

export class NetifyService {
  private client: net.Socket | null = null;
  private static instance: NetifyService;
  private reconnectAttempts: number = 0;
  private readonly MAX_RECONNECT_ATTEMPTS = 30;
  private readonly RECONNECT_DELAY = 5000; // 5 seconds

  private constructor() {
    console.log('NetifyService instance created');
  }

  public static getInstance(): NetifyService {
    if (!NetifyService.instance) {
      NetifyService.instance = new NetifyService();
    }
    return NetifyService.instance;
  }

  public connect(host: string, port: number) {
    console.log(`Attempting to connect to Netify agent at ${host}:${port}`);
    
    this.client = new net.Socket();

    this.client.connect(port, host, () => {
      console.log('Successfully connected to Netify agent');
      this.reconnectAttempts = 0; // Reset counter on successful connection
    });

    this.client.on('data', (data) => {
      console.log('Received data from Netify agent');
      const lines = data.toString().split('\n');
      
      lines.forEach(line => {
        if (line.trim()) {
          try {
            const flowData = JSON.parse(line);
            console.log('Parsed flow data:', flowData);
            
            if (
              flowData.type === 'flow' &&
              flowData.established === true &&
              flowData.flow.detected_protocol_name &&
              ['DNS', 'HTTPS', 'HTTP'].includes(flowData.flow.detected_protocol_name)
            ) {
              console.log('Valid flow detected, saving to database');
              this.saveFlow(flowData);
            }
          } catch (error) {
            console.error('Error parsing flow data:', error);
          }
        }
      });
    });

    this.client.on('error', async (error) => {
      console.error('Netify connection error:', error);
      
      if (this.reconnectAttempts < this.MAX_RECONNECT_ATTEMPTS) {
        this.reconnectAttempts++;
        console.log(`Reconnection attempt ${this.reconnectAttempts} of ${this.MAX_RECONNECT_ATTEMPTS}`);
        setTimeout(() => this.connect(host, port), this.RECONNECT_DELAY);
      } else {
        console.error('Max reconnection attempts reached');
        const errorMessage = `Failed to connect to Netify agent after ${this.MAX_RECONNECT_ATTEMPTS} attempts`;
        
        // Show toast notification
        toast({
          title: "Connection Error",
          description: errorMessage,
          variant: "destructive",
        });

        // Save notification to database
        try {
          const sql = `
            INSERT INTO notifications (uuid, sev, type, msg, detect_time, action)
            VALUES (?, ?, ?, ?, ?, ?)
          `;
          const params = [
            uuidv4(),
            'error',
            'netify_connection',
            errorMessage,
            Date.now(),
            'none'
          ];
          await databases.notifications.run(sql, params);
          console.log('Error notification saved to database');
        } catch (dbError) {
          console.error('Error saving notification to database:', dbError);
        }
      }
    });

    this.client.on('close', () => {
      console.log('Netify connection closed');
    });
  }

  private async saveFlow(flowData: NetifyFlow) {
    const sql = `
      INSERT INTO flow (
        timeinsert,
        hostname,
        local_ip,
        local_mac,
        fqdn,
        dest_ip,
        dest_port,
        dest_type,
        detected_protocol_name,
        detected_app_name,
        interface,
        internal
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const params = [
      new Date(flowData.flow.first_seen_at).toISOString(),
      flowData.flow.host_server_name || '',
      flowData.flow.local_ip,
      flowData.flow.local_mac,
      flowData.flow.host_server_name || '',
      flowData.flow.other_ip,
      flowData.flow.other_port,
      'remote',
      flowData.flow.detected_protocol_name,
      flowData.flow.detected_application_name || '',
      flowData.interface,
      flowData.internal ? 1 : 0
    ];

    try {
      await databases.flows.run(sql, params);
      console.log('Flow saved successfully to database');
    } catch (error) {
      console.error('Error saving flow:', error);
    }
  }

  public disconnect() {
    if (this.client) {
      console.log('Disconnecting from Netify agent');
      this.client.destroy();
      this.client = null;
    }
  }
}

export const netifyService = NetifyService.getInstance();