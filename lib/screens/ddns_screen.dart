import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/ddns_info.dart';
import 'package:openwalla/screens/router_setup_screen.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class DdnsScreen extends ConsumerStatefulWidget {
  const DdnsScreen({super.key});

  @override
  ConsumerState<DdnsScreen> createState() => _DdnsScreenState();
}

class _DdnsScreenState extends ConsumerState<DdnsScreen> {
  DdnsOverview? _overview;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final overview = await ref
          .read(appStateProvider)
          .fetchDdnsOverview(context: context);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load DDNS: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openEditor([DdnsInstance? instance]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DdnsEditorSheet(instance: instance),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggleGlobal(bool enabled) async {
    final ok = await ref
        .read(appStateProvider)
        .toggleGlobalDdns(enabled, context: context);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'DDNS updated.' : 'Failed to update DDNS.')),
    );
    await _load();
  }

  Future<void> _delete(DdnsInstance instance) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete DDNS entry?'),
        content: Text('Remove ${instance.name} from this router?'),
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
    if (confirm != true) return;
    if (!mounted) return;
    final ok = await ref
        .read(appStateProvider)
        .deleteDdnsInstance(instance.name, context: context);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'DDNS entry deleted.' : 'Delete failed.')),
    );
    await _load();
  }

  Future<void> _test(DdnsInstance instance) async {
    final result = await ref
        .read(appStateProvider)
        .testDdnsConfiguration(instance, context: context);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.isValid
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: result.isValid
                          ? const Color(0xFF20CF70)
                          : colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      result.isValid ? 'DDNS Test Passed' : 'DDNS Test Failed',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  result.errorMessage ?? result.testOutput ?? 'No output.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final overview = _overview;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'DDNS',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Add DDNS',
            onPressed: _isLoading ? null : () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              'Dynamic DNS',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Keep a hostname pointed at your WAN address.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _DdnsInfoCard(
                icon: Icons.cloud_off_rounded,
                title: 'DDNS unavailable',
                message: _error!,
                actionLabel: 'Try Again',
                onAction: _load,
              )
            else if (overview != null) ...[
              if (!overview.isInstalled)
                _DdnsInfoCard(
                  icon: Icons.download_rounded,
                  title: 'DDNS is not installed',
                  message:
                      'Install ddns-scripts on this router before creating update jobs.',
                  actionLabel: 'Router Setup',
                  onAction: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RouterSetupScreen(),
                      ),
                    );
                  },
                ),
              _DdnsGlobalCard(overview: overview, onChanged: _toggleGlobal),
              const SizedBox(height: 14),
              if (overview.instances.isEmpty)
                _DdnsInfoCard(
                  icon: Icons.public_rounded,
                  title: 'No DDNS entries',
                  message: 'Add a provider and hostname to start syncing.',
                  actionLabel: 'Add DDNS',
                  onAction: () => _openEditor(),
                )
              else
                ...overview.instances.map(
                  (instance) => _DdnsInstanceCard(
                    instance: instance,
                    onTap: () => _openEditor(instance),
                    onTest: () => _test(instance),
                    onDelete: () => _delete(instance),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DdnsGlobalCard extends StatelessWidget {
  final DdnsOverview overview;
  final ValueChanged<bool> onChanged;

  const _DdnsGlobalCard({required this.overview, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        secondary: Icon(Icons.cloud_sync_rounded, color: colorScheme.primary),
        title: Text('DDNS Service', style: LuciTextStyles.cardTitle(context)),
        subtitle: Text(
          overview.isGlobalEnabled ? 'Enabled on this router' : 'Stopped',
          style: LuciTextStyles.cardSubtitle(context),
        ),
        value: overview.isGlobalEnabled,
        onChanged: overview.isInstalled ? onChanged : null,
      ),
    );
  }
}

class _DdnsInstanceCard extends StatelessWidget {
  final DdnsInstance instance;
  final VoidCallback onTap;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _DdnsInstanceCard({
    required this.instance,
    required this.onTap,
    required this.onTest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final preset = kDdnsProviderPresets.firstWhere(
      (item) => item.serviceName == instance.serviceName,
      orElse: () => kDdnsProviderPresets.last,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.public_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          instance.lookupHost.isEmpty
                              ? instance.name
                              : instance.lookupHost,
                          style: LuciTextStyles.cardTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${preset.label} • ${instance.interface}',
                          style: LuciTextStyles.cardSubtitle(context),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(enabled: instance.enabled),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                instance.statusStr?.isNotEmpty == true
                    ? instance.statusStr!
                    : 'Checks every ${instance.checkInterval} ${instance.checkUnit}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTest,
                      icon: const Icon(Icons.network_check_rounded),
                      label: const Text('Test'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool enabled;

  const _StatusPill({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? const Color(0xFF20CF70) : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        enabled ? 'On' : 'Off',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DdnsInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _DdnsInfoCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary, size: 30),
            const SizedBox(height: 14),
            Text(title, style: LuciTextStyles.cardTitle(context)),
            const SizedBox(height: 8),
            Text(message, style: LuciTextStyles.cardSubtitle(context)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DdnsEditorSheet extends ConsumerStatefulWidget {
  final DdnsInstance? instance;

  const _DdnsEditorSheet({this.instance});

  @override
  ConsumerState<_DdnsEditorSheet> createState() => _DdnsEditorSheetState();
}

class _DdnsEditorSheetState extends ConsumerState<_DdnsEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _lookupController;
  late final TextEditingController _domainController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _interfaceController;
  late final TextEditingController _ipUrlController;
  late final TextEditingController _updateUrlController;
  var _serviceName = kDdnsProviderPresets.first.serviceName;
  var _enabled = true;
  var _saving = false;
  var _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final inst = widget.instance;
    _serviceName = inst?.serviceName ?? kDdnsProviderPresets.first.serviceName;
    _enabled = inst?.enabled ?? true;
    _nameController = TextEditingController(text: inst?.name ?? 'myddns_ipv4');
    _lookupController = TextEditingController(text: inst?.lookupHost ?? '');
    _domainController = TextEditingController(text: inst?.domain ?? '');
    _usernameController = TextEditingController(text: inst?.username ?? '');
    _passwordController = TextEditingController(text: inst?.password ?? '');
    _interfaceController = TextEditingController(
      text: inst?.interface ?? 'wan',
    );
    _ipUrlController = TextEditingController(
      text: inst?.ipUrl ?? 'http://checkip.dyndns.com',
    );
    _updateUrlController = TextEditingController(text: inst?.updateUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lookupController.dispose();
    _domainController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _interfaceController.dispose();
    _ipUrlController.dispose();
    _updateUrlController.dispose();
    super.dispose();
  }

  DdnsProviderPreset get _preset => kDdnsProviderPresets.firstWhere(
    (item) => item.serviceName == _serviceName,
    orElse: () => kDdnsProviderPresets.last,
  );

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  DdnsInstance _buildInstance() {
    return DdnsInstance(
      name: _nameController.text.trim(),
      enabled: _enabled,
      serviceName: _serviceName,
      lookupHost: _lookupController.text.trim(),
      domain: _domainController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      interface: _interfaceController.text.trim().isEmpty
          ? 'wan'
          : _interfaceController.text.trim(),
      ipUrl: _ipUrlController.text.trim(),
      updateUrl: _updateUrlController.text.trim(),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await ref
        .read(appStateProvider)
        .saveDdnsInstance(_buildInstance(), context: context);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save DDNS.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.instance != null;
    return FractionallySizedBox(
      heightFactor: 0.92,
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
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.cloud_sync_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Edit DDNS' : 'Add DDNS',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Keep a hostname pointed at your router.',
                          style: LuciTextStyles.cardSubtitle(context),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving
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
                  _DdnsSectionLabel(
                    icon: Icons.tune_rounded,
                    title: 'Service',
                    subtitle: 'Name the job and choose its DDNS provider.',
                  ),
                  const SizedBox(height: 10),
                  _DdnsFormGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Entry Name',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                          validator: _required,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _serviceName,
                          decoration: const InputDecoration(
                            labelText: 'Provider',
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                          items: kDdnsProviderPresets
                              .map(
                                (preset) => DropdownMenuItem(
                                  value: preset.serviceName,
                                  child: Text(
                                    preset.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _serviceName = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          title: const Text('Active'),
                          subtitle: const Text('Run this DDNS update job'),
                          secondary: Icon(
                            _enabled
                                ? Icons.play_circle_outline_rounded
                                : Icons.pause_circle_outline_rounded,
                            color: _enabled
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _DdnsSectionLabel(
                    icon: Icons.language_rounded,
                    title: 'Hostname',
                    subtitle: 'Set the public name this job will maintain.',
                  ),
                  const SizedBox(height: 10),
                  _DdnsFormGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _lookupController,
                          decoration: InputDecoration(
                            labelText: 'Lookup Hostname',
                            hintText: _preset.lookupHostHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                          ),
                          validator: _required,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _domainController,
                          decoration: InputDecoration(
                            labelText: 'Domain',
                            hintText: _preset.domainHint,
                            prefixIcon: const Icon(Icons.public_rounded),
                          ),
                          validator: _required,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _DdnsSectionLabel(
                    icon: Icons.key_rounded,
                    title: 'Credentials',
                    subtitle: 'Enter the account or token for this provider.',
                  ),
                  const SizedBox(height: 10),
                  _DdnsFormGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: _preset.usernameHint,
                            prefixIcon: const Icon(
                              Icons.person_outline_rounded,
                            ),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password or Token',
                            hintText: _preset.passwordHint,
                            prefixIcon: const Icon(Icons.password_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _DdnsSectionLabel(
                    icon: Icons.settings_ethernet_rounded,
                    title: 'Connection',
                    subtitle: 'Choose the source interface and IP service.',
                  ),
                  const SizedBox(height: 10),
                  _DdnsFormGroup(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _interfaceController,
                          decoration: const InputDecoration(
                            labelText: 'Interface',
                            prefixIcon: Icon(Icons.hub_outlined),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ipUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Public IP URL',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: _preset.requiresCustomUrl
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: _preset.requiresCustomUrl
                              ? null
                              : (_) => _save(),
                        ),
                        if (_preset.requiresCustomUrl) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _updateUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Update URL',
                              prefixIcon: Icon(Icons.sync_alt_rounded),
                            ),
                            validator: _required,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Provider package: ${_preset.requiredPackage}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving' : 'Save DDNS'),
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

class _DdnsSectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DdnsSectionLabel({
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
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: LuciTextStyles.cardSubtitle(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DdnsFormGroup extends StatelessWidget {
  final Widget child;

  const _DdnsFormGroup({required this.child});

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
