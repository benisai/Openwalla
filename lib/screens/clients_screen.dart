import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/flows_screen.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_loading_states.dart';
import 'package:openwalla/widgets/openwalla_toast.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/widgets/luci_refresh_components.dart';
import 'package:openwalla/utils/self_device_guard.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

enum ClientFilter { online, blocked, offline }

enum _DeviceSort { hostname, ipAddress }

enum _DeviceRemovalAction { hide, delete }

class _DeviceIconOption {
  final String key;
  final String label;
  final IconData icon;

  const _DeviceIconOption(this.key, this.label, this.icon);
}

const List<_DeviceIconOption> _deviceIconOptions = [
  _DeviceIconOption('device', 'Device', Icons.devices_other_rounded),
  _DeviceIconOption('phone', 'Phone', Icons.phone_android_rounded),
  _DeviceIconOption('laptop', 'Laptop', Icons.laptop_mac_rounded),
  _DeviceIconOption('desktop', 'Desktop', Icons.desktop_windows_rounded),
  _DeviceIconOption('tablet', 'Tablet', Icons.tablet_mac_rounded),
  _DeviceIconOption('tv', 'TV', Icons.tv_rounded),
  _DeviceIconOption('camera', 'Camera', Icons.videocam_rounded),
  _DeviceIconOption('speaker', 'Speaker', Icons.speaker_rounded),
  _DeviceIconOption('game', 'Game', Icons.sports_esports_rounded),
  _DeviceIconOption('router', 'Router', Icons.router_rounded),
  _DeviceIconOption('plug', 'Plug', Icons.power_rounded),
  _DeviceIconOption('watch', 'Watch', Icons.watch_rounded),
];

_DeviceIconOption _deviceIconOptionFor(String? key) {
  final normalized = key?.trim();
  if (normalized == null || normalized.isEmpty) return _deviceIconOptions.first;
  return _deviceIconOptions.firstWhere(
    (option) => option.key == normalized,
    orElse: () => _deviceIconOptions.first,
  );
}

IconData _clientIconData(Client client) {
  if (client.deviceIcon?.trim().isNotEmpty == true) {
    return _deviceIconOptionFor(client.deviceIcon).icon;
  }
  if (client.isBlocked) return Icons.block_rounded;
  if (client.isOffline) return Icons.cloud_off_rounded;
  if (client.connectionType == ConnectionType.wireless) {
    return Icons.wifi_rounded;
  }
  if (client.connectionType == ConnectionType.wired) {
    return Icons.settings_ethernet;
  }
  return Icons.devices_other_rounded;
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _searchQuery = '';
  _DeviceSort _deviceSort = _DeviceSort.hostname;
  ClientFilter _currentFilter = ClientFilter.online;
  late TextEditingController _searchController;
  bool _aggregateAllRouters = true;
  Future<List<Client>>? _clientsFuture;
  String? _lastSelectedRouterId;
  String? _activeClientCacheKey;
  List<Client> _visibleClients = const [];
  final Set<String> _blockingMacs = {};
  bool _isRefreshingClients = false;
  static final Map<String, List<Client>> _clientCache = {};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
    // Initialize toggle from persisted state
    final initState = ref.read(appStateProvider);
    _aggregateAllRouters = initState.clientsAggregateAllRouters;
    _lastSelectedRouterId = initState.selectedRouter?.id;
    _computeClientsFuture();
  }

  void _computeClientsFuture() {
    final appState = ref.read(appStateProvider);
    final cacheKey = _clientCacheKey(appState);
    _activeClientCacheKey = cacheKey;
    _visibleClients = _clientCache[cacheKey] ?? const [];
    _clientsFuture = _loadClients(cacheKey);
  }

  String _clientCacheKey(dynamic appState) {
    if (_aggregateAllRouters) return 'aggregate';
    return appState.selectedRouter?.id?.toString() ?? 'selected:none';
  }

  Future<List<Client>> _loadClients(String cacheKey) async {
    final appState = ref.read(appStateProvider);
    final clients = _aggregateAllRouters
        ? await appState.fetchAggregatedClients()
        : await appState.fetchClientsForSelectedRouter();
    _clientCache[cacheKey] = clients;
    if (mounted && _activeClientCacheKey == cacheKey) {
      setState(() {
        _visibleClients = clients;
      });
    }
    return clients;
  }

  Future<void> _refreshClients() async {
    if (_isRefreshingClients) return;
    setState(() => _isRefreshingClients = true);
    try {
      final appState = ref.read(appStateProvider);
      if (!_aggregateAllRouters) {
        await appState.refreshOpenwallaDeviceInventory(context: context);
      }
      await appState.fetchDashboardData();
      if (!mounted) return;
      setState(() {
        _computeClientsFuture();
      });
      await _clientsFuture;
    } finally {
      if (mounted) {
        setState(() => _isRefreshingClients = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchedAppState = ref.watch(appStateProvider);
    // Recompute future only when selected router changes
    Future<List<Client>>? future = _clientsFuture;
    final currentId = watchedAppState.selectedRouter?.id;
    if (currentId != _lastSelectedRouterId) {
      _lastSelectedRouterId = currentId;
      _computeClientsFuture();
      future = _clientsFuture;
    }
    return FutureBuilder<List<Client>>(
      future: future,
      builder: (context, snapshot) {
        final aggregatedClients = snapshot.data ?? _visibleClients;
        return Scaffold(
          appBar: LuciAppBar(
            title: 'Devices',
            showBack: true,
            actions: [
              PopupMenuButton<_DeviceSort>(
                tooltip: 'Sort devices',
                initialValue: _deviceSort,
                onSelected: (sort) => setState(() => _deviceSort = sort),
                icon: const Icon(Icons.sort_rounded),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.65),
                  ),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _DeviceSort.hostname,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sort_by_alpha_rounded),
                      title: Text('Name'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _DeviceSort.ipAddress,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.lan_rounded),
                      title: Text('IP address'),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  tooltip: 'Refresh devices',
                  onPressed: _isRefreshingClients ? null : _refreshClients,
                  icon: _isRefreshingClients
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Builder(
                builder: (context) {
                  final appState = ref.watch(appStateProvider);
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting &&
                      (aggregatedClients.isEmpty);
                  final dashboardError = appState.dashboardError;

                  if (isLoading) {
                    return SafeArea(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: LuciSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: LuciSpacing.lg),
                            LuciSkeleton(
                              width: 230,
                              height: 34,
                              borderRadius: BorderRadius.circular(
                                LuciSpacing.sm,
                              ),
                            ),
                            SizedBox(height: LuciSpacing.sm),
                            LuciSkeleton(
                              width: 210,
                              height: 18,
                              borderRadius: BorderRadius.circular(
                                LuciSpacing.xs,
                              ),
                            ),
                            SizedBox(height: LuciSpacing.lg),
                            LuciSkeleton(
                              width: double.infinity,
                              height: 56,
                              borderRadius: BorderRadius.circular(
                                LuciSpacing.sm,
                              ),
                            ),
                            SizedBox(height: LuciSpacing.md),
                            Row(
                              children: List.generate(
                                3,
                                (index) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: index == 2 ? 0 : LuciSpacing.md,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: LuciSkeleton(
                                        width: double.infinity,
                                        height: double.infinity,
                                        borderRadius: BorderRadius.circular(
                                          LuciSpacing.sm,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: LuciSpacing.md),
                            Expanded(
                              child: ListView.separated(
                                itemCount: 6,
                                separatorBuilder: (context, index) =>
                                    SizedBox(height: LuciSpacing.sm),
                                itemBuilder: (context, index) =>
                                    LuciListItemSkeleton(
                                      showLeading: true,
                                      showTrailing: true,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (dashboardError != null && aggregatedClients.isEmpty) {
                    return LuciErrorDisplay(
                      title: 'Failed to Load Clients',
                      message:
                          'Could not connect to the router. Please check your network connection and the router\'s IP address.',
                      actionLabel: 'Retry',
                      onAction: () => ref
                          .read(appStateProvider)
                          .retryDashboardConnection(context: context),
                      icon: Icons.wifi_off_rounded,
                    );
                  }

                  final clients = aggregatedClients;
                  final blockedClients = clients
                      .where((client) => client.isBlocked)
                      .toList();
                  final offlineClients = clients
                      .where((client) => !client.isBlocked && client.isOffline)
                      .toList();
                  final onlineClients = clients
                      .where((client) => !client.isBlocked && !client.isOffline)
                      .toList();

                  final blockedCount = blockedClients.length;
                  final offlineCount = offlineClients.length;
                  final onlineCount = onlineClients.length;

                  final activeCategoryClients = switch (_currentFilter) {
                    ClientFilter.online => onlineClients,
                    ClientFilter.blocked => blockedClients,
                    ClientFilter.offline => offlineClients,
                  };

                  final filteredClients = activeCategoryClients.where((client) {
                    final query = _searchQuery.toLowerCase();
                    if (query.isEmpty) return true;
                    return client.hostname.toLowerCase().contains(query) ||
                        client.ipAddress.toLowerCase().contains(query) ||
                        client.macAddress.toLowerCase().contains(query) ||
                        (client.vendor?.toLowerCase().contains(query) ??
                            false) ||
                        (client.dnsName?.toLowerCase().contains(query) ??
                            false);
                  }).toList()..sort(_compareClients);

                  String emptyTitle;
                  String emptyMessage;
                  IconData emptyIcon;

                  if (_searchQuery.isNotEmpty) {
                    emptyTitle = 'No Matching Clients';
                    emptyMessage =
                        'No clients match your search criteria. Try a different search term.';
                    emptyIcon = Icons.search_off_rounded;
                  } else {
                    switch (_currentFilter) {
                      case ClientFilter.online:
                        emptyTitle = 'No Online Clients Found';
                        emptyMessage =
                            'No clients are currently connected to the router. Pull down to refresh the list.';
                        emptyIcon = Icons.wifi_off_rounded;
                        break;
                      case ClientFilter.blocked:
                        emptyTitle = 'No Blocked Clients';
                        emptyMessage =
                            'No devices are currently blocked from accessing the internet.';
                        emptyIcon = Icons.shield_outlined;
                        break;
                      case ClientFilter.offline:
                        emptyTitle = 'No Offline Clients';
                        emptyMessage =
                            'No offline clients found in recent device history.';
                        emptyIcon = Icons.cloud_off_outlined;
                        break;
                    }
                  }

                  final stats = SafeArea(
                    top: false,
                    bottom: false,
                    child: _buildClientStats(
                      context,
                      onlineCount: onlineCount,
                      blockedCount: blockedCount,
                      offlineCount: offlineCount,
                      currentFilter: _currentFilter,
                      onFilterChanged: (filter) {
                        setState(() {
                          _currentFilter = filter;
                        });
                      },
                    ),
                  );

                  return Column(
                    children: [
                      SafeArea(
                        top: false,
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                          child: _buildSearchField(context),
                        ),
                      ),
                      Expanded(
                        child: LuciPullToRefresh(
                          onRefresh: _refreshClients,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 16),
                            children: [
                              stats,
                              if (filteredClients.isEmpty)
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.45,
                                  child: LuciEmptyState(
                                    title: emptyTitle,
                                    message: emptyMessage,
                                    icon: emptyIcon,
                                  ),
                                )
                              else
                                for (final client in filteredClients)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      12,
                                    ),
                                    child: _UnifiedClientCard(
                                      client: client,
                                      isPaused: appState.isInternetPaused(
                                        client.macAddress,
                                      ),
                                      onOpenSettings: () =>
                                          _showDeviceSettingsSheet(client),
                                      onLongPress: () =>
                                          _showDeleteDeviceSheet(client),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String normalizeMac(String mac) => mac.toUpperCase().replaceAll('-', ':');

  Widget _buildClientStats(
    BuildContext context, {
    required int onlineCount,
    required int blockedCount,
    required int offlineCount,
    required ClientFilter currentFilter,
    required ValueChanged<ClientFilter> onFilterChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _buildClientStatCard(
              context,
              icon: Icons.wifi_rounded,
              count: onlineCount,
              label: 'Online',
              color: const Color(0xFF22C55E),
              isSelected: currentFilter == ClientFilter.online,
              onTap: () => onFilterChanged(ClientFilter.online),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildClientStatCard(
              context,
              icon: Icons.block_rounded,
              count: blockedCount,
              label: 'Blocked',
              color: const Color(0xFFFF4D5A),
              isSelected: currentFilter == ClientFilter.blocked,
              onTap: () => onFilterChanged(ClientFilter.blocked),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildClientStatCard(
              context,
              icon: Icons.cloud_off_outlined,
              count: offlineCount,
              label: 'Offline',
              color: colorScheme.onSurfaceVariant,
              isSelected: currentFilter == ClientFilter.offline,
              onTap: () => onFilterChanged(ClientFilter.offline),
            ),
          ),
        ],
      ),
    );
  }

  int _compareClients(Client left, Client right) {
    final result = switch (_deviceSort) {
      _DeviceSort.hostname => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
      _DeviceSort.ipAddress => _ipv4SortValue(
        left.ipAddress,
      ).compareTo(_ipv4SortValue(right.ipAddress)),
    };
    if (result != 0) return result;
    return left.macAddress.compareTo(right.macAddress);
  }

  int _ipv4SortValue(String address) {
    final octets = address.trim().split('.');
    if (octets.length != 4) return 0x100000000;
    var value = 0;
    for (final octet in octets) {
      final parsed = int.tryParse(octet);
      if (parsed == null || parsed < 0 || parsed > 255) return 0x100000000;
      value = (value << 8) | parsed;
    }
    return value;
  }

  Widget _buildSearchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      autofocus: false,
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name, IP, or MAC',
        prefixIcon: const Icon(Icons.search_rounded, size: 28),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                  });
                },
                tooltip: 'Clear search',
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }

  String _normalizeMac(String mac) =>
      mac.trim().toUpperCase().replaceAll('-', ':');

  void _applyCachedClientBlockState(String mac, bool blocked) {
    Client updateClient(Client client) {
      if (_normalizeMac(client.macAddress) != mac) return client;
      return client.copyWith(
        isBlocked: blocked,
        isQuarantined: blocked ? client.isQuarantined : false,
        status: blocked ? 'blocked' : 'online',
      );
    }

    _visibleClients = _visibleClients.map(updateClient).toList();
    for (final entry in _clientCache.entries.toList()) {
      _clientCache[entry.key] = entry.value.map(updateClient).toList();
    }
  }

  void _applyCachedClientIdentity(
    String mac, {
    required String hostname,
    required String deviceIcon,
    required String staticIpAddress,
  }) {
    final normalizedMac = _normalizeMac(mac);
    Client updateClient(Client client) {
      if (_normalizeMac(client.macAddress) != normalizedMac) return client;
      return client.copyWith(
        hostname: hostname,
        deviceIcon: deviceIcon,
        staticIpAddress: staticIpAddress,
      );
    }

    setState(() {
      _visibleClients = _visibleClients.map(updateClient).toList();
      for (final entry in _clientCache.entries.toList()) {
        _clientCache[entry.key] = entry.value.map(updateClient).toList();
      }
      _clientsFuture = Future.value(_visibleClients);
    });
  }

  Future<void> _setClientInternetBlocked(Client client, bool blocked) async {
    final mac = _normalizeMac(client.macAddress);
    if (mac.isEmpty || mac == 'N/A') return;
    final wasQuarantined = client.isQuarantined;

    setState(() {
      _blockingMacs.add(mac);
      _applyCachedClientBlockState(mac, blocked);
      _clientsFuture = Future.value(_visibleClients);
    });
    if (!blocked) {
      ref.read(appStateProvider).queueClientInternetUnblock(client);
      if (!mounted) return;
      setState(() => _blockingMacs.remove(mac));
      context.showToastSuccess(
        wasQuarantined ? 'Device unquarantined' : 'Device unblocked',
        subtitle: client.displayName,
        actionKey: 'client-block-$mac',
      );
      return;
    }
    context.showToastLoading(
      'Blocking device...',
      subtitle: client.displayName,
      actionKey: 'client-block-$mac',
    );

    try {
      await ref
          .read(appStateProvider)
          .setClientInternetBlocked(client, blocked);
      if (!mounted) return;
      context.showToastSuccess(
        'Internet access blocked',
        subtitle: client.displayName,
        actionKey: 'client-block-$mac',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyCachedClientBlockState(mac, !blocked);
        _clientsFuture = Future.value(_visibleClients);
      });
      context.showToastError(
        'Device access could not be updated',
        subtitle: e.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'client-block-$mac',
      );
    } finally {
      if (mounted) {
        setState(() {
          _blockingMacs.remove(mac);
        });
      }
    }
  }

  Future<void> _showDeviceSettingsSheet(Client client) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DeviceSettingsSheet(
        client: client,
        onIdentityUpdated:
            ({
              required hostname,
              required deviceIcon,
              required staticIpAddress,
            }) {
              if (!mounted) return;
              _applyCachedClientIdentity(
                client.macAddress,
                hostname: hostname,
                deviceIcon: deviceIcon,
                staticIpAddress: staticIpAddress,
              );
            },
        onToggleInternetPause: (paused) async {
          final success = await ref
              .read(appStateProvider)
              .pauseClientInternet(
                client.macAddress,
                pause: paused,
                context: context,
              );
          if (!success) throw StateError('Unable to update internet access');
        },
        onToggleInternetBlock: (blocked) =>
            _setClientInternetBlocked(client, blocked),
      ),
    );
  }

  Future<void> _showDeleteDeviceSheet(Client client) async {
    final action = await showModalBottomSheet<_DeviceRemovalAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: colors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remove ${client.displayName}?',
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          client.macAddress,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Hide keeps DHCP settings but exempts this MAC from Devices and Quarantine detection. Delete removes its Openwalla record and OpenWrt DHCP entry.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(
                        sheetContext,
                      ).pop(_DeviceRemovalAction.hide),
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: const Text('Hide'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(
                        sheetContext,
                      ).pop(_DeviceRemovalAction.delete),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    try {
      if (action == _DeviceRemovalAction.hide) {
        await ref.read(appStateProvider).hideOpenwallaDeviceRecord(client);
      } else {
        await ref
            .read(appStateProvider)
            .deleteOpenwallaDeviceRecord(client, context: context);
      }
      if (!mounted) return;
      final normalizedMac = client.macAddress.toUpperCase().replaceAll(
        '-',
        ':',
      );
      setState(() {
        for (final entry in _clientCache.entries) {
          entry.value.removeWhere(
            (cached) =>
                cached.macAddress.toUpperCase().replaceAll('-', ':') ==
                normalizedMac,
          );
        }
        _visibleClients = _visibleClients
            .where(
              (cached) =>
                  cached.macAddress.toUpperCase().replaceAll('-', ':') !=
                  normalizedMac,
            )
            .toList();
        _clientsFuture = Future.value(_visibleClients);
      });
      context.showToastSuccess(
        action == _DeviceRemovalAction.hide
            ? 'Device hidden'
            : 'Device removed',
        subtitle: client.displayName,
        actionKey: 'remove-device-$normalizedMac',
      );
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        action == _DeviceRemovalAction.hide
            ? 'Device could not be hidden'
            : 'Device could not be removed',
        subtitle: e.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'remove-device-${_normalizeMac(client.macAddress)}',
      );
    }
  }

  Widget _buildClientStatCard(
    BuildContext context, {
    required IconData icon,
    required int count,
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1.08,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.34,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.24),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: color, size: 22),
                    if (isSelected)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    height: 1.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceSettingsSheet extends ConsumerStatefulWidget {
  final Client client;
  final void Function({
    required String hostname,
    required String deviceIcon,
    required String staticIpAddress,
  })
  onIdentityUpdated;
  final Future<void> Function(bool paused) onToggleInternetPause;
  final Future<void> Function(bool blocked) onToggleInternetBlock;

  const _DeviceSettingsSheet({
    required this.client,
    required this.onIdentityUpdated,
    required this.onToggleInternetPause,
    required this.onToggleInternetBlock,
  });

  @override
  ConsumerState<_DeviceSettingsSheet> createState() =>
      _DeviceSettingsSheetState();
}

class _DeviceSettingsSheetState extends ConsumerState<_DeviceSettingsSheet> {
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _nameFocusNode = FocusNode();
  bool _staticIpEnabled = false;
  String _selectedIconKey = 'device';
  late final String _initialName;
  late String _savedName;
  late String _savedIconKey;
  late String _currentStaticIp;
  late bool _isBlocked;
  late bool _isQuarantined;
  late bool _isPaused;
  bool _isEditingName = false;
  bool _isSaving = false;
  bool _isSavingName = false;
  bool _isBlocking = false;
  bool _isPausing = false;
  bool _hasSavedChanges = false;
  bool _netifyFlowsEnabled = false;
  int _deviceFlowCount = 0;

  @override
  void initState() {
    super.initState();
    _initialName = widget.client.hostname;
    _nameController.text = _initialName;
    _ipController.text = widget.client.staticIpAddress?.isNotEmpty == true
        ? widget.client.staticIpAddress!
        : widget.client.ipAddress == 'N/A'
        ? ''
        : widget.client.ipAddress;
    _staticIpEnabled = widget.client.staticIpAddress?.isNotEmpty == true;
    _currentStaticIp = _staticIpEnabled ? _ipController.text.trim() : '';
    _isBlocked = widget.client.isBlocked;
    _isQuarantined = widget.client.isQuarantined;
    _isPaused = ref
        .read(appStateProvider)
        .isInternetPaused(widget.client.macAddress);
    _selectedIconKey = widget.client.deviceIcon?.trim().isNotEmpty == true
        ? widget.client.deviceIcon!.trim()
        : 'device';
    _savedName = _initialName;
    _savedIconKey = _selectedIconKey;
    _nameController.addListener(_handleNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceFlows());
  }

  Future<void> _loadDeviceFlows() async {
    final appState = ref.read(appStateProvider);
    final provider = await appState.detectFlowProvider(context: context);
    if (!mounted) return;
    final enabled = provider == OpenwallaFlowProvider.netify;
    final count = enabled
        ? await appState.fetchNetifyFlowCount(
            deviceMac: widget.client.macAddress,
            hoursBack: 24,
            context: context,
          )
        : 0;
    if (!mounted) return;
    setState(() {
      _netifyFlowsEnabled = enabled;
      _deviceFlowCount = count;
    });
  }

  void _openDeviceFlows() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlowsScreen(
          deviceMac: widget.client.macAddress,
          deviceName: _nameController.text.trim(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    _ipController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  bool get _identityDirty =>
      _nameController.text.trim() != _savedName ||
      _selectedIconKey != _savedIconKey;

  void _handleNameChanged() {
    if (mounted) setState(() {});
  }

  void _editName() {
    setState(() => _isEditingName = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_nameFocusNode.hasFocus) _nameFocusNode.requestFocus();
    });
  }

  Future<bool> _saveNameOnly() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Device name is required.');
      return false;
    }

    final previousName = _savedName;
    final previousIconKey = _savedIconKey;
    setState(() => _isSavingName = true);
    widget.onIdentityUpdated(
      hostname: name,
      deviceIcon: _selectedIconKey,
      staticIpAddress: _currentStaticIp,
    );
    try {
      await ref
          .read(appStateProvider)
          .saveClientDeviceIdentity(
            widget.client,
            hostname: name,
            deviceIcon: _selectedIconKey,
            context: context,
          );
      if (!mounted) return false;
      setState(() {
        _savedName = name;
        _savedIconKey = _selectedIconKey;
        _isEditingName = false;
        _isSavingName = false;
        _hasSavedChanges = true;
      });
      widget.onIdentityUpdated(
        hostname: name,
        deviceIcon: _selectedIconKey,
        staticIpAddress: _currentStaticIp,
      );
      context.showToastSuccess(
        'Device name saved',
        actionKey: 'device-name-${widget.client.macAddress}',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      widget.onIdentityUpdated(
        hostname: previousName,
        deviceIcon: previousIconKey,
        staticIpAddress: _currentStaticIp,
      );
      _showError('Failed to save device name: $e');
      setState(() => _isSavingName = false);
      return false;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Device name is required.');
      return;
    }

    if (_identityDirty) {
      final saved = await _saveNameOnly();
      if (mounted && saved) Navigator.of(context).pop(true);
      return;
    }

    Navigator.of(context).pop(_hasSavedChanges);
  }

  Future<void> _showStaticIpDialog() async {
    final result = await showDialog<_StaticIpDialogResult>(
      context: context,
      builder: (context) => _StaticIpDialog(
        initialIpAddress: _staticIpEnabled
            ? _currentStaticIp
            : widget.client.ipAddress == 'N/A'
            ? ''
            : widget.client.ipAddress,
        hasReservation: _staticIpEnabled,
      ),
    );
    if (result == null || !mounted) return;

    final nextStaticIp = result.enabled ? result.ipAddress.trim() : '';
    if (result.enabled && nextStaticIp.isEmpty) {
      _showError('Static IP address is required.');
      return;
    }

    final previousStaticIpEnabled = _staticIpEnabled;
    final previousStaticIp = _currentStaticIp;
    final previousIpText = _ipController.text;
    final deviceName = _nameController.text.trim().isEmpty
        ? widget.client.hostname
        : _nameController.text.trim();
    final toastKey = 'static-ip-${widget.client.macAddress}';
    setState(() {
      _staticIpEnabled = result.enabled;
      _currentStaticIp = nextStaticIp;
      _ipController.text = nextStaticIp.isNotEmpty
          ? nextStaticIp
          : widget.client.ipAddress == 'N/A'
          ? ''
          : widget.client.ipAddress;
      _isSaving = true;
    });
    OpenwallaToast.showLoading(
      context,
      key: toastKey,
      message: result.enabled
          ? 'Creating static lease for $deviceName...'
          : 'Removing static lease for $deviceName...',
    );
    try {
      await ref
          .read(appStateProvider)
          .saveClientStaticIpReservation(
            widget.client,
            staticIpEnabled: result.enabled,
            staticIpAddress: nextStaticIp,
            hostname: deviceName,
            context: context,
          );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _hasSavedChanges = true;
      });
      widget.onIdentityUpdated(
        hostname: deviceName,
        deviceIcon: _selectedIconKey,
        staticIpAddress: nextStaticIp,
      );
      OpenwallaToast.showSuccess(
        context,
        key: toastKey,
        message: result.enabled
            ? 'Static lease reserved: $deviceName ($nextStaticIp)'
            : 'Static lease removed for $deviceName',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _staticIpEnabled = previousStaticIpEnabled;
        _currentStaticIp = previousStaticIp;
        _ipController.text = previousIpText;
        _isSaving = false;
      });
      OpenwallaToast.showError(
        context,
        key: toastKey,
        message: 'Failed to update static IP. Please try again.',
      );
    }
  }

  Future<void> _toggleInternetBlock() async {
    final nextBlocked = !_isBlocked;
    final wasQuarantined = _isQuarantined;
    if (nextBlocked) {
      final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
        context,
        actionName: 'Block device',
        targetMac: widget.client.macAddress,
        targetIp: widget.client.ipAddress,
        targetHostname: widget.client.displayName,
      );
      if (!safe || !mounted) return;
    }
    setState(() {
      _isBlocked = nextBlocked;
      if (!nextBlocked) _isQuarantined = false;
      _isBlocking = true;
    });
    try {
      await widget.onToggleInternetBlock(nextBlocked);
      if (!mounted) return;
      setState(() {
        _isBlocking = false;
        _hasSavedChanges = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isBlocked = !nextBlocked;
        _isQuarantined = wasQuarantined;
        _isBlocking = false;
      });
    }
  }

  Future<void> _toggleInternetPause() async {
    final nextPaused = !_isPaused;
    if (nextPaused) {
      final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
        context,
        actionName: 'Pause internet access',
        targetMac: widget.client.macAddress,
        targetIp: widget.client.ipAddress,
        targetHostname: widget.client.displayName,
      );
      if (!safe || !mounted) return;
    }
    setState(() {
      _isPaused = nextPaused;
      _isPausing = true;
    });
    final actionKey = 'device-pause-${widget.client.macAddress}';
    context.showToastLoading(
      nextPaused
          ? 'Pausing internet access...'
          : 'Restoring internet access...',
      subtitle: widget.client.displayName,
      actionKey: actionKey,
    );
    try {
      await widget.onToggleInternetPause(nextPaused);
      if (!mounted) return;
      setState(() {
        _isPausing = false;
        _hasSavedChanges = true;
      });
      context.showToastSuccess(
        nextPaused ? 'Internet access paused' : 'Internet access restored',
        subtitle: widget.client.displayName,
        actionKey: actionKey,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPaused = !nextPaused;
        _isPausing = false;
      });
      context.showToastError(
        'Internet access could not be updated',
        subtitle: e.toString().replaceFirst('Bad state: ', ''),
        actionKey: actionKey,
      );
    }
  }

  void _showError(String message) {
    context.showToastError(
      'Unable to update device',
      subtitle: message.replaceFirst('Bad state: ', ''),
      actionKey: 'device-settings-${widget.client.macAddress}',
    );
  }

  Future<void> _pickIcon() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Icon',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _deviceIconOptions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemBuilder: (context, index) {
                    final option = _deviceIconOptions[index];
                    final isSelected = option.key == _selectedIconKey;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(option.key),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: 0.16)
                              : colorScheme.surfaceContainerHighest.withValues(
                                  alpha: 0.28,
                                ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.72)
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.28,
                                  ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              option.icon,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              option.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedIconKey = selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedIcon = _deviceIconOptionFor(_selectedIconKey).icon;
    final isIdentityBusy =
        _isSaving || _isSavingName || _isBlocking || _isPausing;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: isIdentityBusy ? null : _pickIcon,
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            selectedIcon,
                            color: colorScheme.primary,
                            size: 30,
                          ),
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 13,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          enabled: !_isSaving && !_isSavingName,
                          readOnly: !_isEditingName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                            hintText: 'Device name',
                            suffixIcon: IconButton(
                              tooltip: _identityDirty
                                  ? 'Save device name'
                                  : 'Edit device name',
                              onPressed: isIdentityBusy
                                  ? null
                                  : _identityDirty
                                  ? _saveNameOnly
                                  : _editName,
                              icon: _isSavingName
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _identityDirty
                                          ? Icons.save_rounded
                                          : Icons.edit_rounded,
                                    ),
                            ),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (_identityDirty && !isIdentityBusy) {
                              unawaited(_saveNameOnly());
                            }
                          },
                        ),
                        if (widget.client.connectionType ==
                            ConnectionType.wireless)
                          _DeviceWirelessIdentity(client: widget.client),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: isIdentityBusy
                        ? null
                        : () => Navigator.of(context).pop(_hasSavedChanges),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DeviceUsagePanel(client: widget.client),
              if (_netifyFlowsEnabled) ...[
                const SizedBox(height: 12),
                _DeviceNetifyPanel(
                  flowCount: _deviceFlowCount,
                  onTap: _openDeviceFlows,
                ),
              ],
              _ActiveScheduleNotice(client: widget.client),
              const SizedBox(height: 22),
              _DeviceAddressRow(
                label: _staticIpEnabled ? 'IP Address (Static)' : 'IP Address',
                value: _currentStaticIp.isNotEmpty
                    ? _currentStaticIp
                    : widget.client.ipAddress,
                isPinned: _staticIpEnabled,
                isBusy: _isSaving,
                onPinTap: _showStaticIpDialog,
              ),
              const SizedBox(height: 18),
              Text(
                'MAC Address',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: widget.client.macAddress,
                enabled: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.memory_rounded),
                  hintText: 'MAC address',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildPauseButton(context)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildBlockButton(context)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: isIdentityBusy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _identityDirty
                        ? colorScheme.primary.withValues(alpha: 0.24)
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: _identityDirty
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_isSaving ? 'Saving' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockButton(BuildContext context) {
    const unblockColor = Color(0xFF34C759);
    const blockColor = Color(0xFFFFB800);
    final color = _isBlocked ? unblockColor : blockColor;
    return OutlinedButton.icon(
      onPressed: (_isSaving || _isBlocking || _isPausing)
          ? null
          : _toggleInternetBlock,
      icon: _isBlocking
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color.withValues(alpha: 0.9),
              ),
            )
          : Icon(_isBlocked ? Icons.lock_open_rounded : Icons.block_rounded),
      label: Text(
        _isBlocking
            ? 'Wait'
            : _isBlocked
            ? _isQuarantined
                  ? 'Unquarantine'
                  : widget.client.status.toLowerCase() == 'block-scheduled'
                  ? 'Unblock'
                  : 'Unban'
            : 'Block',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.42)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildPauseButton(BuildContext context) {
    const pausedColor = Color(0xFF34C759);
    const pauseColor = Color(0xFFE85D8E);
    final color = _isPaused ? pausedColor : pauseColor;
    return OutlinedButton.icon(
      onPressed: (_isSaving || _isBlocking || _isPausing)
          ? null
          : _toggleInternetPause,
      icon: _isPausing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
      label: Text(
        _isPausing
            ? 'Wait'
            : _isPaused
            ? 'Resume'
            : 'Pause',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.58)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _DeviceNetifyPanel extends StatelessWidget {
  static const Color _flowColor = Color(0xFF8B5CF6);

  final int flowCount;
  final VoidCallback onTap;

  const _DeviceNetifyPanel({required this.flowCount, required this.onTap});

  String get _formattedCount {
    if (flowCount < 1000) return flowCount.toString();
    if (flowCount < 1000000) {
      final thousands = flowCount / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
    }
    final millions = flowCount / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _flowColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: _flowColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detailed Flow',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formattedCount,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            'Netify',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceWirelessIdentity extends StatelessWidget {
  final Client client;

  const _DeviceWirelessIdentity({required this.client});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ssid = client.ssid?.trim() ?? '';
    final interfaceName = client.wirelessInterface?.trim() ?? '';
    final band = client.wirelessBand?.trim() ?? '';
    final parts = <String>[
      'Wi-Fi',
      if (ssid.isNotEmpty)
        ssid
      else if (interfaceName.isNotEmpty)
        interfaceName,
      if (band.isNotEmpty) band,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(Icons.wifi_rounded, size: 13, color: colorScheme.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              parts.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceAddressRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isPinned;
  final bool isBusy;
  final VoidCallback onPinTap;

  const _DeviceAddressRow({
    required this.label,
    required this.value,
    required this.isPinned,
    required this.isBusy,
    required this.onPinTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pinColor = isPinned
        ? const Color(0xFF188CFF)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.62);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.lan_rounded, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty || value == 'N/A' ? 'No IP address' : value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: isPinned ? 'Edit static IP' : 'Pin static IP',
            onPressed: isBusy ? null : onPinTap,
            style: IconButton.styleFrom(
              backgroundColor: pinColor.withValues(
                alpha: isPinned ? 0.18 : 0.1,
              ),
            ),
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.push_pin_rounded, color: pinColor),
          ),
        ],
      ),
    );
  }
}

class _StaticIpDialogResult {
  final bool enabled;
  final String ipAddress;

  const _StaticIpDialogResult({required this.enabled, required this.ipAddress});
}

class _StaticIpDialog extends StatefulWidget {
  final String initialIpAddress;
  final bool hasReservation;

  const _StaticIpDialog({
    required this.initialIpAddress,
    required this.hasReservation,
  });

  @override
  State<_StaticIpDialog> createState() => _StaticIpDialogState();
}

class _StaticIpDialogState extends State<_StaticIpDialog> {
  late bool _enabled;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _enabled = widget.hasReservation;
    _controller = TextEditingController(text: widget.initialIpAddress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Static IP Reservation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pin this IP address'),
            subtitle: const Text('Reserve this address for the device MAC.'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: _enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.lan_rounded),
              labelText: 'IP Address',
              hintText: '192.168.1.50',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.hasReservation)
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const _StaticIpDialogResult(enabled: false, ipAddress: '')),
            child: Text('Clear', style: TextStyle(color: colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            _StaticIpDialogResult(
              enabled: _enabled,
              ipAddress: _controller.text,
            ),
          ),
          icon: const Icon(Icons.push_pin_rounded),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeviceUsagePanel extends StatelessWidget {
  final Client client;

  const _DeviceUsagePanel({required this.client});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _usageMetric(
              context,
              label: 'Download',
              value: _formatBytes(client.totalDownloadBytes),
              icon: Icons.arrow_downward_rounded,
              color: const Color(0xFF18AEEA),
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          Expanded(
            child: _usageMetric(
              context,
              label: 'Upload',
              value: _formatBytes(client.totalUploadBytes),
              icon: Icons.arrow_upward_rounded,
              color: const Color(0xFFF27C24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final decimals = value >= 100 || unit == 0
        ? 0
        : value >= 10
        ? 1
        : 2;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }
}

class _ActiveScheduleNotice extends ConsumerWidget {
  final Client client;

  const _ActiveScheduleNotice({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<OpenwallaActiveSchedule?>(
      future: ref
          .read(appStateProvider)
          .fetchActiveScheduleForMac(client.macAddress, context: context),
      builder: (context, snapshot) {
        final schedule = snapshot.data;
        final fallbackUntil = client.scheduledBlockUntil;
        if (schedule == null &&
            !client.hasScheduledBlock &&
            (fallbackUntil == null || fallbackUntil.isEmpty)) {
          return const SizedBox.shrink();
        }
        final until = schedule?.endTime ?? fallbackUntil ?? '';
        final name = schedule?.name ?? 'Scheduled block';
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.tertiary.withValues(alpha: 0.26),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_busy_rounded,
                  color: colorScheme.tertiary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    until.isEmpty
                        ? '$name is active'
                        : '$name is active until $until',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UnifiedClientCard extends StatelessWidget {
  final Client client;
  final bool isPaused;
  final VoidCallback onOpenSettings;
  final VoidCallback onLongPress;

  const _UnifiedClientCard({
    required this.client,
    required this.isPaused,
    required this.onOpenSettings,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isBlocked = client.isBlocked;
    final stateLabel = client.isQuarantined
        ? 'Quarantined'
        : isPaused
        ? 'Paused'
        : isBlocked
        ? client.status.toLowerCase() == 'block-scheduled'
              ? 'Blocked'
              : 'Banned'
        : null;
    final stateColor = client.isQuarantined || isBlocked
        ? const Color(0xFFFF4D5A)
        : const Color(0xFFE85D8E);
    final borderColor = isBlocked
        ? const Color(0xFFFF4D5A).withValues(alpha: 0.45)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.10);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(color: borderColor, width: isBlocked ? 1.3 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      color: isBlocked
          ? colorScheme.errorContainer.withValues(alpha: 0.08)
          : null,
      child: InkWell(
        onTap: onOpenSettings,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.13,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _clientIconData(client),
                      color: client.isBlocked
                          ? const Color(0xFFFF4D5A)
                          : client.isOffline
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.primary,
                      size: 22,
                      semanticLabel: 'Client icon',
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Tooltip(
                      message: client.isBlocked
                          ? 'Client is blocked'
                          : client.isOffline
                          ? 'Client is offline'
                          : 'Client is online',
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: client.isBlocked
                              ? const Color(0xFFFF4D5A)
                              : client.isOffline
                              ? colorScheme.onSurfaceVariant
                              : Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            client.hostname,
                            style: LuciTextStyles.cardTitle(context),
                            semanticsLabel:
                                'Client hostname: ${client.hostname}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (stateLabel != null) ...[
                          const SizedBox(width: 8),
                          _ClientStateBadge(
                            label: stateLabel,
                            color: stateColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: LuciSpacing.xs),
                    Container(
                      margin: const EdgeInsets.only(right: 32),
                      child: Divider(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.10,
                        ),
                        thickness: 1,
                        height: 8,
                      ),
                    ),
                    Text(
                      _buildMinimalClientSubtitle(client),
                      style: LuciTextStyles.cardSubtitle(context),
                      semanticsLabel:
                          'Client details: ${_buildMinimalClientSubtitle(client)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 26,
                semanticLabel: 'Open device settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildMinimalClientSubtitle(Client client) {
    final v4 = client.ipAddress;
    final staticIp = client.staticIpAddress?.trim() ?? '';
    final v6s = client.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != 'N/A') {
      shown = staticIp.isNotEmpty ? '$v4 (static)' : v4;
      if (v6 != null) extra++;
    } else if (staticIp.isNotEmpty) {
      shown = '$staticIp (static)';
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return '';
    if (extra > 0) {
      return '$shown  +$extra';
    } else {
      return shown;
    }
  }
}

class _ClientStateBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ClientStateBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
