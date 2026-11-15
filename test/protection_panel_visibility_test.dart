import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/screens/geo_blocking_screen.dart';
import 'package:openwalla/screens/quarantine_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _ProtectionState extends ChangeNotifier implements AppState {
  bool enabled = false;
  bool fail = false;
  final changes = <bool>[];
  final devices = [
    Client(
      ipAddress: '192.168.1.20',
      macAddress: 'aa:bb:cc:dd:ee:ff',
      hostname: 'Test device',
      isQuarantined: true,
    ),
  ];

  @override
  Future<OpenwrtFeatureStatus> getOpenwrtFeatureStatus(
    OpenwrtFeature feature, {
    bool forceRefresh = false,
    BuildContext? context,
  }) async => OpenwrtFeatureStatus(
    feature: feature,
    label: feature.name,
    installed: true,
    checkedAt: DateTime.now(),
  );

  @override
  Future<String> fetchGeoBlockingStatus() async =>
      'Geo-blocking: ${enabled ? 'enabled' : 'disabled'}\nCountry codes: CN RU\n';

  void change(bool value) {
    changes.add(value);
    if (fail) throw StateError('Router rejected the update');
    enabled = value;
  }

  @override
  Future<String> setGeoBlockingEnabled(
    bool value, {
    void Function(String chunk)? onOutput,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    change(value);
    return '';
  }

  @override
  Future<OpenwallaQuarantineSnapshot> fetchQuarantineSnapshot({
    BuildContext? context,
  }) async => OpenwallaQuarantineSnapshot(
    enabled: enabled,
    running: enabled,
    intervalSeconds: 60,
    devices: devices,
  );

  @override
  Future<({bool enabled, bool running, int intervalSeconds})>
  saveQuarantineSettings({
    required bool enabled,
    required int intervalSeconds,
    BuildContext? context,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    change(enabled);
    return (
      enabled: enabled,
      running: enabled,
      intervalSeconds: intervalSeconds,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final geo in [true, false]) {
    final name = geo ? 'Geo Block' : 'Quarantine';
    final labels = geo
        ? ['Blocked Countries', 'Router Status']
        : ['Quarantined Devices', 'Test device'];

    Future<void> mount(WidgetTester tester, _ProtectionState state) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: MaterialApp(
            home: geo ? const GeoBlockingScreen() : const QuarantineScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> toggle(WidgetTester tester) async {
      final finder = geo ? find.byType(SwitchListTile) : find.byType(Switch);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('$name initially hides dependent sections while disabled', (
      tester,
    ) async {
      final state = _ProtectionState();
      await mount(tester, state);
      for (final label in labels) {
        expect(find.text(label), findsNothing);
      }
      expect(
        find.text(geo ? 'Protection disabled' : 'Automatic Quarantine'),
        findsOneWidget,
      );
      expect(state.changes, isEmpty);
    });

    testWidgets(
      '$name toggling restores dependent sections without deleting data',
      (tester) async {
        final state = _ProtectionState()..enabled = true;
        await mount(tester, state);
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        await toggle(tester);
        for (final label in labels) {
          expect(find.text(label), findsNothing);
        }
        await toggle(tester);
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        expect(state.changes, [false, true]);
        if (geo) {
          expect(find.text('2 selected'), findsOneWidget);
        } else {
          expect(state.devices.single.isQuarantined, isTrue);
          expect(find.text('Release'), findsOneWidget);
        }
      },
    );

    testWidgets('$name failed disable retains enabled sections', (
      tester,
    ) async {
      final state = _ProtectionState()
        ..enabled = true
        ..fail = true;
      await mount(tester, state);
      await toggle(tester);
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(state.enabled, isTrue);
    });
  }
}
