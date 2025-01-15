class VnstatParser {
  static parseVnstatText(text) {
    const lines = text.split('\n');
    const data = {
      monthly: [],
      daily: [],
      hourly: []
    };

    lines.forEach(line => {
      if (!line.trim()) return;
      
      const [interface_name, type, year, month, ...rest] = line.split(',');
      
      switch (type) {
        case 'Monthly':
          const [timestamp, rx, tx] = rest;
          data.monthly.push({
            interface_name,
            year: parseInt(year),
            month: parseInt(month),
            timestamp: parseInt(timestamp),
            rx: parseInt(rx),
            tx: parseInt(tx)
          });
          break;

        case 'Daily':
          const [day, dailyTimestamp, dailyRx, dailyTx] = rest;
          data.daily.push({
            interface_name,
            year: parseInt(year),
            month: parseInt(month),
            day: parseInt(day),
            timestamp: parseInt(dailyTimestamp),
            rx: parseInt(dailyRx),
            tx: parseInt(dailyTx)
          });
          break;

        case 'Hourly':
          const [hourlyDay, hour, minute, hourlyTimestamp, hourlyRx, hourlyTx] = rest;
          data.hourly.push({
            interface_name,
            year: parseInt(year),
            month: parseInt(month),
            day: parseInt(hourlyDay),
            hour: parseInt(hour),
            timestamp: parseInt(hourlyTimestamp),
            rx: parseInt(hourlyRx),
            tx: parseInt(hourlyTx)
          });
          break;
      }
    });

    console.log('Parsed data:', {
      monthlyCount: data.monthly.length,
      dailyCount: data.daily.length,
      hourlyCount: data.hourly.length
    });

    return data;
  }
}

module.exports = VnstatParser;