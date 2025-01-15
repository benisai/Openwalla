class VnstatDataProcessor {
  static validateVnstatData(data) {
    if (!data || !data.interfaces || !Array.isArray(data.interfaces)) {
      console.error('Invalid vnstat data structure:', data);
      return false;
    }
    return true;
  }

  static findBestInterface(data, preferredInterface = 'br-lan') {
    if (!this.validateVnstatData(data)) return null;

    // First try to find preferred interface
    const preferred = data.interfaces.find(i => i.name === preferredInterface);
    if (preferred) {
      console.log('Found preferred interface:', preferred.name);
      return preferred;
    }
    
    // If preferred not found, find first interface with non-zero traffic
    const active = data.interfaces.find(i => 
      i.traffic && i.traffic.total && (i.traffic.total.rx > 0 || i.traffic.total.tx > 0)
    );

    if (active) {
      console.log('Found active interface:', active.name);
      return active;
    }

    console.error('No suitable interface found');
    return null;
  }

  static extractTrafficData(interfaceData, type) {
    if (!interfaceData?.traffic?.[type]) {
      console.error(`No valid ${type} data found`);
      return [];
    }
    return interfaceData.traffic[type];
  }
}

module.exports = VnstatDataProcessor;