import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/network_performance_settings_screen.dart';
import 'package:openwalla/screens/recent_events_screen.dart';
import 'package:openwalla/screens/router_setup_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';
import 'package:openwalla/widgets/luci_toast.dart';
import 'package:openwalla/widgets/ssh_console_sheet.dart';

class NetworkPerformanceScreen extends ConsumerStatefulWidget {
  const NetworkPerformanceScreen({super.key});

  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);
  static const Color _green = Color(0xFF20CF70);
  static const Color _yellow = Color(0xFFEAB308);

  static List<PingMonitorSample> _samplesFromDashboard(AppState appState) {
    final rawSamples = appState.dashboardData?['pingSamples'];
    if (rawSamples is List<PingMonitorSample>) return rawSamples;
    return const [];
  }

  static String formatLatency(double? latencyMs) {
    if (latencyMs == null) return 'No data';
    if (latencyMs >= 100) return '${latencyMs.toStringAsFixed(0)}ms';
    return '${latencyMs.toStringAsFixed(1)}ms';
  }

  static double? averageLatestPingLatency(
    List<PingMonitorSample> samples, {
    int count = 5,
  }) {
    final latestLatencies = samples.where((sample) => sample.isOk).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final selected = latestLatencies
        .take(count)
        .map((sample) => sample.latencyMs)
        .whereType<double>()
        .toList();
    if (selected.isEmpty) return null;
    return selected.reduce((a, b) => a + b) / selected.length;
  }

  static List<_PingHourBucket> _hourBuckets(List<PingMonitorSample> samples) {
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

  static Color _bucketColor(_PingHourBucket bucket, Color emptyColor) {
    if (!bucket.hasSamples) return emptyColor.withValues(alpha: 0.76);
    if (bucket.hasOnlyFailures) return const Color(0xFFFF424B);
    final latency = bucket.averageLatencyMs ?? 0;
    if (latency >= 100) return _yellow;
    return _green;
  }

  @override
  ConsumerState<NetworkPerformanceScreen> createState() =>
      _NetworkPerformanceScreenState();
}

class _NetworkPerformanceScreenState
    extends ConsumerState<NetworkPerformanceScreen> {
  List<PingMonitorSample>? _freshSamples;
  List<SpeedtestMonitorSample>? _speedtestSamples;
  List<OpenwallaNotification>? _recentNotifications;
  Future<bool>? _supportFuture;
  bool _isInstallingSupport = false;
  bool _isSpeedtestRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSamples());
  }

  Future<void> _refreshSamples() async {
    final appState = ref.read(appStateProvider);
    final results = await Future.wait([
      appState.fetchPingMonitorSamples(context: mounted ? context : null),
      appState.fetchSpeedtestMonitorSamples(
        limit: 30,
        context: mounted ? context : null,
      ),
      appState.fetchNotifications(
        limit: 50,
        includeArchived: true,
        context: mounted ? context : null,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _freshSamples = results[0] as List<PingMonitorSample>;
      _speedtestSamples = results[1] as List<SpeedtestMonitorSample>;
      _recentNotifications = (results[2] as List<OpenwallaNotification>)
          .where((event) => event.isNetworkPerformanceEvent)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final dashboardSamples = NetworkPerformanceScreen._samplesFromDashboard(
      appState,
    );
    final samples = _freshSamples ?? dashboardSamples;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Network Performance',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Performance settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openPerformanceSettings,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshSamples,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              FutureBuilder<bool>(
                future: _networkPerformanceSupport(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data != true) {
                    return _NetworkSetupRequiredCard(
                      isInstalling: _isInstallingSupport,
                      onInstall: _installNetworkPerformanceSupport,
                      onRouterSetup: _openRouterSetup,
                    );
                  }
                  return Column(
                    children: [
                      _NetworkTimelineCard(samples: samples),
                      const SizedBox(height: 14),
                      _RecentEventsCard(
                        notifications: _recentNotifications ?? const [],
                        onViewAll: _openRecentEvents,
                      ),
                      const SizedBox(height: 14),
                      _PingTestCard(samples: samples),
                      const SizedBox(height: 14),
                      _SpeedTestCard(
                        samples: _speedtestSamples ?? const [],
                        isRunning: _isSpeedtestRunning,
                        onRun: _runSpeedtest,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _networkPerformanceSupport() {
    return _supportFuture ??= ref
        .read(appStateProvider)
        .hasNetworkPerformanceSupport(context: context);
  }

  void _openRouterSetup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const RouterSetupScreen()));
  }

  Future<void> _installNetworkPerformanceSupport() async {
    setState(() => _isInstallingSupport = true);
    final console = SshConsoleController(
      initialOutput:
          'Connecting to router over SSH...\nInstalling Network Performance tools...\n\nConsole output will appear here as the install runs.',
      running: true,
    );
    if (mounted) {
      unawaited(
        showSshConsoleSheet(
          context: context,
          controller: console,
          title: 'Install Network Performance',
        ).whenComplete(console.dispose),
      );
    }
    try {
      final outputBuffer = StringBuffer();
      await ref
          .read(appStateProvider)
          .installOpenwallaSetupFeatures(
            const ['network-monitor', 'dns', 'speedtest', 'notifications'],
            postInstallCheck:
                '[ -x /usr/bin/openwalla-network-monitor ] && [ -x /usr/bin/openwalla-dns-monitor ] && [ -x /usr/bin/openwalla-speedtest-monitor ] && echo OK',
            onOutput: (chunk) {
              outputBuffer.write(chunk);
              console.setOutput(outputBuffer.toString().trimRight());
            },
          );
      console.setOutput(
        outputBuffer.toString().trim().isEmpty
            ? 'Network monitoring install finished. The router did not return console output.'
            : outputBuffer.toString().trimRight(),
      );
      if (!mounted) return;
      setState(() {
        _supportFuture = null;
        _freshSamples = null;
        _speedtestSamples = null;
        _recentNotifications = null;
      });
      await _refreshSamples();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network monitoring installed.')),
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

  void _openPerformanceSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NetworkPerformanceSettingsScreen(),
      ),
    );
  }

  void _openRecentEvents() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RecentEventsScreen(networkIssuesOnly: true),
      ),
    );
  }

  Future<void> _runSpeedtest() async {
    if (_isSpeedtestRunning) return;
    setState(() => _isSpeedtestRunning = true);
    var waitDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _SpeedtestWaitDialog(),
      ).whenComplete(() => waitDialogOpen = false),
    );
    try {
      await ref
          .read(appStateProvider)
          .runSpeedtestMonitorOnce(context: context);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 30));
      if (!mounted) return;
      await _refreshSamples();
      if (!mounted) return;
      context.showToastSuccess(
        'Speed test complete',
        subtitle: 'The latest result is now available.',
        actionKey: 'manual-speedtest',
      );
    } catch (error) {
      if (!mounted) return;
      if (waitDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      context.showToastError(
        'Speed test could not be started',
        subtitle: error.toString().replaceFirst('Bad state: ', ''),
        actionKey: 'manual-speedtest',
      );
    } finally {
      if (mounted) setState(() => _isSpeedtestRunning = false);
    }
  }
}

class _OpenwallaPanel extends StatelessWidget {
  final Widget child;

  const _OpenwallaPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: child,
    );
  }
}

class _NetworkSetupRequiredCard extends StatelessWidget {
  final bool isInstalling;
  final VoidCallback onInstall;
  final VoidCallback onRouterSetup;

  const _NetworkSetupRequiredCard({
    required this.isInstalling,
    required this.onInstall,
    required this.onRouterSetup,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _OpenwallaPanel(
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
              Icons.network_check_rounded,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Network monitoring is not installed',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Install the Openwalla network, DNS, and speedtest helpers to enable the timeline and test graphs.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: isInstalling ? null : onInstall,
            icon: isInstalling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              isInstalling ? 'Installing...' : 'Install Monitoring Tools',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: isInstalling ? null : onRouterSetup,
            icon: const Icon(Icons.router_rounded),
            label: const Text('Router Setup'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _NetworkTimelineCard extends StatelessWidget {
  final List<PingMonitorSample> samples;

  const _NetworkTimelineCard({required this.samples});

  String _formatHour(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
  }

  String _bucketTooltip(
    _PingHourBucket bucket,
    String startLabel,
    String endLabel,
  ) {
    if (!bucket.hasSamples) {
      return '$startLabel - $endLabel\nNo ping data';
    }
    final latency = bucket.averageLatencyMs == null
        ? 'No replies'
        : NetworkPerformanceScreen.formatLatency(bucket.averageLatencyMs);
    return '$startLabel - $endLabel\n'
        'Average latency: $latency\n'
        'Samples: ${bucket.sampleCount}\n'
        'Failures: ${bucket.failureCount}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final buckets = NetworkPerformanceScreen._hourBuckets(samples);
    final averageLatency = NetworkPerformanceScreen.averageLatestPingLatency(
      samples,
    );
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final labels = List<String>.generate(7, (index) {
      if (index == 6) return 'Now';
      return _formatHour(currentHour.subtract(Duration(hours: 5 - index)));
    });

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Network Timeline'),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NetworkPerformanceScreen.formatLatency(averageLatency),
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
                  message: _bucketTooltip(
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
                      color: NetworkPerformanceScreen._bucketColor(
                        bucket,
                        colorScheme.surfaceContainerHighest,
                      ),
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

class _RecentEventsCard extends StatelessWidget {
  final List<OpenwallaNotification> notifications;
  final VoidCallback onViewAll;

  const _RecentEventsCard({
    required this.notifications,
    required this.onViewAll,
  });

  Color _eventColor(OpenwallaNotification notification) {
    return switch (notification.effectiveSeverity) {
      'resolved' => NetworkPerformanceScreen._green,
      'warning' => NetworkPerformanceScreen._yellow,
      'critical' => const Color(0xFFFF4D4F),
      _ => NetworkPerformanceScreen._cyan,
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
    final events = notifications.take(1).toList();

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Expanded(child: _SectionTitle('Recent Events')),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (events.isEmpty)
            Text(
              'No recent events',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            )
          else
            ...List.generate(events.length, (index) {
              final event = events[index];
              final color = _eventColor(event);
              final isLast = index == events.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (!isLast)
                            Container(
                              width: 1,
                              height: 44,
                              margin: const EdgeInsets.only(top: 4),
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.42,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.displayTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _formatTimestamp(event.timestamp),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.86),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PingTestCard extends StatelessWidget {
  final List<PingMonitorSample> samples;

  const _PingTestCard({required this.samples});

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentSlot = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 5) * 5,
    );
    final slots = List<DateTime>.generate(
      12,
      (index) => currentSlot.subtract(Duration(minutes: (11 - index) * 5)),
    );
    final slotSamples = slots.map((slotStart) {
      final slotEnd = slotStart.add(const Duration(minutes: 5));
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(slotStart) && time.isBefore(slotEnd);
      }).toList();
      if (matches.isEmpty) return null;
      return matches.last;
    }).toList();
    final labels = slots.map(_formatTime).toList();
    final validLatencies = slotSamples
        .map((sample) => sample?.latencyMs)
        .whereType<double>()
        .toList();
    final maxLatency = validLatencies.isEmpty
        ? 100.0
        : validLatencies.reduce((a, b) => a > b ? a : b).clamp(1, 1000);
    final averageLatency = NetworkPerformanceScreen.averageLatestPingLatency(
      samples,
    );
    final minLatency = validLatencies.isEmpty
        ? null
        : validLatencies.reduce((a, b) => a < b ? a : b);
    final maxLatencyValue = validLatencies.isEmpty
        ? null
        : validLatencies.reduce((a, b) => a > b ? a : b);
    final bars = slotSamples
        .map(
          (sample) => sample?.latencyMs == null
              ? 0.16
              : (sample!.latencyMs! / maxLatency).clamp(0.04, 1.0),
        )
        .toList();
    final hasData = slotSamples
        .map((sample) => sample?.latencyMs != null)
        .toList();
    final readableLabels = labels.asMap().entries.map((entry) {
      final index = entry.key;
      if (index == 0 || index == labels.length ~/ 2) return entry.value;
      if (index == labels.length - 1) return 'Now';
      return '';
    }).toList();
    final tooltips = slotSamples.asMap().entries.map((entry) {
      final sample = entry.value;
      final slotLabel = entry.key == slotSamples.length - 1
          ? 'Now'
          : labels[entry.key];
      if (sample == null) return '$slotLabel\nNo ping data';
      final latency = NetworkPerformanceScreen.formatLatency(sample.latencyMs);
      return '$slotLabel\nLatency: $latency\nStatus: ${sample.status}\nTarget: ${sample.target}';
    }).toList();

    return _ChartPanel(
      title: 'Ping Test',
      value: NetworkPerformanceScreen.formatLatency(averageLatency),
      label: 'Last 5 avg',
      bars: bars,
      hasData: hasData,
      color: NetworkPerformanceScreen._green,
      secondaryColor: NetworkPerformanceScreen._yellow,
      labels: readableLabels,
      tooltips: tooltips,
      stats: [
        (
          label: 'Min',
          value: NetworkPerformanceScreen.formatLatency(minLatency),
        ),
        (
          label: 'Avg',
          value: NetworkPerformanceScreen.formatLatency(averageLatency),
        ),
        (
          label: 'Max',
          value: NetworkPerformanceScreen.formatLatency(maxLatencyValue),
        ),
      ],
    );
  }
}

class _SpeedTestCard extends StatelessWidget {
  final List<SpeedtestMonitorSample> samples;
  final bool isRunning;
  final VoidCallback onRun;

  const _SpeedTestCard({
    required this.samples,
    required this.isRunning,
    required this.onRun,
  });

  String _formatDay(DateTime time) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[time.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slots = List<DateTime>.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
    final slotSamples = slots.map((slotStart) {
      final slotEnd = slotStart.add(const Duration(days: 1));
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(slotStart) && time.isBefore(slotEnd);
      }).toList();
      if (matches.isEmpty) return null;
      return matches.last;
    }).toList();
    final labels = slots.map(_formatDay).toList();
    final validSpeeds = slotSamples
        .expand((sample) => [sample?.downloadMbps, sample?.uploadMbps])
        .whereType<double>()
        .toList();
    final maxSpeed = validSpeeds.isEmpty
        ? 100.0
        : validSpeeds.reduce((a, b) => a > b ? a : b).clamp(1, 10000);
    final latestSample = slotSamples.reversed
        .whereType<SpeedtestMonitorSample>()
        .where(
          (sample) => sample.downloadMbps != null || sample.uploadMbps != null,
        )
        .firstOrNull;
    final downloadBars = slotSamples
        .map(
          (sample) => sample?.downloadMbps == null
              ? 0.16
              : (sample!.downloadMbps! / maxSpeed).clamp(0.04, 1.0),
        )
        .toList();
    final uploadBars = slotSamples
        .map(
          (sample) => sample?.uploadMbps == null
              ? 0.16
              : (sample!.uploadMbps! / maxSpeed).clamp(0.04, 1.0),
        )
        .toList();
    final hasData = slotSamples
        .map(
          (sample) =>
              sample?.downloadMbps != null || sample?.uploadMbps != null,
        )
        .toList();
    final tooltips = slotSamples.asMap().entries.map((entry) {
      final sample = entry.value;
      final label = entry.key == slotSamples.length - 1
          ? 'Today'
          : labels[entry.key];
      if (sample == null) return '$label\nNo speedtest data';
      final down = sample.downloadMbps == null
          ? 'N/A'
          : '${sample.downloadMbps!.toStringAsFixed(1)} Mbps';
      final up = sample.uploadMbps == null
          ? 'N/A'
          : '${sample.uploadMbps!.toStringAsFixed(1)} Mbps';
      return '$label\nDownload: $down\nUpload: $up\nStatus: ${sample.status}';
    }).toList();

    return _ChartPanel(
      title: 'Speed Test',
      value: latestSample?.downloadMbps == null
          ? 'No data'
          : '${latestSample!.downloadMbps!.toStringAsFixed(0)} Mbps',
      label: 'Latest download',
      bars: downloadBars,
      secondaryBars: uploadBars,
      hasData: hasData,
      color: NetworkPerformanceScreen._cyan,
      secondaryColor: NetworkPerformanceScreen._orange,
      primaryLegend: 'Download',
      secondaryLegend: 'Upload',
      labels: labels,
      tooltips: tooltips,
      stats: [
        (
          label: 'Download',
          value: latestSample?.downloadMbps == null
              ? 'N/A'
              : '${latestSample!.downloadMbps!.toStringAsFixed(1)} Mbps',
        ),
        (
          label: 'Upload',
          value: latestSample?.uploadMbps == null
              ? 'N/A'
              : '${latestSample!.uploadMbps!.toStringAsFixed(1)} Mbps',
        ),
      ],
      trailing: OutlinedButton.icon(
        onPressed: isRunning ? null : onRun,
        icon: isRunning
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow_rounded, size: 18),
        label: Text(isRunning ? 'Running' : 'Run'),
      ),
    );
  }
}

class _SpeedtestWaitDialog extends StatefulWidget {
  const _SpeedtestWaitDialog();

  @override
  State<_SpeedtestWaitDialog> createState() => _SpeedtestWaitDialogState();
}

class _SpeedtestWaitDialogState extends State<_SpeedtestWaitDialog> {
  static const _durationSeconds = 30;
  Timer? _timer;
  int _remainingSeconds = _durationSeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final complete = _remainingSeconds == 0;
    final progress = (_durationSeconds - _remainingSeconds) / _durationSeconds;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NetworkPerformanceScreen._cyan.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.speed_rounded,
              color: complete
                  ? NetworkPerformanceScreen._green
                  : NetworkPerformanceScreen._cyan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              complete ? 'Speed Test Complete' : 'Running Speed Test',
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            complete
                ? 'The latest result will appear on the Speed Test card.'
                : 'Testing download and upload performance. You can close this window while the test continues.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              complete ? 'Complete' : '$_remainingSeconds seconds remaining',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: complete
                    ? NetworkPerformanceScreen._green
                    : colors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          label: const Text('Close'),
        ),
      ],
    );
  }
}

class _ChartStatPill extends StatelessWidget {
  final String label;
  final String value;

  const _ChartStatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
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

class _ChartPanel extends StatelessWidget {
  final String title;
  final String value;
  final String label;
  final List<double> bars;
  final List<double> secondaryBars;
  final List<bool> hasData;
  final Color color;
  final Color secondaryColor;
  final List<String> labels;
  final List<String> tooltips;
  final String? primaryLegend;
  final String? secondaryLegend;
  final List<({String label, String value})> stats;
  final Widget? trailing;

  const _ChartPanel({
    required this.title,
    required this.value,
    required this.label,
    required this.bars,
    this.secondaryBars = const [],
    required this.hasData,
    required this.color,
    required this.secondaryColor,
    required this.labels,
    this.tooltips = const [],
    this.primaryLegend,
    this.secondaryLegend,
    this.stats = const [],
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _SectionTitle(title)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: stats
                  .map(
                    (stat) => Expanded(
                      child: _ChartStatPill(
                        label: stat.label,
                        value: stat.value,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (primaryLegend != null && secondaryLegend != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _ChartLegend(color: color, label: primaryLegend!),
                const SizedBox(width: 18),
                _ChartLegend(color: secondaryColor, label: secondaryLegend!),
              ],
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(bars.length, (index) {
                final height = 112 * bars[index].clamp(0, 1).toDouble();
                final hasSample = index < hasData.length && hasData[index];
                final secondaryHeight = index < secondaryBars.length
                    ? 112 * secondaryBars[index].clamp(0, 1).toDouble()
                    : null;
                return Expanded(
                  child: Tooltip(
                    message: index < tooltips.length
                        ? tooltips[index]
                        : labels[index],
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 3),
                    preferBelow: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ChartBar(
                            height: height,
                            color: !hasSample
                                ? colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.28,
                                  )
                                : secondaryHeight == null &&
                                      index == bars.length - 2
                                ? secondaryColor
                                : color,
                          ),
                          if (secondaryHeight != null) ...[
                            const SizedBox(width: 4),
                            _ChartBar(
                              height: secondaryHeight,
                              color: hasSample
                                  ? secondaryColor
                                  : colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.18,
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(labels.length, (index) {
              final label = labels[index];
              return Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  final double height;
  final Color color;

  const _ChartBar({required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: height < 3 ? 3 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
