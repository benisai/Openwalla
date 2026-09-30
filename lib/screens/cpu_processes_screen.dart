import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class CpuProcessesScreen extends ConsumerStatefulWidget {
  const CpuProcessesScreen({super.key});

  @override
  ConsumerState<CpuProcessesScreen> createState() => _CpuProcessesScreenState();
}

class _CpuProcessesScreenState extends ConsumerState<CpuProcessesScreen> {
  late Future<List<ProcessCpuUsage>> _processesFuture;

  @override
  void initState() {
    super.initState();
    _processesFuture = _loadProcesses();
  }

  Future<List<ProcessCpuUsage>> _loadProcesses() {
    return ref
        .read(appStateProvider)
        .fetchTopCpuProcesses(limit: 10, context: context);
  }

  Future<void> _refresh() async {
    final future = _loadProcesses();
    setState(() {
      _processesFuture = future;
    });
    await future;
  }

  String _formatPercent(double value) {
    if (value >= 10 || value == value.roundToDouble()) {
      return '${value.round()}%';
    }
    return '${value.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'CPU Processes', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<ProcessCpuUsage>>(
            future: _processesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data ?? const <ProcessCpuUsage>[];
              if (rows.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No process CPU data',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pull down to try again.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              }

              final maxCpu = rows
                  .map((row) => row.cpuPercent)
                  .fold<double>(0, (max, value) => value > max ? value : max);
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: rows.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox(height: 12)
                    : const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CpuSummaryCard(
                      totalRows: rows.length,
                      top: rows.first,
                      formatPercent: _formatPercent,
                    );
                  }
                  final row = rows[index - 1];
                  return _ProcessCpuCard(
                    rank: index,
                    process: row,
                    maxCpu: maxCpu,
                    formatPercent: _formatPercent,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CpuSummaryCard extends StatelessWidget {
  final int totalRows;
  final ProcessCpuUsage top;
  final String Function(double value) formatPercent;

  const _CpuSummaryCard({
    required this.totalRows,
    required this.top,
    required this.formatPercent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.speed_rounded, color: Color(0xFF22C55E)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top CPU usage',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalRows processes shown from top',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatPercent(top.cpuPercent),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessCpuCard extends StatelessWidget {
  final int rank;
  final ProcessCpuUsage process;
  final double maxCpu;
  final String Function(double value) formatPercent;

  const _ProcessCpuCard({
    required this.rank,
    required this.process,
    required this.maxCpu,
    required this.formatPercent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = maxCpu > 0
        ? (process.cpuPercent / maxCpu).clamp(0.0, 1.0)
        : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        process.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PID ${process.pid}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPercent(process.cpuPercent),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'CPU',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              process.command,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (process.memoryPercent > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Memory: ${formatPercent(process.memoryPercent)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
