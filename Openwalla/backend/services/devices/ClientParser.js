class ClientParser {
  // Validate MAC address format (XX:XX:XX:XX:XX:XX)
  static isValidMacAddress(mac) {
    const macRegex = /^([0-9a-f]{2}:){5}([0-9a-f]{2})$/i;
    return macRegex.test(mac) && mac.toLowerCase() !== '00:00:00:00:00:00';
  }

  static parse(data) {
    const devices = [];
    const lines = data.split('\n');
    
    ////console.log('Parsing client list, number of lines:', lines.length);
    
    for (const line of lines) {
      const trimmedLine = line.trim();
      if (trimmedLine) {
        // Split by multiple spaces to handle variable spacing
        const parts = trimmedLine.split(/\s+/);
        
        // Check if we have at least the minimum required fields and MAC address is valid
        if (parts.length >= 3 && this.isValidMacAddress(parts[1])) {
          devices.push({
            hostname: parts[0],
            mac: parts[1].toLowerCase(),
            ip: parts[2],
            source: parts.length >= 4 ? (parts[3] === 'ARP' ? 'ARP Only' : 'DHCP Lease') : 'Unknown'
          });
        }
      }
    }
    
    ////console.log('Parsed client devices:', devices);
    return devices;
  }
}

module.exports = ClientParser;
