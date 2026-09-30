import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

const _routerComponentsRawBase =
    'https://raw.githubusercontent.com/benisai/openwalla-apk/main/openwrt-setup';

String buildRouterComponentsCommand(String action) => [
  'export OPENWALLA_RAW_BASE=$_routerComponentsRawBase',
  'SCRIPT=/tmp/openwalla-components.sh',
  'if command -v wget >/dev/null 2>&1; then wget -qO "\$SCRIPT" "\$OPENWALLA_RAW_BASE/openwalla-components.sh"; else curl -fsSL "\$OPENWALLA_RAW_BASE/openwalla-components.sh" -o "\$SCRIPT"; fi',
  'chmod 0755 "\$SCRIPT"',
  'sh "\$SCRIPT" $action',
].join(' && ');

class RouterComponentsScreen extends ConsumerStatefulWidget {
  const RouterComponentsScreen({super.key});

  @override
  ConsumerState<RouterComponentsScreen> createState() =>
      _RouterComponentsScreenState();
}

class _RouterComponentsScreenState
    extends ConsumerState<RouterComponentsScreen> {
  RouterComponentStatus? _status;
  String? _error;
  bool _checking = true;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (mounted) {
      setState(() {
        _checking = true;
        _error = null;
      });
    }
    try {
      final output = await ref
          .read(appStateProvider)
          .runRouterSetupCommandViaSsh(buildRouterComponentsCommand('status'));
      if (!mounted) return;
      setState(() => _status = RouterComponentStatus.parse(output));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _update() async {
    if (_updating) return;
    setState(() => _updating = true);
    final console = SshConsoleController(
      initialOutput:
          'Connecting to the router...\nChecking installed Openwalla components...\n',
      running: true,
    );
    unawaited(
      showSshConsoleSheet(
        context: context,
        controller: console,
        title: 'Update Router Components',
      ).whenComplete(console.dispose),
    );

    try {
      final buffer = StringBuffer();
      final output = await ref
          .read(appStateProvider)
          .runRouterSetupCommandViaSsh(
            buildRouterComponentsCommand('update'),
            onOutput: (chunk) {
              buffer.write(chunk);
              console.setOutput(buffer.toString().trimRight());
            },
          );
      console.setOutput(output.trim());
      console.complete();
      if (!mounted) return;
      setState(() {
        _status = RouterComponentStatus.parse(output);
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Router components are up to date.')),
      );
    } catch (error) {
      console.setOutput('Component update failed.\n\n$error');
      console.complete();
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _status;
    final hasComponents = status != null && status.managedCount > 0;
    final current = status?.isCurrent ?? false;
    final heading = !hasComponents
        ? 'No Managed Components Found'
        : current
        ? 'Components Up to Date'
        : 'Component Update Available';
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Router Components',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Check again',
            onPressed: _checking || _updating ? null : _check,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              current
                                  ? Icons.verified_rounded
                                  : Icons.system_update_alt_rounded,
                              color: current
                                  ? const Color(0xFF20CF70)
                                  : colors.primary,
                              size: 30,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    heading,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    'Installed ${status?.installedVersion ?? 'Unknown'}  •  Available ${status?.availableVersion ?? 'Unknown'}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: colors.error)),
                        ],
                        if (status != null) ...[
                          const SizedBox(height: 18),
                          _StatusRow(
                            label: 'Managed files found',
                            value: '${status.managedCount}',
                          ),
                          _StatusRow(
                            label: 'Files needing updates',
                            value: '${status.outdatedFiles.length}',
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _updating || !hasComponents
                              ? null
                              : _update,
                          icon: _updating
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.system_update_alt_rounded),
                          label: Text(
                            _updating
                                ? 'Updating Components'
                                : current
                                ? 'Verify & Update'
                                : 'Update Components',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (status != null && status.outdatedFiles.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Files to update',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...status.outdatedFiles.map(
                    (path) => ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.description_outlined,
                        color: colors.primary,
                      ),
                      title: Text(path),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Updates only existing Openwalla helper files and restarts affected services. Router settings, packages, databases, and history are preserved.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class RouterComponentStatus {
  final String availableVersion;
  final String installedVersion;
  final int managedCount;
  final List<String> outdatedFiles;

  const RouterComponentStatus({
    required this.availableVersion,
    required this.installedVersion,
    required this.managedCount,
    required this.outdatedFiles,
  });

  bool get isCurrent =>
      managedCount > 0 &&
      outdatedFiles.isEmpty &&
      availableVersion != 'Unknown' &&
      installedVersion == availableVersion;

  factory RouterComponentStatus.parse(String output) {
    var availableVersion = 'Unknown';
    var installedVersion = 'Unknown';
    var managedCount = 0;
    final outdated = <String>[];
    for (final line in output.split('\n')) {
      final fields = line.trim().split('|');
      if (fields.length < 2) continue;
      switch (fields.first) {
        case 'AVAILABLE_VERSION':
          availableVersion = fields[1];
        case 'INSTALLED_VERSION':
          installedVersion = fields[1];
        case 'OUTDATED':
          outdated.add(fields[1]);
        case 'UPDATED':
          outdated.remove(fields[1]);
        case 'SUMMARY':
          for (final value in fields.skip(1)) {
            if (value.startsWith('managed=')) {
              managedCount = int.tryParse(value.substring(8)) ?? 0;
            }
          }
      }
    }
    return RouterComponentStatus(
      availableVersion: availableVersion,
      installedVersion: installedVersion,
      managedCount: managedCount,
      outdatedFiles: outdated,
    );
  }
}
