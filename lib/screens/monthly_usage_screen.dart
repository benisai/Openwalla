import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class MonthlyUsageScreen extends ConsumerStatefulWidget {
  final String interfaceName;
  final int monthlyLimitGb;

  const MonthlyUsageScreen({
    super.key,
    required this.interfaceName,
    this.monthlyLimitGb = 0,
  });

  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);

  @override
  ConsumerState<MonthlyUsageScreen> createState() => _MonthlyUsageScreenState();
}

class _MonthlyUsageScreenState extends ConsumerState<MonthlyUsageScreen> {
  late final Future<List<VnstatUsageSample>> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = ref
        .read(appStateProvider)
        .fetchVnstatUsageSamples(
          period: 'daily',
          interfaceName: widget.interfaceName,
          limit: 62,
          context: context,
        );
  }

  int _daysInMonth(DateTime date) {
    final nextMonth = DateTime(date.year, date.month + 1);
    return nextMonth.subtract(const Duration(days: 1)).day;
  }

  List<_MonthlyDailyUsage> _dailyUsageSamples(
    List<VnstatUsageSample> samples,
    DateTime now,
    int totalDays,
  ) {
    return List.generate(totalDays, (index) {
      final day = DateTime(now.year, now.month, index + 1);
      final nextDay = day.add(const Duration(days: 1));
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(day) && time.isBefore(nextDay);
      }).toList();
      final downloadBytes = matches.fold<int>(
        0,
        (sum, sample) => sum + sample.downloadBytes,
      );
      final uploadBytes = matches.fold<int>(
        0,
        (sum, sample) => sum + sample.uploadBytes,
      );
      return _MonthlyDailyUsage(
        day: index + 1,
        downloadBytes: downloadBytes,
        uploadBytes: uploadBytes,
        hasData: matches.isNotEmpty,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final totalDays = _daysInMonth(now);
    final daysLeft = totalDays - now.day;

    return Scaffold(
      appBar: LuciAppBar(
        title: '${widget.interfaceName} Monthly Usage',
        showBack: true,
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<VnstatUsageSample>>(
          future: _usageFuture,
          builder: (context, snapshot) {
            final samples = _dailyUsageSamples(
              snapshot.data ?? const [],
              now,
              totalDays,
            );
            final monthlyTotal = samples.fold<int>(
              0,
              (sum, sample) => sum + sample.downloadBytes + sample.uploadBytes,
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                _MonthlySummaryCard(
                  interfaceName: widget.interfaceName,
                  daysLeft: daysLeft,
                  usedBytes: monthlyTotal,
                  progress: _monthlyProgress(monthlyTotal, totalDays),
                ),
                const SizedBox(height: 14),
                _DailyUsageChartCard(samples: samples),
              ],
            );
          },
        ),
      ),
    );
  }

  double _monthlyProgress(int usedBytes, int totalDays) {
    final limitBytes = widget.monthlyLimitGb <= 0
        ? 0
        : widget.monthlyLimitGb * 1024 * 1024 * 1024;
    if (limitBytes > 0) return usedBytes / limitBytes;
    return totalDays > 0 ? DateTime.now().day / totalDays : 0;
  }
}

class _MonthlyDailyUsage {
  final int day;
  final int downloadBytes;
  final int uploadBytes;
  final bool hasData;

  const _MonthlyDailyUsage({
    required this.day,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.hasData,
  });
}

class _OpenwallaPanel extends StatelessWidget {
  final Widget child;

  const _OpenwallaPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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

class _MonthlySummaryCard extends StatelessWidget {
  final String interfaceName;
  final int daysLeft;
  final int usedBytes;
  final double progress;

  const _MonthlySummaryCard({
    required this.interfaceName,
    required this.daysLeft,
    required this.usedBytes,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$interfaceName Monthly Usage',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatUsageTotal(usedBytes),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '$daysLeft days left',
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 16,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(
                MonthlyUsageScreen._cyan,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUsageTotal(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    if (gb >= 100) return '${gb.toStringAsFixed(0)} GB';
    if (gb >= 10) return '${gb.toStringAsFixed(1)} GB';
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _DailyUsageChartCard extends StatelessWidget {
  final List<_MonthlyDailyUsage> samples;

  const _DailyUsageChartCard({required this.samples});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxTotal = samples.fold<int>(0, (max, sample) {
      final total = sample.downloadBytes + sample.uploadBytes;
      return total > max ? total : max;
    });

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usage Per Day',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _UsageAxis(maxTotal: maxTotal),
                const SizedBox(width: 12),
                Expanded(
                  child: _DailyBars(samples: samples, maxTotal: maxTotal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageAxis extends StatelessWidget {
  final int maxTotal;

  const _UsageAxis({required this.maxTotal});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final labels = [
      _formatUsageTotal(maxTotal),
      _formatUsageTotal((maxTotal * 0.75).round()),
      _formatUsageTotal((maxTotal * 0.5).round()),
      _formatUsageTotal((maxTotal * 0.25).round()),
      '0 B',
    ];

    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: labels
            .map(
              (label) => Text(
                label,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color.withValues(alpha: 0.76),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  String _formatUsageTotal(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    if (gb >= 100) return '${gb.toStringAsFixed(0)} GB';
    if (gb >= 10) return '${gb.toStringAsFixed(1)} GB';
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _DailyBars extends StatelessWidget {
  final List<_MonthlyDailyUsage> samples;
  final int maxTotal;

  const _DailyBars({required this.samples, required this.maxTotal});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelEvery = samples.length > 28 ? 5 : 4;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(samples.length, (index) {
        final sample = samples[index];
        final total = sample.downloadBytes + sample.uploadBytes;
        final totalFactor = maxTotal > 0
            ? (total / maxTotal).clamp(0.08, 1.0)
            : 0.0;
        final barHeight = 204 * totalFactor;
        final downloadHeight = total > 0
            ? (barHeight * (sample.downloadBytes / total)).clamp(4.0, barHeight)
            : 0.0;
        final uploadHeight = total > 0
            ? (barHeight * (sample.uploadBytes / total)).clamp(
                sample.uploadBytes > 0 ? 4.0 : 0.0,
                barHeight,
              )
            : 0.0;
        final day = sample.day;
        final showLabel =
            day == 1 || day == samples.length || day % labelEvery == 0;

        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 210,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 7,
                    height: 210,
                    alignment: Alignment.bottomCenter,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.42,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: sample.hasData
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: uploadHeight,
                                color: MonthlyUsageScreen._orange,
                              ),
                              Container(
                                height: downloadHeight,
                                color: MonthlyUsageScreen._cyan,
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                showLabel ? day.toString() : '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                maxLines: 1,
              ),
            ],
          ),
        );
      }),
    );
  }
}
