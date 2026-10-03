import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

Future<bool?> showAddPbrPolicySheet(
  BuildContext context, {
  String initialDestination = '',
  String initialName = '',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AddPbrPolicySheet(
      initialDestination: initialDestination,
      initialName: initialName,
    ),
  );
}

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  List<OpenwrtStaticRoute> _routes = const [];
  List<OpenwrtPbrPolicy> _pbrPolicies = const [];
  bool _hasPbrSupport = false;
  bool _isInstallingPbr = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoutes());
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final appState = ref.read(appStateProvider);
      final routes = await appState.fetchStaticRoutes(context: context);
      final hasPbr = await appState.hasPbrSupport();
      final policies = hasPbr
          ? await appState.fetchPbrPolicies()
          : const <OpenwrtPbrPolicy>[];
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _hasPbrSupport = hasPbr;
        _pbrPolicies = policies;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load static routes.';
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddRouteSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AddRouteSheet(),
    );
    if (saved == true) await _loadRoutes();
  }

  Future<void> _showAddPbrSheet() async {
    final saved = await showAddPbrPolicySheet(context);
    if (saved == true) await _loadRoutes();
  }

  Future<void> _installPbr() async {
    if (_isInstallingPbr) return;
    setState(() => _isInstallingPbr = true);
    final console = SshConsoleController(
      initialOutput: 'Connecting to router...\nInstalling PBR support...',
      running: true,
    );
    unawaited(
      showSshConsoleSheet(
        context: context,
        controller: console,
        title: 'Install Policy-Based Routing',
      ).whenComplete(console.dispose),
    );
    try {
      final output = StringBuffer();
      await ref
          .read(appStateProvider)
          .installPbrSupport(
            onOutput: (chunk) {
              output.write(chunk);
              console.setOutput(output.toString().trimRight());
            },
          );
      console.complete();
      if (!mounted) return;
      context.showToastSuccess(
        'PBR installed',
        subtitle: 'Domain routing policies are ready.',
        actionKey: 'install-pbr',
      );
      await _loadRoutes();
    } catch (error) {
      console.setOutput('PBR installation failed.\n\n$error');
      console.complete();
      if (!mounted) return;
      context.showToastError(
        'PBR installation failed',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'install-pbr',
      );
    } finally {
      if (mounted) setState(() => _isInstallingPbr = false);
    }
  }

  Future<void> _togglePbrPolicy(OpenwrtPbrPolicy policy, bool enabled) async {
    final oldPolicies = _pbrPolicies;
    setState(() {
      _pbrPolicies = _pbrPolicies
          .map(
            (item) => item.section == policy.section
                ? OpenwrtPbrPolicy(
                    section: item.section,
                    name: item.name,
                    destination: item.destination,
                    interfaceName: item.interfaceName,
                    enabled: enabled,
                  )
                : item,
          )
          .toList();
    });
    try {
      await ref
          .read(appStateProvider)
          .setPbrPolicyEnabled(policy.section, enabled);
      if (!mounted) return;
      context.showToastSuccess(
        enabled ? 'Routing policy enabled' : 'Routing policy disabled',
        subtitle: policy.name,
        actionKey: 'pbr-${policy.section}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _pbrPolicies = oldPolicies);
      context.showToastError(
        'Routing policy could not be updated',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'pbr-${policy.section}',
      );
    }
  }

  Future<void> _deletePbrPolicy(OpenwrtPbrPolicy policy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete routing policy?'),
        content: Text('Delete "${policy.name}" from the router?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(appStateProvider).deletePbrPolicy(policy.section);
      if (!mounted) return;
      setState(
        () => _pbrPolicies = _pbrPolicies
            .where((item) => item.section != policy.section)
            .toList(),
      );
      context.showToastSuccess(
        'Routing policy deleted',
        subtitle: policy.name,
        actionKey: 'pbr-${policy.section}',
      );
    } catch (error) {
      if (!mounted) return;
      context.showToastError(
        'Routing policy could not be deleted',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'pbr-${policy.section}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Routing',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Add route',
            onPressed: _showAddRouteSheet,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadRoutes,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (!_isLoading) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Static IPv4 Routes',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _showAddRouteSheet,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  _RouteEmptyCard(message: _error!, onRefresh: _loadRoutes)
                else if (_routes.isEmpty)
                  _RouteEmptyCard(
                    message: 'No static routes found.',
                    onRefresh: _loadRoutes,
                  )
                else
                  ..._routes.map((route) => _RouteCard(route: route)),
                const SizedBox(height: 22),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Policy-Based Routing',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (!_isLoading && _hasPbrSupport)
                    FilledButton.icon(
                      onPressed: _showAddPbrSheet,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Policy'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Route domains or addresses through a VPN or another interface.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const _PbrCheckingCard()
              else if (!_hasPbrSupport)
                _PbrInstallCard(
                  isInstalling: _isInstallingPbr,
                  onInstall: _installPbr,
                )
              else if (_pbrPolicies.isEmpty)
                _RouteEmptyCard(
                  message: 'No domain routing policies found.',
                  onRefresh: _loadRoutes,
                )
              else
                ..._pbrPolicies.map(
                  (policy) => _PbrPolicyCard(
                    policy: policy,
                    onChanged: (enabled) => _togglePbrPolicy(policy, enabled),
                    onDelete: () => _deletePbrPolicy(policy),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PbrCheckingCard extends StatelessWidget {
  const _PbrCheckingCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checking PBR support',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  'Reading routing policies from the router...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PbrInstallCard extends StatelessWidget {
  final bool isInstalling;
  final VoidCallback onInstall;

  const _PbrInstallCard({required this.isInstalling, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.alt_route_rounded, color: colors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PBR component required',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text('Install the OpenWrt PBR service to route domains.'),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: isInstalling ? null : onInstall,
            icon: isInstalling
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(isInstalling ? 'Installing' : 'Install'),
          ),
        ],
      ),
    );
  }
}

class _PbrPolicyCard extends StatelessWidget {
  final OpenwrtPbrPolicy policy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;

  const _PbrPolicyCard({
    required this.policy,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.language_rounded, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  policy.name.isEmpty ? policy.destination : policy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${policy.destination}  ->  ${policy.interfaceName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: policy.enabled, onChanged: onChanged),
          IconButton(
            tooltip: 'Delete policy',
            onPressed: onDelete,
            color: colors.error,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _AddPbrPolicySheet extends ConsumerStatefulWidget {
  final String initialDestination;
  final String initialName;

  const _AddPbrPolicySheet({
    required this.initialDestination,
    required this.initialName,
  });

  @override
  ConsumerState<_AddPbrPolicySheet> createState() => _AddPbrPolicySheetState();
}

class _AddPbrPolicySheetState extends ConsumerState<_AddPbrPolicySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _destinationController;
  late List<String> _interfaces;
  late String _interfaceName;
  bool _enabled = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _destinationController = TextEditingController(
      text: widget.initialDestination,
    );
    _interfaces = ref
        .read(appStateProvider)
        .dashboardInterfaceNames()
        .where((name) => name != 'lan' && name != 'loopback')
        .toSet()
        .toList();
    if (_interfaces.isEmpty) _interfaces = ['wan'];
    _interfaceName = _interfaces.firstWhere(
      (name) => name.toLowerCase().contains('wg'),
      orElse: () => _interfaces.first,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  String? _validateDestination(String? value) {
    final destination = value?.trim().toLowerCase() ?? '';
    if (destination.isEmpty) return 'Enter a domain or destination address';
    if (destination.contains('://') || destination.contains('/path')) {
      return 'Enter a domain only, without http:// or a path';
    }
    if (!RegExp(r'^[a-z0-9.*:_/ -]+$').hasMatch(destination)) {
      return 'Enter a valid domain, IP address, or CIDR';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final destination = _destinationController.text.trim();
    final name = _nameController.text.trim().isEmpty
        ? 'Route $destination'
        : _nameController.text.trim();
    try {
      await ref
          .read(appStateProvider)
          .addPbrPolicy(
            name: name,
            destination: destination,
            interfaceName: _interfaceName,
            enabled: _enabled,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      context.showToastSuccess(
        'Routing policy created',
        subtitle: '$destination through $_interfaceName',
        actionKey: 'add-pbr-policy',
      );
    } catch (error) {
      if (!mounted) return;
      context.showToastError(
        'Routing policy could not be created',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'add-pbr-policy',
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.alt_route_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Routing Policy',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Send a domain through a selected interface.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 20),
                children: [
                  _RouteFieldGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Policy Name',
                            hintText: 'Streaming over VPN',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _destinationController,
                          enabled: !_isSaving,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Domain or Destination',
                            hintText: 'example.com',
                            helperText: 'Hostnames, IP addresses, and CIDRs',
                            prefixIcon: Icon(Icons.language_rounded),
                          ),
                          validator: _validateDestination,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _interfaceName,
                          decoration: const InputDecoration(
                            labelText: 'Route Through',
                            prefixIcon: Icon(Icons.vpn_lock_rounded),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: colors.surfaceContainerHigh,
                          items: _interfaces
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(
                                  () =>
                                      _interfaceName = value ?? _interfaceName,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    title: const Text('Policy Active'),
                    subtitle: const Text('Apply this policy after saving'),
                    value: _enabled,
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_isSaving ? 'Creating' : 'Create Policy'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final OpenwrtStaticRoute route;

  const _RouteCard({required this.route});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gateway = route.gateway.isEmpty ? 'parent gateway' : route.gateway;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_rounded,
                color: route.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  route.target,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                route.routeType,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RouteMeta(
                  label: 'Interface',
                  value: route.interfaceName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RouteMeta(label: 'Gateway', value: gateway),
              ),
              const SizedBox(width: 12),
              _RouteMeta(label: 'Metric', value: route.metric),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteMeta extends StatelessWidget {
  final String label;
  final String value;

  const _RouteMeta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '-' : value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RouteEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback onRefresh;

  const _RouteEmptyCard({required this.message, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _AddRouteSheet extends ConsumerStatefulWidget {
  const _AddRouteSheet();

  @override
  ConsumerState<_AddRouteSheet> createState() => _AddRouteSheetState();
}

class _AddRouteSheetState extends ConsumerState<_AddRouteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _targetController = TextEditingController();
  final _gatewayController = TextEditingController();
  final _metricController = TextEditingController();
  var _interfaceName = 'lan';
  var _routeType = 'unicast';
  var _interfaces = const ['lan', 'wan'];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final names = ref.read(appStateProvider).dashboardInterfaceNames();
    _interfaces = names.isEmpty ? _interfaces : names;
    _interfaceName = _interfaces.first;
  }

  @override
  void dispose() {
    _targetController.dispose();
    _gatewayController.dispose();
    _metricController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final target = _targetController.text.trim();
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .addStaticRoute(
            interfaceName: _interfaceName,
            routeType: _routeType,
            target: target,
            gateway: _gatewayController.text,
            metric: _metricController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add route: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.route_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Static Route',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Send traffic for a destination through a gateway.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 20),
                children: [
                  const _RouteSectionLabel(
                    icon: Icons.alt_route_rounded,
                    title: 'Route Destination',
                    subtitle: 'Define the network and route behavior.',
                  ),
                  const SizedBox(height: 10),
                  _RouteFieldGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _targetController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Target Network',
                            hintText: '0.0.0.0/0',
                            prefixIcon: Icon(Icons.my_location_rounded),
                          ),
                          validator: (value) => value?.trim().isEmpty == true
                              ? 'Target network is required'
                              : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _routeType,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: colors.surfaceContainerHigh,
                          iconEnabledColor: colors.primary,
                          decoration: const InputDecoration(
                            labelText: 'Route Type',
                            prefixIcon: Icon(Icons.signpost_rounded),
                          ),
                          items:
                              const [
                                    'unicast',
                                    'blackhole',
                                    'unreachable',
                                    'prohibit',
                                  ]
                                  .map(
                                    (type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(type),
                                    ),
                                  )
                                  .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(
                                  () => _routeType = value ?? _routeType,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _RouteSectionLabel(
                    icon: Icons.router_rounded,
                    title: 'Next Hop',
                    subtitle: 'Choose the outgoing interface and gateway.',
                  ),
                  const SizedBox(height: 10),
                  _RouteFieldGroup(
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _interfaceName,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: colors.surfaceContainerHigh,
                          iconEnabledColor: colors.primary,
                          decoration: const InputDecoration(
                            labelText: 'Interface',
                            prefixIcon: Icon(Icons.lan_outlined),
                          ),
                          items: _interfaces
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(
                                  () =>
                                      _interfaceName = value ?? _interfaceName,
                                ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _gatewayController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Gateway',
                            hintText: '192.168.0.1',
                            prefixIcon: Icon(Icons.hub_outlined),
                            helperText:
                                'Optional for directly connected routes',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _metricController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Metric',
                            hintText: '0',
                            prefixIcon: Icon(Icons.low_priority_rounded),
                            helperText: 'Lower values are preferred',
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _save(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_isSaving ? 'Creating' : 'Create Route'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _RouteSectionLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteFieldGroup extends StatelessWidget {
  final Widget child;

  const _RouteFieldGroup({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
