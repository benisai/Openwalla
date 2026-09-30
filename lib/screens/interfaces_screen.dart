import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:flutter/services.dart';
import 'package:openwalla/models/interface.dart';
import 'package:openwalla/models/wifi_scan_result.dart';
import 'package:openwalla/state/app_state.dart';
import 'dart:math';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/screens/router_dashboard_settings_screen.dart';
import 'package:openwalla/design/luci_design_system.dart';
import 'package:openwalla/widgets/luci_loading_states.dart';
import 'package:openwalla/widgets/luci_refresh_components.dart';
import 'package:qr_flutter/qr_flutter.dart';

bool shouldShowWiredInterface({
  required Map<String, dynamic> interface,
  required Set<String> enabledInterfaces,
  required bool selectionInitialized,
}) {
  final name = interface['interface']?.toString() ?? '';
  if (selectionInitialized) {
    return enabledInterfaces.isEmpty || enabledInterfaces.contains(name);
  }
  if (enabledInterfaces.isNotEmpty) {
    return enabledInterfaces.contains(name);
  }

  final disabled = interface['disabled']?.toString().trim().toLowerCase();
  final isDisabled = disabled == '1' || disabled == 'true' || disabled == 'yes';
  return !isDisabled;
}

class InterfacesScreen extends ConsumerStatefulWidget {
  final String? scrollToInterface;
  final VoidCallback? onScrollComplete;
  final bool wirelessOnly;

  const InterfacesScreen({
    super.key,
    this.scrollToInterface,
    this.onScrollComplete,
    this.wirelessOnly = false,
  });

  @override
  ConsumerState<InterfacesScreen> createState() => _InterfacesScreenState();
}

class _InterfacesScreenState extends ConsumerState<InterfacesScreen> {
  final ScrollController _scrollController = ScrollController();
  final PageController _networkPageController = PageController();
  final PageController _wirelessPageController = PageController();
  String? _targetInterface;
  String? _expandedInterface;
  final Map<String, GlobalKey> _interfaceKeys = {};
  int _networkPanelIndex = 0;
  int _wirelessPanelIndex = 0;
  bool _isLoadingNetworkPanels = false;
  bool _isRefreshingWireless = false;
  String? _routerPublicIp;
  bool _isLoadingPublicIp = false;
  final Set<String> _updatingWirelessRadios = <String>{};
  final Set<String> _updatingWirelessInterfaces = <String>{};
  final Set<String> _updatingNetworkInterfaces = <String>{};
  List<OpenwrtPortForward> _portForwards = const [];
  List<OpenwrtFirewallZone> _firewallZones = const [];
  OpenwrtFirewallDefaults _firewallDefaults = const OpenwrtFirewallDefaults(
    input: 'ACCEPT',
    output: 'ACCEPT',
    forward: 'REJECT',
    synFloodProtection: false,
  );

  /// Safely extract a String from a UCI config value that may be a List or String.
  static String _uciString(dynamic value, [String fallback = '']) {
    if (value is String) return value;
    if (value is List) {
      return value.isNotEmpty ? value.first.toString() : fallback;
    }
    return value?.toString() ?? fallback;
  }

  static String _wirelessBandLabel(Map? radio, Map? iwinfo) {
    final configuredBand = _uciString(radio?['band']).toLowerCase();
    if (configuredBand == '2g' || configuredBand == '2.4g') return '2.4 GHz';
    if (configuredBand == '5g') return '5 GHz';
    if (configuredBand == '6g') return '6 GHz';

    final frequency = double.tryParse(iwinfo?['frequency']?.toString() ?? '');
    if (frequency != null) {
      if (frequency < 3000) return '2.4 GHz';
      if (frequency < 5925) return '5 GHz';
      return '6 GHz';
    }

    final hwMode = _uciString(radio?['hwmode']).toLowerCase();
    if (hwMode.contains('11a')) return '5 GHz';
    if (hwMode.contains('11b') || hwMode.contains('11g')) return '2.4 GHz';
    return 'Wi-Fi';
  }

  Future<void> _setWirelessRadioEnabled(
    BuildContext context,
    String radioName,
    bool enabled, {
    String? interfaceSection,
  }) async {
    if (radioName.isEmpty || _updatingWirelessRadios.contains(radioName)) {
      return;
    }
    setState(() => _updatingWirelessRadios.add(radioName));
    final success = await ref
        .read(appStateProvider)
        .setWirelessRadioState(
          radioName,
          enabled,
          interfaceSection: interfaceSection,
          context: context,
        );
    if (!mounted || !context.mounted) return;
    setState(() => _updatingWirelessRadios.remove(radioName));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '$radioName turned ${enabled ? 'on' : 'off'}'
              : 'Could not update $radioName',
        ),
      ),
    );
  }

  Future<void> _setWirelessInterfaceEnabled(
    BuildContext context,
    String section,
    bool enabled,
  ) async {
    if (section.isEmpty || _updatingWirelessInterfaces.contains(section)) {
      return;
    }
    setState(() => _updatingWirelessInterfaces.add(section));
    final success = await ref
        .read(appStateProvider)
        .setWirelessInterfaceState(section, enabled, context: context);
    if (!mounted || !context.mounted) return;
    setState(() => _updatingWirelessInterfaces.remove(section));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Repeater ${enabled ? 'enabled' : 'disabled'}'
              : 'Could not update repeater',
        ),
      ),
    );
  }

  // Unified key generator for all interfaces
  String _interfaceKey({String? name, String? ssid, String? deviceName}) {
    if (ssid != null && ssid.trim().isNotEmpty) {
      return ssid.trim(); // SSID is case sensitive
    } else if (deviceName != null && deviceName.trim().isNotEmpty) {
      return deviceName.trim().toLowerCase();
    } else if (name != null && name.trim().isNotEmpty) {
      return name.trim().toLowerCase();
    }
    return '';
  }

  // Unified key generator and matcher for all interfaces
  String _normalizeInterfaceKey(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _interfaceKeyForWireless({
    String? ssid,
    String? radioName,
    String? deviceName,
    String? name,
  }) {
    final radio = (radioName ?? '').trim();
    final ssidTrimmed = (ssid ?? '').trim();

    // If SSID is empty, we need to ensure uniqueness even with same radio
    if (ssidTrimmed.isEmpty) {
      // Use device name as fallback for uniqueness
      final device = (deviceName ?? '').trim();
      if (device.isNotEmpty && device != radio) {
        return '${ssidTrimmed.toLowerCase()}__${device.toLowerCase()}';
      }
      // Use interface name as fallback
      final interfaceName = (name ?? '').trim();
      if (interfaceName.isNotEmpty && interfaceName != radio) {
        return '${ssidTrimmed.toLowerCase()}__${interfaceName.toLowerCase()}';
      }
      // If all names are the same, add a unique suffix
      return '${ssidTrimmed.toLowerCase()}__${radio.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
    }

    // If SSID is not empty, use SSID + radio
    return '${ssidTrimmed.toLowerCase()}__${radio.toLowerCase()}';
  }

  bool _isLoopbackInterface(Map<String, dynamic> iface) {
    final names = [
      iface['interface'],
      iface['device'],
      iface['l3_device'],
      iface['ifname'],
    ].map((value) => value?.toString().toLowerCase().trim());

    return names.any((name) => name == 'loopback' || name == 'lo');
  }

  @override
  void initState() {
    super.initState();
    _targetInterface = widget.scrollToInterface;
    if (!widget.wirelessOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadNetworkPanels();
        _loadRouterPublicIp();
      });
    }
    if (_targetInterface != null) {
      // Delay scrolling to allow the widget to build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInterface(_targetInterface!);
      });
    }
  }

  @override
  void didUpdateWidget(InterfacesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle parameter changes (important for iOS navigation)
    if (widget.scrollToInterface != oldWidget.scrollToInterface) {
      _targetInterface = widget.scrollToInterface;
      if (_targetInterface != null) {
        // Delay scrolling to allow the widget to build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToInterface(_targetInterface!);
        });
      } else {
        // Clear target interface if no new target is provided
        setState(() {
          _targetInterface = null;
        });
      }
    }
  }

  @override
  void dispose() {
    // Clear target interface when widget is disposed
    _targetInterface = null;
    _scrollController.dispose();
    _networkPageController.dispose();
    _wirelessPageController.dispose();
    super.dispose();
  }

  Future<void> _refreshNetworkData() async {
    await ref.read(appStateProvider).fetchDashboardData();
    if (!widget.wirelessOnly) {
      await Future.wait([
        _loadNetworkPanels(),
        _loadRouterPublicIp(forceRefresh: true),
      ]);
    }
  }

  Future<void> _loadRouterPublicIp({bool forceRefresh = false}) async {
    if (_isLoadingPublicIp) return;
    if (mounted) setState(() => _isLoadingPublicIp = true);
    try {
      final publicIp = await ref
          .read(appStateProvider)
          .fetchRouterPublicIp(forceRefresh: forceRefresh);
      if (mounted) setState(() => _routerPublicIp = publicIp);
    } finally {
      if (mounted) setState(() => _isLoadingPublicIp = false);
    }
  }

  Future<void> _refreshWirelessData() async {
    if (_isRefreshingWireless) return;
    setState(() => _isRefreshingWireless = true);
    try {
      await ref.read(appStateProvider).fetchDashboardData();
    } finally {
      if (mounted) setState(() => _isRefreshingWireless = false);
    }
  }

  Future<void> _loadNetworkPanels() async {
    if (!mounted) return;
    setState(() => _isLoadingNetworkPanels = true);
    try {
      final appState = ref.read(appStateProvider);
      final results = await Future.wait([
        appState.fetchPortForwards(context: context),
        appState.fetchFirewallOverview(context: context),
      ]);
      if (!mounted) return;
      setState(() {
        _portForwards = results[0] as List<OpenwrtPortForward>;
        final firewall = results[1] as OpenwrtFirewallOverview;
        _firewallZones = firewall.zones;
        _firewallDefaults = firewall.defaults;
        _isLoadingNetworkPanels = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingNetworkPanels = false);
    }
  }

  void _scrollToInterface(String interfaceName) {
    if (!_scrollController.hasClients) return;

    // Find the target interface and calculate its position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Get the app state to access interface data
        final appState = ref.read(appStateProvider);
        final dashboardData = appState.dashboardData;

        if (dashboardData != null) {
          // Check wired interfaces first
          final wiredInterfaces =
              dashboardData['interfaceDump']?['interface'] as List<dynamic>?;
          if (wiredInterfaces != null) {
            for (int i = 0; i < wiredInterfaces.length; i++) {
              final iface = wiredInterfaces[i] as Map<String, dynamic>;
              if (_isLoopbackInterface(iface)) continue;
              final name = iface['interface'] as String? ?? '';
              final keyStr = _interfaceKey(name: name);
              // Use exact matching only
              if (keyStr == interfaceName.toLowerCase()) {
                _scrollToExpandedCard(keyStr);
                return;
              }
            }
          }

          // If not found in wired, check wireless interfaces
          final wirelessData =
              dashboardData['wireless'] as Map<String, dynamic>?;
          if (wirelessData != null) {
            final normalizedTarget = _normalizeInterfaceKey(interfaceName);
            wirelessData.forEach((radioName, radioData) {
              final interfaces = radioData['interfaces'] as List<dynamic>?;
              if (interfaces != null) {
                for (var i = 0; i < interfaces.length; i++) {
                  final interface = interfaces[i];
                  final config = interface['config'] ?? {};
                  final iwinfo = interface['iwinfo'] ?? {};
                  final deviceName = _uciString(config['device'], radioName);
                  final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                      ? _uciString(iwinfo['ssid'])
                      : _uciString(config['ssid']);
                  final name = interface['name'] ?? '';
                  final keyStr = _interfaceKeyForWireless(
                    ssid: ssid,
                    radioName: radioName,
                    deviceName: deviceName,
                    name: name,
                  );
                  // Generate all possible normalized keys for matching
                  final ssidKey = _normalizeInterfaceKey(ssid);
                  final deviceKey = _normalizeInterfaceKey(deviceName);
                  final nameKey = _normalizeInterfaceKey(name);
                  // Match against all possible keys
                  if (normalizedTarget == ssidKey ||
                      normalizedTarget == deviceKey ||
                      normalizedTarget == nameKey) {
                    _scrollToExpandedCard(keyStr);
                    return;
                  }
                }
              }
            });
          }
        }

        // If not found, use section-based scrolling
        if (interfaceName.toLowerCase().contains('wifi') ||
            interfaceName.toLowerCase().contains('wireless') ||
            interfaceName.toLowerCase().contains('radio')) {
          _scrollToSection(200); // Wireless section
        } else {
          _scrollToSection(80); // Wired section
        }
      }
    });
  }

  double _headerOffset(BuildContext context) {
    // App bar (56) + section header (60)
    return 116.0;
  }

  void _scrollToExpandedCard(String keyStr, {int retry = 0}) {
    if (!mounted) return;

    // Set the expanded interface
    if (_expandedInterface != keyStr) {
      setState(() {
        _expandedInterface = keyStr;
      });

      // Wait for the expansion animation to complete (400ms) before calculating scroll
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _performScrollToCard(keyStr, retry: retry);
      });
    } else {
      // Already expanded, perform scroll immediately
      _performScrollToCard(keyStr, retry: retry);
    }
  }

  void _performScrollToCard(String keyStr, {int retry = 0}) {
    if (!mounted) return;

    final key = _interfaceKeys[keyStr];
    final currentContext = context; // Store context

    final ctx = key?.currentContext;
    if (ctx == null) {
      if (retry < 5) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _performScrollToCard(keyStr, retry: retry + 1);
        });
      }
      return;
    }

    final headerOffset = _headerOffset(currentContext);
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      if (retry < 5) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _performScrollToCard(keyStr, retry: retry + 1);
        });
      }
      return;
    }

    final cardOffset = renderBox.localToGlobal(Offset.zero).dy;
    final cardHeight = renderBox.size.height;
    final scrollableBox = _scrollController.position.hasContentDimensions
        ? _scrollController.position.context.storageContext.findRenderObject()
              as RenderBox?
        : null;
    final scrollableTop = scrollableBox?.localToGlobal(Offset.zero).dy ?? 0.0;
    final visibleTop = scrollableTop + headerOffset;
    final visibleBottom = MediaQuery.of(currentContext).size.height;
    final cardBottom = cardOffset + cardHeight;

    // Calculate how much of the card is visible
    final visibleCardTop = max(cardOffset, visibleTop);
    final visibleCardBottom = min(cardBottom, visibleBottom);
    final visibleCardHeight = max(0.0, visibleCardBottom - visibleCardTop);
    final cardVisibilityRatio = cardHeight > 0
        ? visibleCardHeight / cardHeight
        : 0.0;

    // Only scroll if less than 90% of the card is visible
    final needsScroll = cardVisibilityRatio < 0.9;

    if (needsScroll) {
      // Calculate optimal scroll position to center the card
      final screenHeight = MediaQuery.of(currentContext).size.height;
      final availableHeight = screenHeight - headerOffset;
      final targetPosition =
          cardOffset - headerOffset - (availableHeight - cardHeight) / 2;
      final clampedPosition = targetPosition.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController
          .animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.fastOutSlowIn,
          )
          .then((_) {
            if (mounted) {
              setState(() {
                _targetInterface = null;
              });
              widget.onScrollComplete?.call();
            }
          });
    } else {
      if (mounted) {
        setState(() {
          _targetInterface = null;
        });
        widget.onScrollComplete?.call();
      }
    }
  }

  void _scrollToSection(double targetPosition) {
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedPosition = targetPosition.clamp(0.0, maxScroll);

    _scrollController
        .animateTo(
          clampedPosition,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        )
        .then((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _targetInterface = null;
              });
              widget.onScrollComplete?.call();
            }
          });
        });
  }

  void _showNetworkInterfaceSettings() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Network Interfaces',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: RouterDashboardSettingsScreen(
                    title: 'Network Interfaces',
                    showThroughput: false,
                    showDashboardCards: false,
                    showShortcutPanel: false,
                    showWirelessInterfaces: false,
                    embedded: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditInterfaceSheet(NetworkInterface iface) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _NetworkInterfaceEditSheet(interfaceName: iface.name),
    );
    if (updated == true && mounted) {
      await ref.read(appStateProvider).fetchDashboardData();
    }
  }

  Future<bool> _confirmInterfaceAction(
    NetworkInterface interface, {
    required bool restart,
  }) async {
    final action = restart
        ? 'Restart'
        : interface.isUp
        ? 'Stop'
        : 'Turn On';
    final isLan = _normalizeInterfaceKey(interface.name) == 'lan';
    final message = restart
        ? 'Restarting ${interface.name.toUpperCase()} will briefly interrupt devices using this interface.'
        : interface.isUp
        ? isLan
              ? 'Stopping LAN will disconnect this app and devices using the LAN interface. You may need another connection or router access method to turn it back on.'
              : 'Stopping ${interface.name.toUpperCase()} will disconnect devices using this interface.'
        : 'Turn on ${interface.name.toUpperCase()} now?';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('$action ${interface.name.toUpperCase()}?'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: !restart && interface.isUp
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(
                          dialogContext,
                        ).colorScheme.error,
                        foregroundColor: Theme.of(
                          dialogContext,
                        ).colorScheme.onError,
                      )
                    : null,
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runInterfaceAction(
    NetworkInterface interface, {
    required bool restart,
  }) async {
    final name = interface.name;
    if (_updatingNetworkInterfaces.contains(name)) return;
    if (!await _confirmInterfaceAction(interface, restart: restart) ||
        !mounted) {
      return;
    }

    setState(() => _updatingNetworkInterfaces.add(name));
    try {
      final appState = ref.read(appStateProvider);
      if (restart) {
        await appState.restartNetworkInterface(name, context: context);
      } else {
        await appState.setNetworkInterfaceOperationalState(
          name,
          enabled: !interface.isUp,
          context: context,
        );
      }
      if (!mounted) return;
      final action = restart
          ? 'restart'
          : interface.isUp
          ? 'stop'
          : 'turn on';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${interface.name.toUpperCase()} $action scheduled.'),
        ),
      );
      Future<void>.delayed(const Duration(seconds: 4), () async {
        if (!mounted) return;
        await ref.read(appStateProvider).fetchDashboardData();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update ${interface.name.toUpperCase()}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingNetworkInterfaces.remove(name));
      }
    }
  }

  Future<void> _showEditWirelessSheet(String section) async {
    if (section.isEmpty) return;
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WirelessNetworkEditSheet(section: section),
    );
    if (updated == true && mounted) {
      await ref.read(appStateProvider).fetchDashboardData();
    }
  }

  Future<void> _showJoinWifiSheet() async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _WirelessJoinSheet(),
    );
    if (updated == true && mounted) {
      await ref.read(appStateProvider).fetchDashboardData();
    }
  }

  Future<void> _showWirelessDisplaySettings() async {
    final appState = ref.read(appStateProvider);
    final current = appState.dashboardPreferences.showInactiveWirelessNetworks;
    final pageContext = context;
    var showInactive = current;
    final next = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wi-Fi Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage nearby networks and how Wi-Fi appears in Openwalla.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.24),
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.wifi_find_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        title: const Text('Scan & Connect'),
                        subtitle: const Text(
                          'Use Wi-Fi as this router\'s internet connection',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Future.microtask(() {
                            if (mounted && pageContext.mounted) {
                              _showJoinWifiSheet();
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show inactive Wi-Fi networks'),
                      subtitle: const Text('Disabled radios and SSIDs'),
                      value: showInactive,
                      onChanged: (value) =>
                          setSheetState(() => showInactive = value),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(showInactive),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (next == null || next == current) return;
    await appState.saveDashboardPreferences(
      appState.dashboardPreferences.copyWith(
        showInactiveWirelessNetworks: next,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showWirelessInfoSheet(Map<String, dynamic> iface) async {
    final details = iface['details'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.wifi_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            iface['ssid']?.toString().isNotEmpty == true
                                ? iface['ssid'].toString()
                                : 'Wi-Fi Info',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            iface['subtitle']?.toString() ?? '',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.34,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInfoSheetRow(
                        context,
                        'Status',
                        iface['isEnabled'] == true ? 'Active' : 'Inactive',
                      ),
                      _buildInfoSheetRow(
                        context,
                        'Radio',
                        iface['radioName']?.toString() ?? 'N/A',
                      ),
                      _buildInfoSheetRow(
                        context,
                        'Interface',
                        iface['interfaceName']?.toString() ?? 'N/A',
                      ),
                      if (details is Map)
                        ...details.entries.map(
                          (entry) => _buildInfoSheetRow(
                            context,
                            entry.key.toString(),
                            entry.value?.toString() ?? 'N/A',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoSheetRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value.isEmpty ? 'N/A' : value,
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

  Future<void> _showShareWifiDialog(Map<String, dynamic> iface) async {
    final ssid = iface['ssid']?.toString() ?? '';
    if (ssid.trim().isEmpty) return;
    final password = iface['password']?.toString() ?? '';
    final encryption = iface['encryption']?.toString() ?? '';
    final hidden = iface['hidden'] == true;
    final qrData = _wifiQrPayload(
      ssid: ssid,
      password: password,
      encryption: encryption,
      hidden: hidden,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _ShareWifiSheet(ssid: ssid, password: password, qrData: qrData),
    );
  }

  String _wifiQrPayload({
    required String ssid,
    required String password,
    required String encryption,
    required bool hidden,
  }) {
    final normalized = encryption.toLowerCase();
    final authType = normalized.contains('wep')
        ? 'WEP'
        : normalized == 'none' || normalized == 'nopass'
        ? 'nopass'
        : 'WPA';
    final escapedSsid = _escapeWifiQrValue(ssid);
    final escapedPassword = _escapeWifiQrValue(password);
    return 'WIFI:T:$authType;S:$escapedSsid;P:$escapedPassword;H:${hidden ? 'true' : 'false'};;';
  }

  String _escapeWifiQrValue(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll(':', r'\:');
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.read(appStateProvider);

    return Scaffold(
      appBar: LuciAppBar(
        title: widget.wirelessOnly ? 'Wi-Fi' : 'Network',
        showBack: true,
        actions: widget.wirelessOnly
            ? [
                IconButton(
                  tooltip: 'Wi-Fi settings',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: _showWirelessDisplaySettings,
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Network interface settings',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: _showNetworkInterfaceSettings,
                ),
              ],
      ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            LuciPullToRefresh(
              onRefresh: _refreshNetworkData,
              child: Builder(
                builder: (context) {
                  final watchedAppState = ref.watch(appStateProvider);
                  final isLoading = watchedAppState.isDashboardLoading;
                  final dashboardError = watchedAppState.dashboardError;
                  final dashboardData = watchedAppState.dashboardData;

                  if (isLoading && dashboardData == null) {
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: LuciSpacing.md),
                      child: Column(
                        children: [
                          SizedBox(height: LuciSpacing.md),
                          // Interface cards skeleton
                          Expanded(
                            child: ListView.separated(
                              itemCount: 4,
                              separatorBuilder: (context, index) =>
                                  SizedBox(height: LuciSpacing.md),
                              itemBuilder: (context, index) => LuciCardSkeleton(
                                showTitle: true,
                                showSubtitle: true,
                                contentLines: 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (dashboardError != null && dashboardData == null) {
                    return LuciErrorDisplay(
                      title: 'Failed to Load Network',
                      message:
                          'Could not connect to the router. Please check your network connection and router settings.',
                      actionLabel: 'Retry',
                      onAction: () =>
                          appState.retryDashboardConnection(context: context),
                      icon: Icons.wifi_off_rounded,
                    );
                  }

                  if (dashboardData == null) {
                    return LuciEmptyState(
                      title: 'No Network Data',
                      message:
                          'Unable to fetch network information. Pull down to refresh or tap the button below.',
                      icon: Icons.device_hub_outlined,
                      actionLabel: 'Fetch Data',
                      onAction: () => appState.fetchDashboardData(),
                    );
                  }

                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      if (widget.wirelessOnly) ...[
                        _buildWirelessInterfacesList(),
                      ] else ...[
                        SliverFillRemaining(
                          child: Column(
                            children: [
                              _NetworkPanelSwitcher(
                                selectedIndex: _networkPanelIndex,
                                onSelected: _selectNetworkPanel,
                              ),
                              Expanded(
                                child: PageView(
                                  controller: _networkPageController,
                                  onPageChanged: (index) => setState(
                                    () => _networkPanelIndex = index,
                                  ),
                                  children: [
                                    CustomScrollView(
                                      slivers: [_buildWiredInterfacesList()],
                                    ),
                                    _PortForwardingPanel(
                                      isLoading: _isLoadingNetworkPanels,
                                      forwards: _portForwards,
                                      onRefresh: _loadNetworkPanels,
                                      onAdd: _showAddPortForwardSheet,
                                      onEdit: _showAddPortForwardSheet,
                                    ),
                                    _FirewallZonesPanel(
                                      isLoading: _isLoadingNetworkPanels,
                                      defaults: _firewallDefaults,
                                      zones: _firewallZones,
                                      onRefresh: _loadNetworkPanels,
                                      onEdit: _showEditFirewallZoneSheet,
                                    ),
                                  ],
                                ),
                              ),
                              _NetworkPanelDots(
                                count: 3,
                                currentIndex: _networkPanelIndex,
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                      if (widget.wirelessOnly)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: SizedBox.shrink(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectNetworkPanel(int index) {
    setState(() => _networkPanelIndex = index);
    _networkPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectWirelessPanel(int index) {
    setState(() => _wirelessPanelIndex = index);
    _wirelessPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showAddPortForwardSheet([OpenwrtPortForward? forward]) async {
    final routerIp = ref.read(appStateProvider).selectedRouter?.ipAddress ?? '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) =>
          _AddPortForwardSheet(forward: forward, routerIp: routerIp),
    );
    if (saved == true) await _loadNetworkPanels();
  }

  Future<void> _showEditFirewallZoneSheet(OpenwrtFirewallZone zone) async {
    final dashboard = ref.read(appStateProvider).dashboardData;
    final interfaceRows = dashboard?['interfaceDump']?['interface'];
    final availableNetworks = <String>{};
    if (interfaceRows is List) {
      for (final row in interfaceRows) {
        if (row is! Map) continue;
        final name = row['interface']?.toString().trim() ?? '';
        if (name.isNotEmpty && name != 'loopback') availableNetworks.add(name);
      }
    }
    availableNetworks.addAll(
      zone.networks
          .split(RegExp(r'[,\s]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item != 'Any'),
    );

    final update = await showModalBottomSheet<_FirewallZoneUpdate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _FirewallZoneEditSheet(
        zone: zone,
        availableNetworks: availableNetworks.toList()..sort(),
      ),
    );
    if (update == null || !mounted) return;

    try {
      await ref
          .read(appStateProvider)
          .updateFirewallZone(
            zone: zone,
            networks: update.networks,
            input: update.input,
            output: update.output,
            forward: update.forward,
            masquerading: update.masquerading,
            mtuFix: update.mtuFix,
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${zone.name} zone updated.')));
      await _loadNetworkPanels();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update ${zone.name}: $error')),
      );
    }
  }

  Widget _buildWiredInterfacesList() {
    final appState = ref.watch(appStateProvider);
    final dynamic detailedData = appState.dashboardData?['interfaceDump'];
    final dynamic statsDataSource = appState.dashboardData?['networkDevices'];
    final preferences = appState.dashboardPreferences;
    final enabledWiredInterfaces = preferences.enabledWiredInterfaces;
    var interfacesList = <NetworkInterface>[];

    if (detailedData is Map &&
        detailedData.containsKey('interface') &&
        detailedData['interface'] is List) {
      final List<dynamic> interfaceDataList = detailedData['interface'];
      final Map<String, dynamic> networkStatsMap = statsDataSource is Map
          ? Map<String, dynamic>.from(statsDataSource)
          : <String, dynamic>{};

      interfacesList = interfaceDataList
          .whereType<Map<String, dynamic>>()
          .where(
            (detailedInterfaceMap) =>
                !_isLoopbackInterface(detailedInterfaceMap),
          )
          .where((detailedInterfaceMap) {
            return shouldShowWiredInterface(
              interface: detailedInterfaceMap,
              enabledInterfaces: enabledWiredInterfaces,
              selectionInitialized:
                  preferences.wiredInterfaceSelectionInitialized,
            );
          })
          .map((detailedInterfaceMap) {
            final mutableInterfaceMap = Map<String, dynamic>.from(
              detailedInterfaceMap,
            );
            final stats = mutableInterfaceMap['stats'];
            if (stats == null || (stats is Map && stats.isEmpty)) {
              final String? deviceName =
                  mutableInterfaceMap['l3_device'] ??
                  mutableInterfaceMap['device'];
              if (deviceName != null) {
                final statsContainer = networkStatsMap[deviceName];
                if (statsContainer is Map && statsContainer['stats'] is Map) {
                  mutableInterfaceMap['stats'] = statsContainer['stats'];
                }
              }
            }
            return NetworkInterface.fromJson(mutableInterfaceMap);
          })
          .toList();
    }

    final interfaces = interfacesList;
    if (interfaces.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final iface = interfaces[index];
        final isTargetInterface =
            _targetInterface != null &&
            iface.name.toLowerCase() == _targetInterface!.toLowerCase();

        final keyStr = _interfaceKey(name: iface.name);
        final key = _interfaceKeys.putIfAbsent(keyStr, () => GlobalKey());
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _UnifiedNetworkCard(
            key: key,
            name: iface.name.toUpperCase(),
            subtitle: _buildMinimalInterfaceSubtitle(iface),
            isUp: iface.isUp,
            icon: _getInterfaceIcon(iface.protocol),
            details: _buildWiredDetails(context, iface),
            initiallyExpanded:
                isTargetInterface || _expandedInterface == keyStr,
          ),
        );
      }, childCount: interfaces.length),
    );
  }

  Widget _buildWirelessInterfacesList() {
    final appState = ref.watch(appStateProvider);
    final dashboardData = appState.dashboardData;
    final wirelessData = dashboardData?['wireless'] as Map<String, dynamic>?;
    final uciWirelessConfig = dashboardData?['uciWirelessConfig'];
    final associatedWirelessMacs =
        dashboardData?['associatedWirelessMacs'] as Map? ?? const {};
    final interfacesList = <Map<String, dynamic>>[];

    final uciRadios = <String, Map>{};
    final uciInterfaces = <String, Map>{};

    final uciValues = uciWirelessConfig is Map
        ? (uciWirelessConfig['values'] is Map
              ? uciWirelessConfig['values'] as Map
              : uciWirelessConfig)
        : null;
    if (uciValues != null) {
      uciValues.forEach((key, value) {
        final typedValue = value as Map?;
        final sectionType = _uciString(typedValue?['.type']);
        if (sectionType == 'wifi-device') {
          uciRadios[key] = typedValue!;
        } else if (sectionType == 'wifi-iface') {
          uciInterfaces[key] = typedValue!;
        }
      });
    }

    final runtimeInterfaces = <String>{};
    if (wirelessData != null) {
      wirelessData.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          final radioClients = <String>{};
          for (final rawIface in interfaces) {
            if (rawIface is! Map) continue;
            for (final candidate in [rawIface['ifname'], rawIface['name']]) {
              final stations = associatedWirelessMacs[candidate?.toString()];
              if (stations is Iterable) {
                radioClients.addAll(
                  stations.map((station) => station.toString()),
                );
              }
            }
          }
          for (final iface in interfaces) {
            final config = iface['config'] ?? {};
            final iwinfo = iface['iwinfo'] ?? {};
            final uciName = iface['section'] as String?;
            final uciConfig = uciName == null ? null : uciInterfaces[uciName];
            final ifaceConfig = uciConfig ?? config;
            if (uciName != null) {
              runtimeInterfaces.add(uciName);
            }

            final isRadioEnabled =
                _uciString(uciRadios[radioName]?['disabled'], '0') != '1';
            final isIfaceEnabled =
                _uciString(ifaceConfig['disabled'], '0') != '1';
            final isEnabled = isRadioEnabled && isIfaceEnabled;
            final hidden = _uciString(ifaceConfig['hidden'], '0') == '1';
            final encryption = _uciString(ifaceConfig['encryption'], 'N/A');
            final password = _uciString(ifaceConfig['key']);
            final txPower = _uciString(uciRadios[radioName]?['txpower']);
            final band = _wirelessBandLabel(uciRadios[radioName], iwinfo);

            final name = iface['name'] ?? '';
            final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                ? _uciString(iwinfo['ssid'])
                : _uciString(ifaceConfig['ssid']);
            final deviceName = _uciString(ifaceConfig['device'], radioName);
            final mode =
                _uciString(ifaceConfig['mode']).toUpperCase().isNotEmpty
                ? _uciString(ifaceConfig['mode']).toUpperCase()
                : (iwinfo['mode']?.toString().toUpperCase() ?? 'N/A');
            final isSta =
                mode == 'STA' ||
                mode.contains('CLIENT') ||
                _uciString(ifaceConfig['ssid']).toUpperCase() == 'STA' ||
                _uciString(iwinfo['ssid']).toUpperCase() == 'STA';
            interfacesList.add({
              'section': uciName ?? '',
              'name': _uciString(ifaceConfig['ssid']).isNotEmpty
                  ? _uciString(ifaceConfig['ssid'])
                  : (iwinfo['ssid']?.toString() ?? 'Unnamed'),
              'subtitle':
                  '$band • Ch. ${iwinfo['channel']?.toString() ?? _uciString(uciRadios[radioName]?['channel'], 'N/A')}',
              'isEnabled': isEnabled,
              'radioEnabled': isRadioEnabled,
              'clientCount': radioClients.length,
              'band': band,
              'deviceName': deviceName,
              'radioName': radioName,
              'ssid': ssid,
              'password': password,
              'encryption': encryption,
              'hidden': hidden,
              'mode': mode,
              'isSta': isSta,
              'interfaceName': name,
              'details': {
                'Device': _uciString(ifaceConfig['device'], radioName),
                'Mode': _uciString(ifaceConfig['mode']).isNotEmpty
                    ? _uciString(ifaceConfig['mode'])
                    : (iwinfo['mode']?.toString() ?? 'N/A'),
                'Channel':
                    iwinfo['channel']?.toString() ??
                    _uciString(ifaceConfig['channel'], 'N/A'),
                'Signal': '${iwinfo['signal']?.toString() ?? '--'} dBm',
                'Network': (ifaceConfig['network'] is List)
                    ? (ifaceConfig['network'] as List).join(', ')
                    : _uciString(ifaceConfig['network'], 'N/A'),
                'Security': encryption,
                'SSID Visibility': hidden ? 'Hidden' : 'Visible',
                'TX Power': txPower.isEmpty ? 'Auto' : '$txPower dBm',
              },
            });
          }
        }
      });
    }

    uciInterfaces.forEach((uciName, config) {
      if (!runtimeInterfaces.contains(uciName)) {
        final radioName = _uciString(config['device']);
        final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
        final isIfaceEnabled = _uciString(config['disabled']) != '1';
        final isEnabled = isRadioEnabled && isIfaceEnabled;

        final name = _uciString(config['ssid'], 'Unnamed');
        final hidden = _uciString(config['hidden'], '0') == '1';
        final encryption = _uciString(config['encryption'], 'N/A');
        final mode = _uciString(config['mode'], 'N/A').toUpperCase();
        final isSta =
            mode == 'STA' ||
            mode.contains('CLIENT') ||
            _uciString(config['ssid']).toUpperCase() == 'STA';
        final txPower = _uciString(uciRadios[radioName]?['txpower']);
        final band = _wirelessBandLabel(uciRadios[radioName], null);
        interfacesList.add({
          'section': uciName,
          'name': name,
          'subtitle':
              '$band • Ch. ${_uciString(uciRadios[radioName]?['channel'], 'N/A')}',
          'isEnabled': isEnabled,
          'radioEnabled': isRadioEnabled,
          'clientCount': 0,
          'band': band,
          'deviceName': radioName,
          'radioName': radioName,
          'ssid': name,
          'password': _uciString(config['key']),
          'encryption': encryption,
          'hidden': hidden,
          'mode': mode,
          'isSta': isSta,
          'interfaceName': name,
          'details': {
            'Device': radioName,
            'Mode': _uciString(config['mode'], 'N/A'),
            'SSID': _uciString(config['ssid'], 'N/A'),
            'Network': (config['network'] is List)
                ? (config['network'] as List).join(', ')
                : _uciString(config['network'], 'N/A'),
            'Security': encryption,
            'SSID Visibility': hidden ? 'Hidden' : 'Visible',
            'TX Power': txPower.isEmpty ? 'Auto' : '$txPower dBm',
          },
        });
      }
    });

    final representedRadios = interfacesList
        .map((iface) => iface['radioName']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    uciRadios.forEach((radioName, radioConfig) {
      if (representedRadios.contains(radioName)) return;
      final radioEnabled = _uciString(radioConfig['disabled'], '0') != '1';
      final band = _wirelessBandLabel(radioConfig, null);
      final channel = _uciString(radioConfig['channel'], 'Auto');
      interfacesList.add({
        'section': '',
        'name': radioName,
        'subtitle': '$band • Ch. $channel',
        'isEnabled': radioEnabled,
        'radioEnabled': radioEnabled,
        'clientCount': 0,
        'band': band,
        'deviceName': radioName,
        'radioName': radioName,
        'ssid': radioName,
        'password': '',
        'encryption': 'N/A',
        'hidden': false,
        'mode': 'AP',
        'isSta': false,
        'interfaceName': radioName,
        'details': {
          'Device': radioName,
          'Mode': 'Radio',
          'Channel': channel,
          'Security': 'Not configured',
          'TX Power': _uciString(radioConfig['txpower']).isEmpty
              ? 'Auto'
              : '${_uciString(radioConfig['txpower'])} dBm',
        },
      });
    });

    final activeInterfaces = interfacesList
        .where((iface) => iface['isEnabled'] == true)
        .toList();
    final disabledInterfaces = interfacesList
        .where((iface) => iface['isEnabled'] != true)
        .toList();
    if (activeInterfaces.isEmpty && disabledInterfaces.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final showInactive =
        appState.dashboardPreferences.showInactiveWirelessNetworks;
    final mainActive = activeInterfaces
        .where((iface) => iface['isSta'] != true)
        .toList();
    final staActive = activeInterfaces
        .where((iface) => iface['isSta'] == true)
        .toList();
    final visibleDisabled = disabledInterfaces
        .where(
          (iface) =>
              iface['isSta'] == true ||
              showInactive ||
              iface['radioEnabled'] != true,
        )
        .toList();
    final mainDisabled = visibleDisabled
        .where((iface) => iface['isSta'] != true)
        .toList();
    final staDisabled = visibleDisabled
        .where((iface) => iface['isSta'] == true)
        .toList();
    if (_wirelessPanelIndex > 1) _wirelessPanelIndex = 0;
    return SliverFillRemaining(
      child: Column(
        children: [
          _WirelessPanelSwitcher(
            selectedIndex: _wirelessPanelIndex,
            onSelected: _selectWirelessPanel,
          ),
          Expanded(
            child: PageView(
              controller: _wirelessPageController,
              onPageChanged: (index) =>
                  setState(() => _wirelessPanelIndex = index),
              children: [
                CustomScrollView(
                  slivers: [_buildWirelessSliver(mainActive, mainDisabled)],
                ),
                CustomScrollView(
                  slivers: [
                    if (staActive.isEmpty && staDisabled.isEmpty)
                      _buildRepeaterEmptySliver()
                    else
                      _buildWirelessSliver(staActive, staDisabled),
                  ],
                ),
              ],
            ),
          ),
          _NetworkPanelDots(count: 2, currentIndex: _wirelessPanelIndex),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildRepeaterEmptySliver() {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.wifi_find_rounded,
                    size: 36,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Connect to a Wi-Fi Network',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Scan nearby networks and use one as this router\'s internet connection.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _showJoinWifiSheet,
                    icon: const Icon(Icons.wifi_find_rounded),
                    label: const Text('Scan Nearby Networks'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWirelessSliver(
    List<Map<String, dynamic>> activeInterfaces,
    List<Map<String, dynamic>> disabledInterfaces,
  ) {
    if (activeInterfaces.isEmpty && disabledInterfaces.isEmpty) {
      return _buildNoWirelessRadiosSliver();
    }
    if (activeInterfaces.isEmpty) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _buildWirelessCard(context, disabledInterfaces[index]),
          childCount: disabledInterfaces.length,
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= activeInterfaces.length) {
            return _buildDisabledWirelessSection(context, disabledInterfaces);
          }
          final iface = activeInterfaces[index];
          return _buildWirelessCard(context, iface);
        },
        childCount:
            activeInterfaces.length + (disabledInterfaces.isEmpty ? 0 : 1),
      ),
    );
  }

  Widget _buildNoWirelessRadiosSliver() {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 44,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                'No Wi-Fi Radios Found',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Check the router wireless configuration again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _isRefreshingWireless ? null : _refreshWirelessData,
                icon: _isRefreshingWireless
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                  _isRefreshingWireless ? 'Checking...' : 'Check Again',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWirelessCard(BuildContext context, Map<String, dynamic> iface) {
    final deviceName = iface['deviceName'] ?? '';
    final radioName = iface['radioName'] ?? '';
    final ssid = iface['ssid'] ?? '';
    final name = iface['interfaceName'] ?? '';
    final keyStr = _interfaceKeyForWireless(
      ssid: ssid,
      radioName: radioName,
      deviceName: deviceName,
      name: name,
    );
    final key = _interfaceKeys.putIfAbsent(keyStr, () => GlobalKey());
    final displayName = ssid.toString().isNotEmpty
        ? ssid.toString()
        : deviceName.toString();

    final isTargetInterface =
        _targetInterface != null &&
        (_normalizeInterfaceKey(ssid) ==
                _normalizeInterfaceKey(_targetInterface!) ||
            _normalizeInterfaceKey(deviceName) ==
                _normalizeInterfaceKey(_targetInterface!) ||
            _normalizeInterfaceKey(name) ==
                _normalizeInterfaceKey(_targetInterface!));

    final shouldExpand = isTargetInterface || _expandedInterface == keyStr;
    final isSta = iface['isSta'] == true;
    final clientCount = iface['clientCount'] as int? ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: _UnifiedNetworkCard(
        key: key,
        name: displayName,
        subtitle: iface['subtitle'],
        isUp: iface['isEnabled'],
        icon: Icons.wifi,
        headerTrailing: isSta
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$clientCount ${clientCount == 1 ? 'device' : 'devices'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        details: _buildWirelessDetails(context, iface),
        initiallyExpanded: shouldExpand,
      ),
    );
  }

  Widget _buildDisabledWirelessSection(
    BuildContext context,
    List<Map<String, dynamic>> disabledInterfaces,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: Icon(
              Icons.wifi_off_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              'Disabled Wi-Fi',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${disabledInterfaces.length} radio or SSID ${disabledInterfaces.length == 1 ? 'is' : 'are'} off',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            children: [
              for (final iface in disabledInterfaces)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: _buildWirelessCard(context, iface),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWirelessDetails(
    BuildContext context,
    Map<String, dynamic> iface,
  ) {
    final section = iface['section']?.toString() ?? '';
    final password = iface['password']?.toString() ?? '';
    final isSta = iface['isSta'] == true;
    final radioName = iface['radioName']?.toString() ?? '';
    final isInterfaceEnabled = iface['isEnabled'] == true;
    final isUpdating = isSta
        ? _updatingWirelessInterfaces.contains(section)
        : _updatingWirelessRadios.contains(radioName);
    final canShare =
        !isSta &&
        iface['isEnabled'] == true &&
        (iface['ssid']?.toString().trim().isNotEmpty ?? false);
    final primaryActions = <Widget>[
      if (section.isNotEmpty)
        _WirelessActionButton(
          label: 'Edit Wi-Fi',
          icon: Icons.tune_rounded,
          color: const Color(0xFFE85D8E),
          onPressed: () => _showEditWirelessSheet(section),
        ),
      _WirelessActionButton(
        label: 'Info',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF18A999),
        onPressed: () => _showWirelessInfoSheet(iface),
      ),
    ];
    final statusAction = _WirelessActionButton(
      label: isUpdating
          ? 'Wait'
          : isSta
          ? (isInterfaceEnabled ? 'Disconnect' : 'Connect')
          : (isInterfaceEnabled ? 'Enabled' : 'Disabled'),
      icon: isUpdating
          ? Icons.hourglass_top_rounded
          : isSta
          ? (isInterfaceEnabled ? Icons.link_off_rounded : Icons.link_rounded)
          : (isInterfaceEnabled
                ? Icons.check_circle_outline_rounded
                : Icons.power_settings_new_rounded),
      color: isSta && isInterfaceEnabled
          ? const Color(0xFFE85D8E)
          : const Color(0xFF18A999),
      onPressed: isUpdating
          ? null
          : isSta
          ? (section.isEmpty
                ? null
                : () => _setWirelessInterfaceEnabled(
                    context,
                    section,
                    !isInterfaceEnabled,
                  ))
          : (radioName.isEmpty
                ? null
                : () => _setWirelessRadioEnabled(
                    context,
                    radioName,
                    !isInterfaceEnabled,
                    interfaceSection: section.isEmpty ? null : section,
                  )),
    );
    return Column(
      children: [
        _buildDetailRow(context, 'SSID', iface['ssid']?.toString() ?? 'N/A'),
        _buildDetailRow(
          context,
          'Password',
          password.isEmpty ? 'No password set' : password,
          onTap: canShare ? () => _showShareWifiDialog(iface) : null,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (
                    var index = 0;
                    index < primaryActions.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: primaryActions[index]),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              statusAction,
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildWiredDetails(BuildContext context, NetworkInterface interface) {
    final canEditLan = _normalizeInterfaceKey(interface.name) == 'lan';
    final isWan = _normalizeInterfaceKey(interface.name) == 'wan';
    return Column(
      children: [
        _buildDetailRow(context, 'Device', interface.device),
        _buildDetailRow(context, 'Uptime', interface.formattedUptime),
        if (interface.ipAddress != null)
          _buildDetailRow(
            context,
            'IP Address',
            interface.ipAddress!,
            onTap: () =>
                _copyToClipboard(context, interface.ipAddress!, 'IP Address'),
          ),
        if (isWan)
          _buildDetailRow(
            context,
            'Public IP',
            _routerPublicIp ??
                (_isLoadingPublicIp ? 'Checking...' : 'Unavailable'),
            onTap: _routerPublicIp == null
                ? () => _loadRouterPublicIp(forceRefresh: true)
                : () =>
                      _copyToClipboard(context, _routerPublicIp!, 'Public IP'),
          ),
        if (interface.ipv6Addresses != null &&
            interface.ipv6Addresses!.isNotEmpty)
          ...interface.ipv6Addresses!.map(
            (ipv6) => _buildDetailRow(
              context,
              'IPv6 Address',
              ipv6,
              onTap: () => _copyToClipboard(context, ipv6, 'IPv6 Address'),
            ),
          ),
        if (interface.gateway != null)
          _buildDetailRow(
            context,
            'Gateway',
            interface.gateway!,
            onTap: () =>
                _copyToClipboard(context, interface.gateway!, 'Gateway IP'),
          ),
        if (interface.dnsServers.isNotEmpty)
          _buildDetailRow(
            context,
            'DNS',
            interface.dnsServers.join(', '),
            onTap: () => _copyToClipboard(
              context,
              interface.dnsServers.join(', '),
              'DNS Servers',
            ),
          ),
        // Add WireGuard peer information if this is a WireGuard interface
        if (interface.protocol.toLowerCase() == 'wireguard') ...[
          Builder(
            builder: (context) {
              return _buildWireGuardPeersSection(context, interface.name);
            },
          ),
        ],
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildStatsRow(context, interface.stats),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _updatingNetworkInterfaces.contains(interface.name)
                      ? null
                      : () => _runInterfaceAction(interface, restart: false),
                  icon: Icon(
                    interface.isUp
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(interface.isUp ? 'Stop' : 'On'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _updatingNetworkInterfaces.contains(interface.name)
                      ? null
                      : () => _runInterfaceAction(interface, restart: true),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Restart'),
                ),
              ),
              if (canEditLan) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        _updatingNetworkInterfaces.contains(interface.name)
                        ? null
                        : () => _showEditInterfaceSheet(interface),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildWireGuardPeersSection(
    BuildContext context,
    String interfaceName,
  ) {
    final appState = ref.watch(appStateProvider);
    final wireguardData =
        appState.dashboardData?['wireguard'] as Map<String, dynamic>?;
    final peerData = wireguardData?[interfaceName];
    if (peerData == null) {
      return const SizedBox.shrink();
    }
    final peers = peerData['peers'] as Map<String, dynamic>?;
    if (peers == null || peers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: const Divider(height: 24, thickness: 1, indent: 0, endIndent: 0),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, thickness: 1, indent: 0, endIndent: 0),
          const SizedBox(height: 8),
          ...peers.values.map(
            (peer) =>
                _buildCohesivePeerRow(context, peer as Map<String, dynamic>),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCohesivePeerRow(
    BuildContext context,
    Map<String, dynamic> peer,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final publicKey = peer['public_key'] as String? ?? 'Unknown';
    final endpoint = peer['endpoint'] as String? ?? 'N/A';
    final peerName = peer['name'] as String?;
    int lastHandshake = 0;
    final rawHandshake = peer['last_handshake'] ?? peer['latest_handshake'];
    if (rawHandshake != null) {
      if (rawHandshake is int) {
        lastHandshake = rawHandshake;
      } else if (rawHandshake is String) {
        lastHandshake = int.tryParse(rawHandshake) ?? 0;
      }
    }
    final displayKey = publicKey.length > 16
        ? '${publicKey.substring(0, 8)}...${publicKey.substring(publicKey.length - 8)}'
        : publicKey;
    String formatHandshakeTime(int timestamp) {
      if (timestamp == 0) return 'Never';
      final now = DateTime.now();
      final handshakeTime = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
      );
      final difference = now.difference(handshakeTime);
      if (difference.inSeconds < 0) return 'Never';
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return '${difference.inSeconds}s ago';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.vpn_key, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  displayKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (peerName != null && peerName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                peerName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Last Handshake',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHandshakeTime(lastHandshake),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Endpoint',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      endpoint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String title,
    String value, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
                if (onTap != null)
                  GestureDetector(
                    onTap: onTap,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(
                        Icons.copy_all_outlined,
                        size: 16,
                        semanticLabel: 'Copy',
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

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, Map<String, dynamic> stats) {
    String formatBytes(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ["B", "KB", "MB", "GB", "TB"];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatColumn(
          context,
          'Received',
          formatBytes(stats['rx_bytes'] ?? 0),
          Icons.arrow_downward,
          Colors.green,
        ),
        _buildStatColumn(
          context,
          'Transmitted',
          formatBytes(stats['tx_bytes'] ?? 0),
          Icons.arrow_upward,
          Colors.blue,
        ),
      ],
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  IconData _getInterfaceIcon(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'wireguard':
        return Icons.shield_outlined;
      case 'static':
        return Icons.settings_ethernet;
      case 'dhcp':
        return Icons.dns_outlined;
      default:
        return Icons.device_hub_outlined;
    }
  }

  String _buildMinimalInterfaceSubtitle(NetworkInterface iface) {
    final v4 = iface.ipAddress;
    final v6s = iface.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != null) {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return iface.protocol;
    if (extra > 0) {
      return '${iface.protocol} • $shown  +$extra';
    } else {
      return '${iface.protocol} • $shown';
    }
  }
}

class LuciSectionHeader extends StatelessWidget {
  final String title;
  const LuciSectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NetworkPanelSwitcher extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _NetworkPanelSwitcher({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const tabs = ['Interfaces', 'Port Forwarding', 'Firewall'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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

class _WirelessPanelSwitcher extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _WirelessPanelSwitcher({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const tabs = ['Wi-Fi', 'Repeater'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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

class _NetworkPanelDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _NetworkPanelDots({required this.count, required this.currentIndex});

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

class _PortForwardingPanel extends StatelessWidget {
  final bool isLoading;
  final List<OpenwrtPortForward> forwards;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final ValueChanged<OpenwrtPortForward> onEdit;

  const _PortForwardingPanel({
    required this.isLoading,
    required this.forwards,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && forwards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final header = _NetworkPanelActionHeader(
      title: 'Port Forwarding',
      count: forwards.length,
      buttonLabel: 'Add',
      icon: Icons.add_rounded,
      onPressed: onAdd,
    );
    if (forwards.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          header,
          _NetworkPanelEmptyState(
            icon: Icons.low_priority_rounded,
            title: 'No Port Forwards',
            message: 'No firewall redirect rules were found on this router.',
            onRefresh: onRefresh,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        header,
        ...forwards.map(
          (forward) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PortForwardCard(
              forward: forward,
              onTap: () => onEdit(forward),
            ),
          ),
        ),
      ],
    );
  }
}

class _PortForwardCard extends StatelessWidget {
  final OpenwrtPortForward forward;
  final VoidCallback onTap;

  const _PortForwardCard({required this.forward, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = forward.enabled
        ? const Color(0xFF20CF70)
        : colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
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
                  Expanded(
                    child: Text(
                      forward.name,
                      style: LuciTextStyles.cardTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _NetworkBadge(
                    label: forward.enabled ? 'Enabled' : 'Disabled',
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _NetworkValueBlock(
                      label: '${forward.source.toUpperCase()} Port',
                      value: forward.wanPort,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NetworkValueBlock(
                      label: forward.destinationZone.toUpperCase(),
                      value:
                          '${forward.destinationIp}:${forward.destinationPort}',
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                forward.protocol.toUpperCase(),
                style: LuciTextStyles.cardSubtitle(
                  context,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirewallZoneUpdate {
  const _FirewallZoneUpdate({
    required this.networks,
    required this.input,
    required this.output,
    required this.forward,
    required this.masquerading,
    required this.mtuFix,
  });

  final List<String> networks;
  final String input;
  final String output;
  final String forward;
  final bool masquerading;
  final bool mtuFix;
}

class _FirewallZoneEditSheet extends StatefulWidget {
  const _FirewallZoneEditSheet({
    required this.zone,
    required this.availableNetworks,
  });

  final OpenwrtFirewallZone zone;
  final List<String> availableNetworks;

  @override
  State<_FirewallZoneEditSheet> createState() => _FirewallZoneEditSheetState();
}

class _FirewallZoneEditSheetState extends State<_FirewallZoneEditSheet> {
  static const _policies = ['ACCEPT', 'REJECT', 'DROP'];
  late final Set<String> _networks;
  late String _input;
  late String _output;
  late String _forward;
  late bool _masquerading;
  late bool _mtuFix;

  @override
  void initState() {
    super.initState();
    _networks = widget.zone.networks
        .split(RegExp(r'[,\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != 'Any')
        .toSet();
    _input = widget.zone.input;
    _output = widget.zone.output;
    _forward = widget.zone.forward;
    _masquerading = widget.zone.masquerading;
    _mtuFix = widget.zone.mtuFix;
  }

  void _save() {
    Navigator.of(context).pop(
      _FirewallZoneUpdate(
        networks: _networks.toList()..sort(),
        input: _input,
        output: _output,
        forward: _forward,
        masquerading: _masquerading,
        mtuFix: _mtuFix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit ${widget.zone.name.toUpperCase()} Zone',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'UCI section: ${widget.zone.section}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Covered Networks',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Interfaces assigned to this firewall zone',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: widget.availableNetworks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No logical network interfaces found.'),
                    )
                  : Column(
                      children: [
                        for (
                          var index = 0;
                          index < widget.availableNetworks.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(height: 1),
                          CheckboxListTile(
                            dense: true,
                            title: Text(widget.availableNetworks[index]),
                            value: _networks.contains(
                              widget.availableNetworks[index],
                            ),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _networks.add(widget.availableNetworks[index]);
                              } else {
                                _networks.remove(
                                  widget.availableNetworks[index],
                                );
                              }
                            }),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            Text(
              'Default Policies',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FirewallPolicyField(
                    label: 'Input',
                    value: _input,
                    policies: _policies,
                    onChanged: (value) => setState(() => _input = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FirewallPolicyField(
                    label: 'Output',
                    value: _output,
                    policies: _policies,
                    onChanged: (value) => setState(() => _output = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FirewallPolicyField(
                    label: 'Forward',
                    value: _forward,
                    policies: _policies,
                    onChanged: (value) => setState(() => _forward = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Masquerading (NAT)'),
              subtitle: const Text('Rewrite outgoing source addresses'),
              value: _masquerading,
              onChanged: (value) => setState(() => _masquerading = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('MSS Clamping'),
              subtitle: const Text('Adjust TCP MSS to the outgoing MTU'),
              value: _mtuFix,
              onChanged: (value) => setState(() => _mtuFix = value),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save Zone'),
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

class _FirewallPolicyField extends StatelessWidget {
  const _FirewallPolicyField({
    required this.label,
    required this.value,
    required this.policies,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> policies;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: policies.contains(value) ? value : 'REJECT',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 14,
        ),
      ),
      items: policies
          .map(
            (policy) => DropdownMenuItem(
              value: policy,
              child: Text(
                policy,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _FirewallZonesPanel extends StatelessWidget {
  final bool isLoading;
  final OpenwrtFirewallDefaults defaults;
  final List<OpenwrtFirewallZone> zones;
  final Future<void> Function() onRefresh;
  final ValueChanged<OpenwrtFirewallZone> onEdit;

  const _FirewallZonesPanel({
    required this.isLoading,
    required this.defaults,
    required this.zones,
    required this.onRefresh,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && zones.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (zones.isEmpty) {
      return _NetworkPanelEmptyState(
        icon: Icons.security_rounded,
        title: 'No Firewall Zones',
        message: 'No firewall zone sections were found on this router.',
        onRefresh: onRefresh,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const SizedBox(height: 12),
        const _FirewallSectionHeader(
          icon: Icons.shield_outlined,
          title: 'Global Default Policies',
        ),
        const SizedBox(height: 10),
        _FirewallDefaultsCard(defaults: defaults),
        const SizedBox(height: 18),
        const _FirewallSectionHeader(
          icon: Icons.layers_outlined,
          title: 'Firewall Zones Overview',
        ),
        const SizedBox(height: 10),
        ...zones.map(
          (zone) => _FirewallZoneCard(zone: zone, onEdit: () => onEdit(zone)),
        ),
      ],
    );
  }
}

class _FirewallSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FirewallSectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _FirewallDefaultsCard extends StatelessWidget {
  final OpenwrtFirewallDefaults defaults;

  const _FirewallDefaultsCard({required this.defaults});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            _FirewallPolicyRow(label: 'Default Input', value: defaults.input),
            const Divider(height: 1),
            _FirewallPolicyRow(label: 'Default Output', value: defaults.output),
            const Divider(height: 1),
            _FirewallPolicyRow(
              label: 'Default Forward',
              value: defaults.forward,
            ),
            const Divider(height: 1),
            _FirewallPolicyRow(
              label: 'SYN Flood Protection',
              value: defaults.synFloodProtection ? 'ENABLED' : 'DISABLED',
            ),
          ],
        ),
      ),
    );
  }
}

class _FirewallPolicyRow extends StatelessWidget {
  final String label;
  final String value;

  const _FirewallPolicyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = _firewallPolicyColor(context, value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _firewallPolicyColor(BuildContext context, String policy) {
  switch (policy.toUpperCase()) {
    case 'ACCEPT':
    case 'ENABLED':
      return const Color(0xFF20CF70);
    case 'REJECT':
      return const Color(0xFFF0A020);
    case 'DROP':
      return Theme.of(context).colorScheme.error;
    default:
      return const Color(0xFF1688D4);
  }
}

class _FirewallZoneCard extends StatelessWidget {
  final OpenwrtFirewallZone zone;
  final VoidCallback onEdit;

  const _FirewallZoneCard({required this.zone, required this.onEdit});

  Color _policyColor(BuildContext context, String policy) {
    return _firewallPolicyColor(context, policy);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWan = zone.name.toLowerCase().contains('wan');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isWan ? Icons.public_rounded : Icons.router_rounded,
                  color: isWan ? colorScheme.error : colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zone: ${zone.name.toUpperCase()}',
                    style: LuciTextStyles.cardTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (zone.masquerading)
                  const _NetworkBadge(
                    label: 'MASQUERADE (NAT)',
                    color: Color(0xFF1688D4),
                  ),
                IconButton(
                  tooltip: 'Edit ${zone.name} zone',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Covered Networks: ${zone.networks}',
              style: LuciTextStyles.cardSubtitle(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _FirewallCompactPolicy(
                    label: 'Input',
                    value: zone.input,
                    color: _policyColor(context, zone.input),
                  ),
                ),
                Expanded(
                  child: _FirewallCompactPolicy(
                    label: 'Output',
                    value: zone.output,
                    color: _policyColor(context, zone.output),
                  ),
                ),
                Expanded(
                  child: _FirewallCompactPolicy(
                    label: 'Forward',
                    value: zone.forward,
                    color: _policyColor(context, zone.forward),
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

class _FirewallCompactPolicy extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _FirewallCompactPolicy({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: LuciTextStyles.cardSubtitle(context)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _NetworkPanelActionHeader extends StatelessWidget {
  final String title;
  final int count;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onPressed;

  const _NetworkPanelActionHeader({
    required this.title,
    required this.count,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$title ($count)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _NetworkPanelEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRefresh;

  const _NetworkPanelEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: Column(
        children: [
          Icon(icon, size: 54, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: LuciTextStyles.cardSubtitle(context),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _NetworkBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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

class _NetworkValueBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;

  const _NetworkValueBlock({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LuciTextStyles.detailLabel(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: LuciTextStyles.detailValue(
            context,
          ).copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w900),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _AddPortForwardSheet extends ConsumerStatefulWidget {
  final OpenwrtPortForward? forward;
  final String routerIp;

  const _AddPortForwardSheet({this.forward, required this.routerIp});

  @override
  ConsumerState<_AddPortForwardSheet> createState() =>
      _AddPortForwardSheetState();
}

class _AddPortForwardSheetState extends ConsumerState<_AddPortForwardSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _externalPortController = TextEditingController();
  final _destinationIpController = TextEditingController();
  final _internalPortController = TextEditingController();
  String _sourceZone = 'wan';
  String _destinationZone = 'lan';
  String _protocol = 'tcp';
  bool _isSaving = false;

  bool get _isEditing => widget.forward != null;

  @override
  void initState() {
    super.initState();
    final forward = widget.forward;
    if (forward == null) return;
    _nameController.text = forward.name;
    _externalPortController.text = forward.wanPort == 'Any'
        ? ''
        : forward.wanPort;
    _destinationIpController.text = forward.destinationIp == 'Any'
        ? ''
        : forward.destinationIp;
    _internalPortController.text = forward.destinationPort == 'Any'
        ? ''
        : forward.destinationPort;
    _sourceZone = forward.source;
    _destinationZone =
        widget.routerIp.isNotEmpty &&
            forward.destinationIp == widget.routerIp &&
            forward.destinationZone == 'lan'
        ? 'router'
        : forward.destinationZone;
    final protocol = _normalizeProtocol(forward.protocol);
    _protocol = const {'tcp', 'udp', 'tcp udp'}.contains(protocol)
        ? protocol
        : 'tcp';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _externalPortController.dispose();
    _destinationIpController.dispose();
    _internalPortController.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _portValidator(String? value) {
    final error = _required(value);
    if (error != null) return error;
    final port = int.tryParse(value!.trim());
    if (port == null || port < 1 || port > 65535) {
      return 'Use a port from 1 to 65535';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appState = ref.read(appStateProvider);
      final forward = widget.forward;
      final destinationZone = _destinationZone == 'router'
          ? 'lan'
          : _destinationZone;
      final destinationIp = _destinationZone == 'router'
          ? widget.routerIp
          : _destinationIpController.text;
      if (forward == null) {
        await appState.addPortForward(
          name: _nameController.text,
          sourceZone: _sourceZone,
          externalPort: _externalPortController.text,
          protocol: _protocol,
          destinationZone: destinationZone,
          destinationIp: destinationIp,
          internalPort: _internalPortController.text,
        );
      } else {
        await appState.updatePortForward(
          forward,
          name: _nameController.text,
          sourceZone: _sourceZone,
          externalPort: _externalPortController.text,
          protocol: _protocol,
          destinationZone: destinationZone,
          destinationIp: destinationIp,
          internalPort: _internalPortController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Port forward updated.' : 'Port forward added.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Failed to update port forward: $e'
                : 'Failed to add port forward: $e',
          ),
        ),
      );
    }
  }

  List<String> _zones(String selected, {bool includeRouter = false}) {
    return <String>{
      'wan',
      'lan',
      if (includeRouter) 'router',
      selected,
    }.where((zone) => zone.trim().isNotEmpty).toList();
  }

  String _zoneLabel(String zone) {
    return zone == 'router' ? 'Router' : zone.toUpperCase();
  }

  List<DropdownMenuItem<String>> _zoneItems(
    BuildContext context,
    String selected, {
    bool includeRouter = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return _zones(selected, includeRouter: includeRouter)
        .map(
          (zone) => DropdownMenuItem(
            value: zone,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: zone == selected
                    ? colors.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: zone == selected
                    ? Border.all(color: colors.primary.withValues(alpha: 0.5))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _zoneLabel(zone),
                      style: TextStyle(
                        color: zone == selected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                        fontWeight: zone == selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (zone == selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                ],
              ),
            ),
          ),
        )
        .toList();
  }

  List<Widget> _selectedZoneItems(
    BuildContext context,
    String selected, {
    bool includeRouter = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return _zones(selected, includeRouter: includeRouter)
        .map(
          (zone) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _zoneLabel(zone),
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        )
        .toList();
  }

  String _normalizeProtocol(String value) {
    return value
        .toLowerCase()
        .replaceAll(',', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final colors = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.9,
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
                          _isEditing ? 'Edit Port Forward' : 'New Port Forward',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Route incoming traffic to a device on your network.',
                          style: LuciTextStyles.cardSubtitle(context),
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
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Rule Name',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                    validator: _required,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),
                  _PortForwardSectionLabel(
                    icon: Icons.public_rounded,
                    title: 'Incoming Traffic',
                    subtitle: 'Choose where the connection enters the router.',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.32,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _sourceZone,
                                borderRadius: BorderRadius.circular(8),
                                dropdownColor: colors.surfaceContainerHigh,
                                iconEnabledColor: colors.primary,
                                decoration: const InputDecoration(
                                  labelText: 'Source Zone',
                                  prefixIcon: Icon(Icons.shield_outlined),
                                ),
                                items: _zoneItems(context, _sourceZone),
                                selectedItemBuilder: (context) =>
                                    _selectedZoneItems(context, _sourceZone),
                                onChanged: (value) => setState(
                                  () => _sourceZone = value ?? 'wan',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _externalPortController,
                                decoration: const InputDecoration(
                                  labelText: 'External Port',
                                  prefixIcon: Icon(Icons.input_rounded),
                                ),
                                keyboardType: TextInputType.number,
                                validator: _portValidator,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Protocol',
                            style: LuciTextStyles.detailLabel(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'tcp', label: Text('TCP')),
                              ButtonSegment(value: 'udp', label: Text('UDP')),
                              ButtonSegment(
                                value: 'tcp udp',
                                label: Text('Both'),
                              ),
                            ],
                            selected: {_protocol},
                            onSelectionChanged: (selection) =>
                                setState(() => _protocol = selection.first),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      color: colors.primary,
                    ),
                  ),
                  _PortForwardSectionLabel(
                    icon: Icons.devices_rounded,
                    title: 'Forward To',
                    subtitle: 'Select the internal destination for traffic.',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.32,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _destinationZone,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: colors.surfaceContainerHigh,
                          iconEnabledColor: colors.primary,
                          decoration: const InputDecoration(
                            labelText: 'Destination Zone',
                            prefixIcon: Icon(Icons.lan_outlined),
                          ),
                          items: _zoneItems(
                            context,
                            _destinationZone,
                            includeRouter: true,
                          ),
                          selectedItemBuilder: (context) => _selectedZoneItems(
                            context,
                            _destinationZone,
                            includeRouter: true,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _destinationZone = value ?? 'lan';
                              if (_destinationZone == 'router') {
                                _destinationIpController.text = widget.routerIp;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _destinationIpController,
                          decoration: InputDecoration(
                            labelText: 'Destination IP Address',
                            prefixIcon: const Icon(Icons.computer_rounded),
                            helperText: _destinationZone == 'router'
                                ? 'Router local address'
                                : null,
                          ),
                          validator: _required,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          readOnly: _destinationZone == 'router',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _internalPortController,
                          decoration: const InputDecoration(
                            labelText: 'Destination Port',
                            prefixIcon: Icon(Icons.output_rounded),
                          ),
                          keyboardType: TextInputType.number,
                          validator: _portValidator,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _save(),
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
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isEditing ? Icons.save_rounded : Icons.add_rounded,
                          ),
                    label: Text(
                      _isSaving
                          ? 'Saving'
                          : _isEditing
                          ? 'Save Rule'
                          : 'Create Rule',
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

class _PortForwardSectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PortForwardSectionLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
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
              Text(subtitle, style: LuciTextStyles.cardSubtitle(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareWifiSheet extends StatelessWidget {
  final String ssid;
  final String password;
  final String qrData;

  const _ShareWifiSheet({
    required this.ssid,
    required this.password,
    required this.qrData,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share Wi-Fi',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ssid,
              textAlign: TextAlign.left,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Password',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              child: SelectableText(
                password.isEmpty ? 'No password set' : password,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: password.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: password));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Wi-Fi password copied.'),
                              ),
                            );
                          },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
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

class _NetworkInterfaceEditSheet extends ConsumerStatefulWidget {
  final String interfaceName;

  const _NetworkInterfaceEditSheet({required this.interfaceName});

  @override
  ConsumerState<_NetworkInterfaceEditSheet> createState() =>
      _NetworkInterfaceEditSheetState();
}

class _NetworkInterfaceEditSheetState
    extends ConsumerState<_NetworkInterfaceEditSheet> {
  final _ipController = TextEditingController();
  final _netmaskController = TextEditingController();
  final _dnsController = TextEditingController();
  final _startIpController = TextEditingController();
  final _endIpController = TextEditingController();
  final _leaseTimeController = TextEditingController();
  OpenwrtNetworkInterfaceConfig? _config;
  var _protocol = 'static';
  var _dhcpEnabled = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _ipController.dispose();
    _netmaskController.dispose();
    _dnsController.dispose();
    _startIpController.dispose();
    _endIpController.dispose();
    _leaseTimeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref
        .read(appStateProvider)
        .fetchNetworkInterfaceConfig(widget.interfaceName, context: context);
    if (!mounted) return;
    if (config == null) {
      setState(() => _isLoading = false);
      return;
    }
    _config = config;
    _protocol = config.protocol;
    _dhcpEnabled = config.dhcpEnabled;
    _ipController.text = config.ipAddress;
    _netmaskController.text = config.netmask;
    _dnsController.text = config.dnsText;
    _startIpController.text = _offsetToIp(
      config.ipAddress,
      config.netmask,
      config.dhcpStart,
    );
    _endIpController.text = _offsetToIp(
      config.ipAddress,
      config.netmask,
      config.dhcpStart + config.dhcpLimit - 1,
    );
    _leaseTimeController.text = config.leaseTime;
    setState(() => _isLoading = false);
  }

  String _offsetToIp(String routerIp, String netmask, int offset) {
    final router = _ipv4ToInt(routerIp);
    final mask = _ipv4ToInt(netmask);
    if (router == null || mask == null || offset <= 0) {
      return offset.toString();
    }
    return _intToIpv4((router & mask) + offset);
  }

  int _dhcpOffsetOrNumber(
    String value,
    int fallback,
    int routerIp,
    int netmask,
  ) {
    final trimmed = value.trim();
    final ip = _ipv4ToInt(trimmed);
    if (ip != null) return ip - (routerIp & netmask);
    return int.tryParse(trimmed) ?? fallback;
  }

  int? _ipv4ToInt(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return null;
    var result = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      result = (result << 8) + octet;
    }
    return result;
  }

  String _intToIpv4(int value) {
    return [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ].join('.');
  }

  bool _isContiguousNetmask(int mask) {
    final inverted = (~mask) & 0xffffffff;
    return mask != 0 && (inverted & (inverted + 1)) == 0;
  }

  String? _validateLanConfig({
    required String ipAddress,
    required String netmask,
    required int dhcpStart,
    required int dhcpEnd,
  }) {
    final routerIp = _ipv4ToInt(ipAddress);
    if (routerIp == null) return 'Enter a valid LAN IPv4 address.';

    final mask = _ipv4ToInt(netmask);
    if (mask == null || !_isContiguousNetmask(mask)) {
      return 'Enter a valid contiguous subnet mask.';
    }

    if (!_dhcpEnabled) return null;

    final network = routerIp & mask;
    final broadcast = network | ((~mask) & 0xffffffff);
    final startIp = network + dhcpStart;
    final endIp = network + dhcpEnd;

    if (dhcpStart <= 0 || dhcpEnd <= 0 || startIp > endIp) {
      return 'Enter a valid DHCP start and end IP range.';
    }
    if (startIp <= network || endIp >= broadcast) {
      return 'DHCP range must stay inside the LAN subnet and cannot use the network or broadcast address.';
    }
    if (routerIp >= startIp && routerIp <= endIp) {
      return 'DHCP range cannot include the router LAN IP address.';
    }
    return null;
  }

  Future<void> _save() async {
    final current = _config;
    if (current == null) return;
    final ipAddress = _ipController.text.trim();
    final netmask = _netmaskController.text.trim();
    final routerIp = _ipv4ToInt(ipAddress);
    final mask = _ipv4ToInt(netmask);
    final start = routerIp == null || mask == null
        ? current.dhcpStart
        : _dhcpOffsetOrNumber(
            _startIpController.text,
            current.dhcpStart,
            routerIp,
            mask,
          ).clamp(1, 65534);
    final end = routerIp == null || mask == null
        ? current.dhcpStart + current.dhcpLimit - 1
        : _dhcpOffsetOrNumber(
            _endIpController.text,
            current.dhcpStart + current.dhcpLimit - 1,
            routerIp,
            mask,
          ).clamp(1, 65534);
    final validationError = _validateLanConfig(
      ipAddress: ipAddress,
      netmask: netmask,
      dhcpStart: start,
      dhcpEnd: end,
    );
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    final dnsServers = _dnsController.text
        .split(RegExp(r'[\s,]+'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();

    final next = current.copyWith(
      protocol: _protocol,
      ipAddress: ipAddress,
      netmask: netmask,
      dnsServers: dnsServers,
      dhcpEnabled: _dhcpEnabled,
      dhcpStart: start,
      dhcpLimit: end - start + 1,
      leaseTime: _leaseTimeController.text.trim().isEmpty
          ? '12h'
          : _leaseTimeController.text.trim(),
    );

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveNetworkInterfaceConfig(next, context: context);
      if (!mounted) return;
      final changedLanAddress =
          current.ipAddress.trim() != next.ipAddress.trim() ||
          current.netmask.trim() != next.netmask.trim();
      if (changedLanAddress) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('LAN address updated'),
            content: Text(
              'The router may now be reachable at ${next.ipAddress}. Log out and log back in with the new IP address if the app disconnects.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save interface: $e')));
      setState(() => _isSaving = false);
    }
  }

  bool get _showDhcp {
    final name = widget.interfaceName.toLowerCase();
    return name == 'lan' || _config?.dhcpSection != null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(child: CircularProgressIndicator()),
              )
            : _config == null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Unable to load ${widget.interfaceName}.'),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.router_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.interfaceName.toUpperCase()} Settings',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'IPv4 and DHCP configuration',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Close',
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'IPv4',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FormPanel(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _protocol,
                          decoration: const InputDecoration(
                            labelText: 'Protocol',
                            prefixIcon: Icon(Icons.settings_ethernet_rounded),
                          ),
                          items: const ['static', 'dhcp', 'dhcpv6', 'wireguard']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(
                                  () => _protocol = value ?? _protocol,
                                ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _ipController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            hintText: '192.168.10.1',
                            prefixIcon: Icon(Icons.dns_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _netmaskController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Subnet Mask',
                            hintText: '255.255.255.0',
                            prefixIcon: Icon(Icons.grid_4x4_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dnsController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Upstream DNS Servers',
                            hintText: '1.1.1.1 8.8.8.8',
                            prefixIcon: Icon(Icons.travel_explore_rounded),
                          ),
                        ),
                      ],
                    ),
                    if (_showDhcp) ...[
                      const SizedBox(height: 16),
                      Text(
                        'DHCPv4 Server',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _FormPanel(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.36),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('DHCPv4 Server'),
                              subtitle: const Text(
                                'Assign addresses to LAN devices',
                              ),
                              value: _dhcpEnabled,
                              onChanged: _isSaving
                                  ? null
                                  : (value) =>
                                        setState(() => _dhcpEnabled = value),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _startIpController,
                            enabled: !_isSaving && _dhcpEnabled,
                            decoration: const InputDecoration(
                              labelText: 'Start IP Address',
                              hintText: '192.168.10.100',
                              prefixIcon: Icon(Icons.first_page_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _endIpController,
                            enabled: !_isSaving && _dhcpEnabled,
                            decoration: const InputDecoration(
                              labelText: 'End IP Address',
                              hintText: '192.168.10.249',
                              prefixIcon: Icon(Icons.last_page_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _leaseTimeController,
                            enabled: !_isSaving && _dhcpEnabled,
                            decoration: const InputDecoration(
                              labelText: 'Lease Time',
                              hintText: '12h',
                              prefixIcon: Icon(Icons.schedule_rounded),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Dismiss'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _save,
                            icon: _isSaving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: const Text('Save'),
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

class _WirelessJoinSheet extends ConsumerStatefulWidget {
  const _WirelessJoinSheet();

  @override
  ConsumerState<_WirelessJoinSheet> createState() => _WirelessJoinSheetState();
}

class _WirelessJoinSheetState extends ConsumerState<_WirelessJoinSheet> {
  List<Map<String, String>> _radios = const [];
  List<WifiScanResult> _results = const [];
  WifiScanResult? _selected;
  String? _selectedRadio;
  bool _isScanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final radios = ref.read(appStateProvider).availableWirelessScanDevices();
      if (!mounted) return;
      setState(() {
        _radios = radios;
        _selectedRadio = radios.firstOrNull?['radio'];
      });
      _scan();
    });
  }

  String get _scanDevice {
    final selected = _radios.firstWhere(
      (entry) => entry['radio'] == _selectedRadio,
      orElse: () => _radios.isNotEmpty
          ? _radios.first
          : {'radio': 'radio0', 'device': 'radio0', 'label': 'radio0'},
    );
    return selected['device'] ?? selected['radio'] ?? 'radio0';
  }

  String get _uciRadioDevice {
    final selected = _radios.firstWhere(
      (entry) => entry['radio'] == _selectedRadio,
      orElse: () => _radios.isNotEmpty
          ? _radios.first
          : {'radio': 'radio0', 'uciRadio': 'radio0'},
    );
    return selected['uciRadio'] ?? selected['radio'] ?? 'radio0';
  }

  Future<void> _scan() async {
    if (_selectedRadio == null || _isScanning) return;
    setState(() {
      _isScanning = true;
      _error = null;
      _selected = null;
    });
    try {
      final results = await ref
          .read(appStateProvider)
          .scanWirelessNetworks(device: _scanDevice, context: context);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Scan failed: $e';
        _results = const [];
        _isScanning = false;
      });
    }
  }

  Future<void> _showConnectionDetails() async {
    final radio = _selectedRadio;
    final selected = _selected;
    if (radio == null || selected == null) return;
    if (selected.encryption.openwrtEncryption == 'wpa-eap') {
      setState(() => _error = 'Enterprise Wi-Fi is not supported yet.');
      return;
    }
    setState(() => _error = null);
    final joined = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RepeaterConnectionSheet(
        radioDevice: _uciRadioDevice,
        network: selected,
      ),
    );
    if (joined == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  IconData _signalIcon(WifiScanResult result) {
    if (result.signal >= -55) return Icons.wifi_rounded;
    if (result.signal >= -70) return Icons.wifi_2_bar_rounded;
    return Icons.wifi_1_bar_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selected;
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
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.wifi_find_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Join Wi-Fi as WAN',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Connect this router to another Wi-Fi network.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedRadio),
                      initialValue: _selectedRadio,
                      decoration: const InputDecoration(
                        labelText: 'Radio',
                        prefixIcon: Icon(Icons.router_rounded),
                      ),
                      items: _radios
                          .map(
                            (radio) => DropdownMenuItem(
                              value: radio['radio'],
                              child: Text(radio['label'] ?? radio['radio']!),
                            ),
                          )
                          .toList(),
                      onChanged: _isScanning
                          ? null
                          : (value) {
                              setState(() => _selectedRadio = value);
                              _scan();
                            },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isScanning ? null : _scan,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                _results.isEmpty && !_isScanning
                    ? 'No networks found'
                    : 'Nearby networks',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: _isScanning && _results.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          final isSelected = identical(result, selected);
                          final title = result.ssid.trim().isEmpty
                              ? 'Hidden network'
                              : result.ssid;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _selected = result),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primary.withValues(
                                        alpha: 0.14,
                                      )
                                    : colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? colorScheme.primary.withValues(
                                          alpha: 0.55,
                                        )
                                      : colorScheme.outlineVariant.withValues(
                                          alpha: 0.35,
                                        ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _signalIcon(result),
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${result.band} • ${result.encryption.shortLabel} • ${result.signal} dBm',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: colorScheme.primary,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selected == null ? null : _showConnectionDetails,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeaterConnectionSheet extends ConsumerStatefulWidget {
  final String radioDevice;
  final WifiScanResult network;

  const _RepeaterConnectionSheet({
    required this.radioDevice,
    required this.network,
  });

  @override
  ConsumerState<_RepeaterConnectionSheet> createState() =>
      _RepeaterConnectionSheetState();
}

class _RepeaterConnectionSheetState
    extends ConsumerState<_RepeaterConnectionSheet> {
  final _passwordController = TextEditingController();
  final _hiddenSsidController = TextEditingController();
  bool _showPassword = false;
  bool _isJoining = false;
  String? _error;

  bool get _needsPassword =>
      widget.network.encryption.enabled &&
      widget.network.encryption.openwrtEncryption != 'owe';

  @override
  void dispose() {
    _passwordController.dispose();
    _hiddenSsidController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final ssid = widget.network.ssid.trim().isEmpty
        ? _hiddenSsidController.text.trim()
        : widget.network.ssid.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'SSID is required.');
      return;
    }
    if (_needsPassword && _passwordController.text.length < 8) {
      setState(() => _error = 'Wi-Fi password must be at least 8 characters.');
      return;
    }
    setState(() {
      _isJoining = true;
      _error = null;
    });
    try {
      await ref
          .read(appStateProvider)
          .connectWirelessWwan(
            radioDevice: widget.radioDevice,
            network: widget.network,
            ssid: ssid,
            password: _passwordController.text,
            context: context,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final detail = e
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '')
          .trim();
      setState(() {
        _isJoining = false;
        _error = detail.isEmpty
            ? 'Could not connect to $ssid.'
            : 'Could not connect to $ssid. $detail';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final networkName = widget.network.ssid.trim().isEmpty
        ? 'Hidden network'
        : widget.network.ssid;
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
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.wifi_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect to Wi-Fi',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Enter the connection details for this network.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isJoining
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi_rounded, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            networkName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${widget.network.band} • ${widget.network.encryption.shortLabel} • ${widget.network.signal} dBm',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (widget.network.ssid.trim().isEmpty) ...[
                TextField(
                  controller: _hiddenSsidController,
                  enabled: !_isJoining,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Network name (SSID)',
                    prefixIcon: Icon(Icons.wifi_rounded),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_needsPassword) ...[
                TextField(
                  controller: _passwordController,
                  enabled: !_isJoining,
                  autofocus: widget.network.ssid.trim().isNotEmpty,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _isJoining ? null : _join(),
                  decoration: InputDecoration(
                    labelText: 'Wi-Fi password',
                    hintText: 'Enter network password',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use the password for $networkName.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No password is required for this network.',
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isJoining ? null : _join,
                  icon: _isJoining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text(_isJoining ? 'Connecting...' : 'Connect'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WirelessNetworkEditSheet extends ConsumerStatefulWidget {
  final String section;

  const _WirelessNetworkEditSheet({required this.section});

  @override
  ConsumerState<_WirelessNetworkEditSheet> createState() =>
      _WirelessNetworkEditSheetState();
}

class _WirelessNetworkEditSheetState
    extends ConsumerState<_WirelessNetworkEditSheet> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _txPowerController = TextEditingController();
  OpenwrtWirelessNetworkConfig? _config;
  bool _enabled = true;
  bool _hidden = false;
  bool _showPassword = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _txPowerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref
        .read(appStateProvider)
        .fetchWirelessNetworkConfig(widget.section, context: context);
    if (!mounted) return;
    if (config == null) {
      setState(() => _isLoading = false);
      return;
    }
    _config = config;
    _ssidController.text = config.ssid;
    _passwordController.text = config.password;
    _txPowerController.text = config.txPower?.toString() ?? '';
    _enabled = config.enabled;
    _hidden = config.hidden;
    setState(() => _isLoading = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final current = _config;
    if (current == null) return;
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      _showError('SSID is required.');
      return;
    }
    final password = _passwordController.text;
    final currentEncryption = current.encryption.trim().toLowerCase();
    final isOpenNetwork =
        currentEncryption.isEmpty ||
        currentEncryption == 'none' ||
        currentEncryption == 'open';
    final encryption = password.isNotEmpty && isOpenNetwork
        ? 'psk2'
        : (currentEncryption.isEmpty ? 'none' : currentEncryption);
    if (encryption != 'none' && encryption != 'owe' && password.length < 8) {
      _showError('Wi-Fi password must be at least 8 characters.');
      return;
    }
    final txText = _txPowerController.text.trim();
    final txPower = txText.isEmpty ? null : int.tryParse(txText);
    if (txText.isNotEmpty && (txPower == null || txPower < 0 || txPower > 40)) {
      _showError('TX power must be a number from 0 to 40.');
      return;
    }

    final next = current.copyWith(
      ssid: ssid,
      password: password,
      encryption: encryption,
      enabled: _enabled,
      hidden: _hidden,
      txPower: txPower,
    );

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveWirelessNetworkConfig(next, context: context);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save Wi-Fi settings: $e');
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(child: CircularProgressIndicator()),
              )
            : _config == null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Unable to load ${widget.section}.'),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Edit Wi-Fi',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
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
                    const SizedBox(height: 6),
                    Text(
                      _config!.radioSection.isEmpty
                          ? widget.section
                          : '${widget.section} on ${_config!.radioSection}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FormPanel(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Wi-Fi On'),
                          subtitle: const Text('Enable or disable this SSID'),
                          value: _enabled,
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(() => _enabled = value),
                        ),
                        const Divider(height: 20),
                        TextField(
                          controller: _ssidController,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'SSID',
                            hintText: 'Openwalla',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          enabled: !_isSaving,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'At least 8 characters',
                            suffixIcon: IconButton(
                              tooltip: _showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: _isSaving
                                  ? null
                                  : () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Radio',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FormPanel(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('SSID Visible'),
                          subtitle: const Text(
                            'Hide the network name when off',
                          ),
                          value: !_hidden,
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(() => _hidden = !value),
                        ),
                        const Divider(height: 20),
                        TextField(
                          controller: _txPowerController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'TX Power',
                            hintText: 'Auto',
                            suffixText: 'dBm',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Dismiss'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _save,
                            icon: _isSaving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: const Text('Save'),
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

class _FormPanel extends StatelessWidget {
  final List<Widget> children;

  const _FormPanel({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _WirelessActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _WirelessActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        backgroundColor: Colors.transparent,
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        overlayColor: color.withValues(alpha: 0.08),
        textStyle: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _UnifiedNetworkCard extends StatefulWidget {
  final String name;
  final String subtitle;
  final bool isUp;
  final IconData icon;
  final Widget details;
  final Widget? headerTrailing;
  final bool initiallyExpanded;

  const _UnifiedNetworkCard({
    required this.name,
    required this.subtitle,
    required this.isUp,
    required this.icon,
    required this.details,
    this.headerTrailing,
    this.initiallyExpanded = false,
    super.key,
  });

  @override
  State<_UnifiedNetworkCard> createState() => _UnifiedNetworkCardState();
}

class _UnifiedNetworkCardState extends State<_UnifiedNetworkCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    if (widget.initiallyExpanded) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _UnifiedNetworkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      setState(() {
        _isExpanded = widget.initiallyExpanded;
        if (_isExpanded) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final card = Card(
      elevation: _isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(
          color: widget.initiallyExpanded && _isExpanded
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: widget.initiallyExpanded && _isExpanded ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedScale(
        scale: widget.initiallyExpanded && _isExpanded ? 1.02 : 1.0,
        duration: LuciAnimations.standard,
        curve: Curves.easeOutBack,
        child: Column(
          children: [
            InkWell(
              onTap: _toggleExpand,
              borderRadius: LuciCardStyles.standardRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuciSpacing.lg,
                  vertical: 10.0,
                ),
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
                          child: AnimatedScale(
                            scale: widget.initiallyExpanded && _isExpanded
                                ? 1.1
                                : 1.0,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.elasticOut,
                            child: Icon(
                              widget.icon,
                              color: widget.isUp
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                              size: 22,
                              semanticLabel: 'Interface icon',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tooltip(
                            message: widget.isUp
                                ? 'Interface is up'
                                : 'Interface is down',
                            child: LuciStatusIndicators.statusDot(
                              context,
                              widget.isUp,
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
                          Text(
                            widget.name,
                            style: LuciTextStyles.cardTitle(context),
                            semanticsLabel: 'Interface name: ${widget.name}',
                          ),
                          const SizedBox(height: LuciSpacing.xs),
                          Container(
                            margin: const EdgeInsets.only(right: 32),
                            child: Divider(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.10),
                              thickness: 1,
                              height: 8,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: LuciTextStyles.cardSubtitle(context),
                            semanticsLabel:
                                'Interface details: ${widget.subtitle}',
                          ),
                        ],
                      ),
                    ),
                    if (widget.headerTrailing != null)
                      widget.headerTrailing!
                    else if (!widget.isUp)
                      Padding(
                        padding: const EdgeInsets.only(right: LuciSpacing.xs),
                        child: LuciStatusIndicators.statusChip(
                          context,
                          'OFF',
                          false,
                        ),
                      ),
                    const SizedBox(width: LuciSpacing.sm),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 26,
                      semanticLabel: _isExpanded
                          ? 'Collapse details'
                          : 'Expand details',
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 18, endIndent: 18),
                  widget.details,
                ],
              ),
          ],
        ),
      ),
    );

    if (!widget.isUp) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: card,
      );
    }
    return card;
  }
}
