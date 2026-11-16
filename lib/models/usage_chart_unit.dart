import 'dart:math' as math;

enum UsageChartUnit {
  kb('KB', 1024),
  mb('MB', 1024 * 1024),
  gb('GB', 1024 * 1024 * 1024),
  tb('TB', 1024 * 1024 * 1024 * 1024);

  const UsageChartUnit(this.label, this.bytes);

  final String label;
  final int bytes;

  static UsageChartUnit parse(Object? value) => values.firstWhere(
    (unit) => unit.name == value?.toString().toLowerCase(),
    orElse: () => gb,
  );

  String format(num byteCount) {
    if (byteCount <= 0) return '0';
    final value = byteCount / bytes;
    // Keep small nonzero buckets visible even when a larger unit is selected.
    final decimals = (2 - (math.log(value) / math.ln10).floor()).clamp(0, 12);
    final result = value.toStringAsFixed(decimals);
    return result.contains('.')
        ? result
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : result;
  }
}
