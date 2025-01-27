import axios from 'axios';

export interface Config {
  hostname: string;
  router_ip: string;  // New consolidated router IP field
  openwrt_user: string;
  openwrt_pass: string;
  netdata_url: string;
  netify_port: string;
  data_plan_limit: string;
  ping_address: string;
  wan_ip: string;
}

export const getConfig = async (): Promise<Config> => {
  const response = await axios.get<Config>('/api/config');
  return response.data;
};

export const updateConfig = async (updates: Partial<Config>): Promise<void> => {
  await axios.post('/api/config', updates);
};