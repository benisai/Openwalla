
const net = require('net');

class NetifyConnectionManager {
  constructor(options = {}) {
    this.host = options.host || '192.168.1.1';
    this.port = options.port || 7150;
    this.client = null;
    this.reconnectAttempts = 0;
    this.MAX_RECONNECT_ATTEMPTS = options.maxReconnectAttempts || 9999;
    this.RECONNECT_DELAY = options.reconnectDelay || 5000;
    this.isShuttingDown = false;
    this.dataHandler = options.dataHandler || this._defaultDataHandler;
    this.errorHandler = options.errorHandler || this._defaultErrorHandler;
    this.closeHandler = options.closeHandler || this._defaultCloseHandler;
  }

  connect() {
    if (this.isShuttingDown) {
      console.log('[NetifyConnectionManager] Service is shutting down, not reconnecting');
      return;
    }

    console.log(`[NetifyConnectionManager] Connecting to agent at ${this.host}:${this.port}`);
    
    this.client = new net.Socket();

    this.client.connect(this.port, this.host, () => {
      console.log('[NetifyConnectionManager] Successfully connected to agent');
      this.reconnectAttempts = 0;
    });

    this.client.on('data', (data) => this.dataHandler(data));
    this.client.on('error', (error) => this.errorHandler(error));
    this.client.on('close', () => this.closeHandler());
  }

  _defaultDataHandler(data) {
    console.log('[NetifyConnectionManager] Received data (no handler specified)');
  }

  _defaultErrorHandler(error) {
    console.error('[NetifyConnectionManager] Connection error:', error.message);
    this.handleReconnection('error');
  }

  _defaultCloseHandler() {
    console.log('[NetifyConnectionManager] Connection closed');
    this.handleReconnection('close');
  }

  handleReconnection(trigger) {
    if (this.isShuttingDown) {
      console.log('[NetifyConnectionManager] Service is shutting down, not attempting reconnection');
      return;
    }

    if (this.reconnectAttempts < this.MAX_RECONNECT_ATTEMPTS) {
      this.reconnectAttempts++;
      console.log(`[NetifyConnectionManager] Reconnection attempt ${this.reconnectAttempts} of ${this.MAX_RECONNECT_ATTEMPTS} (triggered by ${trigger})`);
      setTimeout(() => this.connect(), this.RECONNECT_DELAY);
    } else {
      console.error('[NetifyConnectionManager] Max reconnection attempts reached');
      
      // Reset reconnection attempts after a longer delay and try again
      setTimeout(() => {
        console.log('[NetifyConnectionManager] Resetting reconnection attempts and trying again');
        this.reconnectAttempts = 0;
        this.connect();
      }, this.RECONNECT_DELAY * 6); // Wait 30 seconds before starting fresh
    }
  }

  stop() {
    this.isShuttingDown = true;
    if (this.client) {
      this.client.destroy();
      this.client = null;
    }
  }

  restart() {
    this.isShuttingDown = false;
    this.reconnectAttempts = 0;
    this.stop();
    this.connect();
  }
}

module.exports = NetifyConnectionManager;
