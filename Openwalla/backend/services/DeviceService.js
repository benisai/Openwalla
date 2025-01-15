const axios = require('axios');
const ClientParser = require('./parsers/ClientParser');
const NlbwParser = require('./parsers/NlbwParser');
const DeviceDataManager = require('./DeviceDataManager');

class DeviceService {
  constructor(config) {
    this.routerUrl = `http://${config.openwrt_ip || config.router_ip || '192.168.1.1'}`;
    this.updateInterval = null;
  }

  async start() {
    console.log('Starting device service with router URL:', this.routerUrl);
    // Update immediately then schedule updates
    await this.updateDevices();
    this.updateInterval = setInterval(() => this.updateDevices(), 30 * 1000); // Every 30 seconds
  }

  stop() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }
  }

  async updateDevices() {
    try {
      console.log('Fetching device data from:', this.routerUrl);
      const [clientData, nlbwData] = await Promise.all([
        this.fetchClientList(),
        this.fetchNlbwData()
      ]);

      ////console.log('Client Data:', clientData);
      ////console.log('NLBW Data:', nlbwData);

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
      ////console.log('Raw client list response:', response.data);
      return ClientParser.parse(response.data);
    } catch (error) {
      console.error('Error fetching client list:', error);
      return [];
    }
  }

  async fetchNlbwData() {
    try {
      const response = await axios.get(`${this.routerUrl}/nlbw.html`);
      ////console.log('Raw NLBW response:', response.data);
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
    
    ////console.log('Merged device data:', devices);
    return devices;
  }
}

module.exports = DeviceService;
