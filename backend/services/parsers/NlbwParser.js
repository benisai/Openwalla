class NlbwParser {
  static parse(data) {
    const devices = [];
    const lines = data.split('\n');
    
    ////console.log('Parsing NLBW data, number of lines:', lines.length);
    
    // Skip header line
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      
      const [mac, ip, conns, rx_bytes, rx_packets, tx_bytes, tx_tackets] = line.split(/\s+/);
      if (mac && ip) {
        devices.push({
          mac: mac.toLowerCase(),
          ip,
          connections: parseInt(conns) || 0,
          dl_speed: 0, // Setting to 0 as requested
          ul_speed: 0, // Setting to 0 as requested
          total_download: parseInt(rx_bytes) || 0,
          total_upload: parseInt(tx_bytes) || 0
        });
      }
    }
    
    ////console.log('Parsed NLBW devices:', devices);
    return devices;
  }
}

module.exports = NlbwParser;
