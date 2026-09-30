import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/cron_job.dart';

void main() {
  test('cron document preserves unrelated lines when editing', () {
    const source = '# OPENWALLA MANAGED\n0 4 * * * /usr/bin/backup\n\n';
    final document = CronDocument.parse(source);

    final result = document.replace(
      document.jobs.single,
      document.jobs.single.copyWith(expression: '30 2 * * *'),
    );

    expect(result, '# OPENWALLA MANAGED\n30 2 * * * /usr/bin/backup\n\n');
  });

  test('disabled jobs parse while ordinary comments remain hidden', () {
    const source = '# explanatory note\n# 0 3 * * 0 /sbin/wifi reload\n';
    final document = CronDocument.parse(source);

    expect(document.jobs, hasLength(1));
    expect(document.jobs.single.isEnabled, isFalse);
    expect(
      CronSchedule.describe(document.jobs.single.expression),
      'Every Sunday at 3:00 AM',
    );
  });

  test('cron validation rejects invalid time fields', () {
    expect(CronSchedule.validate('0 25 * * *'), isNotNull);
    expect(CronSchedule.validate('*/15 * * * *'), isNull);
  });
}
