const NetifyService = require('./NetifyService');
const InternetMonitorService = require('./InternetMonitorService');
const DeviceService = require('./DeviceService');
const VnstatService = require('./VnstatService');
const ApplicationUsageAggregator = require('./ApplicationUsageAggregator');
const OpenWrtService = require('./OpenWrtService');
const PurgeService = require('./purge/PurgeService');

class ServicesManager {
  constructor(config) {
    console.log('Initializing ServicesManager with config:', config);
    this.config = config;
    this.services = {
      netify: null,
      internetMonitor: null,
      devices: null,
      vnstat: null,
      applicationUsage: null,
      openwrt: null,
      purge: null
    };
  }

  async startAll() {
    await this.startInternetMonitor();
    await this.startDeviceService();
    await this.startVnstatService();
    await this.startNetifyService();
    await this.startApplicationUsageAggregator();
    await this.startOpenWrtService();
    this.startPurgeService();
  }

  stopAll() {
    Object.values(this.services).forEach(service => {
      if (service && typeof service.stop === 'function') {
        service.stop();
      }
    });
  }

  async startNetifyService() {
    if (this.config.netify_enabled) {
      console.log('Starting Netify service with config:', {
        ip: this.config.router_ip,
        port: this.config.netify_port
      });
      
      this.services.netify = new NetifyService(this.config);
      this.services.netify.connect();
    } else {
      console.log('Netify service is disabled in config');
    }
  }

  async startInternetMonitor() {
    console.log('Starting internet monitor service...');
    if (this.services.internetMonitor) {
      this.services.internetMonitor.stop();
    }
    this.services.internetMonitor = new InternetMonitorService(this.config);
    await this.services.internetMonitor.start();
  }

  async startDeviceService() {
    console.log('Starting device service...');
    this.services.devices = new DeviceService(this.config);
    await this.services.devices.start();
  }

  async startVnstatService() {
    console.log('Starting vnstat service...');
    this.services.vnstat = new VnstatService(this.config);
    await this.services.vnstat.startHourlyUpdates();
  }

  async startApplicationUsageAggregator() {
    console.log('Starting application usage aggregator...');
    this.services.applicationUsage = new ApplicationUsageAggregator(this.config);
    await this.services.applicationUsage.start();
  }

  async startOpenWrtService() {
    console.log('Starting OpenWrt service...');
    this.services.openwrt = new OpenWrtService(this.config);
    try {
      await this.services.openwrt.authenticate();
      console.log('OpenWrt service initialized and authenticated successfully');
    } catch (error) {
      console.error('Failed to initialize OpenWrt service:', error);
    }
  }

  startPurgeService() {
    const retentionDays = parseInt(this.config.retention_days) || 7;
    console.log(`Starting purge service with ${retentionDays} days retention...`);
    this.services.purge = new PurgeService(retentionDays);
    this.services.purge.start();
  }

  updateConfig(newConfig) {
    console.log('Updating services with new config:', newConfig);
    this.config = { ...this.config, ...newConfig };
    
    // Update internet monitor service with new config
    if (this.services.internetMonitor) {
      this.services.internetMonitor.updateConfig(this.config);
    }

    // Update purge service retention days if changed
    if (this.services.purge && newConfig.retention_days) {
      this.services.purge.updateRetentionDays(parseInt(newConfig.retention_days));
    }
  }
}

module.exports = ServicesManager;
