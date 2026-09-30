import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  Future<List<OpenwallaServiceStatus>>? _servicesFuture;
  String? _busyService;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _loadServices();
  }

  Future<List<OpenwallaServiceStatus>> _loadServices() {
    return ref.read(appStateProvider).fetchOpenwallaServices(context: context);
  }

  Future<void> _refresh() async {
    setState(() {
      _servicesFuture = _loadServices();
    });
    await _servicesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Services',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh services',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<OpenwallaServiceStatus>>(
        future: _servicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LuciLoadingWidget();
          }

          final services = snapshot.data ?? const <OpenwallaServiceStatus>[];
          if (snapshot.hasError) {
            return _ServicesEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load services',
              message: snapshot.error.toString(),
              onRefresh: _refresh,
            );
          }
          if (services.isEmpty) {
            return _ServicesEmptyState(
              icon: Icons.miscellaneous_services_rounded,
              title: 'No services found',
              message: 'Pull down to refresh the router service list.',
              onRefresh: _refresh,
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: services.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final service = services[index];
                return _ServiceCard(
                  service: service,
                  isBusy: _busyService == service.name,
                  onTap: () => _openServiceDetail(service),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openServiceDetail(OpenwallaServiceStatus service) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ServiceDetailScreen(initialService: service),
      ),
    );
    if (mounted) await _refresh();
  }
}

class _ServiceCard extends StatelessWidget {
  final OpenwallaServiceStatus service;
  final bool isBusy;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
    required this.isBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = !service.installed
        ? colorScheme.onSurfaceVariant
        : service.running
        ? const Color(0xFF20CF70)
        : const Color(0xFFFF4D4F);
    final statusLabel = !service.installed
        ? 'Missing'
        : service.running
        ? 'Running'
        : 'Stopped';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.miscellaneous_services_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      service.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      service.category,
                      style: LuciTextStyles.cardSubtitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: statusLabel, color: statusColor),
              const SizedBox(width: 4),
              if (isBusy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ServiceDetailScreen extends ConsumerStatefulWidget {
  final OpenwallaServiceStatus initialService;

  const ServiceDetailScreen({super.key, required this.initialService});

  @override
  ConsumerState<ServiceDetailScreen> createState() =>
      _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  late OpenwallaServiceStatus _service = widget.initialService;
  bool _isLoading = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final services = await ref
          .read(appStateProvider)
          .fetchOpenwallaServices(context: context);
      final updated = services.where((item) => item.name == _service.name);
      if (!mounted) return;
      setState(() {
        if (updated.isNotEmpty) _service = updated.first;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to refresh service: $e')));
    }
  }

  Future<void> _toggle(bool enabled) async {
    await _run(() async {
      await ref
          .read(appStateProvider)
          .setOpenwallaServiceEnabled(_service.name, enabled, context: context);
    }, '${_service.label} ${enabled ? 'enabled' : 'disabled'}.');
  }

  Future<void> _action(String action) async {
    await _run(() async {
      await ref
          .read(appStateProvider)
          .runOpenwallaServiceAction(
            _service.name,
            action: action,
            context: context,
          );
    }, '${_service.label} ${_pastTense(action)}.');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Service action failed: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _pastTense(String action) {
    return switch (action) {
      'start' => 'started',
      'stop' => 'stopped',
      'restart' => 'restarted',
      'reload' => 'reloaded',
      _ => '$action complete',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = !_service.installed
        ? colorScheme.onSurfaceVariant
        : _service.running
        ? const Color(0xFF20CF70)
        : const Color(0xFFFF4D4F);
    final statusLabel = !_service.installed
        ? 'Missing'
        : _service.running
        ? 'Running'
        : 'Stopped';

    return Scaffold(
      appBar: LuciAppBar(
        title: _service.label,
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh service',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isBusy ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _ServiceDetailCard(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.miscellaneous_services_rounded,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _service.label,
                            style: LuciTextStyles.cardTitle(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _service.name,
                            style: LuciTextStyles.cardSubtitle(context),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      _StatusPill(label: statusLabel, color: statusColor),
                  ],
                ),
                const SizedBox(height: 18),
                _ServiceDetailRow(label: 'Category', value: _service.category),
                _ServiceDetailRow(
                  label: 'Installed',
                  value: _service.installed ? 'Yes' : 'No',
                ),
                _ServiceDetailRow(
                  label: 'Enabled',
                  value: _service.enabled ? 'Yes' : 'No',
                ),
                _ServiceDetailRow(
                  label: 'Status',
                  value: _service.statusText.isEmpty
                      ? statusLabel
                      : _service.statusText,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ServiceDetailCard(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable at Boot'),
                  subtitle: const Text('Control the init.d enabled state.'),
                  value: _service.enabled,
                  onChanged: _service.installed && !_isBusy ? _toggle : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _service.installed && !_isBusy
                            ? () => _action('start')
                            : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _service.installed && !_isBusy
                            ? () => _action('stop')
                            : null,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Stop'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _service.installed && !_isBusy
                            ? () => _action('restart')
                            : null,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Restart'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _service.installed && !_isBusy
                            ? () => _action('reload')
                            : null,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reload'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceDetailCard extends StatelessWidget {
  final List<Widget> children;

  const _ServiceDetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _ServiceDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ServiceDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: LuciTextStyles.cardSubtitle(context)),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ServicesEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRefresh;

  const _ServicesEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(icon, size: 56, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
