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

      // Extract the first three parts, then treat the rest as XML
      const firstComma = line.indexOf(',');
      const secondComma = line.indexOf(',', firstComma + 1);
      const thirdComma = line.indexOf(',', secondComma + 1);
      if (firstComma === -1 || secondComma === -1 || thirdComma === -1) return;

      const interfaceName = line.substring(0, firstComma).replace(/[<>]/g, '');
      const recordType = line.substring(firstComma + 1, secondComma).replace(/[<>]/g, '');
      const xmlData = line.substring(thirdComma + 1);

      try {
        if (recordType === 'Monthly') {
          const yearMatch = xmlData.match(/<year>(\d+)<\/year>/);
          const monthMatch = xmlData.match(/<date>.*?<month>(\d+)<\/month>/);
          const rxMatch = xmlData.match(/<rx>(\d+)<\/rx>/);
          const txMatch = xmlData.match(/<tx>(\d+)<\/tx>/);

          if (yearMatch && monthMatch && rxMatch && txMatch) {
            data.monthly.push({
              interface_name: interfaceName,
              year: parseInt(yearMatch[1]),
              month: parseInt(monthMatch[1]),
              rx: parseInt(rxMatch[1]),
              tx: parseInt(txMatch[1])
            });
          }
        } else if (recordType === 'Daily') {
          const yearMatch = xmlData.match(/<year>(\d+)<\/year>/);
          const monthMatch = xmlData.match(/<date>.*?<month>(\d+)<\/month>/);
          const dayMatch = xmlData.match(/<day>(\d+)<\/day>/);
          const rxMatch = xmlData.match(/<rx>(\d+)<\/rx>/);
          const txMatch = xmlData.match(/<tx>(\d+)<\/tx>/);

          if (yearMatch && monthMatch && dayMatch && rxMatch && txMatch) {
            data.daily.push({
              interface_name: interfaceName,
              year: parseInt(yearMatch[1]),
              month: parseInt(monthMatch[1]),
              day: parseInt(dayMatch[1]),
              rx: parseInt(rxMatch[1]),
              tx: parseInt(txMatch[1])
            });
          }
        } else if (recordType === 'Hourly') {
          const yearMatch = xmlData.match(/<year>(\d+)<\/year>/);
          const monthMatch = xmlData.match(/<date>.*?<month>(\d+)<\/month>/);
          const dayMatch = xmlData.match(/<day>(\d+)<\/day>/);
          const hourMatch = xmlData.match(/<time>.*?<hour>(\d+)<\/hour>/);
          const rxMatch = xmlData.match(/<rx>(\d+)<\/rx>/);
          const txMatch = xmlData.match(/<tx>(\d+)<\/tx>/);

          if (yearMatch && monthMatch && dayMatch && hourMatch && rxMatch && txMatch) {
            data.hourly.push({
              interface_name: interfaceName,
              year: parseInt(yearMatch[1]),
              month: parseInt(monthMatch[1]),
              day: parseInt(dayMatch[1]),
              hour: parseInt(hourMatch[1]),
              rx: parseInt(rxMatch[1]),
              tx: parseInt(txMatch[1])
            });
          }
        }
      } catch (error) {
        console.error('Error parsing vnstat line:', error, '\nLine:', line);
      }
    });

    console.log('Parsed vnstat data:', {
      monthlyCount: data.monthly.length,
      dailyCount: data.daily.length,
      hourlyCount: data.hourly.length
    });

    return data;
  }
}

module.exports = VnstatParser;