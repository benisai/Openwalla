import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/clients_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';

enum _NotificationMenuAction { archiveAll, deleteAll }

enum _NotificationFilter { all, critical, warning, resolved }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<OpenwallaNotification> _notifications = const [];
  bool _isLoading = true;
  String _query = '';
  _NotificationFilter _filter = _NotificationFilter.all;
  final TextEditingController _searchController = TextEditingController();
  bool _openingDevice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotifications());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final notifications = await appState.fetchNotifications(context: context);
    if (mounted) {
      await appState.markNotificationsSeen(context: context);
    }
    await appState.refreshNotificationCount();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });
  }

  Future<void> _archiveOne(OpenwallaNotification notification) async {
    await ref
        .read(appStateProvider)
        .archiveNotification(notification.id, context: context);
    await _loadNotifications();
  }

  Future<void> _openDevice(OpenwallaNotification notification) async {
    final mac = notification.deviceMacAddress;
    if (mac == null || _openingDevice) return;
    _openingDevice = true;
    try {
      final appState = ref.read(appStateProvider);
      final clients = await appState.fetchClientsForSelectedRouter();
      if (!mounted) return;
      final matches = clients.where(
        (client) => client.macAddress.toUpperCase().replaceAll('-', ':') == mac,
      );
      if (matches.isEmpty) {
        context.showToastWarning('Device no longer found', subtitle: mac);
        return;
      }
      final client = matches.first;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (pageContext) => DeviceDetailsPage(
            client: client,
            onIdentityUpdated:
                ({
                  required hostname,
                  required deviceIcon,
                  required staticIpAddress,
                }) {},
            onToggleInternetPause: (paused) async {
              final success = await appState.pauseClientInternet(
                client.macAddress,
                pause: paused,
              );
              if (!success) {
                throw StateError('Unable to update internet access');
              }
            },
            onToggleInternetBlock: (blocked) async {
              final actionKey = 'notification-device-block-$mac';
              pageContext.showToastLoading(
                blocked ? 'Blocking device...' : 'Releasing device...',
                actionKey: actionKey,
              );
              try {
                await appState.setClientInternetBlocked(client, blocked);
                if (!pageContext.mounted) return;
                pageContext.showToastSuccess(
                  blocked ? 'Device blocked' : 'Device released',
                  actionKey: actionKey,
                );
              } catch (error) {
                if (pageContext.mounted) {
                  pageContext.showToastError(
                    'Device access could not be updated',
                    subtitle: error.toString().replaceFirst('Bad state: ', ''),
                    actionKey: actionKey,
                  );
                }
                rethrow;
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      context.showToastError(
        'Could not open device',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      _openingDevice = false;
    }
  }

  Future<void> _archiveAll() async {
    await ref.read(appStateProvider).archiveAllNotifications(context: context);
    await _loadNotifications();
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all notifications?'),
        content: const Text(
          'This will remove all active and archived notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(appStateProvider).deleteAllNotifications(context: context);
    await _loadNotifications();
  }

  Future<void> _handleMenuAction(_NotificationMenuAction action) async {
    switch (action) {
      case _NotificationMenuAction.archiveAll:
        await _archiveAll();
      case _NotificationMenuAction.deleteAll:
        await _deleteAll();
    }
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
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month ${local.day.toString().padLeft(2, '0')}, ${local.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final filtered = _notifications.where((notification) {
      final matchesFilter =
          _filter == _NotificationFilter.all ||
          notification.effectiveSeverity == _filter.name;
      final matchesQuery =
          query.isEmpty ||
          notification.displayTitle.toLowerCase().contains(query) ||
          notification.displayDetails.toLowerCase().contains(query) ||
          notification.app.toLowerCase().contains(query);
      return matchesFilter && matchesQuery;
    }).toList();

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Notifications',
        showBack: true,
        actions: [
          PopupMenuButton<_NotificationFilter>(
            initialValue: _filter,
            tooltip: 'Filter notifications',
            onSelected: (filter) => setState(() => _filter = filter),
            icon: Icon(
              Icons.filter_list_rounded,
              color: _filter == _NotificationFilter.all
                  ? colorScheme.onSurface
                  : colorScheme.primary,
            ),
            itemBuilder: (context) => _NotificationFilter.values.map((filter) {
              final (label, icon) = switch (filter) {
                _NotificationFilter.all => ('All', Icons.notifications_rounded),
                _NotificationFilter.critical => (
                  'Critical',
                  Icons.error_rounded,
                ),
                _NotificationFilter.warning => (
                  'Warnings',
                  Icons.warning_amber_rounded,
                ),
                _NotificationFilter.resolved => (
                  'Resolved',
                  Icons.check_circle_rounded,
                ),
              };
              return PopupMenuItem<_NotificationFilter>(
                value: filter,
                child: Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label)),
                    if (_filter == filter) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<_NotificationMenuAction>(
              onSelected: _handleMenuAction,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: colorScheme.onSurface,
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _NotificationMenuAction.archiveAll,
                  child: Text('Archive All'),
                ),
                PopupMenuItem(
                  value: _NotificationMenuAction.deleteAll,
                  child: Text('Delete All'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          child: _isLoading
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: const [
                    SizedBox(height: 180),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Search events',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Recent Events',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        Text(
                          '${filtered.length}',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (filtered.isEmpty)
                      Container(
                        height: 180,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.42,
                            ),
                          ),
                        ),
                        child: Text(
                          _notifications.isEmpty
                              ? 'No active events'
                              : 'No matching events',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      )
                    else
                      ...List.generate(filtered.length, (index) {
                        final notification = filtered[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == filtered.length - 1 ? 0 : 10,
                          ),
                          child: _NotificationCard(
                            notification: notification,
                            timestamp: _formatTimestamp(notification.timestamp),
                            onArchive: () => _archiveOne(notification),
                            onTap: notification.deviceMacAddress == null
                                ? null
                                : () => _openDevice(notification),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final OpenwallaNotification notification;
  final String timestamp;
  final VoidCallback onArchive;
  final VoidCallback? onTap;

  const _NotificationCard({
    required this.notification,
    required this.timestamp,
    required this.onArchive,
    this.onTap,
  });

  Color _notificationColor() {
    if (notification.isQuarantineEvent) return const Color(0xFFFF8FB3);
    return switch (notification.effectiveSeverity) {
      'critical' => const Color(0xFFFF424B),
      'warning' => const Color(0xFFFFB020),
      'resolved' => const Color(0xFF20CF70),
      _ => const Color(0xFF18AEEA),
    };
  }

  IconData _notificationIcon() {
    if (notification.effectiveCategory == 'network_health') {
      return notification.effectiveSeverity == 'resolved'
          ? Icons.wifi_rounded
          : Icons.wifi_off_rounded;
    }
    if (notification.effectiveCategory == 'device') {
      return Icons.devices_rounded;
    }
    if (notification.effectiveCategory == 'interface') {
      return Icons.settings_ethernet_rounded;
    }
    if (notification.effectiveCategory == 'vpn') {
      return Icons.vpn_key_rounded;
    }
    return Icons.notifications_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final accent = _notificationColor();
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: notification.isQuarantineEvent
                  ? accent.withValues(alpha: 0.55)
                  : colorScheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_notificationIcon(), color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.displayTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.displayDetails,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          timestamp,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.72,
                                ),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        Text(
                          notification.app.replaceAll('-', ' ').toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Archive',
                onPressed: onArchive,
                icon: Icon(Icons.close_rounded, color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
