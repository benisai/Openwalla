const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const PingStatsParser = require('./internetmonitoring/PingStatsParser');
const NetworkNotificationManager = require('./internetmonitoring/NetworkNotificationManager');
const PingStatsManager = require('./internetmonitoring/PingStatsManager');
const NetworkErrorHandler = require('./internetmonitoring/NetworkErrorHandler');

class InternetMonitorService {
  constructor(config = {}) {
    this.targetIp = config.ping_address || '1.1.1.1';
    this.monitorInterval = null;
    this.LATENCY_THRESHOLD = 100; // ms
    this.PING_INTERVAL = 60000; // 60 seconds in milliseconds
  }

  async start() {
    try {
      if (this.monitorInterval) {
        clearInterval(this.monitorInterval);
      }

      this.monitorInterval = setInterval(() => this.checkConnection(), this.PING_INTERVAL);
      console.log(`Internet monitoring started for IP: ${this.targetIp}`);
    } catch (error) {
      console.error('Error starting internet monitor:', error);
    }
  }

  stop() {
    if (this.monitorInterval) {
      clearInterval(this.monitorInterval);
      this.monitorInterval = null;
      console.log('Internet monitoring stopped');
    }
  }

  checkConnection() {
    exec(`ping -c 5 ${this.targetIp}`, (error, stdout, stderr) => {
      const now = new Date();
      const timestamp = now.getTime();
      const date = now.toISOString().split('T')[0];
      const time = now.toTimeString().split(' ')[0];
      
      let message = '';
      let severity = 'info';
      let status = 'success';
      let latency = null;
      let packetLoss = 0;
      let maxLatency = 0;
      let medianLatency = 0;
      let errorMessage = null;

      if (error) {
        const reason = NetworkErrorHandler.getErrorReason(error);
        message = `Internet connection down at ${now.toISOString()} - Cause: ${reason}`;
        severity = 'error';
        status = 'error';
        packetLoss = 100;
        errorMessage = error.message;
        NetworkNotificationManager.saveNotification(message, severity);
      } else {
        const stats = PingStatsParser.parse(stdout);
        latency = stats.avgLatency;
        maxLatency = stats.maxLatency;
        medianLatency = stats.medianLatency;
        packetLoss = stats.packetLoss;
        
        if (medianLatency > this.LATENCY_THRESHOLD) {
          message = `High latency detected: ${medianLatency.toFixed(1)}ms at ${now.toISOString()}`;
          severity = 'warning';
          NetworkNotificationManager.saveNotification(message, severity);
          console.log('Created high latency notification:', message);
        }

        if (packetLoss > 0) {
          message = `Packet loss detected: ${packetLoss}% at ${now.toISOString()}`;
          severity = 'warning';
          NetworkNotificationManager.saveNotification(message, severity);
          console.log('Created packet loss notification:', message);
        }
      }

      PingStatsManager.savePingStats({
        uuid: uuidv4(),
        ip: this.targetIp,
        ms: latency,
        max_latency: maxLatency,
        median_latency: medianLatency,
        packetloss: packetLoss,
        date,
        time,
        timestamp,
        target_ip: this.targetIp,
        latency,
        packet_loss: packetLoss,
        status,
        error_message: errorMessage
      });
    });
  }
}

module.exports = InternetMonitorService;