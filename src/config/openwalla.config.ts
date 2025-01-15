interface OpenwallaConfig {
  hostname: string;
  openwrt_ip: string;
  openwrt_user: string;
  openwrt_pass: string;
  openwrt_token: string;
  netdata_url: string;
  wan_ip: string;
  ping_interval: string;
  ping_timeout: string;
  netify_ip: string;
  netify_port: string;
  data_plan_limit: string;
}

// Initialize config from localStorage or use defaults
const loadConfig = (): OpenwallaConfig => {
  const savedConfig = localStorage.getItem('openwalla_config');
  if (savedConfig) {
    return JSON.parse(savedConfig);
  }
  
  return {
    hostname: '',
    openwrt_ip: '',
    openwrt_user: '',
    openwrt_pass: '',
    openwrt_token: '',
    netdata_url: '',
    wan_ip: '',
    ping_interval: '60',
    ping_timeout: '5',
    netify_ip: '',
    netify_port: '7150',
    data_plan_limit: '2.00'
  };
};

export const config: OpenwallaConfig = loadConfig();

// Helper function to update config values
export const updateConfig = (key: keyof OpenwallaConfig, value: string) => {
  config[key] = value;
  // Save to localStorage
  localStorage.setItem('openwalla_config', JSON.stringify(config));
};

// Helper function to get config values
export const getConfig = (key: keyof OpenwallaConfig): string => {
  return config[key];
};