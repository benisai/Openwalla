import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/modules/parental_controls/models/parental_controls_store.dart';
import 'package:openwalla/modules/parental_controls/models/parental_profile.dart';

void main() {
  final store = ParentalControlsStore.instance;

  setUp(() {
    for (final profile in store.profiles.toList()) {
      store.deleteProfile(profile.id);
    }
    store.clearActivityLog();
  });

  test('profiles preserve YALA settings through persistence', () {
    store.addProfile(
      const ParentalProfile(
        id: 'kids',
        name: 'Kids',
        icon: '👧',
        color: '#F97316',
        macAddresses: ['AA:BB:CC:DD:EE:FF'],
        dailyTimeLimitMinutes: 120,
        schedule: TimeSchedule(
          activeDays: {ScheduleDay.monday, ScheduleDay.friday},
          blockHour: 21,
          blockMinute: 0,
          resumeHour: 7,
          resumeMinute: 0,
        ),
        contentFilter: ContentFilterDns.cloudflareFamilySafe,
      ),
    );

    final encoded = store.toJsonString();
    store.loadFromString(encoded);

    final profile = store.profiles.single;
    expect(profile.name, 'Kids');
    expect(profile.macAddresses, ['AA:BB:CC:DD:EE:FF']);
    expect(profile.dailyTimeLimitMinutes, 120);
    expect(profile.schedule?.activeDays, {
      ScheduleDay.monday,
      ScheduleDay.friday,
    });
    expect(profile.contentFilter, ContentFilterDns.cloudflareFamilySafe);
  });

  test('bypassing a profile disables its paused-device state', () {
    store.addProfile(
      const ParentalProfile(
        id: 'console',
        name: 'Console',
        icon: '🎮',
        color: '#3B82F6',
        macAddresses: ['11:22:33:44:55:66'],
        isPaused: true,
      ),
    );

    expect(store.isMacPaused('11:22:33:44:55:66'), isTrue);
    store.toggleProfileEnabled('console');
    expect(store.isMacPaused('11:22:33:44:55:66'), isFalse);
  });
}
