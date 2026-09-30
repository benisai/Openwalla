import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';

class SmartQueueScreen extends ConsumerStatefulWidget {
  const SmartQueueScreen({super.key});

  @override
  ConsumerState<SmartQueueScreen> createState() => _SmartQueueScreenState();
}

class _SmartQueueScreenState extends ConsumerState<SmartQueueScreen> {
  OpenwrtSqmQueue? _queue;
  List<String> _interfaces = const ['eth1', 'wan'];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasStartedLoad = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final appState = ref.read(appStateProvider);
      final results = await Future.wait([
        appState.fetchSqmQueues(context: context),
        appState.fetchVnstatInterfaceNames(context: context),
      ]);
      if (!mounted) return;
      final queues = results[0] as List<OpenwrtSqmQueue>;
      final interfaces = results[1] as List<String>;
      setState(() {
        _queue =
            queues.firstOrNull ??
            OpenwrtSqmQueue(
              section: '',
              enabled: false,
              interfaceName: interfaces.firstOrNull ?? 'eth1',
              downloadKbps: 0,
              uploadKbps: 0,
              qdisc: 'cake',
              script: 'piece_of_cake.qos',
              debugLogging: false,
              verbosity: '5',
            );
        _interfaces = interfaces.isEmpty ? _interfaces : interfaces;
        if (!_interfaces.contains(_queue!.interfaceName)) {
          _interfaces = [..._interfaces, _queue!.interfaceName];
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load SQM settings.';
        _isLoading = false;
      });
    }
  }

  void _update(OpenwrtSqmQueue queue) => setState(() => _queue = queue);

  Future<void> _save() async {
    final queue = _queue;
    if (queue == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(appStateProvider).saveSqmQueue(queue);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Smart Queue settings saved.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save SQM settings: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Smart Queue', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'Smart Queue Management',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure SQM traffic shaping for one network interface.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 18),
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.sqm,
                title: 'SQM is not installed',
                message:
                    'Install sqm-scripts before configuring Smart Queue traffic shaping on this router.',
                installLabel: 'Install Smart Queue',
                builder: (_) => _buildInstalledContent(queue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstalledContent(OpenwrtSqmQueue? queue) {
    if (!_hasStartedLoad) {
      _hasStartedLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _SqmEmptyCard(message: _error!, onRefresh: _load);
    }
    if (queue == null) return const SizedBox.shrink();
    return _SqmEditor(
      queue: queue,
      interfaces: _interfaces,
      isSaving: _isSaving,
      onChanged: _update,
      onSave: _save,
    );
  }
}

class _SqmEditor extends StatelessWidget {
  final OpenwrtSqmQueue queue;
  final List<String> interfaces;
  final bool isSaving;
  final ValueChanged<OpenwrtSqmQueue> onChanged;
  final VoidCallback onSave;

  const _SqmEditor({
    required this.queue,
    required this.interfaces,
    required this.isSaving,
    required this.onChanged,
    required this.onSave,
  });

  OpenwrtSqmQueue _copy({
    bool? enabled,
    String? interfaceName,
    int? downloadKbps,
    int? uploadKbps,
    String? qdisc,
    String? script,
    bool? debugLogging,
    String? verbosity,
  }) {
    return OpenwrtSqmQueue(
      section: queue.section,
      enabled: enabled ?? queue.enabled,
      interfaceName: interfaceName ?? queue.interfaceName,
      downloadKbps: downloadKbps ?? queue.downloadKbps,
      uploadKbps: uploadKbps ?? queue.uploadKbps,
      qdisc: qdisc ?? queue.qdisc,
      script: script ?? queue.script,
      debugLogging: debugLogging ?? queue.debugLogging,
      verbosity: verbosity ?? queue.verbosity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
          Container(
            decoration: BoxDecoration(
              color: queue.enabled
                  ? colorScheme.primary.withValues(alpha: 0.09)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    (queue.enabled
                            ? colorScheme.primary
                            : colorScheme.outlineVariant)
                        .withValues(alpha: 0.3),
              ),
            ),
            child: SwitchListTile.adaptive(
              secondary: Icon(
                Icons.speed_rounded,
                color: queue.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              title: const Text('Smart Queue'),
              subtitle: Text(queue.enabled ? 'Enabled' : 'Disabled'),
              value: queue.enabled,
              onChanged: isSaving
                  ? null
                  : (value) => onChanged(_copy(enabled: value)),
            ),
          ),
          const SizedBox(height: 20),
          const _SqmSectionLabel(
            icon: Icons.swap_vert_rounded,
            title: 'Connection & Bandwidth',
            subtitle: 'Select the WAN interface and available line speed.',
          ),
          const SizedBox(height: 10),
          _SqmFieldGroup(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: queue.interfaceName,
                  borderRadius: BorderRadius.circular(8),
                  dropdownColor: colorScheme.surfaceContainerHigh,
                  iconEnabledColor: colorScheme.primary,
                  decoration: const InputDecoration(
                    labelText: 'Network Interface',
                    prefixIcon: Icon(Icons.lan_outlined),
                  ),
                  items: interfaces
                      .map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      )
                      .toList(),
                  onChanged: isSaving
                      ? null
                      : (value) => onChanged(_copy(interfaceName: value)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Download Speed',
                  icon: Icons.download_rounded,
                  value: queue.downloadKbps,
                  enabled: !isSaving,
                  onChanged: (value) => onChanged(_copy(downloadKbps: value)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Upload Speed',
                  icon: Icons.upload_rounded,
                  value: queue.uploadKbps,
                  enabled: !isSaving,
                  onChanged: (value) => onChanged(_copy(uploadKbps: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SqmSectionLabel(
            icon: Icons.tune_rounded,
            title: 'Queue Behavior',
            subtitle: 'Choose how traffic is classified and scheduled.',
          ),
          const SizedBox(height: 10),
          _SqmFieldGroup(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: queue.qdisc,
                  borderRadius: BorderRadius.circular(8),
                  dropdownColor: colorScheme.surfaceContainerHigh,
                  iconEnabledColor: colorScheme.primary,
                  decoration: const InputDecoration(
                    labelText: 'Queueing Discipline',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: const ['cake', 'fq_codel', 'codel', 'sfq', 'pie']
                      .map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      )
                      .toList(),
                  onChanged: isSaving
                      ? null
                      : (value) => onChanged(_copy(qdisc: value)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: queue.script,
                  borderRadius: BorderRadius.circular(8),
                  dropdownColor: colorScheme.surfaceContainerHigh,
                  iconEnabledColor: colorScheme.primary,
                  decoration: const InputDecoration(
                    labelText: 'Queue Setup Script',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  items:
                      const [
                            'piece_of_cake.qos',
                            'layer_cake.qos',
                            'simple.qos',
                            'simplest.qos',
                            'simplest_tbf.qos',
                          ]
                          .map(
                            (name) => DropdownMenuItem(
                              value: name,
                              child: Text(name),
                            ),
                          )
                          .toList(),
                  onChanged: isSaving
                      ? null
                      : (value) => onChanged(_copy(script: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SqmSectionLabel(
            icon: Icons.bug_report_outlined,
            title: 'Diagnostics',
            subtitle: 'Optional logging for troubleshooting SQM.',
          ),
          const SizedBox(height: 10),
          _SqmFieldGroup(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.terminal_rounded),
                  title: const Text('Debug Logging'),
                  subtitle: const Text('Write detailed SQM events to the log'),
                  value: queue.debugLogging,
                  onChanged: isSaving
                      ? null
                      : (value) => onChanged(_copy(debugLogging: value)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: queue.verbosity,
                  borderRadius: BorderRadius.circular(8),
                  dropdownColor: colorScheme.surfaceContainerHigh,
                  iconEnabledColor: colorScheme.primary,
                  decoration: const InputDecoration(
                    labelText: 'Log Verbosity',
                    prefixIcon: Icon(Icons.format_list_numbered_rounded),
                  ),
                  items: const ['0', '1', '2', '3', '4', '5', '6', '7', '8']
                      .map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      )
                      .toList(),
                  onChanged: isSaving
                      ? null
                      : (value) => onChanged(_copy(verbosity: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isSaving ? null : onSave,
              icon: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Save & Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final IconData icon;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value.toString();
    if (_controller.text != next) _controller.text = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon),
        suffixText: 'kbit/s',
      ),
      onChanged: (value) => widget.onChanged(int.tryParse(value) ?? 0),
    );
  }
}

class _SqmSectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SqmSectionLabel({
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

class _SqmFieldGroup extends StatelessWidget {
  final Widget child;

  const _SqmFieldGroup({required this.child});

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

class _SqmEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback onRefresh;

  const _SqmEmptyCard({required this.message, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(message),
      ),
    );
  }
}
