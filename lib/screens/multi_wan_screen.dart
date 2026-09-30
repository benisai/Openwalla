import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/openwrt_feature_gate.dart';

class MultiWanScreen extends ConsumerStatefulWidget {
  const MultiWanScreen({super.key});

  @override
  ConsumerState<MultiWanScreen> createState() => _MultiWanScreenState();
}

class _MultiWanScreenState extends ConsumerState<MultiWanScreen> {
  Mwan3Snapshot? _snapshot;
  bool _loading = true;
  bool _restarting = false;
  bool _started = false;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(appStateProvider)
          .fetchMwan3Snapshot(context: context);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to read the Multi-WAN configuration.';
        _loading = false;
      });
    }
  }

  Future<void> _restart() async {
    setState(() => _restarting = true);
    try {
      await ref.read(appStateProvider).restartMwan3(context: context);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Multi-WAN service restarted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to restart Multi-WAN: $error')),
      );
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'Multi-WAN', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'WAN Traffic Management',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Monitor mwan3 failover, load balancing, and routing policies.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.mwan3,
                title: 'Multi-WAN is not installed',
                message:
                    'Install mwan3 and the firewall compatibility packages required by this router.',
                installLabel: 'Install Multi-WAN',
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
      return _MessageCard(message: _error!, onRetry: _load);
    }
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ServiceCard(
          running: snapshot.running,
          restarting: _restarting,
          onRestart: _restart,
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'WAN Interfaces',
          count: snapshot.interfaces.length,
        ),
        const SizedBox(height: 10),
        if (snapshot.interfaces.isEmpty)
          const _EmptyCard(
            text: 'No mwan3 interfaces are configured on this router.',
          )
        else
          ...snapshot.interfaces.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InterfaceCard(
                section: item,
                liveStatus: snapshot.liveStatus,
              ),
            ),
          ),
        const SizedBox(height: 8),
        _SectionTitle(title: 'Policies', count: snapshot.policies.length),
        const SizedBox(height: 10),
        if (snapshot.policies.isEmpty)
          const _EmptyCard(text: 'No failover or balancing policies found.')
        else
          ...snapshot.policies.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PolicyCard(section: item),
            ),
          ),
        const SizedBox(height: 8),
        _SectionTitle(title: 'Traffic Rules', count: snapshot.rules.length),
        const SizedBox(height: 10),
        if (snapshot.rules.isEmpty)
          const _EmptyCard(text: 'No custom Multi-WAN traffic rules found.')
        else
          ...snapshot.rules.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RuleCard(section: item),
            ),
          ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final bool running;
  final bool restarting;
  final VoidCallback onRestart;

  const _ServiceCard({
    required this.running,
    required this.restarting,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = running ? const Color(0xFF20CF70) : colors.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.alt_route_rounded, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'mwan3 Service',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    running ? 'Running' : 'Stopped',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: restarting ? null : onRestart,
              icon: restarting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt_rounded),
              label: Text(restarting ? 'Waiting' : 'Restart'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ),
      Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _InterfaceCard extends StatelessWidget {
  final Mwan3Section section;
  final String liveStatus;

  const _InterfaceCard({required this.section, required this.liveStatus});

  @override
  Widget build(BuildContext context) {
    final lowerStatus = liveStatus.toLowerCase();
    final marker = RegExp(
      'interface\\s+${RegExp.escape(section.name.toLowerCase())}\\s+is\\s+(online|offline|unknown)',
    ).firstMatch(lowerStatus);
    final status = marker?.group(1) ?? 'unknown';
    final statusColor = status == 'online'
        ? const Color(0xFF20CF70)
        : status == 'offline'
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return _DataCard(
      icon: Icons.language_rounded,
      iconColor: statusColor,
      title: section.name.toUpperCase(),
      badge: status.toUpperCase(),
      badgeColor: statusColor,
      details: [
        'Tracking: ${section.options['track_method'] ?? 'ping'}',
        'Family: ${section.options['family'] ?? 'ipv4'}',
        if (section.options['track_ip'] case final value?) 'Target: $value',
      ],
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final Mwan3Section section;

  const _PolicyCard({required this.section});

  @override
  Widget build(BuildContext context) => _DataCard(
    icon: Icons.balance_rounded,
    iconColor: const Color(0xFF8B5CF6),
    title: section.name,
    details: [
      if (section.members.isNotEmpty) section.members.join('  •  '),
      'Fallback: ${section.options['last_resort'] ?? 'unreachable'}',
    ],
  );
}

class _RuleCard extends StatelessWidget {
  final Mwan3Section section;

  const _RuleCard({required this.section});

  @override
  Widget build(BuildContext context) => _DataCard(
    icon: Icons.rule_rounded,
    iconColor: const Color(0xFFF27C24),
    title: section.name,
    badge: section.options['use_policy'],
    badgeColor: Theme.of(context).colorScheme.primary,
    details: [
      [
        if ((section.options['src_ip'] ?? '').isNotEmpty)
          'From ${section.options['src_ip']}',
        if ((section.options['dest_ip'] ?? '').isNotEmpty)
          'To ${section.options['dest_ip']}',
        if ((section.options['proto'] ?? '').isNotEmpty)
          section.options['proto']!,
      ].join('  •  '),
    ].where((value) => value.isNotEmpty).toList(),
  );
}

class _DataCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? badge;
  final Color? badgeColor;
  final List<String> details;

  const _DataCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.badge,
    this.badgeColor,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (badge != null && badge!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? colors.primary).withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: badgeColor ?? colors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                    ],
                  ),
                  for (final detail in details.where((item) => item.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MessageCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}
