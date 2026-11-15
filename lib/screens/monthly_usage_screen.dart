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
        date: day,
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
  final DateTime date;
  int get day => date.day;
  final int downloadBytes;
  final int uploadBytes;
  final bool hasData;

  const _MonthlyDailyUsage({
    required this.date,
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
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
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
}

class _DailyBars extends StatelessWidget {
  final List<_MonthlyDailyUsage> samples;
  final int maxTotal;

  const _DailyBars({required this.samples, required this.maxTotal});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(samples.length, (index) {
            final sample = samples[index];
            final total = sample.downloadBytes + sample.uploadBytes;
            final totalFactor = maxTotal > 0
                ? (total / maxTotal).clamp(0.08, 1.0)
                : 0.0;
            final barHeight = 204 * totalFactor;
            final downloadHeight = total > 0
                ? (barHeight * (sample.downloadBytes / total)).clamp(
                    4.0,
                    barHeight,
                  )
                : 0.0;
            final uploadHeight = total > 0
                ? (barHeight * (sample.uploadBytes / total)).clamp(
                    sample.uploadBytes > 0 ? 4.0 : 0.0,
                    barHeight,
                  )
                : 0.0;

            final dateLabel =
                '${MaterialLocalizations.of(context).formatShortMonthDay(sample.date)}, ${sample.date.year}';
            return Expanded(
              child: Tooltip(
                key: ValueKey('monthly-usage-bar-${sample.day}'),
                message: sample.hasData
                    ? '$dateLabel\nTotal ${_formatUsageTotal(total)}\nDown ${_formatUsageTotal(sample.downloadBytes)}  Up ${_formatUsageTotal(sample.uploadBytes)}'
                    : '$dateLabel\nNo usage data',
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 5),
                preferBelow: false,
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.28,
                  letterSpacing: 0,
                ),
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
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.42),
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
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        MonthlyUsageDayAxis(days: samples.length),
      ],
    );
  }
}

class MonthlyUsageDayAxis extends StatelessWidget {
  const MonthlyUsageDayAxis({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    if (days < 1) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final labels = <int>{
      1,
      7,
      14,
      21,
      days,
    }.where((day) => day <= days).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        double height = 0;
        final positions = <({int day, double left, double width})>[];
        for (final day in labels) {
          final painter = TextPainter(
            text: TextSpan(text: '$day', style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = (painter.width.ceilToDouble() + 2).clamp(
            0.0,
            constraints.maxWidth,
          );
          if (painter.height > height) height = painter.height.ceilToDouble();
          painter.dispose();
          final fraction = (day - 0.5) / days;
          final center =
              constraints.maxWidth *
              (direction == TextDirection.rtl ? 1 - fraction : fraction);
          positions.add((
            day: day,
            left: (center - width / 2).clamp(0.0, constraints.maxWidth - width),
            width: width,
          ));
        }
        positions.sort((a, b) => a.left.compareTo(b.left));
        final visible = [positions.first];
        final last = positions.last;
        if (positions.length > 1) {
          // Keep the endpoint labels, thinning intermediate ticks for large text.
          if (visible.first.left + visible.first.width + 2 > last.left) {
            visible.clear();
          } else {
            for (final position
                in positions.skip(1).take(positions.length - 2)) {
              if (position.left >= visible.last.left + visible.last.width + 2 &&
                  position.left + position.width + 2 <= last.left) {
                visible.add(position);
              }
            }
          }
          visible.add(last);
        }
        return SizedBox(
          key: const ValueKey('monthly-day-axis'),
          height: height,
          child: Stack(
            children: [
              for (final position in visible)
                Positioned(
                  left: position.left,
                  top: 0,
                  width: position.width,
                  child: Text(
                    '${position.day}',
                    key: ValueKey('monthly-day-label-${position.day}'),
                    style: style,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
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
