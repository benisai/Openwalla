import path from 'path';

export const DATABASE_CONFIG = {
  OPENWALLA_DB: path.join(__dirname, '../database/openwalla.sqlite'),
  OPENWRT_DB: path.join(__dirname, '../database/openwrt.sqlite'),
  FLOWS_DB: path.join(__dirname, '../database/flows.sqlite'),
  CONFIGS_DB: path.join(__dirname, '../database/configs.sqlite'),
  NOTIFICATIONS_DB: path.join(__dirname, '../database/notifications.sqlite'),
  HOURLY_WAN_USAGE_DB: path.join(__dirname, '../database/hourlywanusage.sqlite'),
  PING_STATS_DB: path.join(__dirname, '../database/pingstats.sqlite'),
};