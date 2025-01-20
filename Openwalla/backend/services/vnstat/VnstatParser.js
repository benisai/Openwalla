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
            rx: parseInt(dailyRx),
            tx: parseInt(dailyTx)
          });
          break;

        case 'Hourly':
          const [hourlyDay, hour, minute, hourlyRx, hourlyTx] = rest;
          data.hourly.push({
            interface_name,
            year: parseInt(year),
            month: parseInt(month),
            day: parseInt(hourlyDay),
            hour: parseInt(hour),
            rx: parseInt(hourlyRx),
            tx: parseInt(hourlyTx),
            timestamp: Math.floor(new Date(`${year}-${month}-${hourlyDay} ${hour}:${minute}`).getTime() / 1000)
          });
          break;
      }
    });

    console.log('Parsed vnstat data:', {
      monthlyCount: data.monthly.length,
      dailyCount: data.daily.length,
      hourlyCount: data.hourly.length,
      sampleHourly: data.hourly[0]
    });

    return data;
  }
}

module.exports = VnstatParser;
