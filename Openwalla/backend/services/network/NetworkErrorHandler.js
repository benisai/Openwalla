class NetworkErrorHandler {
  static getErrorReason(error) {
    if (!error) return 'Unknown reason';
    
    if (error.message.includes('Network is unreachable')) {
      return 'Network interface is down or disconnected';
    }
    if (error.message.includes('Name or service not known')) {
      return 'DNS resolution failure';
    }
    if (error.message.includes('Host unreachable')) {
      return 'Router or gateway is unreachable';
    }
    if (error.message.includes('Request timeout')) {
      return 'Connection timed out - possible network congestion';
    }
    if (error.message.includes('Permission denied')) {
      return 'System permissions issue';
    }
    
    const match = error.message.match(/error=(.*?)(?:\s|$)/);
    if (match) {
      return match[1];
    }
    
    return 'Connection failure';
  }
}

module.exports = NetworkErrorHandler;