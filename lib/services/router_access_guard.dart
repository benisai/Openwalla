/// Cached browsing never authenticates a session or queues router commands.
class RouterAccessGuard {
  static bool offline = false;

  static void requireLiveConnection() {
    if (offline) {
      throw StateError(
        'Offline viewing is read-only. Reconnect to make changes.',
      );
    }
  }

  static void checkRpc(String object, String method) {
    // Permit identity reads used to verify the router during reconnection.
    if ((object == 'system' && method == 'board') ||
        (object == 'network.interface.lan' && method == 'status') ||
        (object == 'network.device' && method == 'status')) {
      return;
    }
    requireLiveConnection();
  }
}
