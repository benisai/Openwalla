import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/monthly_usage_screen.dart';
import 'package:openwalla/screens/router_setup_screen.dart';
import 'package:openwalla/screens/usage_settings_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_refresh_components.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

enum _StatsUsageRange { minute, hour, day, week }

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);
  static const Color _border = Color(0xFF313C52);
  static const double _radius = 8;

  _StatsUsageRange _usageRange = _StatsUsageRange.day;
  Future<MonthlyUsageSettings>? _monthlyUsageSettingsFuture;
  Future<bool>? _statisticsSupportFuture;
  Future<List<NlbwDeviceUsage>>? _topDevicesFuture;
  Future<List<NlbwProtocolUsage>>? _protocolUsageFuture;
  final Map<String, Future<List<VnstatUsageSample>>> _usageFutures = {};
  StatisticsPreloadData? _boundPreloadData;
  Future<StatisticsPreloadData>? _boundPreloadFuture;
  Future<MonthlyUsageSettings>? _preloadSettingsFuture;
  Future<bool>? _preloadSupportFuture;
  Future<List<NlbwDeviceUsage>>? _preloadTopDevicesFuture;
  Future<List<NlbwProtocolUsage>>? _preloadProtocolUsageFuture;
  final Map<String, Future<List<VnstatUsageSample>>> _preloadUsageFutures = {};
  bool _isInstallingSupport = false;
  final PageController _usageRangeController = PageController(
    initialPage: _StatsUsageRange.day.index,
  );

  @override
  void dispose() {
    _usageRangeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.read(appStateProvider);
    final isInitialDashboardLoading = ref.watch(
      appStateProvider.select(
        (state) => state.isDashboardLoading && state.dashboardData == null,
      ),
    );

    if (isInitialDashboardLoading) {
      return Scaffold(
        appBar: LuciAppBar(
          title: 'Statistics',
          showBack: true,
          onBack: _backToDashboard,
        ),
        body: LuciLoadingWidget(),
      );
    }

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Statistics',
        showBack: true,
        onBack: _backToDashboard,
        actions: [
          IconButton(
            tooltip: 'Usage settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openUsageSettings,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: LuciPullToRefresh(
          onRefresh: () async {
            _usageFutures.clear();
            _monthlyUsageSettingsFuture = null;
            _statisticsSupportFuture = null;
            _topDevicesFuture = null;
            _protocolUsageFuture = null;
            _clearPreloadBindings();
            appState.clearStatisticsPreload();
            await appState.fetchDashboardData();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              FutureBuilder<bool>(
                future: _statisticsSupport(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data != true) {
                    return _SetupRequiredCard(
                      title: 'Statistics tools are not installed',
                      message:
                          'Install vnStat or nlbwmon with the Openwalla helper scripts to enable usage graphs.',
                      buttonLabel: 'Install Statistics Tools',
                      isInstalling: _isInstallingSupport,
                      onPressed: _installStatisticsSupport,
                      onRouterSetup: _openRouterSetup,
                      onHideStatistics: _hideStatisticsTab,
                    );
                  }
                  return FutureBuilder<MonthlyUsageSettings>(
                    future: _monthlyUsageSettings(),
                    builder: (context, snapshot) {
                      final interfaceName =
                          (snapshot.data?.interfaceName.isNotEmpty ?? false)
                          ? snapshot.data!.interfaceName
                          : _primaryUsageInterfaceName(appState);
                      final settings = snapshot.data;
                      return Column(
                        children: [
                          _buildMonthlyUsageCard(
                            interfaceName,
                            monthlyLimitGb: settings?.monthlyLimitGb ?? 0,
                          ),
                          const SizedBox(height: 12),
                          _buildUsageCard(interfaceName),
                          const SizedBox(height: 12),
                          _buildTopDevicesCard(),
                          const SizedBox(height: 12),
                          _buildActivityAnalysisCard(),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<MonthlyUsageSettings> _monthlyUsageSettings() {
    final appState = ref.read(appStateProvider);
    final preload = appState.statisticsPreloadData;
    if (preload != null) {
      _bindPreloadData(preload);
      return _preloadSettingsFuture!;
    }
    final preloadFuture = appState.statisticsPreloadFuture;
    if (preloadFuture != null) {
      _bindPreloadFuture(preloadFuture);
      return _preloadSettingsFuture ??= preloadFuture.then(
        (data) => data.settings,
      );
    }
    return _monthlyUsageSettingsFuture ??= ref
        .read(appStateProvider)
        .fetchMonthlyUsageSettings();
  }

  Future<bool> _statisticsSupport() {
    final appState = ref.read(appStateProvider);
    final preload = appState.statisticsPreloadData;
    if (preload != null) {
      _bindPreloadData(preload);
      return _preloadSupportFuture!;
    }
    final preloadFuture = appState.statisticsPreloadFuture;
    if (preloadFuture != null) {
      _bindPreloadFuture(preloadFuture);
      return _preloadSupportFuture ??= preloadFuture.then(
        (data) => data.hasSupport,
      );
    }
    return _statisticsSupportFuture ??= ref
        .read(appStateProvider)
        .hasStatisticsSupport(context: context);
  }

  Future<List<NlbwDeviceUsage>> _topDevices() {
    final appState = ref.read(appStateProvider);
    final preload = appState.statisticsPreloadData;
    if (preload != null) {
      _bindPreloadData(preload);
      return _preloadTopDevicesFuture!;
    }
    final preloadFuture = appState.statisticsPreloadFuture;
    if (preloadFuture != null) {
      _bindPreloadFuture(preloadFuture);
      return _preloadTopDevicesFuture ??= preloadFuture.then(
        (data) => data.topDevices,
      );
    }
    return _topDevicesFuture ??= ref
        .read(appStateProvider)
        .fetchNlbwTopDevices(limit: 5);
  }

  Future<List<NlbwProtocolUsage>> _protocolUsage() {
    final appState = ref.read(appStateProvider);
    final preload = appState.statisticsPreloadData;
    if (preload != null) {
      _bindPreloadData(preload);
      return _preloadProtocolUsageFuture!;
    }
    final preloadFuture = appState.statisticsPreloadFuture;
    if (preloadFuture != null) {
      _bindPreloadFuture(preloadFuture);
      return _preloadProtocolUsageFuture ??= preloadFuture.then(
        (data) => data.protocolUsage,
      );
    }
    return _protocolUsageFuture ??= ref
        .read(appStateProvider)
        .fetchNlbwProtocolUsage(limit: 5);
  }

  void _clearPreloadBindings() {
    _boundPreloadData = null;
    _boundPreloadFuture = null;
    _preloadSettingsFuture = null;
    _preloadSupportFuture = null;
    _preloadTopDevicesFuture = null;
    _preloadProtocolUsageFuture = null;
    _preloadUsageFutures.clear();
  }

  void _bindPreloadData(StatisticsPreloadData preload) {
    if (identical(_boundPreloadData, preload)) return;
    _clearPreloadBindings();
    _boundPreloadData = preload;
    _preloadSettingsFuture = Future.value(preload.settings);
    _preloadSupportFuture = Future.value(preload.hasSupport);
    _preloadTopDevicesFuture = Future.value(preload.topDevices);
    _preloadProtocolUsageFuture = Future.value(preload.protocolUsage);
  }

  void _bindPreloadFuture(Future<StatisticsPreloadData> preloadFuture) {
    if (identical(_boundPreloadFuture, preloadFuture)) return;
    _clearPreloadBindings();
    _boundPreloadFuture = preloadFuture;
  }

  void _openRouterSetup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const RouterSetupScreen()));
  }

  Future<void> _hideStatisticsTab() async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.visibility_off_rounded),
        title: const Text('Hide Statistics Tab?'),
        content: const Text(
          'The Statistics tab will be removed from the bottom navigation. You can enable it again from Settings > Dashboard Settings > Statistics.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hide Tab'),
          ),
        ],
      ),
    );
    if (shouldHide != true || !mounted) return;

    final appState = ref.read(appStateProvider);
    await appState.saveDashboardPreferences(
      appState.dashboardPreferences.copyWith(showStatisticsTab: false),
    );
    if (!mounted) return;
    appState.requestTab(0);
  }

  Future<void> _installStatisticsSupport() async {
    setState(() => _isInstallingSupport = true);
    final console = SshConsoleController(
      initialOutput:
          'Connecting to router over SSH...\nInstalling Statistics tools...\n\nConsole output will appear here as the install runs.',
      running: true,
    );
    if (mounted) {
      unawaited(
        showSshConsoleSheet(
          context: context,
          controller: console,
          title: 'Install Statistics Tools',
        ).whenComplete(console.dispose),
      );
    }
    try {
      final outputBuffer = StringBuffer();
      await ref
          .read(appStateProvider)
          .installOpenwallaSetupFeatures(
            const ['usage', 'bandwidth'],
            postInstallCheck:
                'if command -v vnstat >/dev/null 2>&1 && '
                '(command -v nlbw >/dev/null 2>&1 || command -v nlbwmon >/dev/null 2>&1); '
                'then echo OK; else exit 1; fi',
            onOutput: (chunk) {
              outputBuffer.write(chunk);
              console.setOutput(outputBuffer.toString().trimRight());
            },
          );
      console.setOutput(
        outputBuffer.toString().trim().isEmpty
            ? 'Statistics tools install finished. The router did not return console output.'
            : outputBuffer.toString().trimRight(),
      );
      if (!mounted) return;
      setState(() {
        _usageFutures.clear();
        _monthlyUsageSettingsFuture = null;
        _statisticsSupportFuture = null;
        _topDevicesFuture = null;
        _protocolUsageFuture = null;
        _clearPreloadBindings();
      });
      await ref.read(appStateProvider).fetchDashboardData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Statistics tools installed.')),
      );
    } catch (e) {
      console.setOutput('Install failed.\n\n$e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Install failed: $e')));
    } finally {
      console.complete();
      if (mounted) setState(() => _isInstallingSupport = false);
    }
  }

  void _openUsageSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const UsageSettingsScreen()),
    );
  }

  void _backToDashboard() {
    ref.read(appStateProvider).requestTab(0);
  }

  String _primaryUsageInterfaceName(AppState appState) {
    final interfaces =
        appState.dashboardData?['interfaceDump']?['interface']
            as List<dynamic>?;
    if (interfaces == null) return 'br-lan';

    final names = interfaces
        .whereType<Map<String, dynamic>>()
        .map((interface) => interface['interface']?.toString())
        .whereType<String>()
        .where((name) => name != 'loopback' && name != 'lo')
        .toList();

    return names.firstWhere(
      (name) => name == 'br-lan',
      orElse: () => names.isNotEmpty ? names.first : 'br-lan',
    );
  }

  Widget _card({required Widget child, VoidCallback? onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: isDark
              ? _border
              : colorScheme.outlineVariant.withValues(alpha: 0.62),
        ),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildUsageCard(String interfaceName) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow('$interfaceName Usage'),
          const SizedBox(height: 14),
          _usageRangePager(interfaceName),
        ],
      ),
    );
  }

  Widget _buildMonthlyUsageCard(
    String interfaceName, {
    required int monthlyLimitGb,
  }) {
    return _card(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MonthlyUsageScreen(
              interfaceName: interfaceName,
              monthlyLimitGb: monthlyLimitGb,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow('$interfaceName Monthly Usage', trailing: _subtleArrow()),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FutureBuilder<List<VnstatUsageSample>>(
                future: _monthlyUsageFuture(interfaceName),
                builder: (context, snapshot) {
                  final summary = _monthlySummary(
                    snapshot.data ?? const [],
                    monthlyLimitGb: monthlyLimitGb,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatUsageTotal(summary.totalBytes),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                              height: 0.95,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${summary.daysLeft} days left',
                          style: _mutedTextStyle(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          FutureBuilder<List<VnstatUsageSample>>(
            future: _monthlyUsageFuture(interfaceName),
            builder: (context, snapshot) {
              final summary = _monthlySummary(
                snapshot.data ?? const [],
                monthlyLimitGb: monthlyLimitGb,
              );
              return _progressBar(summary.progress);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopDevicesCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow('Top Devices'),
          const SizedBox(height: 16),
          FutureBuilder<List<NlbwDeviceUsage>>(
            future: _topDevices(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <NlbwDeviceUsage>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  rows.isEmpty) {
                return const SizedBox(
                  height: 92,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (rows.isEmpty) {
                return _emptyStatText('No nlbwmon device usage yet');
              }

              final maxBytes = rows.map((row) => row.totalBytes).reduce(max);
              return Column(
                children: rows
                    .map(
                      (row) => _usageBreakdownRow(
                        icon: Icons.devices_rounded,
                        iconColor: _cyan,
                        title: row.label,
                        subtitle:
                            'Down ${_formatUsageTotal(row.downloadBytes)}  Up ${_formatUsageTotal(row.uploadBytes)}',
                        totalBytes: row.totalBytes,
                        maxBytes: maxBytes,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActivityAnalysisCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow('Activity Analysis'),
          const SizedBox(height: 16),
          FutureBuilder<List<NlbwProtocolUsage>>(
            future: _protocolUsage(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <NlbwProtocolUsage>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  rows.isEmpty) {
                return const SizedBox(
                  height: 92,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (rows.isEmpty) {
                return _emptyStatText('No nlbwmon protocol usage yet');
              }

              final totalBytes = rows.fold<int>(
                0,
                (sum, row) => sum + row.totalBytes,
              );
              final maxBytes = rows.map((row) => row.totalBytes).reduce(max);
              return Column(
                children: rows
                    .map(
                      (row) => _usageBreakdownRow(
                        icon: _protocolIcon(row.protocol),
                        iconColor: _protocolColor(row.protocol),
                        title: _protocolLabel(row.protocol),
                        subtitle:
                            '${_formatPercent(row.totalBytes, totalBytes)} of shown traffic',
                        totalBytes: row.totalBytes,
                        maxBytes: maxBytes,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<VnstatUsageSample>> _monthlyUsageFuture(String interfaceName) {
    final key = '$interfaceName:monthly-summary';
    final preload = ref.read(appStateProvider).statisticsPreloadData;
    if (preload?.interfaceName == interfaceName) {
      _bindPreloadData(preload!);
      final samples = preload.samplesFor('monthly-summary');
      if (samples != null) {
        return _preloadUsageFutures.putIfAbsent(
          key,
          () => Future.value(samples),
        );
      }
    }
    final preloadFuture = ref.read(appStateProvider).statisticsPreloadFuture;
    if (preloadFuture != null) {
      _bindPreloadFuture(preloadFuture);
      return _preloadUsageFutures.putIfAbsent(
        key,
        () => preloadFuture.then((data) {
          if (data.interfaceName == interfaceName) {
            return data.samplesFor('monthly-summary') ?? const [];
          }
          return ref
              .read(appStateProvider)
              .fetchVnstatUsageSamples(
                period: 'daily',
                interfaceName: interfaceName,
                limit: 45,
              );
        }),
      );
    }
    return _usageFutures.putIfAbsent(
      key,
      () => ref
          .read(appStateProvider)
          .fetchVnstatUsageSamples(
            period: 'daily',
            interfaceName: interfaceName,
            limit: 45,
          ),
    );
  }

  Future<List<VnstatUsageSample>> _usageFuture(
    _StatsUsageRange range,
    String interfaceName,
  ) {
    final period = switch (range) {
      _StatsUsageRange.minute => '5min',
      _StatsUsageRange.hour => 'hourly',
      _StatsUsageRange.day => 'hourly',
      _StatsUsageRange.week => 'daily',
    };
    final limit = switch (range) {
      _StatsUsageRange.minute => 12,
      _StatsUsageRange.hour => 12,
      _StatsUsageRange.day => 24,
      _StatsUsageRange.week => 7,
    };
    final key = '$interfaceName:$period:$limit';
    final preload = ref.read(appStateProvider).statisticsPreloadData;
    if (preload?.interfaceName == interfaceName) {
      _bindPreloadData(preload!);
      final samples = preload.samplesFor('$period:$limit');
      if (samples != null) {
        return _preloadUsageFutures.putIfAbsent(
          key,
          () => Future.value(samples),
        );
      }
    }
    final preloadFuture = ref.read(appStateProvider).statisticsPreloadFuture;
    if (preloadFuture != null) {
      _bindPreloadFuture(preloadFuture);
      return _preloadUsageFutures.putIfAbsent(
        key,
        () => preloadFuture.then((data) {
          if (data.interfaceName == interfaceName) {
            return data.samplesFor('$period:$limit') ?? const [];
          }
          return ref
              .read(appStateProvider)
              .fetchVnstatUsageSamples(
                period: period,
                interfaceName: interfaceName,
                limit: limit,
              );
        }),
      );
    }
    return _usageFutures.putIfAbsent(
      key,
      () => ref
          .read(appStateProvider)
          .fetchVnstatUsageSamples(
            period: period,
            interfaceName: interfaceName,
            limit: limit,
          ),
    );
  }

  String _usageRangeLabel(_StatsUsageRange range) {
    return switch (range) {
      _StatsUsageRange.minute => 'Minute',
      _StatsUsageRange.hour => 'Hour',
      _StatsUsageRange.day => 'Day',
      _StatsUsageRange.week => 'Week',
    };
  }

  String _usageSubtitle(_StatsUsageRange range) {
    return switch (range) {
      _StatsUsageRange.minute => 'Last 60 minutes',
      _StatsUsageRange.hour => 'Last 12 hours',
      _StatsUsageRange.day => 'Last 24 hours',
      _StatsUsageRange.week => 'Last 7 days',
    };
  }

  Widget _usageRangePager(String interfaceName) {
    return Column(
      children: [
        SizedBox(
          height: 336,
          child: PageView.builder(
            controller: _usageRangeController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              setState(() => _usageRange = _StatsUsageRange.values[index]);
            },
            itemCount: _StatsUsageRange.values.length,
            itemBuilder: (context, index) {
              final range = _StatsUsageRange.values[index];
              return _usageRangePage(interfaceName, range);
            },
          ),
        ),
        const SizedBox(height: 6),
        _usageRangeDots(),
      ],
    );
  }

  Widget _usageRangePage(String interfaceName, _StatsUsageRange range) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _usageRangeLabel(range),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              _usageSubtitle(range),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<VnstatUsageSample>>(
          future: _usageFuture(range, interfaceName),
          builder: (context, snapshot) {
            final samples = _usageSamplesForRange(
              range,
              snapshot.data ?? const [],
            );
            return _usageLineGraph(samples);
          },
        ),
        const SizedBox(height: 12),
        _usageLegend(),
      ],
    );
  }

  Widget _usageRangeDots() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _StatsUsageRange.values.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: _usageRange.index == index ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: _usageRange.index == index
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
  _usageSamplesForRange(
    _StatsUsageRange range,
    List<VnstatUsageSample> samples,
  ) {
    final now = DateTime.now();
    return switch (range) {
      _StatsUsageRange.minute => _timeBuckets(
        samples,
        count: 12,
        bucket: const Duration(minutes: 5),
        anchor: DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute - (now.minute % 5),
        ),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Now' : _timeLabel(slot),
      ),
      _StatsUsageRange.hour => _timeBuckets(
        samples,
        count: 12,
        bucket: const Duration(hours: 1),
        anchor: DateTime(now.year, now.month, now.day, now.hour),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Now' : _hourLabel(slot),
      ),
      _StatsUsageRange.day => _timeBuckets(
        samples,
        count: 24,
        bucket: const Duration(hours: 1),
        anchor: DateTime(now.year, now.month, now.day, now.hour),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Now' : _hourLabel(slot),
      ),
      _StatsUsageRange.week => _timeBuckets(
        samples,
        count: 7,
        bucket: const Duration(days: 1),
        anchor: DateTime(now.year, now.month, now.day),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Today' : _weekdayShort(slot.weekday),
      ),
    };
  }

  List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
  _timeBuckets(
    List<VnstatUsageSample> samples, {
    required int count,
    required Duration bucket,
    required DateTime anchor,
    required String Function(DateTime slot, int index, int lastIndex) labelFor,
  }) {
    return List.generate(count, (index) {
      final slot = anchor.subtract(bucket * (count - 1 - index));
      final slotEnd = slot.add(bucket);
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(slot) && time.isBefore(slotEnd);
      }).toList();
      return (
        label: labelFor(slot, index, count - 1),
        downloadBytes: matches.fold<int>(
          0,
          (sum, sample) => sum + sample.downloadBytes,
        ),
        uploadBytes: matches.fold<int>(
          0,
          (sum, sample) => sum + sample.uploadBytes,
        ),
        hasData: matches.isNotEmpty,
      );
    });
  }

  Widget _usageLineGraph(
    List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
    samples,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalDownload = samples.fold<int>(
      0,
      (sum, sample) => sum + sample.downloadBytes,
    );
    final totalUpload = samples.fold<int>(
      0,
      (sum, sample) => sum + sample.uploadBytes,
    );
    final maxValue = samples
        .expand((sample) => [sample.downloadBytes, sample.uploadBytes])
        .fold<int>(0, max);
    final maxY = _niceMax(maxValue);
    final labelIndexes = _bottomLabelIndexes(samples.length);
    final hasAnyData = samples.any((sample) => sample.hasData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usageTotalSummary(totalDownload, totalUpload),
        const SizedBox(height: 12),
        SizedBox(
          height: 188,
          child: Stack(
            alignment: Alignment.center,
            children: [
              LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (samples.length - 1)
                      .clamp(1, samples.length)
                      .toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.22),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(
                            _formatUsageTotal(value.round()),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.74),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (!labelIndexes.contains(index) ||
                              index < 0 ||
                              index >= samples.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              samples[index].label,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: index == samples.length - 1
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: index == samples.length - 1
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    _lineBar(samples, _cyan, (sample) => sample.downloadBytes),
                    _lineBar(samples, _orange, (sample) => sample.uploadBytes),
                  ],
                ),
              ),
              if (!hasAnyData)
                Text('No usage data yet', style: _mutedTextStyle()),
            ],
          ),
        ),
      ],
    );
  }

  LineChartBarData _lineBar(
    List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
    samples,
    Color color,
    int Function(
      ({String label, int downloadBytes, int uploadBytes, bool hasData}) sample,
    )
    selector,
  ) {
    return LineChartBarData(
      spots: List.generate(samples.length, (index) {
        final sample = samples[index];
        return FlSpot(
          index.toDouble(),
          sample.hasData ? selector(sample).toDouble() : 0,
        );
      }),
      isCurved: false,
      color: color,
      barWidth: 2,
      isStrokeCapRound: true,
      isStrokeJoinRound: false,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }

  Widget _usageBreakdownRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int totalBytes,
    required int maxBytes,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = maxBytes <= 0 ? 0.0 : totalBytes / maxBytes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatUsageTotal(totalBytes),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: progress.clamp(0, 1),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: _mutedTextStyle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyStatText(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(child: Text(message, style: _mutedTextStyle())),
    );
  }

  IconData _protocolIcon(String protocol) {
    final label = protocol.toLowerCase();
    if (label.contains('web') ||
        label.contains('http') ||
        label.contains('stream')) {
      return Icons.public_rounded;
    }
    if (label.contains('dns')) return Icons.dns_rounded;
    if (label.contains('mail') || label.contains('chat')) {
      return Icons.forum_rounded;
    }
    if (label.contains('video')) return Icons.play_circle_outline_rounded;
    return Icons.help_outline_rounded;
  }

  Color _protocolColor(String protocol) {
    final label = protocol.toLowerCase();
    if (label.contains('web') ||
        label.contains('http') ||
        label.contains('stream')) {
      return _cyan;
    }
    if (label.contains('dns')) return const Color(0xFFEAB308);
    if (label.contains('mail') || label.contains('chat')) {
      return const Color(0xFF20CF70);
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  String _protocolLabel(String protocol) {
    final raw = protocol.trim();
    if (raw.isEmpty || raw == '-') return 'Other';
    final lower = raw.toLowerCase();
    if (lower == 'http' || lower == 'https' || lower == 'http/s') {
      return 'Web & Streaming';
    }
    return raw
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String _formatPercent(int value, int total) {
    if (total <= 0) return '0%';
    final percent = value / total * 100;
    if (percent >= 10) return '${percent.toStringAsFixed(0)}%';
    return '${percent.toStringAsFixed(1)}%';
  }

  Widget _titleRow(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _subtleArrow() {
    return Icon(
      Icons.chevron_right_rounded,
      size: 24,
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    );
  }

  Widget _progressBar(double value) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 16,
        value: value.clamp(0, 1),
        backgroundColor: colorScheme.surfaceContainerHighest,
        valueColor: const AlwaysStoppedAnimation<Color>(_cyan),
      ),
    );
  }

  Widget _usageTotalSummary(int downloadBytes, int uploadBytes) {
    final total = downloadBytes + uploadBytes;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Total ${_formatUsageTotal(total)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              'Down ${_formatUsageTotal(downloadBytes)}  Up ${_formatUsageTotal(uploadBytes)}',
              style: _mutedTextStyle(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _usageLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem('Download', _cyan),
        const SizedBox(width: 18),
        _legendItem('Upload', _orange),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: _mutedTextStyle()),
      ],
    );
  }

  TextStyle? _mutedTextStyle() {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  double _niceMax(int maxBytes) {
    if (maxBytes <= 0) return 1024;
    final units = <int>[
      1024,
      10 * 1024,
      100 * 1024,
      1024 * 1024,
      10 * 1024 * 1024,
      100 * 1024 * 1024,
      1024 * 1024 * 1024,
      10 * 1024 * 1024 * 1024,
      100 * 1024 * 1024 * 1024,
    ];
    for (final unit in units) {
      if (maxBytes <= unit) return unit.toDouble();
    }
    return maxBytes * 1.15;
  }

  Set<int> _bottomLabelIndexes(int length) {
    if (length <= 1) return {0};
    return {0, (length / 3).floor(), ((length * 2) / 3).floor(), length - 1};
  }

  ({int totalBytes, int daysLeft, double progress}) _monthlySummary(
    List<VnstatUsageSample> samples, {
    required int monthlyLimitGb,
  }) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final daysInMonth = end.difference(start).inDays;
    final totalBytes = samples
        .where((sample) {
          final time = sample.timestamp.toLocal();
          return !time.isBefore(start) && time.isBefore(end);
        })
        .fold<int>(
          0,
          (sum, sample) => sum + sample.downloadBytes + sample.uploadBytes,
        );

    final limitBytes = monthlyLimitGb <= 0
        ? 0
        : monthlyLimitGb * 1024 * 1024 * 1024;
    final progress = limitBytes > 0
        ? totalBytes / limitBytes
        : daysInMonth <= 0
        ? 0
        : now.day / daysInMonth;

    return (
      totalBytes: totalBytes,
      daysLeft: max(0, daysInMonth - now.day),
      progress: progress.toDouble(),
    );
  }

  String _timeLabel(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _hourLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
  }

  String _weekdayShort(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  String _formatUsageTotal(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    if (gb >= 100) return '${gb.toStringAsFixed(0)} GB';
    if (gb >= 10) return '${gb.toStringAsFixed(1)} GB';
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _SetupRequiredCard extends StatelessWidget {
  final String title;
  final String message;
  final String buttonLabel;
  final bool isInstalling;
  final VoidCallback onPressed;
  final VoidCallback onRouterSetup;
  final VoidCallback onHideStatistics;

  const _SetupRequiredCard({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.isInstalling,
    required this.onPressed,
    required this.onRouterSetup,
    required this.onHideStatistics,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.construction_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isInstalling ? null : onPressed,
              icon: isInstalling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(isInstalling ? 'Installing...' : buttonLabel),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isInstalling ? null : onRouterSetup,
              icon: const Icon(Icons.router_rounded),
              label: const Text('Router Setup'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: isInstalling ? null : onHideStatistics,
              icon: const Icon(Icons.visibility_off_rounded),
              label: const Text('Hide Statistics Tab'),
            ),
          ],
        ),
      ),
    );
  }
}
