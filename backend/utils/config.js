const getEnvConfig = () => {
  return {
    openwrt_ip: process.env.OPENWRT_IP || '192.168.1.1',
    netdata_url: process.env.NETDATA_URL || 'http://192.168.1.1:19999',
    netify_ip: process.env.NETIFY_IP || '192.168.1.1',
    netify_port: process.env.NETIFY_PORT || '7150',
    netify_enabled: process.env.NETIFY_ENABLED !== 'false',
    data_plan_limit: process.env.DATA_PLAN_LIMIT || '500',
    hostname: process.env.HOSTNAME || 'Openwalla',
    openwrt_user: process.env.OPENWRT_USER || '',
    openwrt_pass: process.env.OPENWRT_PASS || '',
    ping_address: process.env.PING_ADDRESS || '1.1.1.1',
    ping_interval: process.env.PING_INTERVAL || '60',
    vnstat_url: process.env.VNSTAT_URL || 'http://192.168.1.1/vnstat.txt'
  };
};

module.exports = { getEnvConfig };