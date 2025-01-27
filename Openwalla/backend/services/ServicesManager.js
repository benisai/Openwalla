const NetifyService = require('./NetifyService');
const InternetMonitorService = require('./InternetMonitorService');
const DeviceService = require('./DeviceService');
const VnstatService = require('./VnstatService');

class ServicesManager {
  constructor(config) {
    console.log('Initializing ServicesManager with config:', config);
    this.config = config;
    this.services = {
      netify: null,
      internetMonitor: null,
      devices: null,
      vnstat: null
    };
  }

  async startAll() {
    await this.startInternetMonitor();
    await this.startDeviceService();
    await this.startVnstatService();
    await this.startNetifyService();
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

  updateConfig(newConfig) {
    console.log('Updating services with new config:', newConfig);
    this.stopAll();
    this.config = newConfig;
    this.startAll();
  }
}

module.exports = ServicesManager;