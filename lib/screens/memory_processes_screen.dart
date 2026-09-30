import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class MemoryProcessesScreen extends ConsumerStatefulWidget {
  const MemoryProcessesScreen({super.key});

  @override
  ConsumerState<MemoryProcessesScreen> createState() =>
      _MemoryProcessesScreenState();
}

class _MemoryProcessesScreenState extends ConsumerState<MemoryProcessesScreen> {
  late Future<List<ProcessMemoryUsage>> _processesFuture;

  @override
  void initState() {
    super.initState();
    _processesFuture = _loadProcesses();
  }

  Future<List<ProcessMemoryUsage>> _loadProcesses() {
    return ref
        .read(appStateProvider)
        .fetchTopMemoryProcesses(limit: 10, context: context);
  }

  Future<void> _refresh() async {
    final future = _loadProcesses();
    setState(() {
      _processesFuture = future;
    });
    await future;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Memory Processes', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<ProcessMemoryUsage>>(
            future: _processesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data ?? const <ProcessMemoryUsage>[];
              if (rows.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
                  children: [
                    Icon(
                      Icons.memory_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No process memory data',
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

              final maxRss = rows
                  .map((row) => row.rssBytes)
                  .fold<int>(0, (max, value) => value > max ? value : max);
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: rows.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox(height: 12)
                    : const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _SummaryCard(
                      totalRows: rows.length,
                      top: rows.first,
                    );
                  }
                  final row = rows[index - 1];
                  return _ProcessMemoryCard(
                    rank: index,
                    process: row,
                    maxRss: maxRss,
                    formatBytes: _formatBytes,
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

class _SummaryCard extends StatelessWidget {
  final int totalRows;
  final ProcessMemoryUsage top;

  const _SummaryCard({required this.totalRows, required this.top});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    return mb < 1024
        ? '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB'
        : '${(mb / 1024).toStringAsFixed(2)} GB';
  }

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
                color: const Color(0xFF18AEEA).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.memory_rounded, color: Color(0xFF18AEEA)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top memory usage',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalRows processes shown by resident memory',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _formatBytes(top.rssBytes),
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

class _ProcessMemoryCard extends StatelessWidget {
  final int rank;
  final ProcessMemoryUsage process;
  final int maxRss;
  final String Function(int bytes) formatBytes;

  const _ProcessMemoryCard({
    required this.rank,
    required this.process,
    required this.maxRss,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = maxRss > 0
        ? (process.rssBytes / maxRss).clamp(0.0, 1.0)
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
                      formatBytes(process.rssBytes),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'RSS',
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
                valueColor: const AlwaysStoppedAnimation(Color(0xFF18AEEA)),
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
            if (process.virtualBytes > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Virtual: ${formatBytes(process.virtualBytes)}',
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
