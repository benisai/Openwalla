import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/adblock_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _AdblockState extends ChangeNotifier implements AppState {
  OpenwrtAdblockSettings settings = const OpenwrtAdblockSettings(
    section: 'global',
    installed: true,
    enabled: true,
    safeSearch: false,
    reportEnabled: true,
    triggerInterface: 'wwan',
    dnsBackend: 'unbound',
    selectedFeeds: ['adguard', 'custom_feed'],
    serviceStatus: 'enabled',
  );
  final saves = <OpenwrtAdblockSettings>[];
  Completer<void>? gate;
  bool fail = false;
  bool failLoad = false;
  bool installed = true;
  int loads = 0;

  @override
  Future<OpenwrtFeatureStatus> getOpenwrtFeatureStatus(
    OpenwrtFeature feature, {
    bool forceRefresh = false,
    BuildContext? context,
  }) async => OpenwrtFeatureStatus(
    feature: feature,
    label: 'AdBlock',
    installed: installed,
    checkedAt: DateTime.now(),
  );

  @override
  Future<OpenwrtAdblockSettings> fetchAdblockSettings({
    BuildContext? context,
  }) async {
    loads++;
    if (failLoad) throw StateError('Unavailable');
    return settings;
  }

  @override
  Future<void> saveAdblockSettings(OpenwrtAdblockSettings next) async {
    saves.add(next);
    if (gate != null) await gate!.future;
    if (fail) throw StateError('Router unavailable');
    settings = next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    _AdblockState state, {
    ThemeMode mode = ThemeMode.dark,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: const AdblockScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggle(String key) => find.byKey(ValueKey(key));

  testWidgets(
    'three sections in order with feeds initially collapsed and no service panel',
    (tester) async {
      await mount(tester, _AdblockState());
      expect(
        tester.getTopLeft(find.text('Block Ads')).dy,
        lessThan(tester.getTopLeft(find.text('Feeds')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Feeds')).dy,
        lessThan(tester.getTopLeft(find.text('Safe Search')).dy),
      );
      expect(find.text('AdGuard'), findsNothing);
      for (final label in [
        'Service Controls',
        'Settings',
        'Apply Settings',
        'Apply Service State',
        'Startup trigger interface',
        'DNS-Based AdBlock',
      ]) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.text('Feeds'));
      await tester.pumpAndSettle();
      expect(find.text('AdGuard'), findsOneWidget);
      await tester.tap(find.text('Feeds'));
      await tester.pumpAndSettle();
      expect(find.text('AdGuard'), findsNothing);
    },
  );

  testWidgets(
    'Block Ads immediately saves service state and preserves hidden settings',
    (tester) async {
      final state = _AdblockState();
      await mount(tester, state);
      await tester.tap(toggle('adblock-enabled'));
      await tester.pumpAndSettle();
      expect(state.saves.single.enabled, isFalse);
      expect(state.saves.single.safeSearch, isFalse);
      expect(state.saves.single.triggerInterface, 'wwan');
      expect(state.saves.single.dnsBackend, 'unbound');
      expect(state.saves.single.reportEnabled, isTrue);
      expect(state.saves.single.selectedFeeds, ['adguard', 'custom_feed']);
      expect(state.loads, 1);
      await tester.tap(toggle('adblock-enabled'));
      await tester.pumpAndSettle();
      expect(state.saves.last.enabled, isTrue);
    },
  );

  testWidgets(
    'Safe Search saves immediately without enabling disabled AdBlock',
    (tester) async {
      final state = _AdblockState();
      state.settings = state.settings.copyWith(enabled: false);
      await mount(tester, state);
      await tester.tap(toggle('adblock-safesearch'));
      await tester.pumpAndSettle();
      expect(state.saves.single.safeSearch, isTrue);
      expect(state.saves.single.enabled, isFalse);
    },
  );

  testWidgets(
    'pending save locks both switches and feeds; failure restores values',
    (tester) async {
      final state = _AdblockState()
        ..gate = Completer<void>()
        ..fail = true;
      await mount(tester, state);
      await tester.tap(toggle('adblock-enabled'));
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(toggle('adblock-enabled')).onChanged,
        isNull,
      );
      expect(
        tester.widget<SwitchListTile>(toggle('adblock-safesearch')).onChanged,
        isNull,
      );
      await tester.tap(find.text('Feeds'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<CheckboxListTile>(toggle('feed-adguard')).onChanged,
        isNull,
      );
      state.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<SwitchListTile>(toggle('adblock-enabled')).value,
        isTrue,
      );
      expect(state.saves.length, 1);
      expect(find.text('Could not save AdBlock settings'), findsOneWidget);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('feed changes debounce and keep expansion open after saving', (
    tester,
  ) async {
    final state = _AdblockState();
    await mount(tester, state);
    await tester.tap(find.text('Feeds'));
    await tester.pumpAndSettle();
    await tester.tap(toggle('feed-adguard'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(toggle('feed-adguard_tracking'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.saves, isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(state.saves.single.selectedFeeds, [
      'custom_feed',
      'adguard_tracking',
    ]);
    expect(find.text('AdGuard'), findsOneWidget);
    expect(state.loads, 1);
  });

  testWidgets('switch includes pending feed edits rather than dropping them', (
    tester,
  ) async {
    final state = _AdblockState();
    await mount(tester, state);
    await tester.tap(find.text('Feeds'));
    await tester.pumpAndSettle();
    await tester.tap(toggle('feed-adguard'));
    await tester.pump();
    await tester.tap(toggle('adblock-enabled'));
    await tester.pumpAndSettle();
    expect(state.saves.single.enabled, isFalse);
    expect(state.saves.single.selectedFeeds, ['custom_feed']);
    await tester.pump(const Duration(seconds: 1));
    expect(state.saves.length, 1);
  });

  testWidgets('failed feed save restores the last saved selection', (
    tester,
  ) async {
    final state = _AdblockState()..fail = true;
    await mount(tester, state);
    await tester.tap(find.text('Feeds'));
    await tester.pumpAndSettle();
    await tester.tap(toggle('feed-adguard'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(toggle('feed-adguard')).value,
      isTrue,
    );
    expect(find.textContaining('Save failed'), findsOneWidget);
  });

  testWidgets('loading errors have a retry', (tester) async {
    final state = _AdblockState()..failLoad = true;
    await mount(tester, state);
    expect(find.text('Unable to load AdBlock settings.'), findsOneWidget);
    state.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Block Ads'), findsOneWidget);
  });

  for (final mode in ThemeMode.values.where(
    (mode) => mode != ThemeMode.system,
  )) {
    testWidgets('compact and expanded layout fits narrow screen in $mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester, _AdblockState(), mode: mode);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Feeds'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
