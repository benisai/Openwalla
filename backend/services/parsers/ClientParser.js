class ClientParser {
  static parse(data) {
    const devices = [];
    const lines = data.split('\n');
    
    ////console.log('Parsing client list, number of lines:', lines.length);
    
    for (const line of lines) {
      const trimmedLine = line.trim();
      if (trimmedLine) {
        // Split by multiple spaces to handle variable spacing
        const parts = trimmedLine.split(/\s+/);
        
        // Check if we have at least the minimum required fields and MAC is not 00:00:00:00:00:00
        if (parts.length >= 3 && parts[1].toLowerCase() !== '00:00:00:00:00:00') {
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
