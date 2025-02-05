const { databases } = require('../database/database');

class RxTxService {
  static async parseAndSaveRxTxData(data) {
    const lines = data.split('\n');
    
    for (const line of lines) {
      if (!line.trim()) continue;
      
      try {
        const values = {};
        line.split(',').forEach(pair => {
          const [key, value] = pair.split('=');
          if (key && value) {
            values[key.trim()] = value.trim();
          }
        });

        // Only proceed if we have valid MAC and IP addresses
        if (!values.MAC || !values.IP) {
          console.log('Skipping RX/TX entry - missing MAC or IP:', values);
          continue;
        }

        // Parse date/time values, defaulting to 0 if NaN
        const year = parseInt(values.year) || 0;
        const month = parseInt(values.month) || 0;
        const day = parseInt(values.day) || 0;
        const hour = parseInt(values.hour) || 0;
        const minute = parseInt(values.minute) || 0;
        const second = parseInt(values.second) || 0;
        const rx_diff = parseInt(values.RX_Diff) || 0;
        const tx_diff = parseInt(values.TX_Diff) || 0;

        // Create timestamp
        const timestamp = new Date(
          year,
          month - 1,
          day,
          hour,
          minute,
          second
        ).getTime();

        // Only save if we have valid timestamp and traffic data
        if (timestamp && (rx_diff > 0 || tx_diff > 0)) {
          await this.saveRxTxEntry({
            mac: values.MAC,
            ip: values.IP,
            year,
            month,
            day,
            hour,
            minute,
            second,
            rx_diff,
            tx_diff,
            timestamp
          });
        }
      } catch (error) {
        console.error('Error parsing RX/TX line:', error, '\nLine:', line);
      }
    }
  }

  static async saveRxTxEntry(entry) {
    // Validate required fields
    if (!entry.mac || !entry.ip) {
      console.error('Cannot save RX/TX entry - missing required fields:', entry);
      return;
    }

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