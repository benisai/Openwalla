import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/screens/interfaces_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _WifiState extends ChangeNotifier implements AppState {
  int refreshes = 0;
  final data = <String, dynamic>{
    'wireless': <String, dynamic>{},
    'uciWirelessConfig': {
      'values': {
        for (var i = 0; i < 2; i++) ...{
          'radio$i': {
            '.type': 'wifi-device',
            'band': i == 0 ? '2g' : '5g',
            'channel': 'auto',
          },
          'default_radio$i': {
            '.type': 'wifi-iface',
            'device': 'radio$i',
            'mode': 'ap',
            'ssid': 'GL-X2000',
            'encryption': 'none',
          },
        },
      },
    },
  };
  @override
  Map<String, dynamic> get dashboardData => data;
  @override
  bool get isDashboardLoading => false;
  @override
  String? get dashboardError => null;
  @override
  DashboardPreferences get dashboardPreferences => DashboardPreferences();
  @override
  Future<void> fetchDashboardData({bool allowAuthRetry = true}) async {
    refreshes++;
  }

  void loadRuntime() {
    data['wireless'] = {
      for (var i = 0; i < 2; i++)
        'radio$i': {
          'up': true,
          'interfaces': [
            {
              'section': 'default_radio$i',
              'ifname': 'phy$i-ap0',
              'config': {'mode': 'ap', 'device': 'radio$i', 'ssid': 'GL-X2000'},
              'iwinfo': {
                'ssid': 'GL-X2000',
                'mode': 'Master',
                'channel': i == 0 ? 1 : 36,
              },
            },
          ],
        },
    };
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  testWidgets(
    'Wi-Fi list does not inherit an unrelated scroll offset on entry',
    (tester) async {
      final inherited = ScrollController(initialScrollOffset: -180);
      final state = _WifiState();
      addTearDown(inherited.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: PrimaryScrollController(
              controller: inherited,
              child: const InterfacesScreen(wirelessOnly: true),
            ),
          ),
        ),
      );
      final card = find
          .ancestor(
            of: find.text('GL-X2000').first,
            matching: find.byType(Card),
          )
          .first;
      final gap =
          tester.getTopLeft(card).dy -
          tester.getBottomLeft(find.text('Repeater')).dy;
      expect(gap, lessThan(45));
      await tester.pumpAndSettle();
      expect(inherited.hasClients, isFalse);
      final wifiList = find.byKey(const PageStorageKey('wifi-access-points'));
      final refresh = find
          .ancestor(of: wifiList, matching: find.byType(RefreshIndicator))
          .first;
      final refreshing = tester.state<RefreshIndicatorState>(refresh).show();
      await tester.pumpAndSettle();
      await refreshing;
      expect(state.refreshes, 1);
      await tester.tap(find.text('Repeater'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('wifi-repeaters')),
        findsOneWidget,
      );
      expect(inherited.hasClients, isFalse);
      await tester.tap(find.text('Wi-Fi').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(0, 0.01),
      );
      expect(
        tester.getTopLeft(card).dy -
            tester.getBottomLeft(find.text('Repeater')).dy,
        lessThan(45),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Wi-Fi cards stay immediately below tabs before runtime data settles',
    (tester) async {
      tester.view.physicalSize = const Size(390, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _WifiState();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: const MaterialApp(home: InterfacesScreen(wirelessOnly: true)),
        ),
      );
      double gap() {
        final card = find
            .ancestor(
              of: find.text('GL-X2000').first,
              matching: find.byType(Card),
            )
            .first;
        return tester.getTopLeft(card).dy -
            tester.getBottomLeft(find.text('Repeater')).dy;
      }

      expect(gap(), lessThan(45));
      for (final duration in [
        const Duration(milliseconds: 16),
        const Duration(milliseconds: 100),
        const Duration(seconds: 1),
      ]) {
        await tester.pump(duration);
        expect(gap(), lessThan(45));
      }
      state.loadRuntime();
      await tester.pump();
      expect(gap(), lessThan(45));
      await tester.pumpAndSettle();
      expect(gap(), lessThan(45));
      expect(tester.takeException(), isNull);
    },
  );
}
