const axios = require('axios');
const ClientParser = require('./devices/ClientParser');
const NlbwParser = require('./devices/ClientTotalUsage');
const DeviceDataManager = require('./DeviceDataManager');
const RxTxService = require('./RxTxService');

class DeviceService {
  constructor(config) {
    if (!config.router_ip) {
      console.error('Warning: router_ip not found in config, using default');
    }
    this.routerUrl = `http://${config.router_ip}`;
    console.log('DeviceService initialized with router URL:', this.routerUrl);
    this.updateInterval = null;
  }

  async start() {
    console.log('Starting device service with router URL:', this.routerUrl);
    // Update immediately then schedule updates
    await this.updateDevices();
    this.fetchRXTXData(); // Start fetching RX/TX data
    this.updateInterval = setInterval(() => this.updateDevices(), 30 * 1000); // Every 30 seconds
  }

  stop() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }
  }


  async fetchRXTXData() {
    try {
      // Start polling for device data
      this.updateInterval = setInterval(async () => {
        try {
          // Fetch RX/TX data
          const response = await axios.get(`${this.routerUrl}/nlbw_rx_tx.txt`);
          await RxTxService.parseAndSaveRxTxData(response.data);
        } catch (error) {
          console.error('Error fetching RX/TX data:', error);
        }
      }, 15000); // Poll every 15 seconds
    } catch (error) {
      console.error('Error starting device service:', error);
      throw error;
    }
  }


  async updateDevices() {
    try {
      console.log('Fetching device data from:', this.routerUrl);
      const [clientData, nlbwData] = await Promise.all([
        this.fetchClientList(),
        this.fetchNlbwData()
      ]);

      const devices = this.mergeDeviceData(clientData, nlbwData);
      await DeviceDataManager.saveDevices(devices);
      
      console.log(`Updated ${devices.length} devices`);
    } catch (error) {
      console.error('Error updating devices:', error);
    }
  }

  async fetchClientList() {
    try {
      const response = await axios.get(`${this.routerUrl}/clientlist.html`);
      return ClientParser.parse(response.data);
    } catch (error) {
      console.error('Error fetching client list:', error);
      return [];
    }
  }

  async fetchNlbwData() {
    try {
      const response = await axios.get(`${this.routerUrl}/nlbw.html`);
      return NlbwParser.parse(response.data);
    } catch (error) {
      console.error('Error fetching NLBW data:', error);
      return [];
    }
  }

  mergeDeviceData(clientData, nlbwData) {
    const devices = [...clientData];
    
    // Add network data from NLBW
    for (const device of devices) {
      const nlbwDevice = nlbwData.find(n => n.mac === device.mac);
      if (nlbwDevice) {
        device.dl_speed = nlbwDevice.dl_speed;
        device.ul_speed = nlbwDevice.ul_speed;
        device.total_download = nlbwDevice.total_download;
        device.total_upload = nlbwDevice.total_upload;
      } else {
        device.dl_speed = 0;
        device.ul_speed = 0;
        device.total_download = 0;
        device.total_upload = 0;
      }
    }
    
    return devices;
  }
}

module.exports = DeviceService;
