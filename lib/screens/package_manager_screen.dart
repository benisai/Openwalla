import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

class PackageManagerScreen extends ConsumerStatefulWidget {
  const PackageManagerScreen({super.key});

  @override
  ConsumerState<PackageManagerScreen> createState() =>
      _PackageManagerScreenState();
}

class _PackageManagerScreenState extends ConsumerState<PackageManagerScreen> {
  final _searchController = TextEditingController();
  RouterPackageSnapshot? _snapshot;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(appStateProvider)
          .fetchInstalledRouterPackages(context: context);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to read installed packages: $error';
        _loading = false;
      });
    }
  }

  Future<void> _runAction({
    required String action,
    String packageName = '',
  }) async {
    final manager = _snapshot?.manager ?? RouterPackageManager.none;
    if (manager == RouterPackageManager.none || _working) return;
    setState(() => _working = true);
    final label = switch (action) {
      'install' => 'Install Package',
      'remove' => 'Remove Package',
      _ => 'Update Package Lists',
    };
    final console = SshConsoleController(
      initialOutput: 'Connecting to router...\n$label starting...\n',
      running: true,
    );
    if (mounted) {
      unawaited(
        showSshConsoleSheet(
          context: context,
          controller: console,
          title: label,
        ).whenComplete(console.dispose),
      );
    }
    final output = StringBuffer();
    try {
      final result = await ref
          .read(appStateProvider)
          .runRouterPackageAction(
            manager: manager,
            action: action,
            packageName: packageName,
            onOutput: (chunk) {
              output.write(chunk);
              console.setOutput(output.toString().trimRight());
            },
          );
      if (output.isEmpty) console.setOutput(result.trimRight());
      console.complete();
      if (!mounted) return;
      context.showToastSuccess(
        action == 'update'
            ? 'Package lists updated'
            : 'Package action complete',
        subtitle: packageName.isEmpty ? null : packageName,
        actionKey: 'package_action',
      );
      await _load();
    } catch (error) {
      console.setOutput('${output.toString().trimRight()}\n\nFailed: $error');
      console.complete();
      if (!mounted) return;
      context.showToastError(
        'Package action failed',
        subtitle: error.toString(),
        actionKey: 'package_action',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showInstallDialog() async {
    final controller = TextEditingController();
    final packageName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Install Package'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Package Name',
            hintText: 'luci-app-example',
            prefixIcon: Icon(Icons.inventory_2_outlined),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Install'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (packageName != null && mounted) {
      await _runAction(action: 'install', packageName: packageName);
    }
  }

  Future<void> _confirmRemove(RouterPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${package.name}?'),
        content: const Text(
          'The package and features that depend on it may stop working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runAction(action: 'remove', packageName: package.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final managerName = switch (snapshot?.manager) {
      RouterPackageManager.opkg => 'OPKG',
      RouterPackageManager.apk => 'APK',
      _ => 'Not detected',
    };
    final query = _searchController.text.trim().toLowerCase();
    final packages = (snapshot?.packages ?? const <RouterPackage>[])
        .where(
          (package) =>
              query.isEmpty ||
              package.name.toLowerCase().contains(query) ||
              package.version.toLowerCase().contains(query),
        )
        .toList();
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Package Manager',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh packages',
            onPressed: _loading || _working ? null : _load,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _PackageSummaryCard(
              managerName: managerName,
              packageCount: snapshot?.packages.length ?? 0,
              disabled: _loading || _working || snapshot == null,
              onUpdate: () => _runAction(action: 'update'),
              onInstall: _showInstallDialog,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search installed packages',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Installed Packages',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${packages.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _PackageMessageCard(message: _error!, onRetry: _load)
            else if (snapshot?.manager == RouterPackageManager.none)
              const _PackageMessageCard(
                message:
                    'No supported OPKG or APK package manager was detected on this router.',
              )
            else if (packages.isEmpty)
              _PackageMessageCard(
                message: query.isEmpty
                    ? 'No installed packages were returned.'
                    : 'No installed packages match this search.',
              )
            else
              ...packages.map(
                (package) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PackageTile(
                    package: package,
                    manager: snapshot!.manager,
                    disabled: _working,
                    onRemove: () => _confirmRemove(package),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackageSummaryCard extends StatelessWidget {
  final String managerName;
  final int packageCount;
  final bool disabled;
  final VoidCallback onUpdate;
  final VoidCallback onInstall;

  const _PackageSummaryCard({
    required this.managerName,
    required this.packageCount,
    required this.disabled,
    required this.onUpdate,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
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
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.inventory_2_rounded, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$managerName Package Manager',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$packageCount packages installed',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: disabled ? null : onUpdate,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Update Lists'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: disabled ? null : onInstall,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Install'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  final RouterPackage package;
  final RouterPackageManager manager;
  final bool disabled;
  final VoidCallback onRemove;

  const _PackageTile({
    required this.package,
    required this.manager,
    required this.disabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            color: colors.primary,
            size: 20,
          ),
        ),
        title: Text(
          package.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          package.version,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Remove package',
          onPressed: disabled ? null : onRemove,
          color: colors.error,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ),
    );
  }
}

class _PackageMessageCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _PackageMessageCard({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ],
      ),
    ),
  );
}
