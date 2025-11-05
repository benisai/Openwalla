const { databases } = require('../database/database');
const { v4: uuidv4 } = require('uuid');
const TimeUtils = require('../utils/timeUtils');

class DeviceDataManager {
  static async saveDevices(devices) {
    //console.log('Saving devices to database:', devices);

    const checkExistingSql = `
      SELECT mac, hostname FROM clients WHERE mac = ?
    `;

    const clientSql = `
      INSERT INTO clients (mac, hostname, ip, timeinserted, source, new)
      VALUES (?, ?, ?, ?, ?, 1)
    `;

    const updateClientSql = `
      UPDATE clients 
      SET ip = ?, timeinserted = ?, source = ?
      WHERE mac = ?
    `;

    const nlbwSql = `
      INSERT OR REPLACE INTO nlbw (mac, ip, connections, dl_speed, ul_speed, total_download, total_upload)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `;

    const notificationSql = `
      INSERT INTO notifications (uuid, sev, type, msg, detect_time, action)
      VALUES (?, ?, ?, ?, ?, ?)
    `;

    for (const device of devices) {
      try {
        // Check if device already exists and get its current hostname
        const existingDevice = await new Promise((resolve, reject) => {
          databases.devices.get(checkExistingSql, [device.mac], (err, row) => {
            if (err) {
              console.error('Error checking existing device:', err);
              reject(err);
            } else {
              resolve(row);
            }
          });
        });

        if (!existingDevice) {
          // New device - insert with all fields
          await new Promise((resolve, reject) => {
            databases.devices.run(clientSql, [
              device.mac,
              device.hostname,
              device.ip,
              TimeUtils.getUnixTimestampMs(),
              device.source
            ], function(err) {
              if (err) {
                console.error('Error saving to clients table:', err);
                reject(err);
              } else {
                ////console.log(`Saved new device to clients table. Row ID: ${this.lastID}`);
                resolve();
              }
            });
          });

          // Create notification for new device
          const timestamp = TimeUtils.getUnixTimestampMs();
          const notificationMsg = `New device ${device.hostname} with IP ${device.ip} joined the network on ${new Date(timestamp).toLocaleString()}`;
          
          await new Promise((resolve, reject) => {
            databases.notifications.run(notificationSql, [
              uuidv4(),
              'info',
              'new_device',
              notificationMsg,
              timestamp,
              'none'
            ], function(err) {
              if (err) {
                console.error('Error creating notification:', err);
                reject(err);
              } else {
                console.log('Created notification for new device');
                resolve();
              }
            });
          });
        } else {
          // Existing device - update everything except hostname
          await new Promise((resolve, reject) => {
            databases.devices.run(updateClientSql, [
              device.ip,
              TimeUtils.getUnixTimestampMs(),
              device.source,
              device.mac
            ], function(err) {
              if (err) {
                console.error('Error updating client:', err);
                reject(err);
              } else {
                ////console.log(`Updated existing device. Changes: ${this.changes}`);
                resolve();
              }
            });
          });
        }

        // Always update NLBW data
        await new Promise((resolve, reject) => {
          databases.devices.run(nlbwSql, [
            device.mac,
            device.ip,
            device.connections || 0,
            0, // dl_speed set to 0
            0, // ul_speed set to 0
            device.total_download || 0,
            device.total_upload || 0
          ], function(err) {
            if (err) {
              console.error('Error saving to nlbw table:', err);
              reject(err);
            } else {
              ////console.log(`Updated NLBW data. Row ID: ${this.lastID}`);
              resolve();
            }
          });
        });
      } catch (error) {
        console.error('Error saving device:', device.mac, error);
      }
    }
  }
}

module.exports = DeviceDataManager;
