import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/router_setup_screen.dart';
import 'package:openwalla/screens/reboot_countdown_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  Future<OpenwallaStateBackupStatus>? _statusFuture;
  String? _busyAction;
  double? _routerProgress;

  @override
  void initState() {
    super.initState();
    _statusFuture = _loadStatus();
  }

  Future<OpenwallaStateBackupStatus> _loadStatus() {
    return ref
        .read(appStateProvider)
        .fetchOpenwallaStateBackupStatus(context: context);
  }

  Future<void> _refresh() async {
    final future = _loadStatus();
    setState(() {
      _statusFuture = future;
    });
    await future;
  }

  Future<void> _runAction(String action) async {
    if (action == 'restore') {
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore router state?'),
          content: const Text(
            'This copies the latest Openwalla backup into the router runtime files. Running services may use the restored data on their next read.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (shouldRestore != true) return;
      if (!mounted) return;
    }

    setState(() => _busyAction = action);
    try {
      final message = await ref
          .read(appStateProvider)
          .runOpenwallaStateBackupAction(action, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('State sync failed: $e')));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _downloadRouterBackup() async {
    setState(() => _busyAction = 'router-backup');
    try {
      final bytes = await ref
          .read(appStateProvider)
          .createOpenwrtConfigurationBackup();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save OpenWrt configuration backup',
        fileName: 'openwrt-backup-$stamp.tar.gz',
        type: FileType.custom,
        allowedExtensions: const ['gz'],
        bytes: bytes,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Router configuration backup saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Router backup failed: $error')));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _restoreRouterBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gz', 'tgz'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null ||
        bytes.length < 2 ||
        bytes[0] != 0x1f ||
        bytes[1] != 0x8b) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a valid OpenWrt gzip backup.')),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Router Configuration?'),
        content: Text(
          'Restore ${file.name} to this router? Current OpenWrt configuration files will be replaced. A backup from another router or firmware version may break network access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Upload & Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyAction = 'router-restore';
      _routerProgress = 0;
    });
    try {
      await ref
          .read(appStateProvider)
          .restoreOpenwrtConfigurationBackup(
            bytes,
            onProgress: (progress) {
              if (mounted) setState(() => _routerProgress = progress);
            },
          );
      if (!mounted) return;
      setState(() {
        _busyAction = null;
        _routerProgress = null;
      });
      final reboot = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore Complete'),
          content: const Text(
            'The OpenWrt configuration was restored. Reboot now to load every restored network and service setting?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reboot Now'),
            ),
          ],
        ),
      );
      if (reboot == true && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const RebootCountdownDialog(
            duration: 120,
            maxAttempts: 1,
            sendRebootCommand: true,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Router restore failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busyAction = null;
          _routerProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: LuciAppBar(title: 'Backup & Restore', showBack: true),
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Openwalla'),
                Tab(text: 'Router'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_buildOpenwallaTab(), _buildRouterTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenwallaTab() {
    return FutureBuilder<OpenwallaStateBackupStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LuciLoadingWidget();
        }

        final status =
            snapshot.data ??
            OpenwallaStateBackupStatus.notInstalled(
              snapshot.error?.toString() ?? '',
            );

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              Text(
                'Openwalla State',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Keep router runtime databases, monitor logs, app config, and usage history available after a reboot.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              if (!status.installed)
                _MissingStateSyncCard(
                  message: status.message,
                  onSetup: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RouterSetupScreen(),
                      ),
                    );
                    if (!mounted) return;
                    await _refresh();
                  },
                  onRefresh: _refresh,
                )
              else ...[
                _StatusCard(status: status),
                const SizedBox(height: 16),
                _ActionsCard(
                  busyAction: _busyAction,
                  onBackup: () => _runAction('backup'),
                  onRestore: () => _runAction('restore'),
                ),
                const SizedBox(height: 16),
                const _IncludedDataCard(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouterTab() {
    final colors = Theme.of(context).colorScheme;
    final busy = _busyAction?.startsWith('router-') == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      children: [
        Text(
          'OpenWrt Configuration',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Download or restore the router configuration archive created by OpenWrt sysupgrade.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: LuciCardStyles.standardCard(context, isElevated: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _IconBadge(
                icon: Icons.archive_outlined,
                color: Color(0xFF20CF70),
              ),
              const SizedBox(height: 14),
              Text(
                'Configuration Archive',
                style: LuciTextStyles.cardTitle(context),
              ),
              const SizedBox(height: 8),
              Text(
                'Includes OpenWrt configuration, passwords, keys, and files preserved by sysupgrade.',
                style: LuciTextStyles.cardSubtitle(context),
              ),
              if (_routerProgress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _routerProgress),
                const SizedBox(height: 6),
                Text(
                  '${(_routerProgress! * 100).round()}% uploaded',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: busy ? null : _downloadRouterBackup,
                icon: _busyAction == 'router-backup'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: const Text('Download Backup'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : _restoreRouterBackup,
                icon: _busyAction == 'router-restore'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: const Text('Upload & Restore'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final OpenwallaStateBackupStatus status;

  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: LuciCardStyles.standardCard(context, isElevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(
                icon: Icons.cloud_done_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Checkpoint Active',
                  style: LuciTextStyles.cardTitle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _InfoRow(label: 'Backup path', value: status.stateDir),
          _InfoRow(
            label: 'Interval',
            value: _formatInterval(status.backupTimeMinutes),
          ),
          _InfoRow(
            label: 'Last backup',
            value: _formatDateTime(status.lastBackupAt),
          ),
          _InfoRow(label: 'Stored files', value: status.fileCount.toString()),
          _InfoRow(label: 'Backup size', value: status.size),
        ],
      ),
    );
  }

  static String _formatInterval(int minutes) {
    if (minutes >= 1440 && minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return days == 1 ? 'Daily' : 'Every $days days';
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 1 ? 'Hourly' : 'Every $hours hours';
    }
    return 'Every $minutes minutes';
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) return 'No backup yet';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute $suffix';
  }
}

class _ActionsCard extends StatelessWidget {
  final String? busyAction;
  final VoidCallback onBackup;
  final VoidCallback onRestore;

  const _ActionsCard({
    required this.busyAction,
    required this.onBackup,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = busyAction != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: LuciCardStyles.standardCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manual Controls', style: LuciTextStyles.cardTitle(context)),
          const SizedBox(height: 8),
          Text(
            'Create a fresh checkpoint before a reboot or restore the latest saved runtime state.',
            style: LuciTextStyles.cardSubtitle(context),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isBusy ? null : onBackup,
                  icon: busyAction == 'backup'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_rounded),
                  label: const Text('Backup Now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : onRestore,
                  icon: busyAction == 'restore'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore_rounded),
                  label: const Text('Restore'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncludedDataCard extends StatelessWidget {
  const _IncludedDataCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      'Devices, parental controls, notifications, Netify, simple flows, and bandwidth databases',
      'Ping, DNS, speedtest, quarantine state, and Openwalla config',
      'vnStat usage history and recent Openwalla service logs',
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: LuciCardStyles.standardCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Included Data', style: LuciTextStyles.cardTitle(context)),
          const SizedBox(height: 12),
          for (final item in items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (item != items.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _MissingStateSyncCard extends StatelessWidget {
  final String message;
  final VoidCallback onSetup;
  final VoidCallback onRefresh;

  const _MissingStateSyncCard({
    required this.message,
    required this.onSetup,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: LuciCardStyles.standardCard(context, isElevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: Icons.inventory_2_rounded, color: colorScheme.error),
          const SizedBox(height: 18),
          Text(
            'State Sync is not installed',
            style: LuciTextStyles.cardTitle(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Install the Openwalla state-sync helper so runtime files can be restored after router reboot.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(message, style: LuciTextStyles.cardSubtitle(context)),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSetup,
                  icon: const Icon(Icons.construction_rounded),
                  label: const Text('Router Setup'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: LuciTextStyles.cardSubtitle(context)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }
}
