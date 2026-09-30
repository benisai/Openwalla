// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/widgets/luci_animation_system.dart';

class RouterDashboardSettingsScreen extends ConsumerStatefulWidget {
  final String? routerId;
  final bool showThroughput;
  final bool showDashboardCards;
  final bool showShortcutPanel;
  final bool showWirelessInterfaces;
  final bool showWiredInterfaces;
  final String? title;
  final bool embedded;

  const RouterDashboardSettingsScreen({
    super.key,
    this.routerId,
    this.showThroughput = true,
    this.showDashboardCards = true,
    this.showShortcutPanel = true,
    this.showWirelessInterfaces = true,
    this.showWiredInterfaces = true,
    this.title,
    this.embedded = false,
  });

  @override
  ConsumerState<RouterDashboardSettingsScreen> createState() =>
      _RouterDashboardSettingsScreenState();
}

class _RouterDashboardSettingsScreenState
    extends ConsumerState<RouterDashboardSettingsScreen> {
  late DashboardPreferences _preferences;
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _availableWirelessInterfaces = {};
  final Set<String> _availableWiredInterfaces = {};
  final Set<String> _disabledWirelessInterfaces = {};
  final Set<String> _disabledWiredInterfaces = {};
  final List<String> _allInterfaces = [];
  Timer? _autoSaveTimer;
  String? _selectedRouterId;

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 300), () async {
      final appState = ref.read(appStateProvider);
      try {
        await appState.saveDashboardPreferences(_preferences);
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    _selectedRouterId = widget.routerId ?? appState.selectedRouter?.id;
    Future(() async {
      if (_selectedRouterId != null &&
          appState.selectedRouter?.id != _selectedRouterId) {
        await appState.selectRouter(_selectedRouterId!);
      }
      await _loadPreferences();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final appState = ref.read(appStateProvider);
      _availableWirelessInterfaces.clear();
      _availableWiredInterfaces.clear();
      _disabledWirelessInterfaces.clear();
      _disabledWiredInterfaces.clear();
      _allInterfaces.clear();

      if (appState.dashboardData == null) {
        await appState.fetchDashboardData();
      }
      if (appState.dashboardData == null) {
        setState(() {
          _errorMessage =
              'Unable to load dashboard data. Please check your connection.';
          _isLoading = false;
        });
        return;
      }
      _preferences = appState.dashboardPreferences;
      _extractAvailableInterfaces(appState.dashboardData);
      if (_applyDefaultInterfaceSelections()) {
        await appState.saveDashboardPreferences(_preferences);
      }
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectRouter(String routerId) async {
    _autoSaveTimer?.cancel();
    setState(() {
      _selectedRouterId = routerId;
      _isLoading = true;
      _errorMessage = null;
    });
    final appState = ref.read(appStateProvider);
    await appState.selectRouter(routerId);
    await appState.fetchDashboardData();
    await _loadPreferences();
  }

  void _extractAvailableInterfaces(Map<String, dynamic>? dashboardData) {
    if (dashboardData == null) return;

    final wirelessRadios = dashboardData['wireless'] as Map<String, dynamic>?;
    if (wirelessRadios != null) {
      wirelessRadios.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (var interface in interfaces) {
            final config = interface['config'] ?? {};
            final iwinfo = interface['iwinfo'] ?? {};
            final radioDisabled = radioData is Map
                ? _isDisabled(radioData['disabled'])
                : false;
            final interfaceDisabled = _isDisabled(config['disabled']);
            final ssid = iwinfo['ssid'] ?? config['ssid'];
            final deviceName = config['device'] ?? radioName;
            if (ssid != null && ssid.toString().isNotEmpty) {
              final interfaceId = '$ssid ($deviceName)';
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
              if (radioDisabled || interfaceDisabled) {
                _disabledWirelessInterfaces.add(interfaceId);
              }
            }
          }
        }
      });
    }

    final interfaces =
        dashboardData['interfaceDump']?['interface'] as List<dynamic>?;
    if (interfaces != null) {
      for (var item in interfaces) {
        final interface = item as Map<String, dynamic>;
        final name = interface['interface'] as String? ?? '';
        final isDisabled = _isDisabled(interface['disabled']);
        if (name.isNotEmpty && name != 'loopback' && name != 'lo') {
          _availableWiredInterfaces.add(name);
          _allInterfaces.add(name);
          if (isDisabled) {
            _disabledWiredInterfaces.add(name);
          }
        }
      }
    }
    _allInterfaces.sort();
  }

  bool _applyDefaultInterfaceSelections() {
    var next = _preferences;
    var changed = false;

    if (!next.wirelessInterfaceSelectionInitialized &&
        _disabledWirelessInterfaces.isNotEmpty) {
      next = next.copyWith(
        enabledWirelessInterfaces: _availableWirelessInterfaces
            .where(
              (interface) => !_disabledWirelessInterfaces.contains(interface),
            )
            .toSet(),
        wirelessInterfaceSelectionInitialized: true,
      );
      changed = true;
    }

    if (!next.wiredInterfaceSelectionInitialized &&
        _disabledWiredInterfaces.isNotEmpty) {
      next = next.copyWith(
        enabledWiredInterfaces: _availableWiredInterfaces
            .where((interface) => !_disabledWiredInterfaces.contains(interface))
            .toSet(),
        wiredInterfaceSelectionInitialized: true,
      );
      changed = true;
    }

    _preferences = next;
    return changed;
  }

  bool _isDisabled(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  void _onPreferenceChanged() => _scheduleAutoSave();

  Widget _buildCardVisibilitySwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      title: Text(
        title,
        style: LuciTextStyles.detailValue(
          context,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: LuciTextStyles.cardSubtitle(context)),
      secondary: Icon(
        icon,
        size: 22,
        color: value
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      value: value,
      onChanged: onChanged,
      activeTrackColor: Theme.of(context).colorScheme.primary,
      activeThumbColor: Theme.of(context).colorScheme.onPrimary,
    );
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
    IconData? icon,
    bool initiallyExpanded = false,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: icon != null
              ? Icon(icon, color: Theme.of(context).colorScheme.primary)
              : null,
          title: Text(title, style: LuciTextStyles.cardTitle(context)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(subtitle, style: LuciTextStyles.cardSubtitle(context)),
          ),
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: LuciCardStyles.standardRadius,
          ),
          childrenPadding: EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildStaticSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
    IconData? icon,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          LuciSpacing.md,
          LuciSpacing.md,
          LuciSpacing.md,
          LuciSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: LuciSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: LuciTextStyles.cardTitle(context)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: LuciTextStyles.cardSubtitle(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: LuciSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildThroughputSection() {
    final interfaces = _availableWiredInterfaces.toList()..sort();
    return _buildStaticSection(
      title: 'Live Throughput Monitoring',
      subtitle: 'Choose which interfaces feed the Live Traffic dashboard card',
      icon: Icons.speed,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Interfaces',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.showAllThroughput,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        showAllThroughput: true,
                        primaryThroughputInterface: null,
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        showAllThroughput: false,
                        primaryThroughputInterface: interfaces.isNotEmpty
                            ? interfaces.first
                            : null,
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
        const SizedBox(height: LuciSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refresh Interval',
                      style: LuciTextStyles.detailValue(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'How often Live Traffic updates on the dashboard and detail page',
                      style: LuciTextStyles.cardSubtitle(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LuciSpacing.md),
              DropdownButton<int>(
                value: _preferences.liveThroughputRefreshSeconds,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: const [2, 3, 5, 10]
                    .map(
                      (seconds) => DropdownMenuItem<int>(
                        value: seconds,
                        child: Text('${seconds}s'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _preferences = _preferences.copyWith(
                      liveThroughputRefreshSeconds: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
            ],
          ),
        ),
        if (!_preferences.showAllThroughput && interfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...interfaces.map((iface) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: RadioListTile<String>(
                title: Text(iface, style: LuciTextStyles.detailValue(context)),
                secondary: Icon(
                  Icons.lan,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                value: iface,
                groupValue: _preferences.primaryThroughputInterface,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showAllThroughput: false,
                      primaryThroughputInterface: value,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            );
          }),
        ],
      ],
    );
  }

  String _routerLabel(dynamic router) {
    if (router == null) return 'Router';
    final hostname = router.lastKnownHostname?.toString() ?? '';
    if (hostname.isNotEmpty) return hostname;
    return router.ipAddress?.toString() ?? 'Router';
  }

  Widget _buildRouterTitle() {
    final appState = ref.watch(appStateProvider);
    final routers = appState.routers;
    final selectedId = _selectedRouterId ?? appState.selectedRouter?.id;
    final selected = routers
        .where((router) => router.id == selectedId)
        .firstOrNull;
    final selectedName = _routerLabel(selected ?? appState.selectedRouter);
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    );

    if (routers.length <= 1) {
      return Text(selectedName, style: titleStyle);
    }

    return PopupMenuButton<String>(
      initialValue: selectedId,
      tooltip: 'Select router',
      onSelected: (value) {
        if (value == selectedId) return;
        unawaited(_selectRouter(value));
      },
      itemBuilder: (context) {
        return routers.map((router) {
          return PopupMenuItem<String>(
            value: router.id,
            child: Row(
              children: [
                Icon(
                  Icons.router_outlined,
                  size: 18,
                  color: router.id == selectedId
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(_routerLabel(router))),
              ],
            ),
          );
        }).toList();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              selectedName,
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: colorScheme.onSurfaceVariant,
            size: 24,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (widget.title != null) {
      return LuciAppBar(title: widget.title, showBack: true);
    }
    return LuciAppBar(titleWidget: _buildRouterTitle(), showBack: true);
  }

  PreferredSizeWidget _buildStaticAppBar() {
    if (widget.title != null) {
      return LuciAppBar(title: widget.title, showBack: true);
    }
    final appState = ref.watch(appStateProvider);
    final selectedName = _routerLabel(appState.selectedRouter);
    return LuciAppBar(
      titleWidget: Text(
        selectedName,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      showBack: true,
    );
  }

  Widget _buildDashboardCardsSection() {
    return _buildStaticSection(
      title: 'Dashboard Settings',
      subtitle: 'Choose which cards and panels appear on the main dashboard',
      icon: Icons.dashboard_customize_rounded,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildCardVisibilitySwitch(
                title: 'Network Performance',
                subtitle: 'Show the latency timeline card',
                icon: Icons.timeline_rounded,
                value: _preferences.showNetworkPerformanceCard,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showNetworkPerformanceCard: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Statistics',
                subtitle: 'Show the Statistics tab in the bottom navigation',
                icon: Icons.query_stats_rounded,
                value: _preferences.showStatisticsTab,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showStatisticsTab: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Flows',
                subtitle: 'Show the network flows card',
                icon: Icons.account_tree_rounded,
                value: _preferences.showFlowsCard,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(showFlowsCard: value);
                  });
                  _onPreferenceChanged();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutPanelSection() {
    return _buildStaticSection(
      title: 'Shortcut Panel',
      subtitle: 'Choose the panel density and visible dashboard shortcuts',
      icon: Icons.apps_rounded,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              RadioListTile<int>(
                title: Text(
                  'Compact',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Show 3 shortcuts at a time in a scrolling row',
                  style: LuciTextStyles.cardSubtitle(context),
                ),
                secondary: Icon(
                  Icons.view_week_rounded,
                  size: 22,
                  color: _preferences.shortcutPanelVisibleCount == 3
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                value: 3,
                groupValue: _preferences.shortcutPanelVisibleCount,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _preferences = _preferences.copyWith(
                      shortcutPanelVisibleCount: value,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              RadioListTile<int>(
                title: Text(
                  'Standard',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Show 6 shortcuts in the dashboard panel',
                  style: LuciTextStyles.cardSubtitle(context),
                ),
                secondary: Icon(
                  Icons.grid_view_rounded,
                  size: 22,
                  color: _preferences.shortcutPanelVisibleCount == 6
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                value: 6,
                groupValue: _preferences.shortcutPanelVisibleCount,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _preferences = _preferences.copyWith(
                      shortcutPanelVisibleCount: value,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const Divider(height: 1),
              _buildCardVisibilitySwitch(
                title: 'Wi-Fi Shortcut',
                subtitle: 'Show the Wi-Fi shortcut on the dashboard',
                icon: Icons.wifi_rounded,
                value: _preferences.showWifiShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showWifiShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Smart Queue Shortcut',
                subtitle: 'Show the SQM shortcut on the dashboard',
                icon: Icons.sync_alt_rounded,
                value: _preferences.showSmartQueueShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showSmartQueueShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'AdBlock Shortcut',
                subtitle: 'Show the AdBlock shortcut on the dashboard',
                icon: Icons.block_rounded,
                value: _preferences.showAdblockShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showAdblockShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'VPN Shortcut',
                subtitle: 'Show the WireGuard VPN shortcut on the dashboard',
                icon: Icons.security_rounded,
                value: _preferences.showVpnShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showVpnShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Parental Controls Shortcut',
                subtitle: 'Show device schedules and block groups',
                icon: Icons.family_restroom_rounded,
                value: _preferences.showParentalShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showParentalShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Scheduler Shortcut',
                subtitle: 'Show system cron jobs and scheduled commands',
                icon: Icons.schedule_rounded,
                value: _preferences.showSchedulerShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showSchedulerShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'DDNS Shortcut',
                subtitle: 'Show Dynamic DNS controls on the dashboard',
                icon: Icons.cloud_sync_rounded,
                value: _preferences.showDdnsShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showDdnsShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Tor Shortcut',
                subtitle: 'Show Tor routing controls on the dashboard',
                icon: Icons.hub_rounded,
                value: _preferences.showTorShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showTorShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Tailscale Shortcut',
                subtitle: 'Show Tailscale mesh VPN controls',
                icon: Icons.device_hub_rounded,
                value: _preferences.showTailscaleShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showTailscaleShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Multi-WAN Shortcut',
                subtitle: 'Show mwan3 failover and load balancing status',
                icon: Icons.alt_route_rounded,
                value: _preferences.showMultiWanShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showMultiWanShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              _buildCardVisibilitySwitch(
                title: 'Quarantine Shortcut',
                subtitle: 'Show automatic new-device protection',
                icon: Icons.gpp_bad_rounded,
                value: _preferences.showQuarantineShortcut,
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      showQuarantineShortcut: value,
                    );
                  });
                  _onPreferenceChanged();
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Shortcut Order',
                    style: LuciTextStyles.detailValue(
                      context,
                    ).copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _preferences.shortcutOrder.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final order = [..._preferences.shortcutOrder];
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = order.removeAt(oldIndex);
                    order.insert(newIndex, item);
                    _preferences = _preferences.copyWith(shortcutOrder: order);
                  });
                  _onPreferenceChanged();
                },
                itemBuilder: (context, index) {
                  final id = _preferences.shortcutOrder[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey('shortcut-order-$id'),
                    index: index,
                    child: ListTile(
                      dense: true,
                      leading: Icon(_shortcutIcon(id), size: 20),
                      title: Text(_shortcutLabel(id)),
                      trailing: Icon(
                        Icons.drag_handle_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _shortcutLabel(String id) {
    return switch (id) {
      'network' => 'Network',
      'dns' => 'DNS',
      'wifi' => 'Wi-Fi',
      'routes' => 'Routing',
      'smart_queue' => 'Smart Queue',
      'adblock' => 'AdBlock',
      'services' => 'Services',
      'vpn' => 'VPN',
      'parental' => 'Parental Controls',
      'scheduler' => 'Scheduler',
      'ddns' => 'DDNS',
      'tor' => 'Tor',
      'tailscale' => 'Tailscale',
      'multi_wan' => 'Multi-WAN',
      'quarantine' => 'Quarantine',
      _ => id,
    };
  }

  IconData _shortcutIcon(String id) {
    return switch (id) {
      'network' => Icons.public_rounded,
      'dns' => Icons.dns_rounded,
      'wifi' => Icons.wifi_rounded,
      'routes' => Icons.route_rounded,
      'smart_queue' => Icons.sync_alt_rounded,
      'adblock' => Icons.block_rounded,
      'services' => Icons.miscellaneous_services_rounded,
      'vpn' => Icons.security_rounded,
      'parental' => Icons.family_restroom_rounded,
      'scheduler' => Icons.schedule_rounded,
      'ddns' => Icons.cloud_sync_rounded,
      'tor' => Icons.hub_rounded,
      'tailscale' => Icons.device_hub_rounded,
      'multi_wan' => Icons.alt_route_rounded,
      'quarantine' => Icons.gpp_bad_rounded,
      _ => Icons.apps_rounded,
    };
  }

  Widget _buildWirelessInterfacesSection() {
    if (_availableWirelessInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWirelessInterfaces.toList()..sort();
    return _buildSection(
      title: 'Wireless Networks',
      subtitle: 'Choose which wireless networks to display',
      icon: Icons.wifi,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Networks',
                  style: LuciTextStyles.detailValue(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                value: _preferences.enabledWirelessInterfaces.isEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        enabledWirelessInterfaces: {},
                        wirelessInterfaceSelectionInitialized: true,
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        enabledWirelessInterfaces: Set.from(
                          _availableWirelessInterfaces,
                        ),
                        wirelessInterfaceSelectionInitialized: true,
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
        if (_preferences.enabledWirelessInterfaces.isNotEmpty ||
            _disabledWirelessInterfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWirelessInterfaces.contains(
              interface,
            );
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: CheckboxListTile(
                title: Text(
                  interface,
                  style: LuciTextStyles.detailValue(context),
                ),
                secondary: Icon(
                  Icons.wifi,
                  size: 20,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(
                      _preferences.enabledWirelessInterfaces,
                    );
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWirelessInterfaces: newSet,
                      wirelessInterfaceSelectionInitialized: true,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildWiredInterfacesSection() {
    if (_availableWiredInterfaces.isEmpty) return const SizedBox.shrink();
    final sortedInterfaces = _availableWiredInterfaces.toList()..sort();
    final selectedInterfaces = _preferences.enabledWiredInterfaces.isEmpty
        ? Set<String>.from(_availableWiredInterfaces)
        : _preferences.enabledWiredInterfaces;
    return _buildStaticSection(
      title: 'Network Interfaces',
      subtitle: 'Choose which wired/VPN interfaces to display',
      icon: Icons.cable,
      children: [
        ...sortedInterfaces.map((interface) {
          final isEnabled = selectedInterfaces.contains(interface);
          final description = _getInterfaceDescription(interface);
          return Padding(
            padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
            child: CheckboxListTile(
              title: Text(
                interface.toUpperCase(),
                style: LuciTextStyles.detailValue(context),
              ),
              subtitle: description,
              secondary: Icon(
                Icons.cable,
                size: 20,
                color: isEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              value: isEnabled,
              onChanged: (value) {
                setState(() {
                  final newSet = Set<String>.from(selectedInterfaces);
                  if (value ?? false) {
                    newSet.add(interface);
                  } else {
                    newSet.remove(interface);
                  }
                  _preferences = _preferences.copyWith(
                    enabledWiredInterfaces: newSet,
                    wiredInterfaceSelectionInitialized: true,
                  );
                });
                _onPreferenceChanged();
              },
              activeColor: Theme.of(context).colorScheme.primary,
              controlAffinity: ListTileControlAffinity.leading,
              dense: description != null,
            ),
          );
        }),
      ],
    );
  }

  Widget? _getInterfaceDescription(String interface) {
    final lower = interface.toLowerCase();
    if (lower.startsWith('wan')) {
      return Text(
        'Wide Area Network',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.startsWith('lan')) {
      return Text(
        'Local Area Network',
        style: LuciTextStyles.cardSubtitle(context),
      );
    } else if (lower.contains('wireguard') || lower.startsWith('wg')) {
      return Text('WireGuard VPN', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('openvpn')) {
      return Text('OpenVPN', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('pppoe')) {
      return Text(
        'PPPoE Connection',
        style: LuciTextStyles.cardSubtitle(context),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      if (widget.embedded) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scaffold(
        appBar: _buildStaticAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      if (widget.embedded) {
        return Center(child: Text(_errorMessage!));
      }
      return Scaffold(
        appBar: _buildStaticAppBar(),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    final content = ListView(
      shrinkWrap: widget.embedded,
      padding: EdgeInsets.symmetric(vertical: LuciSpacing.sm),
      children: [
        LuciStaggeredAnimation(
          staggerDelay: const Duration(milliseconds: 50),
          children: [
            if (widget.showThroughput) _buildThroughputSection(),
            if (widget.showDashboardCards) _buildDashboardCardsSection(),
            if (widget.showShortcutPanel) _buildShortcutPanelSection(),
            if (widget.showWirelessInterfaces)
              _buildWirelessInterfacesSection(),
            if (widget.showWiredInterfaces) _buildWiredInterfacesSection(),
            SizedBox(height: LuciSpacing.lg),
          ],
        ),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(appBar: _buildAppBar(), body: content);
  }
}
