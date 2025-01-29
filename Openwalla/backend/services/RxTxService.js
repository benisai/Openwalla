const { databases } = require('../database/database');

class RxTxService {
  static async parseAndSaveRxTxData(data) {
    const lines = data.split('\n');
    
    for (const line of lines) {
      if (!line.trim()) continue;
      
      const values = {};
      line.split(',').forEach(pair => {
        const [key, value] = pair.split('=');
        values[key] = value;
      });

      try {
        await this.saveRxTxEntry({
          mac: values.MAC,
          ip: values.IP,
          year: parseInt(values.year),
          month: parseInt(values.month),
          day: parseInt(values.day),
          hour: parseInt(values.hour),
          minute: parseInt(values.minute),
          second: parseInt(values.second),
          rx_diff: parseInt(values.RX_Diff),
          tx_diff: parseInt(values.TX_Diff),
          timestamp: new Date(
            values.year,
            parseInt(values.month) - 1,
            values.day,
            values.hour,
            values.minute,
            values.second
          ).getTime()
        });
      } catch (error) {
        console.error('Error saving RX/TX entry:', error);
      }
    }
  }

  static async saveRxTxEntry(entry) {
    return new Promise((resolve, reject) => {
      databases.devices.run(`
        INSERT INTO rx_tx (
          mac, ip, year, month, day, hour, minute, second,
          rx_diff, tx_diff, timestamp
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        entry.mac,
        entry.ip,
        entry.year,
        entry.month,
        entry.day,
        entry.hour,
        entry.minute,
        entry.second,
        entry.rx_diff,
        entry.tx_diff,
        entry.timestamp
      ], function(err) {
        if (err) reject(err);
        else resolve(this.lastID);
      });
    });
  }

  static async getLatestRxTxForDevice(mac) {
    return new Promise((resolve, reject) => {
      databases.devices.get(`
        SELECT rx_diff, tx_diff
        FROM rx_tx
        WHERE mac = ?
        ORDER BY timestamp DESC
        LIMIT 1
      `, [mac], (err, row) => {
        if (err) reject(err);
        else resolve(row || { rx_diff: 0, tx_diff: 0 });
      });
    });
  }
}

module.exports = RxTxService;