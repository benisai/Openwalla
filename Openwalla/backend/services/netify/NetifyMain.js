
const NetifyConnectionManager = require('./NetifyConnectionManager');
const NetifyFlowProcessor = require('./NetifyFlowProcessor');
const NetifyDataPersistence = require('./NetifyDataPersistence');
const NetifyDeviceCache = require('./NetifyDeviceCache');

class NetifyService {
  constructor(config) {
    this.config = config;
    this.deviceCache = new NetifyDeviceCache();
    this.flowProcessor = new NetifyFlowProcessor();
    this.dataPersistence = new NetifyDataPersistence();
    
    // Initialize connection manager with handlers
    this.connectionManager = new NetifyConnectionManager({
      host: config.router_ip || '192.168.1.1',
      port: parseInt(config.netify_port) || 7150,
      dataHandler: this.handleData.bind(this),
      errorHandler: this.handleError.bind(this),
      closeHandler: this.handleClose.bind(this)
    });
  }

  connect() {
    // Start device cache refresh
    this.deviceCache.startCacheRefresh();
    
    // Connect to Netify agent
    this.connectionManager.connect();
  }

  handleData(data) {
    const lines = data.toString().split('\n');
    
    lines.forEach(line => {
      if (line.trim()) {
        try {
          const flowData = JSON.parse(line);
          const processedData = this.flowProcessor.processFlowData(flowData);
          
          if (processedData) {
            this.handleProcessedData(processedData);
          }
        } catch (error) {
          // Silently ignore JSON parsing errors as they're likely just incomplete chunks
          if (!(error instanceof SyntaxError)) {
            console.error('[NetifyService] Unexpected error processing flow data:', error);
          }
        }
      }
    });
  }

  async handleProcessedData(processedData) {
    try {
      if (processedData.type === 'purge') {
        await this.dataPersistence.saveStatsPurge(processedData.data);
      } else if (processedData.type === 'flow') {
        const deviceInfo = await this.deviceCache.getDeviceInfo(processedData.meta.local_mac);
        await this.dataPersistence.saveFlow(processedData.data, deviceInfo);
      }
    } catch (error) {
      console.error('[NetifyService] Error handling processed data:', error);
    }
  }

  handleError(error) {
    console.error('[NetifyService] Connection error:', error.message);
    this.dataPersistence.saveNotification(`Netify connection error: ${error.message}`);
  }

  handleClose() {
    console.log('[NetifyService] Connection closed');
  }

  stop() {
    this.connectionManager.stop();
  }

  restart() {
    this.connectionManager.restart();
  }
}

module.exports = NetifyService;
