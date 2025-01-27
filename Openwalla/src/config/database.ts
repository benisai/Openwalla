import path from 'path';

export const DATABASE_CONFIG = {
  OPENWALLA_DB: path.join(__dirname, '../../databases/openwalla.sqlite'),
  OPENWRT_DB: path.join(__dirname, '../../databases/openwrt.sqlite'),
  FLOWS_DB: path.join(__dirname, '../../databases/flows.sqlite'),
  CONFIGS_DB: path.join(__dirname, '../../databases/configs.sqlite'),
  NOTIFICATIONS_DB: path.join(__dirname, '../../databases/notifications.sqlite'),
  HOURLY_WAN_USAGE_DB: path.join(__dirname, '../../databases/hourlywanusage.sqlite'),
  PING_STATS_DB: path.join(__dirname, '../../databases/pingstats.sqlite'),
};