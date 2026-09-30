import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class RecentEventsScreen extends ConsumerStatefulWidget {
  final bool networkIssuesOnly;

  const RecentEventsScreen({super.key, this.networkIssuesOnly = false});

  @override
  ConsumerState<RecentEventsScreen> createState() => _RecentEventsScreenState();
}

class _RecentEventsScreenState extends ConsumerState<RecentEventsScreen> {
  List<OpenwallaNotification> _events = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEvents());
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final events = await ref
        .read(appStateProvider)
        .fetchNotifications(
          limit: 100,
          includeArchived: true,
          context: context,
        );
    if (!mounted) return;
    setState(() {
      _events = widget.networkIssuesOnly
          ? events.where((event) => event.isNetworkPerformanceEvent).toList()
          : events;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Recent Events', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadEvents,
          child: _isLoading
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: const [
                    SizedBox(height: 180),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : _events.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    SizedBox(
                      height: 260,
                      child: Center(
                        child: Text(
                          'No recent events',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  itemCount: _events.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _RecentEventTile(
                      event: _events[index],
                      isLast: index == _events.length - 1,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _RecentEventTile extends StatelessWidget {
  final OpenwallaNotification event;
  final bool isLast;

  const _RecentEventTile({required this.event, required this.isLast});

  Color _eventColor() {
    return switch (event.effectiveSeverity) {
      'resolved' => const Color(0xFF20CF70),
      'warning' => const Color(0xFFFFB020),
      'critical' => const Color(0xFFFF4D4F),
      _ => const Color(0xFF18AEEA),
    };
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[(local.month - 1).clamp(0, 11)];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$month ${local.day}, ${local.year} $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final eventColor = _eventColor();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: eventColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 1,
                  height: 42,
                  margin: const EdgeInsets.only(top: 4),
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
            ],
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
                        event.displayTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (event.archived) ...[
                      const SizedBox(width: 8),
                      _StatusPill(label: 'Archived', color: colorScheme),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                if (event.displayDetails != event.displayTitle) ...[
                  Text(
                    event.displayDetails,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                Text(
                  _formatTimestamp(event.timestamp),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                if (event.app.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.app,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.68,
                      ),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final ColorScheme color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
