
import axios from 'axios';

export interface Config {
  hostname: string;
  router_ip: string;
  router_protocol: string;
  openwrt_user: string;
  openwrt_pass: string;
  openwrt_token?: string;
  openwrt_token_timestamp?: string;
  luci_port: string;
  netify_port: string;
  data_plan_limit: string;
  ping_address: string;
  latency_threshold: number;
  wan_ip: string;
  retention_days: string;
  auth_username?: string;
  auth_password?: string;
  ip_lookup_domain: string;
}

export const getConfig = async (): Promise<Config> => {
  const response = await axios.get<Config>('/api/config');
  return response.data;
};

export const updateConfig = async (updates: Partial<Config>): Promise<void> => {
  await axios.post('/api/config', updates);
};
