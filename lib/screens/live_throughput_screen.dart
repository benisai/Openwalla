import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/screens/router_dashboard_settings_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class LiveThroughputScreen extends ConsumerStatefulWidget {
  const LiveThroughputScreen({super.key});

  @override
  ConsumerState<LiveThroughputScreen> createState() =>
      _LiveThroughputScreenState();
}

class _LiveThroughputScreenState extends ConsumerState<LiveThroughputScreen> {
  static const _historyLimit = 36;
  static const _blue = Color(0xFF188CFF);
  static const _orange = Color(0xFFF27C24);

  final List<double> _totalHistory = [];
  final Map<String, LiveDeviceTrafficCounter> _lastCounters = {};
  final Map<String, _LiveDeviceSpeed> _deviceSpeeds = {};
  final Map<String, Client> _clientsByMac = {};
  final Map<String, Client> _clientsByIp = {};
  Timer? _refreshTimer;
  DateTime? _lastSampleAt;
  bool _paused = false;
  bool _loading = true;
  String? _error;

  Duration get _refreshInterval {
    return Duration(
      seconds: ref
          .read(appStateProvider)
          .dashboardPreferences
          .liveThroughputRefreshSeconds,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadClients();
      await _sample();
      _startTimer();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClients() async {
    final clients = await ref
        .read(appStateProvider)
        .fetchClientsForSelectedRouter();
    _clientsByMac
      ..clear()
      ..addEntries(
        clients
            .where((client) => _normalizeMac(client.macAddress).isNotEmpty)
            .map(
              (client) => MapEntry(_normalizeMac(client.macAddress), client),
            ),
      );
    _clientsByIp
      ..clear()
      ..addEntries(
        clients
            .where((client) => client.ipAddress.trim().isNotEmpty)
            .map((client) => MapEntry(client.ipAddress.trim(), client)),
      );
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!_paused) unawaited(_sample());
    });
  }

  Future<void> _openMonitoringSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const RouterDashboardSettingsScreen(
          title: 'Live Throughput Monitoring',
          showDashboardCards: false,
          showShortcutPanel: false,
          showWirelessInterfaces: false,
          showWiredInterfaces: false,
        ),
      ),
    );
    if (!mounted) return;
    _startTimer();
  }

  Future<void> _sample() async {
    if (!mounted) return;
    setState(() {
      _loading = _lastSampleAt == null;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final counters = await appState.fetchLiveDeviceTrafficCounters(
        context: context,
      );
      if (!mounted) return;

      final now = DateTime.now();
      final elapsed = _lastSampleAt == null
          ? _refreshInterval.inSeconds.toDouble()
          : math.max(
              1.0,
              now.difference(_lastSampleAt!).inMilliseconds / 1000.0,
            );

      final nextSpeeds = <String, _LiveDeviceSpeed>{};
      for (final counter in counters) {
        final key = _counterKey(counter);
        final previous = _lastCounters[key];
        final downloadRate = previous == null
            ? 0.0
            : math.max(
                0.0,
                (counter.downloadBytes - previous.downloadBytes) / elapsed,
              );
        final uploadRate = previous == null
            ? 0.0
            : math.max(
                0.0,
                (counter.uploadBytes - previous.uploadBytes) / elapsed,
              );
        final client = _clientFor(counter);
        nextSpeeds[key] = _LiveDeviceSpeed(
          ip: counter.ip,
          mac: counter.mac,
          name: _deviceName(counter, client),
          icon: _deviceIcon(client),
          downloadBytesPerSecond: downloadRate,
          uploadBytesPerSecond: uploadRate,
        );
        _lastCounters[key] = counter;
      }

      final totalRate = nextSpeeds.values.fold<double>(
        0,
        (sum, speed) => sum + speed.totalBytesPerSecond,
      );
      _totalHistory.add(totalRate);
      if (_totalHistory.length > _historyLimit) {
        _totalHistory.removeRange(0, _totalHistory.length - _historyLimit);
      }

      setState(() {
        _deviceSpeeds
          ..clear()
          ..addAll(nextSpeeds);
        _lastSampleAt = now;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load live device throughput.';
        _loading = false;
      });
    }
  }

  String _counterKey(LiveDeviceTrafficCounter counter) {
    final mac = _normalizeMac(counter.mac);
    if (mac.isNotEmpty) return mac;
    return counter.ip;
  }

  Client? _clientFor(LiveDeviceTrafficCounter counter) {
    final mac = _normalizeMac(counter.mac);
    if (mac.isNotEmpty && _clientsByMac.containsKey(mac)) {
      return _clientsByMac[mac];
    }
    return _clientsByIp[counter.ip];
  }

  String _deviceName(LiveDeviceTrafficCounter counter, Client? client) {
    final name = client?.hostname.trim() ?? '';
    if (name.isNotEmpty && name.toLowerCase() != 'unknown') return name;
    return counter.ip;
  }

  IconData _deviceIcon(Client? client) {
    switch (client?.deviceIcon) {
      case 'phone':
        return Icons.phone_android_rounded;
      case 'laptop':
        return Icons.laptop_mac_rounded;
      case 'router':
        return Icons.router_rounded;
      case 'camera':
        return Icons.videocam_rounded;
      case 'tv':
        return Icons.tv_rounded;
      case 'game':
        return Icons.sports_esports_rounded;
      default:
        switch (client?.connectionType) {
          case ConnectionType.wireless:
            return Icons.wifi_rounded;
          case ConnectionType.wired:
            return Icons.computer_rounded;
          default:
            return Icons.devices_other_rounded;
        }
    }
  }

  String _normalizeMac(String value) {
    final cleaned = value.trim().toLowerCase().replaceAll('-', ':');
    if (cleaned == 'n/a') return '';
    return cleaned;
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond.isNaN ||
        bytesPerSecond.isInfinite ||
        bytesPerSecond <= 0) {
      return '0 bps';
    }
    final bitsPerSecond = bytesPerSecond * 8;
    if (bitsPerSecond < 1000) return '${bitsPerSecond.toStringAsFixed(0)} bps';
    if (bitsPerSecond < 1000000) {
      return '${(bitsPerSecond / 1000).toStringAsFixed(0)} Kbps';
    }
    return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    final speeds = _deviceSpeeds.values.toList()
      ..sort((a, b) => b.totalBytesPerSecond.compareTo(a.totalBytesPerSecond));
    final total = speeds.fold<double>(
      0,
      (sum, speed) => sum + speed.totalBytesPerSecond,
    );
    final maxSpeed = speeds.isEmpty
        ? 1.0
        : speeds.first.totalBytesPerSecond.clamp(1.0, double.infinity);

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Live Throughput',
        showBack: true,
        actions: [
          IconButton(
            tooltip: _paused
                ? 'Resume live throughput'
                : 'Pause live throughput',
            onPressed: () {
              final resume = _paused;
              setState(() => _paused = !_paused);
              if (resume) unawaited(_sample());
            },
            icon: Icon(
              _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Live throughput settings',
            onPressed: _openMonitoringSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadClients();
            await _sample();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _TotalThroughputCard(
                totalSpeed: total,
                history: _totalHistory,
                formatter: _formatSpeed,
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 42),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _LiveThroughputEmptyCard(
                  message: _error!,
                  actionLabel: 'Retry',
                  onPressed: _sample,
                )
              else if (speeds.isEmpty)
                _LiveThroughputEmptyCard(
                  message:
                      'No live device traffic yet. Install device-speed from Router Setup if this stays empty.',
                  actionLabel: 'Refresh',
                  onPressed: _sample,
                )
              else
                ...speeds
                    .take(20)
                    .indexed
                    .map(
                      (entry) => _LiveDeviceSpeedCard(
                        rank: entry.$1 + 1,
                        speed: entry.$2,
                        maxSpeed: maxSpeed,
                        formatter: _formatSpeed,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDeviceSpeed {
  final String ip;
  final String mac;
  final String name;
  final IconData icon;
  final double downloadBytesPerSecond;
  final double uploadBytesPerSecond;

  const _LiveDeviceSpeed({
    required this.ip,
    required this.mac,
    required this.name,
    required this.icon,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
  });

  double get totalBytesPerSecond =>
      downloadBytesPerSecond + uploadBytesPerSecond;
}

class _TotalThroughputCard extends StatelessWidget {
  final double totalSpeed;
  final List<double> history;
  final String Function(double value) formatter;

  const _TotalThroughputCard({
    required this.totalSpeed,
    required this.history,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final values = history.isEmpty ? const [0.0, 0.0] : history;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
          Text(
            'Total Throughput',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 98,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: values.indexed
                        .map(
                          (entry) =>
                              FlSpot(entry.$1.toDouble(), entry.$2.toDouble()),
                        )
                        .toList(),
                    isCurved: false,
                    color: _LiveThroughputScreenState._blue,
                    barWidth: 2,
                    isStrokeCapRound: false,
                    isStrokeJoinRound: false,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _LiveThroughputScreenState._blue.withValues(
                        alpha: 0.14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _LiveThroughputScreenState._blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatter(totalSpeed),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveDeviceSpeedCard extends StatelessWidget {
  final int rank;
  final _LiveDeviceSpeed speed;
  final double maxSpeed;
  final String Function(double value) formatter;

  const _LiveDeviceSpeedCard({
    required this.rank,
    required this.speed,
    required this.maxSpeed,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = (speed.totalBytesPerSecond / maxSpeed).clamp(0.02, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(speed.icon, color: _LiveThroughputScreenState._blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  speed.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 10,
              color: _LiveThroughputScreenState._blue,
              backgroundColor: colorScheme.outlineVariant.withValues(
                alpha: 0.42,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _SpeedLabel(
                color: _LiveThroughputScreenState._blue,
                label: formatter(speed.downloadBytesPerSecond),
              ),
              _SpeedLabel(
                color: _LiveThroughputScreenState._orange,
                label: formatter(speed.uploadBytesPerSecond),
              ),
              if (speed.ip.isNotEmpty)
                Text(
                  speed.ip,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedLabel extends StatelessWidget {
  final Color color;
  final String label;

  const _SpeedLabel({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _LiveThroughputEmptyCard extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  const _LiveThroughputEmptyCard({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
