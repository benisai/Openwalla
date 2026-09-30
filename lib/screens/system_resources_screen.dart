import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/system_resource_metrics.dart';
import 'package:openwalla/screens/cpu_processes_screen.dart';
import 'package:openwalla/screens/memory_processes_screen.dart';
import 'package:openwalla/screens/system_logs_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class SystemResourcesScreen extends ConsumerStatefulWidget {
  const SystemResourcesScreen({super.key});

  @override
  ConsumerState<SystemResourcesScreen> createState() =>
      _SystemResourcesScreenState();
}

class _SystemResourcesScreenState extends ConsumerState<SystemResourcesScreen> {
  static const _historyLimit = 36;
  static const _seedSampleCount = 18;

  SystemStorageDetails _storage = SystemStorageDetails.empty;
  bool _isLoadingStorage = true;
  final List<double> _cpuHistory = [];
  final List<double> _memoryHistory = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _appendCurrentSample();
      await _loadStorage();
      _startRefreshTimer();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    final refreshSeconds = ref
        .read(appStateProvider)
        .dashboardPreferences
        .systemResourcesRefreshSeconds;
    _refreshTimer = Timer.periodic(Duration(seconds: refreshSeconds), (
      _,
    ) async {
      if (!mounted) return;
      await ref.read(appStateProvider).fetchDashboardData();
      if (!mounted) return;
      setState(_appendCurrentSample);
    });
  }

  Future<void> _openSettings() async {
    final appState = ref.read(appStateProvider);
    var refreshSeconds =
        appState.dashboardPreferences.systemResourcesRefreshSeconds;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('System Resource Settings'),
          content: DropdownButtonFormField<int>(
            initialValue: refreshSeconds,
            decoration: const InputDecoration(
              labelText: 'Refresh interval',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: const [5, 10, 15, 30]
                .map(
                  (seconds) => DropdownMenuItem<int>(
                    value: seconds,
                    child: Text('$seconds seconds'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => refreshSeconds = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(refreshSeconds),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await appState.saveDashboardPreferences(
      appState.dashboardPreferences.copyWith(
        systemResourcesRefreshSeconds: selected,
      ),
    );
    if (!mounted) return;
    _startRefreshTimer();
    setState(() {});
  }

  Future<void> _loadStorage() async {
    if (!mounted) return;
    setState(() => _isLoadingStorage = true);
    final storage = await ref
        .read(appStateProvider)
        .fetchSystemStorageDetails(context: context);
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _isLoadingStorage = false;
    });
  }

  void _appendCurrentSample() {
    final dashboardData = ref.read(appStateProvider).dashboardData;
    final sysInfo = dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo = dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final metrics = SystemResourceMetrics.fromRouterData(
      sysInfo,
      boardInfo: boardInfo,
    );

    _seedHistoryIfNeeded(_cpuHistory, metrics.cpuUsagePercent);
    _seedHistoryIfNeeded(_memoryHistory, metrics.memoryUsagePercent);
    _pushSample(_cpuHistory, metrics.cpuUsagePercent);
    _pushSample(_memoryHistory, metrics.memoryUsagePercent);
  }

  void _seedHistoryIfNeeded(List<double> history, double currentValue) {
    if (history.isNotEmpty) return;

    for (var i = 0; i < _seedSampleCount; i++) {
      final progress = (i + 1) / _seedSampleCount;
      final wave = (math.sin(i * 0.78) * 3.2) + (math.cos(i * 0.41) * 1.8);
      final trend = (progress - 1) * 4;
      history.add((currentValue + wave + trend).clamp(0, 100).toDouble());
    }
  }

  void _pushSample(List<double> history, double value) {
    history.add(value.clamp(0, 100).toDouble());
    if (history.length > _historyLimit) {
      history.removeRange(0, history.length - _historyLimit);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 1 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
  }

  String _releaseText(Map<String, dynamic>? boardInfo) {
    final release = boardInfo?['release'];
    if (release is Map) {
      final description = release['description']?.toString();
      final revision = release['revision']?.toString();
      return [
        if (description != null && description.isNotEmpty) description,
        if (revision != null && revision.isNotEmpty) revision,
      ].join(' ');
    }
    return boardInfo?['release']?.toString() ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final dashboardData = appState.dashboardData;
    final sysInfo = dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo = dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final metrics = SystemResourceMetrics.fromRouterData(
      sysInfo,
      boardInfo: boardInfo,
    );
    final totalMem = metrics.totalMemoryBytes;
    final usedMem = metrics.usedMemoryBytes;
    final memoryPercent = metrics.memoryUsagePercent;
    final cpuPercent = metrics.cpuUsagePercent;
    final refreshSeconds =
        appState.dashboardPreferences.systemResourcesRefreshSeconds;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'System Resources',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'System resource settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([appState.fetchDashboardData(), _loadStorage()]);
            if (mounted) setState(_appendCurrentSample);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _ResourceGraphCard(
                icon: Icons.speed_rounded,
                title: 'CPU Usage',
                value: '${cpuPercent.round()}%',
                subtitle: '$refreshSeconds second samples',
                color: const Color(0xFF22C55E),
                samples: _cpuHistory,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CpuProcessesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ResourceGraphCard(
                icon: Icons.memory_rounded,
                title: 'Memory Usage',
                value: '${memoryPercent.round()}%',
                subtitle:
                    '${_formatBytes(usedMem)} of ${_formatBytes(totalMem)}',
                color: const Color(0xFF18AEEA),
                samples: _memoryHistory,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const MemoryProcessesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _MetricDetailCard(
                icon: Icons.memory_outlined,
                color: const Color(0xFFF59E0B),
                title: 'CPU Status',
                rows: [
                  ('Estimated Usage', '${cpuPercent.toStringAsFixed(1)}%'),
                  ('1 Min Load', metrics.load1m.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(height: 12),
              _MetricDetailCard(
                icon: Icons.pie_chart_outline_rounded,
                color: const Color(0xFF18AEEA),
                title: 'RAM Memory',
                rows: [
                  ('Usage Percent', '${memoryPercent.toStringAsFixed(1)}%'),
                  ('Used Memory', _formatBytes(usedMem)),
                  ('Free Memory', _formatBytes(metrics.freeMemoryBytes)),
                  ('Buffered', _formatBytes(metrics.bufferedMemoryBytes)),
                  ('Cached', _formatBytes(metrics.cachedMemoryBytes)),
                  ('Total Memory', _formatBytes(totalMem)),
                ],
              ),
              const SizedBox(height: 12),
              _MetricDetailCard(
                icon: Icons.speed_outlined,
                color: const Color(0xFF8B5CF6),
                title: 'Load Average',
                rows: [
                  ('1 Minute', metrics.load1m.toStringAsFixed(2)),
                  ('5 Minutes', metrics.load5m.toStringAsFixed(2)),
                  ('15 Minutes', metrics.load15m.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(height: 12),
              _MetricDetailCard(
                icon: Icons.timer_outlined,
                color: const Color(0xFF22C55E),
                title: 'System Uptime',
                rows: [
                  ('Uptime', metrics.formattedUptime),
                  ('Total Seconds', '${metrics.uptimeSeconds} s'),
                ],
              ),
              const SizedBox(height: 14),
              _StorageOverviewCard(
                storage: _storage,
                isLoading: _isLoadingStorage,
                formatBytes: _formatBytes,
              ),
              const SizedBox(height: 14),
              _SystemInfoPanel(
                release: _releaseText(boardInfo),
                kernel: boardInfo?['kernel']?.toString() ?? '-',
                model: boardInfo?['model']?.toString() ?? '-',
                architecture:
                    boardInfo?['system']?.toString() ??
                    boardInfo?['architecture']?.toString() ??
                    '-',
              ),
              const SizedBox(height: 14),
              _LogsCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SystemLogsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceGraphCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final List<double> samples;
  final VoidCallback? onTap;

  const _ResourceGraphCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.samples,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 34,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GraphAxisLabel(label: '100%'),
                      _GraphAxisLabel(label: '50%'),
                      _GraphAxisLabel(label: '0%'),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CustomPaint(
                    painter: _ResourceLinePainter(
                      samples: List<double>.of(samples),
                      color: color,
                      gridColor: colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                      fillColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class _GraphAxisLabel extends StatelessWidget {
  final String label;

  const _GraphAxisLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ResourceLinePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final Color gridColor;
  final Color fillColor;

  const _ResourceLinePainter({
    required this.samples,
    required this.color,
    required this.gridColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final trackPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      trackPaint,
    );

    if (samples.isEmpty) return;

    final points = <Offset>[];
    final count = math.max(samples.length, 2);
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1
          ? size.width
          : (i / (count - 1)) * size.width;
      final y = size.height - (samples[i].clamp(0, 100) / 100) * size.height;
      points.add(Offset(x, y));
    }
    if (points.length == 1) {
      points.insert(0, Offset(0, points.first.dy));
    }

    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midX = (previous.dx + current.dx) / 2;
      linePath.cubicTo(
        midX,
        previous.dy,
        midX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    canvas.drawCircle(points.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ResourceLinePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _MetricDetailCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<(String, String)> rows;

  const _MetricDetailCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 23),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[index].$1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    rows[index].$2,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StorageOverviewCard extends StatelessWidget {
  const _StorageOverviewCard({
    required this.storage,
    required this.isLoading,
    required this.formatBytes,
  });

  final SystemStorageDetails storage;
  final bool isLoading;
  final String Function(int bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalBytes = storage.totalBytes;
    final usedBytes = storage.usedBytes;
    final freeBytes = storage.freeBytes;
    final usedFraction = storage.usedFraction;
    final usedPercent = usedFraction * 100;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pie_chart_outline_rounded,
                  color: colorScheme.primary,
                  size: 23,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Filesystem Usage Overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (totalBytes <= 0)
              Text(
                'No storage information available.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total System Storage',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Text(
                    '${usedPercent.toStringAsFixed(1)}% Used',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usedFraction,
                  minHeight: 10,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    usedPercent > 85
                        ? colorScheme.error
                        : usedPercent > 65
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF14B8A6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StorageStat(
                      label: 'Total Space',
                      value: formatBytes(totalBytes),
                    ),
                  ),
                  Expanded(
                    child: _StorageStat(
                      label: 'Used Space',
                      value: formatBytes(usedBytes),
                    ),
                  ),
                  Expanded(
                    child: _StorageStat(
                      label: 'Free Space',
                      value: formatBytes(freeBytes),
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StorageStat extends StatelessWidget {
  const _StorageStat({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _LogsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _LogsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.article_rounded,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search recent router log entries',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemInfoPanel extends StatelessWidget {
  final String release;
  final String kernel;
  final String model;
  final String architecture;

  const _SystemInfoPanel({
    required this.release,
    required this.kernel,
    required this.model,
    required this.architecture,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF18AEEA).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.router_rounded,
                    color: Color(0xFF18AEEA),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Router Identity',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        release,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.terminal_rounded,
                  label: 'Kernel',
                  value: kernel,
                ),
                _InfoChip(
                  icon: Icons.devices_other_rounded,
                  label: 'Model',
                  value: model,
                ),
                _InfoChip(
                  icon: Icons.memory_rounded,
                  label: 'Platform',
                  value: architecture,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
