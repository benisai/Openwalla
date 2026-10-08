import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/system_resource_metrics.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_animation_system.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/screens/adblock_screen.dart';
import 'package:openwalla/screens/clients_screen.dart';
import 'package:openwalla/screens/cron_scheduler_screen.dart';
import 'package:openwalla/screens/dns_screen.dart';
import 'package:openwalla/screens/ddns_screen.dart';
import 'package:openwalla/screens/flows_screen.dart';
import 'package:openwalla/screens/geo_blocking_screen.dart';
import 'package:openwalla/screens/interfaces_screen.dart';
import 'package:openwalla/screens/live_throughput_screen.dart';
import 'package:openwalla/screens/multi_wan_screen.dart';
import 'package:openwalla/screens/network_performance_screen.dart';
import 'package:openwalla/screens/notifications_screen.dart';
import 'package:openwalla/screens/quarantine_screen.dart';
import 'package:openwalla/screens/rules_screen.dart';
import 'package:openwalla/screens/router_setup_screen.dart';
import 'package:openwalla/modules/parental_controls/screens/parental_controls_screen.dart';
import 'package:openwalla/screens/simple_flows_screen.dart';
import 'package:openwalla/screens/routes_screen.dart';
import 'package:openwalla/screens/services_screen.dart';
import 'package:openwalla/screens/smart_queue_screen.dart';
import 'package:openwalla/screens/system_resources_screen.dart';
import 'package:openwalla/screens/tor_screen.dart';
import 'package:openwalla/screens/tailscale_screen.dart';
import 'package:openwalla/screens/vpn_screen.dart';
import 'package:openwalla/models/router.dart' as model;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  static const Color _openwallaCyan = Color(0xFF18AEEA);
  static const Color _openwallaOrange = Color(0xFFF27C24);
  static const Color _openwallaGreen = Color(0xFF20CF70);
  static const Color _shortcutDarkBlue = Color(0xFF2563EB);
  static const Color _shortcutYellow = Color(0xFFEAB308);
  static const Color _shortcutPurple = Color(0xFF8B5CF6);
  static const Color _shortcutRed = Color(0xFFFF4D4F);
  static const Color _shortcutRose = Color(0xFFD9468F);
  static const Color _openwallaCardBorder = Color(0xFF313C52);
  static const double _openwallaRadius = 8;
  Timer? _summaryRefreshTimer;
  Timer? _flowSummaryRefreshTimer;
  bool _summaryRefreshInFlight = false;
  bool _flowSummaryRefreshInFlight = false;
  int? _activeFlowRefreshSeconds;
  bool _dashboardRefreshInFlight = false;
  final PageController _shortcutPageController = PageController();
  int _shortcutPanelPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadDashboardAndWarmStatistics());
      _startSummaryRefreshTimer();
      _syncFlowSummaryRefreshTimer();
    });
  }

  Future<void> _loadDashboardAndWarmStatistics({bool force = false}) async {
    if (_dashboardRefreshInFlight) return;
    setState(() => _dashboardRefreshInFlight = true);
    try {
      final appState = ref.read(appStateProvider);
      await appState.fetchDashboardData();
      if (!mounted) return;
      appState.warmStatisticsData(force: force);
    } finally {
      if (mounted) {
        setState(() => _dashboardRefreshInFlight = false);
      }
    }
  }

  @override
  void dispose() {
    _summaryRefreshTimer?.cancel();
    _flowSummaryRefreshTimer?.cancel();
    _shortcutPageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSummaryRefreshTimer();
      _syncFlowSummaryRefreshTimer(force: true);
      _refreshSummaryCounts();
      _refreshFlowSummary();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _summaryRefreshTimer?.cancel();
      _summaryRefreshTimer = null;
      _flowSummaryRefreshTimer?.cancel();
      _flowSummaryRefreshTimer = null;
      _activeFlowRefreshSeconds = null;
    }
  }

  void _startSummaryRefreshTimer() {
    _summaryRefreshTimer?.cancel();
    _summaryRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshSummaryCounts();
    });
  }

  Future<void> _refreshSummaryCounts() async {
    if (!mounted || _summaryRefreshInFlight) return;
    _summaryRefreshInFlight = true;
    try {
      await ref
          .read(appStateProvider)
          .refreshDashboardSummaryCounts(context: context);
    } finally {
      _summaryRefreshInFlight = false;
    }
  }

  void _syncFlowSummaryRefreshTimer({bool force = false}) {
    final preferences = ref.read(appStateProvider).dashboardPreferences;
    if (!preferences.showFlowsCard) {
      _flowSummaryRefreshTimer?.cancel();
      _flowSummaryRefreshTimer = null;
      _activeFlowRefreshSeconds = null;
      return;
    }

    final seconds = preferences.flowCardRefreshSeconds;
    if (!force &&
        _flowSummaryRefreshTimer?.isActive == true &&
        _activeFlowRefreshSeconds == seconds) {
      return;
    }
    _flowSummaryRefreshTimer?.cancel();
    _activeFlowRefreshSeconds = seconds;
    _flowSummaryRefreshTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      _refreshFlowSummary();
    });
  }

  Future<void> _refreshFlowSummary() async {
    if (!mounted || _flowSummaryRefreshInFlight) return;
    _flowSummaryRefreshInFlight = true;
    try {
      await ref
          .read(appStateProvider)
          .refreshDashboardFlowSummary(context: context);
    } finally {
      _flowSummaryRefreshInFlight = false;
    }
  }

  double _loadAveragePercent(Map<String, dynamic>? sysInfo, int index) {
    final load = sysInfo?['load'] as List<dynamic>?;
    if (load == null || load.isEmpty) return 0;
    final safeIndex = index < load.length ? index : 0;
    final value = load[safeIndex];
    if (value is! num) return 0;
    final coreCountValue = sysInfo?['cpuCoreCount'];
    final coreCount = coreCountValue is num && coreCountValue > 0
        ? coreCountValue.toDouble()
        : 1.0;
    return ((value / 65536) / coreCount * 100).clamp(0, 100).toDouble();
  }

  Widget _buildOpenwallaCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? _openwallaCardBorder
        : colorScheme.outlineVariant.withValues(alpha: 0.62);

    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_openwallaRadius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildOpenwallaCardHeader({
    required IconData icon,
    required String title,
    Color? color,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(_openwallaRadius),
          ),
          child: Icon(icon, size: 17, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildDashboardSummaryCards(AppState appState) {
    final deviceCount = appState.dashboardData?['deviceCount'];
    final notificationCount = appState.dashboardData?['notificationCount'];
    final rulesCount = appState.dashboardData?['rulesCount'];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDashboardSummaryCard(
                label: 'Devices',
                count: (deviceCount is int ? deviceCount : 0).toString(),
                icon: Icons.devices_rounded,
                color: _openwallaCyan,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ClientsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDashboardSummaryCard(
                label: 'Notifications',
                count: (notificationCount is int ? notificationCount : 0)
                    .toString(),
                icon: Icons.notifications_rounded,
                color: _openwallaOrange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDashboardSummaryCard(
                label: 'Rules',
                count: (rulesCount is int ? rulesCount : 0).toString(),
                icon: Icons.rule_rounded,
                color: _openwallaGreen,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const RulesScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardSummaryCard({
    required String label,
    required String count,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            count,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardFlowsCard(AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    const flowColor = Color(0xFF8B5CF6);
    final flowSummary = appState.dashboardData?['flowSummary'];
    final flowMode = appState.dashboardPreferences.flowMode;
    final provider = flowSummary is OpenwallaFlowSummary
        ? flowSummary.provider
        : appState.dashboardData?['flowProvider'];
    final isDetailedFlow = flowMode == DashboardFlowMode.detailed;
    final isMissingDetailedFlow =
        isDetailedFlow && provider == OpenwallaFlowProvider.none;
    if (provider == OpenwallaFlowProvider.none && !isMissingDetailedFlow) {
      return const SizedBox.shrink();
    }
    final flowCount = flowSummary is OpenwallaFlowSummary
        ? flowSummary.count
        : appState.dashboardData?['netifyFlowCount'] as int? ?? 0;
    final title = flowMode == DashboardFlowMode.simple
        ? 'Simple Flow'
        : 'Detailed Flow';
    final sourceLabel = isMissingDetailedFlow
        ? 'Netify not installed'
        : flowMode == DashboardFlowMode.simple
        ? 'Conntrack'
        : 'Netify';

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => isMissingDetailedFlow
                ? const RouterSetupScreen(netifyOnly: true)
                : flowMode == DashboardFlowMode.simple
                ? const SimpleFlowsScreen()
                : const FlowsScreen(),
          ),
        );
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: flowColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(_openwallaRadius),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: flowColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isMissingDetailedFlow
                          ? 'Install'
                          : _formatCompactCount(flowCount),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            height: 1,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        sourceLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
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
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  bool _hasDashboardFlowsCard(AppState appState) {
    if (appState.dashboardPreferences.flowMode == DashboardFlowMode.detailed) {
      return true;
    }
    final flowSummary = appState.dashboardData?['flowSummary'];
    final provider = flowSummary is OpenwallaFlowSummary
        ? flowSummary.provider
        : appState.dashboardData?['flowProvider'];
    return provider != OpenwallaFlowProvider.none;
  }

  String _formatTimelineHour(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
  }

  String _formatCompactCount(int value) {
    if (value < 1000) return value.toString();
    if (value < 1000000) {
      final thousands = value / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
    }
    final millions = value / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }

  List<PingMonitorSample> _pingSamples(AppState appState) {
    final rawSamples = appState.dashboardData?['pingSamples'];
    if (rawSamples is List<PingMonitorSample>) return rawSamples;
    return const [];
  }

  String _formatLatencyValue(double? latencyMs) {
    if (latencyMs == null) return 'No data';
    if (latencyMs >= 100) return '${latencyMs.toStringAsFixed(0)}ms';
    return '${latencyMs.toStringAsFixed(1)}ms';
  }

  List<_PingHourBucket> _pingHourBuckets(List<PingMonitorSample> samples) {
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    return List<_PingHourBucket>.generate(6, (index) {
      final start = currentHour.subtract(Duration(hours: 5 - index));
      final end = start.add(const Duration(hours: 1));
      final bucketSamples = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(start) && time.isBefore(end);
      }).toList();
      final latencies = bucketSamples
          .where((sample) => sample.isOk)
          .map((sample) => sample.latencyMs)
          .whereType<double>()
          .toList();
      final failureCount = bucketSamples.length - latencies.length;
      final average = latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a + b) / latencies.length;
      return _PingHourBucket(
        averageLatencyMs: average,
        sampleCount: bucketSamples.length,
        failureCount: failureCount,
        hasSamples: bucketSamples.isNotEmpty,
        hasOnlyFailures: bucketSamples.isNotEmpty && latencies.isEmpty,
      );
    });
  }

  Color _pingBucketColor(_PingHourBucket bucket) {
    if (!bucket.hasSamples) {
      return Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.28);
    }
    if (bucket.hasOnlyFailures) return Theme.of(context).colorScheme.error;
    final latency = bucket.averageLatencyMs ?? 0;
    if (latency >= 100) return const Color(0xFFEAB308);
    return _openwallaGreen;
  }

  String _pingBucketTooltip(
    _PingHourBucket bucket,
    String startLabel,
    String endLabel,
  ) {
    if (!bucket.hasSamples) {
      return '$startLabel - $endLabel\nNo ping data';
    }
    final latency = bucket.averageLatencyMs == null
        ? 'No replies'
        : _formatLatencyValue(bucket.averageLatencyMs);
    return '$startLabel - $endLabel\n'
        'Average latency: $latency\n'
        'Samples: ${bucket.sampleCount}\n'
        'Failures: ${bucket.failureCount}';
  }

  Widget _buildNetworkPerformanceCard({required AppState appState}) {
    final colorScheme = Theme.of(context).colorScheme;
    final samples = _pingSamples(appState);
    final buckets = _pingHourBuckets(samples);
    final averageLatency = NetworkPerformanceScreen.averageLatestPingLatency(
      samples,
    );
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final labels = List<String>.generate(7, (index) {
      if (index == 6) return 'Now';
      return _formatTimelineHour(
        currentHour.subtract(Duration(hours: 5 - index)),
      );
    });

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const NetworkPerformanceScreen(),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Network Performance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _subtleCardArrow(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatLatencyValue(averageLatency),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Latency',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: List.generate(buckets.length, (index) {
              final isLast = index == buckets.length - 1;
              final bucket = buckets[index];
              return Expanded(
                child: Tooltip(
                  message: _pingBucketTooltip(
                    bucket,
                    labels[index],
                    labels[index + 1],
                  ),
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 3),
                  preferBelow: false,
                  child: Container(
                    height: 12,
                    margin: EdgeInsets.only(right: isLast ? 0 : 2),
                    decoration: BoxDecoration(
                      color: _pingBucketColor(bucket),
                      borderRadius: BorderRadius.horizontal(
                        left: index == 0
                            ? const Radius.circular(6)
                            : Radius.zero,
                        right: isLast ? const Radius.circular(6) : Radius.zero,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (label) => Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleWithTimestamp(String title, AppState appState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRealtimeThroughputCard(AppState appState) {
    final prefs = appState.dashboardPreferences;

    // Determine which throughput data to use
    List<double> rxHistory;
    List<double> txHistory;
    double currentRxRate;
    double currentTxRate;
    String throughputLabel = '';

    if (!prefs.showAllThroughput && prefs.primaryThroughputInterface != null) {
      // Use specific interface throughput
      final interface = prefs.primaryThroughputInterface!;
      rxHistory = appState.getRxHistoryForInterface(interface);
      txHistory = appState.getTxHistoryForInterface(interface);
      currentRxRate = appState.getCurrentRxRateForInterface(interface);
      currentTxRate = appState.getCurrentTxRateForInterface(interface);
      throughputLabel = ' - $interface';
    } else {
      // Use combined throughput
      rxHistory = appState.rxHistory;
      txHistory = appState.txHistory;
      currentRxRate = appState.currentRxRate;
      currentTxRate = appState.currentTxRate;
    }

    // Show loading state if we don't have any throughput data yet
    final hasValidData =
        rxHistory.isNotEmpty ||
        txHistory.isNotEmpty ||
        currentRxRate > 0 ||
        currentTxRate > 0; // Show data as soon as we have any throughput info
    // Only show switching state if we're loading AND no dashboard data is available (true router switch)
    final isSwitchingRouter =
        appState.isLoading && appState.dashboardData == null;

    final card = _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOpenwallaCardHeader(
            icon: Icons.show_chart_rounded,
            title: 'Live Traffic',
            color: _openwallaCyan,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (throughputLabel.isNotEmpty) ...[
                  Text(
                    throughputLabel.replaceFirst(' - ', ''),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSpeedIndicator(
                  Icons.arrow_downward,
                  _openwallaCyan,
                  '',
                  isSwitchingRouter ? 0.0 : currentRxRate,
                ),
                _buildSpeedIndicator(
                  Icons.arrow_upward,
                  _openwallaOrange,
                  '',
                  isSwitchingRouter ? 0.0 : currentTxRate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 16.0,
              ), // Add space above the chart
              child: AnimatedSwitcher(
                duration: const Duration(
                  milliseconds: 600,
                ), // Smoother transition
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: hasValidData && !isSwitchingRouter
                    ? LineChart(
                        key: ValueKey('chart_${appState.selectedRouter?.id}'),
                        LineChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              fitInsideVertically: true,
                              getTooltipColor: (LineBarSpot spot) => Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              tooltipBorderRadius: BorderRadius.circular(8),
                              tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              getTooltipItems:
                                  (List<LineBarSpot> touchedSpots) {
                                    return touchedSpots.map((barSpot) {
                                      final flSpot = barSpot;
                                      final Color color =
                                          flSpot.bar.gradient?.colors.first ??
                                          flSpot.bar.color ??
                                          Colors.white;

                                      return LineTooltipItem(
                                        _formatSpeed(flSpot.y),
                                        TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.left,
                                      );
                                    }).toList();
                                  },
                            ),
                          ),
                          lineBarsData: [
                            _buildLineChartBarData(rxHistory, [
                              _openwallaCyan,
                              _openwallaCyan.withValues(alpha: 0.7),
                            ]),
                            _buildLineChartBarData(txHistory, [
                              _openwallaOrange,
                              _openwallaOrange.withValues(alpha: 0.72),
                            ]),
                          ],
                        ),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOut,
                      )
                    : Center(
                        key: ValueKey('loading_${appState.selectedRouter?.id}'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isSwitchingRouter
                                  ? 'Switching router...'
                                  : 'Collecting throughput data...',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.8),
                                  ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(_openwallaRadius),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LiveThroughputScreen()));
      },
      child: card,
    );
  }

  Widget _buildSpeedIndicator(
    IconData icon,
    Color color,
    String label,
    double speed,
  ) {
    // Show 0 if we don't have valid throughput data yet
    final displaySpeed = speed.isNaN || speed.isInfinite || speed < 0
        ? 0.0
        : speed;
    final speedText = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        _formatSpeed(displaySpeed),
        key: ValueKey(displaySpeed),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                speedText,
              ],
            ),
          )
        else
          Flexible(child: speedText),
      ],
    );
  }

  LineChartBarData _buildLineChartBarData(
    List<double> data,
    List<Color> gradientColors,
  ) {
    // Handle single data point case - show a flat line at that value
    if (data.length == 1) {
      return LineChartBarData(
        spots: [
          FlSpot(0, data[0]),
          FlSpot(1, data[0]), // Duplicate the point to create a flat line
        ],
        isCurved: false,
        gradient: LinearGradient(colors: gradientColors),
        barWidth: 2,
        isStrokeCapRound: true,
        isStrokeJoinRound: false,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            return FlDotCirclePainter(
              radius: 3,
              color: gradientColors.first,
              strokeWidth: 0,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: gradientColors
                .map((color) => color.withValues(alpha: 0.1))
                .toList(),
          ),
        ),
      );
    }

    // Don't show chart data if we don't have any data points
    if (data.isEmpty) {
      return LineChartBarData(
        spots: [],
        isCurved: false,
        gradient: LinearGradient(colors: gradientColors),
        barWidth: 2,
        isStrokeCapRound: true,
        isStrokeJoinRound: false,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }

    return LineChartBarData(
      spots: data
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList(),
      isCurved: false,
      gradient: LinearGradient(colors: gradientColors),
      barWidth: 2,
      isStrokeCapRound: true,
      isStrokeJoinRound: false,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: gradientColors
              .map((color) => color.withValues(alpha: 0.3))
              .toList(),
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    // Handle edge cases
    if (bytesPerSecond.isNaN ||
        bytesPerSecond.isInfinite ||
        bytesPerSecond < 0) {
      return '0 bps';
    }

    final bitsPerSecond = bytesPerSecond * 8;
    if (bitsPerSecond < 1_000) return '${bitsPerSecond.toStringAsFixed(0)} bps';
    if (bitsPerSecond < 1_000_000) {
      return '${(bitsPerSecond / 1_000).toStringAsFixed(1)} Kbps';
    }
    return '${(bitsPerSecond / 1_000_000).toStringAsFixed(2)} Mbps';
  }

  Widget _buildSystemGauge({
    required String label,
    required double percent,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = percent.round().clamp(0, 100);

    return SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: CircularProgressIndicator(
              value: displayValue / 100,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$displayValue%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemGaugeColumn({
    required String label,
    required double percent,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSystemGauge(label: label, percent: percent, color: color),
        ],
      ),
    );
  }

  Widget _buildSystemGaugeRow({
    required double cpuPercent,
    required double memoryPercent,
    required double loadPercent,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSystemGaugeColumn(
          label: 'CPU',
          percent: cpuPercent,
          color: _openwallaGreen,
        ),
        _buildSystemGaugeColumn(
          label: 'Mem',
          percent: memoryPercent,
          color: _openwallaCyan,
        ),
        _buildSystemGaugeColumn(
          label: 'Load',
          percent: loadPercent,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildSystemVitalsCard(AppState appState) {
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final metrics = SystemResourceMetrics.fromRouterData(
      sysInfo,
      boardInfo: boardInfo,
    );

    final cpuPercent = metrics.cpuUsagePercent;
    final memoryPercent = metrics.memoryUsagePercent;
    final loadPercent = _loadAveragePercent(sysInfo, 2);

    return _buildOpenwallaCard(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SystemResourcesScreen(),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'System Resources',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _subtleCardArrow(),
            ],
          ),
          const SizedBox(height: 18),
          _buildSystemGaugeRow(
            cpuPercent: cpuPercent,
            memoryPercent: memoryPercent,
            loadPercent: loadPercent,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBottomCards() {
    return _buildDashboardShortcutGrid();
  }

  Widget _buildDashboardShortcutGrid() {
    final preferences = ref.watch(appStateProvider).dashboardPreferences;
    final shortcuts =
        [
          _DashboardShortcutData(
            id: 'network',
            label: 'Network',
            icon: Icons.public_rounded,
            color: _openwallaCyan,
            onTap: () => _openNetworkPage(wirelessOnly: false),
          ),
          _DashboardShortcutData(
            id: 'dns',
            label: 'DNS',
            icon: Icons.dns_rounded,
            color: _shortcutYellow,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DnsScreen()),
              );
            },
          ),
          if (preferences.showWifiShortcut)
            _DashboardShortcutData(
              id: 'wifi',
              label: 'Wi-Fi',
              icon: Icons.wifi_rounded,
              color: _shortcutDarkBlue,
              onTap: () => _openNetworkPage(wirelessOnly: true),
            ),
          _DashboardShortcutData(
            id: 'routes',
            label: 'Routing',
            icon: Icons.route_rounded,
            color: _openwallaOrange,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const RoutesScreen()),
              );
            },
          ),
          if (preferences.showSmartQueueShortcut)
            _DashboardShortcutData(
              id: 'smart_queue',
              label: 'Smart Queue',
              icon: Icons.sync_alt_rounded,
              color: _shortcutPurple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SmartQueueScreen(),
                  ),
                );
              },
            ),
          if (preferences.showAdblockShortcut)
            _DashboardShortcutData(
              id: 'adblock',
              label: 'AdBlock',
              icon: Icons.block_rounded,
              color: _shortcutRed,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AdblockScreen(),
                  ),
                );
              },
            ),
          _DashboardShortcutData(
            id: 'services',
            label: 'Services',
            icon: Icons.miscellaneous_services_rounded,
            color: _openwallaGreen,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ServicesScreen()),
              );
            },
          ),
          if (preferences.showVpnShortcut)
            _DashboardShortcutData(
              id: 'vpn',
              label: 'VPN',
              icon: Icons.security_rounded,
              color: _shortcutDarkBlue,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const VpnScreen()),
                );
              },
            ),
          if (preferences.showParentalShortcut)
            _DashboardShortcutData(
              id: 'parental',
              label: 'Parental',
              icon: Icons.family_restroom_rounded,
              color: _shortcutRose,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ParentalControlsScreen(),
                  ),
                );
              },
            ),
          if (preferences.showSchedulerShortcut)
            _DashboardShortcutData(
              id: 'scheduler',
              label: 'Scheduler',
              icon: Icons.schedule_rounded,
              color: _shortcutYellow,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CronSchedulerScreen(),
                  ),
                );
              },
            ),
          if (preferences.showDdnsShortcut)
            _DashboardShortcutData(
              id: 'ddns',
              label: 'DDNS',
              icon: Icons.cloud_sync_rounded,
              color: _shortcutDarkBlue,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const DdnsScreen()),
                );
              },
            ),
          if (preferences.showTorShortcut)
            _DashboardShortcutData(
              id: 'tor',
              label: 'Tor',
              icon: Icons.hub_rounded,
              color: _shortcutPurple,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const TorScreen()),
                );
              },
            ),
          if (preferences.showTailscaleShortcut)
            _DashboardShortcutData(
              id: 'tailscale',
              label: 'Tailscale',
              icon: Icons.device_hub_rounded,
              color: _openwallaCyan,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const TailscaleScreen(),
                  ),
                );
              },
            ),
          if (preferences.showMultiWanShortcut)
            _DashboardShortcutData(
              id: 'multi_wan',
              label: 'Multi-WAN',
              icon: Icons.alt_route_rounded,
              color: _openwallaOrange,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const MultiWanScreen(),
                  ),
                );
              },
            ),
          if (preferences.showQuarantineShortcut)
            _DashboardShortcutData(
              id: 'quarantine',
              label: 'Quarantine',
              icon: Icons.gpp_bad_rounded,
              color: _shortcutRed,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const QuarantineScreen(),
                  ),
                );
              },
            ),
          if (preferences.showGeoBlockingShortcut)
            _DashboardShortcutData(
              id: 'geo_blocking',
              label: 'Geo-Blocking',
              icon: Icons.public_off_rounded,
              color: _shortcutRose,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const GeoBlockingScreen(),
                  ),
                );
              },
            ),
        ]..sort((a, b) {
          final aIndex = preferences.shortcutOrder.indexOf(a.id);
          final bIndex = preferences.shortcutOrder.indexOf(b.id);
          final safeA = aIndex == -1 ? 999 : aIndex;
          final safeB = bIndex == -1 ? 999 : bIndex;
          return safeA.compareTo(safeB);
        });

    return _buildOpenwallaCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: _buildPagedShortcutPanel(
        shortcuts,
        visibleCount: preferences.shortcutPanelVisibleCount,
      ),
    );
  }

  Widget _buildPagedShortcutPanel(
    List<_DashboardShortcutData> shortcuts, {
    required int visibleCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final perPage = visibleCount == 3 ? 3 : 6;
        final pageCount = (shortcuts.length / perPage).ceil().clamp(1, 99);
        final currentPage = _shortcutPanelPage.clamp(0, pageCount - 1);
        final height = perPage == 3 ? 98.0 : 202.0;

        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView.builder(
                controller: _shortcutPageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (page) {
                  setState(() => _shortcutPanelPage = page);
                },
                itemCount: pageCount,
                itemBuilder: (context, pageIndex) {
                  final start = pageIndex * perPage;
                  final pageShortcuts = shortcuts
                      .skip(start)
                      .take(perPage)
                      .toList();
                  return GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.08,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: spacing,
                    children: [
                      ...pageShortcuts.map(
                        (shortcut) => _buildDashboardShortcut(
                          label: shortcut.label,
                          icon: shortcut.icon,
                          color: shortcut.color,
                          onTap: shortcut.onTap,
                        ),
                      ),
                      for (var i = pageShortcuts.length; i < perPage; i++)
                        const SizedBox.shrink(),
                    ],
                  );
                },
              ),
            ),
            if (pageCount > 1) ...[
              const SizedBox(height: 4),
              _buildShortcutPageDots(pageCount, currentPage),
            ],
          ],
        );
      },
    );
  }

  Widget _buildShortcutPageDots(int pageCount, int currentPage) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        pageCount,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: index == currentPage ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: index == currentPage
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardShortcut({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_openwallaRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNetworkPage({required bool wirelessOnly}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InterfacesScreen(wirelessOnly: wirelessOnly),
      ),
    );
  }

  Widget _subtleCardArrow() {
    final colorScheme = Theme.of(context).colorScheme;

    return Icon(
      Icons.arrow_forward_ios_rounded,
      size: 16,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.74),
    );
  }

  Future<void> _confirmRemoveRouter(model.Router router, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Router'),
        content: Text('Remove $label from this app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ref.read(appStateProvider).removeRouter(router.id);
    if (!mounted) return;
    if (ref.read(appStateProvider).routers.isEmpty) {
      unawaited(
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    _syncFlowSummaryRefreshTimer();
    final List<model.Router> routers = appState.routers;
    final model.Router? selected = appState.selectedRouter;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final hostname = boardInfo?['hostname']?.toString();
    final headerText = (hostname != null && hostname.isNotEmpty)
        ? hostname
        : (selected?.ipAddress ?? 'Loading...');
    return Scaffold(
      appBar: LuciAppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Refresh dashboard',
          onPressed: _dashboardRefreshInFlight
              ? null
              : () => unawaited(_loadDashboardAndWarmStatistics(force: true)),
          icon: _dashboardRefreshInFlight
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
        title: null, // Always use titleWidget now
        titleWidget: routers.isNotEmpty
            ? Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 1.1,
                    ),
                  ),
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final selectedId = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: false,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(_openwallaRadius),
                            ),
                          ),
                          builder: (context) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  left: 8,
                                  right: 8,
                                  bottom: 8,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: 4,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Select Router',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 16),
                                    ...routers.map((r) {
                                      final isSelected = r.id == selected?.id;
                                      String routerTitle;
                                      bool isStale = false;
                                      if (isSelected && boardInfo != null) {
                                        final hostname = boardInfo['hostname']
                                            ?.toString();
                                        routerTitle =
                                            (hostname != null &&
                                                hostname.isNotEmpty)
                                            ? hostname
                                            : (r.lastKnownHostname ??
                                                  r.ipAddress);
                                      } else if (r.lastKnownHostname != null &&
                                          r.lastKnownHostname!.isNotEmpty) {
                                        routerTitle = r.lastKnownHostname!;
                                        isStale = true;
                                      } else {
                                        routerTitle = r.ipAddress;
                                      }
                                      return ListTile(
                                        leading: Icon(
                                          Icons.router,
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                        title: Tooltip(
                                          message: isStale
                                              ? 'Last known hostname (may be out of date)'
                                              : '',
                                          child: Text(
                                            routerTitle,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: isStale
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant
                                                            .withValues(
                                                              alpha: 0.7,
                                                            )
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        subtitle: Text(
                                          r.ipAddress,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSelected)
                                              Icon(
                                                Icons.check_circle,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            IconButton(
                                              tooltip: 'Remove router',
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                    .withValues(alpha: 0.82),
                                              ),
                                              onPressed: () async {
                                                Navigator.of(context).pop();
                                                await _confirmRemoveRouter(
                                                  r,
                                                  routerTitle,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        selected: isSelected,
                                        selectedTileColor: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.07),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        onTap: () =>
                                            Navigator.of(context).pop(r.id),
                                      );
                                    }),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        if (selectedId != null &&
                            selectedId != selected?.id &&
                            context.mounted) {
                          await appState.selectRouter(
                            selectedId,
                            context: context,
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 16.0,
                          right: 8.0,
                          top: 4.0,
                          bottom: 4.0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              headerText,
                              style:
                                  Theme.of(
                                    context,
                                  ).appBarTheme.titleTextStyle ??
                                  Theme.of(
                                    context,
                                  ).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).appBarTheme.titleTextStyle?.color,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : _buildTitleWithTimestamp(headerText, appState),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificationsScreen(),
                ),
              );
            },
            icon: Icon(
              Icons.notifications_none_rounded,
              color: appState.hasUnseenNotifications
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      body: Stack(children: [_buildBody(appState)]),
    );
  }

  Widget _buildBody(AppState appState) {
    if (appState.dashboardError != null) {
      return LuciErrorDisplay(
        title: 'Connection Failed',
        message:
            'Unable to connect to the router. Please check your network connection and router settings.',
        actionLabel: 'Retry Connection',
        onAction: () => appState.retryDashboardConnection(context: context),
        icon: Icons.wifi_off_rounded,
      );
    }

    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return const LuciLoadingWidget();
    }

    if (appState.dashboardData == null) {
      return LuciEmptyState(
        title: 'No Data Available',
        message:
            'Unable to fetch dashboard data. Pull down to refresh or tap the button below.',
        icon: Icons.dashboard_outlined,
        actionLabel: 'Fetch Data',
        onAction: () => _loadDashboardAndWarmStatistics(force: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadDashboardAndWarmStatistics(force: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape;

          // Split layout handling to avoid Expanded widget conflicts with staggered animations
          if (isLandscape) {
            final preferences = appState.dashboardPreferences;
            final hasFlowsCard =
                preferences.showFlowsCard && _hasDashboardFlowsCard(appState);
            final landscapeContent = [
              const SizedBox(height: 16),
              _buildDashboardSummaryCards(appState),
              if (preferences.showNetworkPerformanceCard) ...[
                const SizedBox(height: 12),
                _buildNetworkPerformanceCard(appState: appState),
              ],
              const SizedBox(height: 12),
              _buildSystemVitalsCard(appState),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: _buildRealtimeThroughputCard(appState),
              ),
              if (hasFlowsCard) ...[
                const SizedBox(height: 12),
                _buildDashboardFlowsCard(appState),
              ],
              const SizedBox(height: 12),
              _buildDashboardBottomCards(),
              const SizedBox(height: 12),
              // Extra padding to ensure scroll behavior for RefreshIndicator
              const SizedBox(height: 100),
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: LuciStaggeredAnimation(
                  staggerDelay: const Duration(milliseconds: 50),
                  children: landscapeContent,
                ),
              ),
            );
          } else {
            // Portrait mode: let content scroll naturally so cards never get
            // squeezed into a height that causes internal overflows.
            return LayoutBuilder(
              builder: (context, constraints) {
                final preferences = appState.dashboardPreferences;
                final hasFlowsCard =
                    preferences.showFlowsCard &&
                    _hasDashboardFlowsCard(appState);
                return RefreshIndicator(
                  onRefresh: () => _loadDashboardAndWarmStatistics(force: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              _buildDashboardSummaryCards(appState),
                              if (preferences.showNetworkPerformanceCard) ...[
                                const SizedBox(height: 12),
                                _buildNetworkPerformanceCard(
                                  appState: appState,
                                ),
                              ],
                              const SizedBox(height: 12),
                              _buildSystemVitalsCard(appState),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 220,
                                child: _buildRealtimeThroughputCard(appState),
                              ),
                              if (hasFlowsCard) ...[
                                const SizedBox(height: 12),
                                _buildDashboardFlowsCard(appState),
                              ],
                              const SizedBox(height: 12),
                              _buildDashboardBottomCards(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}

class _DashboardShortcutData {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DashboardShortcutData({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _PingHourBucket {
  final double? averageLatencyMs;
  final int sampleCount;
  final int failureCount;
  final bool hasSamples;
  final bool hasOnlyFailures;

  const _PingHourBucket({
    required this.averageLatencyMs,
    required this.sampleCount,
    required this.failureCount,
    required this.hasSamples,
    required this.hasOnlyFailures,
  });
}
