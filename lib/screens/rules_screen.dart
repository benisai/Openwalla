import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';

enum _RulesPanel { openwalla, defaults }

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  final PageController _pageController = PageController();
  List<OpenwrtFirewallRule> _rules = const [];
  List<OpenwrtPortForward> _portForwards = const [];
  int _panelIndex = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRules());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final results = await Future.wait([
        appState.fetchFirewallRules(context: context),
        appState.fetchPortForwards(context: context),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = results[0] as List<OpenwrtFirewallRule>;
        _portForwards = results[1] as List<OpenwrtPortForward>;
        _isLoading = false;
      });
      await appState.refreshDashboardSummaryCounts();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load firewall rules.';
        _isLoading = false;
      });
    }
  }

  void _selectPanel(int index) {
    setState(() => _panelIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _setRuleEnabled(OpenwrtFirewallRule rule, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider).setFirewallRuleEnabled(rule, enabled);
      if (!mounted) return;
      await _loadRules();
      messenger.showSnackBar(
        SnackBar(content: Text(enabled ? 'Rule enabled.' : 'Rule disabled.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update rule: $e')),
      );
    }
  }

  Future<void> _deleteRule(OpenwrtFirewallRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule?'),
        content: Text('Delete "${rule.name}" from firewall rules?'),
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
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider).deleteFirewallRule(rule);
      if (!mounted) return;
      await _loadRules();
      messenger.showSnackBar(const SnackBar(content: Text('Rule deleted.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete rule: $e')),
      );
    }
  }

  void _showRuleDetails(OpenwrtFirewallRule rule) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _RuleDetailsSheet(
        rule: rule,
        onToggleEnabled: (enabled) {
          Navigator.of(sheetContext).pop();
          _setRuleEnabled(rule, enabled);
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _deleteRule(rule);
        },
      ),
    );
  }

  void _showPortForwardDetails(OpenwrtPortForward forward) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _PortForwardDetailsSheet(
        forward: forward,
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _deletePortForward(forward);
        },
      ),
    );
  }

  Future<void> _deletePortForward(OpenwrtPortForward forward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Delete Port Forward?'),
        content: Text(
          'Delete "${forward.name}" from the router? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(appStateProvider).deletePortForward(forward);
      if (!mounted) return;
      await _loadRules();
      if (!mounted) return;
      context.showToastSuccess(
        'Port forward deleted',
        subtitle: forward.name,
        actionKey: 'port-forward-delete',
      );
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        'Port forward could not be deleted',
        subtitle: e.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'port-forward-delete',
      );
    }
  }

  String _formatCount(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final openwallaRules = _rules
        .where((rule) => rule.isOpenwallaRule)
        .toList();
    final openwrtRules = _rules.where((rule) => !rule.isOpenwallaRule).toList();

    return Scaffold(
      appBar: const LuciAppBar(title: 'Rules', showBack: true),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Router Rules',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatCount(_rules.length + _portForwards.length),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                    ),
                  ),
                ],
              ),
            ),
            _RulesPanelSwitcher(
              selectedIndex: _panelIndex,
              onSelected: _selectPanel,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _panelIndex = index),
                children: [
                  _buildPanel(
                    panel: _RulesPanel.openwalla,
                    title: 'Openwalla Rules',
                    count: openwallaRules.length,
                    rules: openwallaRules,
                    emptyMessage: 'No Openwalla rules found.',
                  ),
                  _buildPanel(
                    panel: _RulesPanel.defaults,
                    title: 'Default Rules',
                    count: openwrtRules.length,
                    rules: openwrtRules,
                    emptyMessage: 'No default OpenWrt rules found.',
                  ),
                  _buildPortForwardPanel(),
                ],
              ),
            ),
            _RulesPanelDots(count: 3, currentIndex: _panelIndex),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({
    required _RulesPanel panel,
    required String title,
    required int count,
    required List<OpenwrtFirewallRule> rules,
    required String emptyMessage,
  }) {
    final isOpenwallaPanel = panel == _RulesPanel.openwalla;

    return RefreshIndicator(
      onRefresh: _loadRules,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _RuleGroupHeader(title: title, count: count),
          if (isOpenwallaPanel)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                'Rules created by Openwalla are shown here first.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                'OpenWrt default firewall rules are separated for easier review.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 44),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _RulesEmptyCard(message: _error!, action: _loadRules)
          else if (_rules.isEmpty)
            _RulesEmptyCard(
              message: 'No firewall rules found.',
              action: _loadRules,
            )
          else if (rules.isEmpty)
            _RulesEmptyCard(message: emptyMessage, action: _loadRules)
          else
            ...rules.map(
              (rule) =>
                  _RuleCard(rule: rule, onTap: () => _showRuleDetails(rule)),
            ),
        ],
      ),
    );
  }

  Widget _buildPortForwardPanel() {
    return RefreshIndicator(
      onRefresh: _loadRules,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _RuleGroupHeader(title: 'Port Forwards', count: _portForwards.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Text(
              'Firewall redirects configured on this router.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 44),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _RulesEmptyCard(message: _error!, action: _loadRules)
          else if (_portForwards.isEmpty)
            _RulesEmptyCard(
              message: 'No port forwarding rules found.',
              action: _loadRules,
            )
          else
            ..._portForwards.map(
              (forward) => _PortForwardRuleCard(
                forward: forward,
                onTap: () => _showPortForwardDetails(forward),
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesPanelSwitcher extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _RulesPanelSwitcher({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const tabs = ['Openwalla', 'Default', 'Port Forwards'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _RulesPanelDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _RulesPanelDots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: index == currentIndex ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: index == currentIndex
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _RuleGroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _RuleGroupHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$title ($count)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback action;

  const _RulesEmptyCard({required this.message, required this.action});

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
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: action,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final OpenwrtFirewallRule rule;
  final VoidCallback onTap;

  const _RuleCard({required this.rule, required this.onTap});

  Color _targetColor(BuildContext context) {
    final action = rule.action.toUpperCase();
    if (action == 'ACCEPT') return const Color(0xFF20CF70);
    if (action == 'REJECT' || action == 'DROP') {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetColor = _targetColor(context);
    final backgroundColor = rule.isBlocked
        ? colorScheme.error.withValues(alpha: 0.045)
        : colorScheme.surface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: rule.isOpenwallaRule
                ? colorScheme.primary.withValues(alpha: 0.35)
                : colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                _RuleBadge(label: rule.action, color: targetColor),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _RuleCompactLine(rule: rule),
          ],
        ),
      ),
    );
  }
}

class _RuleCompactLine extends StatelessWidget {
  final OpenwrtFirewallRule rule;

  const _RuleCompactLine({required this.rule});

  String _value(String value) => value == 'Any' ? '*' : value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destination = [
      _value(rule.destination),
      if (rule.port != 'Any') ':${rule.port}',
    ].join();

    return Row(
      children: [
        Expanded(
          child: Text(
            '${_value(rule.source)} ${_value(rule.sourceIp)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          Icons.arrow_forward_rounded,
          size: 14,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            destination,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PortForwardRuleCard extends StatelessWidget {
  final OpenwrtPortForward forward;
  final VoidCallback onTap;

  const _PortForwardRuleCard({required this.forward, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = forward.enabled
        ? const Color(0xFF20CF70)
        : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                Expanded(
                  child: Text(
                    forward.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                _RuleBadge(
                  label: forward.enabled ? 'ENABLED' : 'DISABLED',
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${forward.source.toUpperCase()} :${forward.wanPort}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${forward.destinationIp}:${forward.destinationPort}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _RuleBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _RuleBadge({
    required this.label,
    required this.color,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _RuleDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _RuleDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleDetailsSheet extends StatelessWidget {
  final OpenwrtFirewallRule rule;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onDelete;

  const _RuleDetailsSheet({
    required this.rule,
    required this.onToggleEnabled,
    required this.onDelete,
  });

  Color _targetColor(BuildContext context) {
    final action = rule.action.toUpperCase();
    if (action == 'ACCEPT') return const Color(0xFF20CF70);
    if (action == 'REJECT' || action == 'DROP') {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetColor = _targetColor(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rule.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RuleBadge(label: rule.action, color: targetColor),
                _RuleBadge(
                  label: rule.enabled ? 'Enabled' : 'Disabled',
                  color: rule.enabled
                      ? const Color(0xFF20CF70)
                      : colorScheme.onSurfaceVariant,
                  filled: false,
                ),
                if (rule.isOpenwallaRule)
                  _RuleBadge(
                    label: 'Openwalla',
                    color: colorScheme.primary,
                    filled: false,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _RuleDetailRow(label: 'Source', value: rule.source),
                  _RuleDetailRow(label: 'Source IP', value: rule.sourceIp),
                  _RuleDetailRow(label: 'Destination', value: rule.destination),
                  _RuleDetailRow(label: 'Protocol', value: rule.protocol),
                  _RuleDetailRow(label: 'Port', value: rule.port),
                  _RuleDetailRow(label: 'Action', value: rule.action),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onToggleEnabled(!rule.enabled),
                    icon: Icon(
                      rule.enabled
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(rule.enabled ? 'Disable' : 'Enable'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
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

class _PortForwardDetailsSheet extends StatelessWidget {
  final OpenwrtPortForward forward;
  final VoidCallback onDelete;

  const _PortForwardDetailsSheet({
    required this.forward,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = forward.enabled
        ? const Color(0xFF20CF70)
        : colorScheme.onSurfaceVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              forward.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RuleBadge(label: 'PORT FORWARD', color: colorScheme.primary),
                _RuleBadge(
                  label: forward.enabled ? 'Enabled' : 'Disabled',
                  color: statusColor,
                  filled: false,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _RuleDetailRow(label: 'Source Zone', value: forward.source),
                  _RuleDetailRow(
                    label: 'External Port',
                    value: forward.wanPort,
                  ),
                  _RuleDetailRow(label: 'Protocol', value: forward.protocol),
                  _RuleDetailRow(
                    label: 'Destination',
                    value: forward.destinationZone,
                  ),
                  _RuleDetailRow(
                    label: 'Destination IP',
                    value: forward.destinationIp,
                  ),
                  _RuleDetailRow(
                    label: 'Internal Port',
                    value: forward.destinationPort,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Manage this rule from Network > Port Forwarding.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete Port Forward'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(
                    color: colorScheme.error.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
