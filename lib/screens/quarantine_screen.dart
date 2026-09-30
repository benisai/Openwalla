import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';

class QuarantineScreen extends ConsumerStatefulWidget {
  const QuarantineScreen({super.key});

  @override
  ConsumerState<QuarantineScreen> createState() => _QuarantineScreenState();
}

class _QuarantineScreenState extends ConsumerState<QuarantineScreen> {
  OpenwallaQuarantineSnapshot? _snapshot;
  bool _started = false;
  bool _loading = true;
  bool _working = false;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(appStateProvider)
          .fetchQuarantineSnapshot(context: context);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final snapshot = _snapshot;
    if (snapshot == null || _working) return;
    setState(() => _working = true);
    const actionKey = 'quarantine-toggle';
    context.showToastLoading(
      enabled ? 'Enabling quarantine...' : 'Disabling quarantine...',
      actionKey: actionKey,
    );
    try {
      final state = await ref
          .read(appStateProvider)
          .saveQuarantineSettings(
            enabled: enabled,
            intervalSeconds: snapshot.intervalSeconds,
            context: context,
          );
      if (!mounted) return;
      setState(() {
        _snapshot = OpenwallaQuarantineSnapshot(
          enabled: state.enabled,
          running: state.running,
          intervalSeconds: state.intervalSeconds,
          devices: snapshot.devices,
        );
      });
      if (enabled && !state.running) {
        context.showToastWarning(
          'Quarantine enabled, service stopped',
          subtitle: 'The setting was saved, but monitoring did not start.',
          actionKey: actionKey,
        );
      } else {
        context.showToastSuccess(
          enabled ? 'Quarantine enabled' : 'Quarantine disabled',
          subtitle: enabled
              ? 'New devices are now being monitored.'
              : 'Automatic device isolation is off.',
          actionKey: actionKey,
        );
      }
    } catch (error) {
      if (!mounted) return;
      context.showToastError(
        'Unable to update quarantine',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: actionKey,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _scanNow() async {
    if (_working) return;
    setState(() => _working = true);
    const actionKey = 'quarantine-scan';
    context.showToastLoading(
      'Scanning for new devices...',
      actionKey: actionKey,
    );
    try {
      await ref.read(appStateProvider).runQuarantineDiscovery(context: context);
      await _load();
      if (!mounted) return;
      context.showToastSuccess('Device scan complete', actionKey: actionKey);
    } catch (error) {
      if (!mounted) return;
      context.showToastError(
        'Device scan failed',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: actionKey,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _release(Client client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Release device?'),
        content: Text(
          '${client.displayName} will regain network and router access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Release'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final actionKey = 'quarantine-release-${client.macAddress}';
    final snapshot = _snapshot;
    if (snapshot != null) {
      final normalizedMac = client.macAddress.toUpperCase().replaceAll(
        '-',
        ':',
      );
      setState(() {
        _snapshot = OpenwallaQuarantineSnapshot(
          enabled: snapshot.enabled,
          running: snapshot.running,
          intervalSeconds: snapshot.intervalSeconds,
          devices: snapshot.devices
              .where(
                (device) =>
                    device.macAddress.toUpperCase().replaceAll('-', ':') !=
                    normalizedMac,
              )
              .toList(),
        );
      });
    }
    ref.read(appStateProvider).queueClientInternetUnblock(client);
    context.showToastSuccess(
      'Device released',
      subtitle: client.displayName,
      actionKey: actionKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'Device Quarantine', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'New Device Protection',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Automatically isolate devices first seen after protection is enabled.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.quarantine,
                title: 'Device quarantine is not installed',
                message:
                    'Install the Openwalla device detector and firewall quarantine service.',
                installLabel: 'Install Quarantine',
                builder: (_) => _buildInstalledContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstalledContent() {
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 52),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _QuarantineMessageCard(message: _error!, onRetry: _load);
    }
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuarantineControlCard(
          snapshot: snapshot,
          working: _working,
          onEnabledChanged: _setEnabled,
          onScanNow: _scanNow,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Quarantined Devices',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${snapshot.devices.length}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (snapshot.devices.isEmpty)
          const _QuarantineEmptyCard()
        else
          ...snapshot.devices.map(
            (client) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _QuarantinedDeviceCard(
                client: client,
                working: _working,
                onRelease: () => _release(client),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuarantineControlCard extends StatelessWidget {
  final OpenwallaQuarantineSnapshot snapshot;
  final bool working;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onScanNow;

  const _QuarantineControlCard({
    required this.snapshot,
    required this.working,
    required this.onEnabledChanged,
    required this.onScanNow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeColor = snapshot.enabled
        ? const Color(0xFF20CF70)
        : colors.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.gpp_good_rounded, color: activeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Automatic Quarantine',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snapshot.enabled
                            ? snapshot.running
                                  ? 'Enabled and monitoring'
                                  : 'Enabled, service stopped'
                            : 'Disabled',
                        style: TextStyle(
                          color: activeColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: snapshot.enabled,
                  onChanged: working ? null : onEnabledChanged,
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Scan interval',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                    child: Text('${snapshot.intervalSeconds} seconds'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: working || !snapshot.enabled ? null : onScanNow,
                  icon: working
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_rounded),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuarantinedDeviceCard extends StatelessWidget {
  final Client client;
  final bool working;
  final VoidCallback onRelease;

  const _QuarantinedDeviceCard({
    required this.client,
    required this.working,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.gpp_bad_rounded, color: colors.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${client.ipAddress}  ${client.macAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: working ? null : onRelease,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Release'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuarantineEmptyCard extends StatelessWidget {
  const _QuarantineEmptyCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 34,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          const Text(
            'No devices are currently quarantined.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _QuarantineMessageCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _QuarantineMessageCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
