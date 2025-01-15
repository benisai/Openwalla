class PingStatsParser {
  static parse(output) {
    const stats = {
      avgLatency: 0,
      maxLatency: 0,
      medianLatency: 0,
      packetLoss: 0
    };

    try {
      // Extract packet loss percentage
      const packetLossMatch = output.match(/(\d+)% packet loss/);
      if (packetLossMatch) {
        stats.packetLoss = parseFloat(packetLossMatch[1]);
      }

      // Extract all round-trip times for better median calculation
      const rtts = output.match(/time=([\d.]+)/g);
      if (rtts && rtts.length > 0) {
        const times = rtts.map(rtt => parseFloat(rtt.split('=')[1])).sort((a, b) => a - b);
        stats.medianLatency = times[Math.floor(times.length / 2)];
        stats.maxLatency = Math.max(...times);
        stats.avgLatency = times.reduce((a, b) => a + b, 0) / times.length;
      }
    } catch (error) {
      console.error('Error parsing ping output:', error);
    }

    return stats;
  }
}

module.exports = PingStatsParser;