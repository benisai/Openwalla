import 'package:flutter/material.dart';

class OfflineSnapshotBanner extends StatelessWidget {
  const OfflineSnapshotBanner({
    super.key,
    required this.savedAt,
    required this.reconnecting,
    required this.onReconnect,
    this.offline = true,
  });
  final DateTime? savedAt;
  final bool reconnecting;
  final VoidCallback onReconnect;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = savedAt?.toLocal().toString().split('.').first;
    return Material(
      color: colors.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${offline ? 'Offline · Read-only' : 'Some panels show saved data'}${time == null ? '' : '\n${offline ? 'Dashboard' : 'Data'} saved $time'}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Reconnect to router',
                onPressed: reconnecting ? null : onReconnect,
                icon: reconnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
