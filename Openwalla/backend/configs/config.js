const getEnvConfig = () => {
  return {
    router_ip: process.env.ROUTER_IP || '10.0.3.1',
    netify_port: process.env.NETIFY_PORT || '7150',
    netify_enabled: process.env.NETIFY_ENABLED !== 'false',
    data_plan_limit: process.env.DATA_PLAN_LIMIT || '500',
    hostname: process.env.HOSTNAME || 'Openwalla',
    openwrt_user: process.env.OPENWRT_USER || '',
    openwrt_pass: process.env.OPENWRT_PASS || '',
    ping_address: process.env.PING_ADDRESS || '1.1.1.1',
    ping_interval: process.env.PING_INTERVAL || '60',
    cpu_cores: process.env.CPU_CORES || '4'  // Default to 4 cores
  };
};

module.exports = { getEnvConfig };