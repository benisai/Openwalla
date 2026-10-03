enum DashboardFlowMode { detailed, simple }

class DashboardPreferences {
  final Set<String> enabledWirelessInterfaces;
  final Set<String> enabledWiredInterfaces;
  final bool wirelessInterfaceSelectionInitialized;
  final bool wiredInterfaceSelectionInitialized;
  final String? primaryThroughputInterface;
  final bool showAllThroughput;
  final bool showNetworkPerformanceCard;
  final bool showFlowsCard;
  final bool showStatisticsTab;
  final bool showWifiShortcut;
  final bool showSmartQueueShortcut;
  final bool showAdblockShortcut;
  final bool showVpnShortcut;
  final bool showParentalShortcut;
  final bool showSchedulerShortcut;
  final bool showDdnsShortcut;
  final bool showTorShortcut;
  final bool showTailscaleShortcut;
  final bool showMultiWanShortcut;
  final bool showQuarantineShortcut;
  final bool showInactiveWirelessNetworks;
  final int shortcutPanelVisibleCount;
  final List<String> shortcutOrder;
  final int liveThroughputRefreshSeconds;
  final int systemResourcesRefreshSeconds;
  final DashboardFlowMode flowMode;

  DashboardPreferences({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    this.wirelessInterfaceSelectionInitialized = false,
    this.wiredInterfaceSelectionInitialized = false,
    this.primaryThroughputInterface,
    this.showAllThroughput = true,
    this.showNetworkPerformanceCard = false,
    this.showFlowsCard = false,
    this.showStatisticsTab = false,
    this.showWifiShortcut = true,
    this.showSmartQueueShortcut = true,
    this.showAdblockShortcut = true,
    this.showVpnShortcut = true,
    this.showParentalShortcut = true,
    this.showSchedulerShortcut = true,
    this.showDdnsShortcut = true,
    this.showTorShortcut = true,
    this.showTailscaleShortcut = true,
    this.showMultiWanShortcut = true,
    this.showQuarantineShortcut = true,
    this.showInactiveWirelessNetworks = false,
    this.shortcutPanelVisibleCount = 6,
    List<String>? shortcutOrder,
    this.liveThroughputRefreshSeconds = 3,
    this.systemResourcesRefreshSeconds = 5,
    this.flowMode = DashboardFlowMode.detailed,
  }) : enabledWirelessInterfaces = enabledWirelessInterfaces ?? {},
       enabledWiredInterfaces = enabledWiredInterfaces ?? {},
       shortcutOrder = shortcutOrder ?? defaultShortcutOrder;

  static const defaultShortcutOrder = [
    'network',
    'dns',
    'wifi',
    'routes',
    'smart_queue',
    'adblock',
    'services',
    'vpn',
    'parental',
    'scheduler',
    'ddns',
    'tor',
    'tailscale',
    'multi_wan',
    'quarantine',
  ];

  DashboardPreferences copyWith({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    bool? wirelessInterfaceSelectionInitialized,
    bool? wiredInterfaceSelectionInitialized,
    String? primaryThroughputInterface,
    bool? showAllThroughput,
    bool? showNetworkPerformanceCard,
    bool? showFlowsCard,
    bool? showStatisticsTab,
    bool? showWifiShortcut,
    bool? showSmartQueueShortcut,
    bool? showAdblockShortcut,
    bool? showVpnShortcut,
    bool? showParentalShortcut,
    bool? showSchedulerShortcut,
    bool? showDdnsShortcut,
    bool? showTorShortcut,
    bool? showTailscaleShortcut,
    bool? showMultiWanShortcut,
    bool? showQuarantineShortcut,
    bool? showInactiveWirelessNetworks,
    int? shortcutPanelVisibleCount,
    List<String>? shortcutOrder,
    int? liveThroughputRefreshSeconds,
    int? systemResourcesRefreshSeconds,
    DashboardFlowMode? flowMode,
  }) {
    return DashboardPreferences(
      enabledWirelessInterfaces:
          enabledWirelessInterfaces ?? this.enabledWirelessInterfaces,
      enabledWiredInterfaces:
          enabledWiredInterfaces ?? this.enabledWiredInterfaces,
      wirelessInterfaceSelectionInitialized:
          wirelessInterfaceSelectionInitialized ??
          this.wirelessInterfaceSelectionInitialized,
      wiredInterfaceSelectionInitialized:
          wiredInterfaceSelectionInitialized ??
          this.wiredInterfaceSelectionInitialized,
      primaryThroughputInterface:
          primaryThroughputInterface ?? this.primaryThroughputInterface,
      showAllThroughput: showAllThroughput ?? this.showAllThroughput,
      showNetworkPerformanceCard:
          showNetworkPerformanceCard ?? this.showNetworkPerformanceCard,
      showFlowsCard: showFlowsCard ?? this.showFlowsCard,
      showStatisticsTab: showStatisticsTab ?? this.showStatisticsTab,
      showWifiShortcut: showWifiShortcut ?? this.showWifiShortcut,
      showSmartQueueShortcut:
          showSmartQueueShortcut ?? this.showSmartQueueShortcut,
      showAdblockShortcut: showAdblockShortcut ?? this.showAdblockShortcut,
      showVpnShortcut: showVpnShortcut ?? this.showVpnShortcut,
      showParentalShortcut: showParentalShortcut ?? this.showParentalShortcut,
      showSchedulerShortcut:
          showSchedulerShortcut ?? this.showSchedulerShortcut,
      showDdnsShortcut: showDdnsShortcut ?? this.showDdnsShortcut,
      showTorShortcut: showTorShortcut ?? this.showTorShortcut,
      showTailscaleShortcut:
          showTailscaleShortcut ?? this.showTailscaleShortcut,
      showMultiWanShortcut: showMultiWanShortcut ?? this.showMultiWanShortcut,
      showQuarantineShortcut:
          showQuarantineShortcut ?? this.showQuarantineShortcut,
      showInactiveWirelessNetworks:
          showInactiveWirelessNetworks ?? this.showInactiveWirelessNetworks,
      shortcutPanelVisibleCount:
          shortcutPanelVisibleCount ?? this.shortcutPanelVisibleCount,
      shortcutOrder: shortcutOrder ?? this.shortcutOrder,
      liveThroughputRefreshSeconds:
          liveThroughputRefreshSeconds ?? this.liveThroughputRefreshSeconds,
      systemResourcesRefreshSeconds:
          systemResourcesRefreshSeconds ?? this.systemResourcesRefreshSeconds,
      flowMode: flowMode ?? this.flowMode,
    );
  }

  DashboardPreferences copyWithShortcutVisibility(
    String shortcutId, {
    required bool visible,
  }) {
    return switch (shortcutId) {
      'wifi' => copyWith(showWifiShortcut: visible),
      'smart_queue' => copyWith(showSmartQueueShortcut: visible),
      'adblock' => copyWith(showAdblockShortcut: visible),
      'vpn' => copyWith(showVpnShortcut: visible),
      'parental' => copyWith(showParentalShortcut: visible),
      'scheduler' => copyWith(showSchedulerShortcut: visible),
      'ddns' => copyWith(showDdnsShortcut: visible),
      'tor' => copyWith(showTorShortcut: visible),
      'tailscale' => copyWith(showTailscaleShortcut: visible),
      'multi_wan' => copyWith(showMultiWanShortcut: visible),
      'quarantine' => copyWith(showQuarantineShortcut: visible),
      _ => this,
    };
  }

  Map<String, dynamic> toJson() => {
    'enabledWirelessInterfaces': enabledWirelessInterfaces.toList(),
    'enabledWiredInterfaces': enabledWiredInterfaces.toList(),
    'wirelessInterfaceSelectionInitialized':
        wirelessInterfaceSelectionInitialized,
    'wiredInterfaceSelectionInitialized': wiredInterfaceSelectionInitialized,
    'primaryThroughputInterface': primaryThroughputInterface,
    'showAllThroughput': showAllThroughput,
    'showNetworkPerformanceCard': showNetworkPerformanceCard,
    'showFlowsCard': showFlowsCard,
    'showStatisticsTab': showStatisticsTab,
    'showWifiShortcut': showWifiShortcut,
    'showSmartQueueShortcut': showSmartQueueShortcut,
    'showAdblockShortcut': showAdblockShortcut,
    'showVpnShortcut': showVpnShortcut,
    'showParentalShortcut': showParentalShortcut,
    'showCronSchedulerShortcut': showSchedulerShortcut,
    'showDdnsShortcut': showDdnsShortcut,
    'showTorShortcut': showTorShortcut,
    'showTailscaleShortcut': showTailscaleShortcut,
    'showMultiWanShortcut': showMultiWanShortcut,
    'showQuarantineShortcut': showQuarantineShortcut,
    'showInactiveWirelessNetworks': showInactiveWirelessNetworks,
    'shortcutPanelVisibleCount': shortcutPanelVisibleCount,
    'shortcutOrder': shortcutOrder,
    'liveThroughputRefreshSeconds': liveThroughputRefreshSeconds,
    'systemResourcesRefreshSeconds': systemResourcesRefreshSeconds,
    'flowMode': flowMode.name,
  };

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    return DashboardPreferences(
      enabledWirelessInterfaces: Set<String>.from(
        json['enabledWirelessInterfaces'] ?? [],
      ),
      enabledWiredInterfaces: Set<String>.from(
        json['enabledWiredInterfaces'] ?? [],
      ),
      wirelessInterfaceSelectionInitialized:
          json['wirelessInterfaceSelectionInitialized'] == true,
      wiredInterfaceSelectionInitialized:
          json['wiredInterfaceSelectionInitialized'] == true,
      primaryThroughputInterface: json['primaryThroughputInterface'],
      showAllThroughput: json['showAllThroughput'] ?? true,
      showNetworkPerformanceCard: json['showNetworkPerformanceCard'] ?? false,
      showFlowsCard: json['showFlowsCard'] ?? false,
      showStatisticsTab: json['showStatisticsTab'] ?? false,
      showWifiShortcut: json['showWifiShortcut'] ?? true,
      showSmartQueueShortcut: json['showSmartQueueShortcut'] ?? true,
      showAdblockShortcut: json['showAdblockShortcut'] ?? true,
      showVpnShortcut: json['showVpnShortcut'] ?? true,
      showParentalShortcut:
          json['showParentalShortcut'] ?? json['showSchedulerShortcut'] ?? true,
      showSchedulerShortcut: json['showCronSchedulerShortcut'] ?? true,
      showDdnsShortcut: json['showDdnsShortcut'] ?? true,
      showTorShortcut: json['showTorShortcut'] ?? true,
      showTailscaleShortcut: json['showTailscaleShortcut'] ?? true,
      showMultiWanShortcut: json['showMultiWanShortcut'] ?? true,
      showQuarantineShortcut: json['showQuarantineShortcut'] ?? true,
      showInactiveWirelessNetworks:
          json['showInactiveWirelessNetworks'] == true,
      shortcutPanelVisibleCount: _parseShortcutPanelVisibleCount(
        json['shortcutPanelVisibleCount'],
      ),
      shortcutOrder: _parseShortcutOrder(json['shortcutOrder']),
      liveThroughputRefreshSeconds: _parseLiveThroughputRefreshSeconds(
        json['liveThroughputRefreshSeconds'],
      ),
      systemResourcesRefreshSeconds: _parseSystemResourcesRefreshSeconds(
        json['systemResourcesRefreshSeconds'],
      ),
      flowMode: DashboardFlowMode.values.firstWhere(
        (mode) => mode.name == json['flowMode']?.toString(),
        orElse: () => DashboardFlowMode.detailed,
      ),
    );
  }

  static int _parseShortcutPanelVisibleCount(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed == 3 ? 3 : 6;
  }

  static int _parseLiveThroughputRefreshSeconds(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return const {2, 3, 5, 10}.contains(parsed) ? parsed! : 3;
  }

  static int _parseSystemResourcesRefreshSeconds(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return const {5, 10, 15, 30}.contains(parsed) ? parsed! : 5;
  }

  static List<String> _parseShortcutOrder(dynamic value) {
    final original = value is List
        ? value.map((item) => item.toString()).toList()
        : const <String>[];
    final raw = original.contains('parental')
        ? original
        : original
              .map((item) => item == 'scheduler' ? 'parental' : item)
              .toList();
    final clean = raw
        .where((item) => defaultShortcutOrder.contains(item))
        .toSet()
        .toList();
    return [
      ...clean,
      ...defaultShortcutOrder.where((item) => !clean.contains(item)),
    ];
  }

  static DashboardPreferences get defaultPreferences => DashboardPreferences();
}
