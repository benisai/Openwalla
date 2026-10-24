import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/manage_device_screen.dart';
import 'package:openwalla/screens/router_system_settings_screen.dart';
import 'package:openwalla/services/router_system_settings_service.dart';
import 'package:openwalla/state/app_state.dart';

class _SystemState extends ChangeNotifier implements AppState {
  String? savedHostname;
  String? savedZone;

  @override
  Future<RouterSystemSettings> fetchRouterSystemSettings() async =>
      const RouterSystemSettings(
        section: 'cfg01',
        hostname: 'OpenWrt',
        zoneName: 'UTC',
      );

  @override
  Future<Map<String, String>> fetchRouterTimezones() async => {
    'UTC': 'UTC0',
    'America/Los Angeles': 'PST8PDT,M3.2.0,M11.1.0',
    'Europe/London': 'GMT0BST,M3.5.0/1,M10.5.0',
  };

  @override
  Future<void> changeRouterHostname(String hostname) async {
    savedHostname = hostname;
  }

  @override
  Future<void> changeRouterTimezone(String zoneName) async {
    savedZone = zoneName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _SystemState state,
    Widget page,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((_) => state)],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Manage Device has hostname and timezone rows', (tester) async {
    await show(tester, _SystemState(), const ManageDeviceScreen());
    expect(find.text('Change Hostname'), findsOneWidget);
    expect(find.text('Timezone'), findsOneWidget);
    await tester.tap(find.text('Change Hostname'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'OpenWrt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hostname loads and enables Save after an edit', (tester) async {
    final state = _SystemState();
    await show(tester, state, const RouterSystemSettingsScreen());
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'travel-router');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('timezone search selects a router-provided zone on mobile', (
    tester,
  ) async {
    await show(
      tester,
      _SystemState(),
      const RouterSystemSettingsScreen(timezone: true),
    );
    await tester.enterText(find.byType(TextField), 'los');
    await tester.pumpAndSettle();
    expect(find.text('Europe/London'), findsNothing);
    await tester.tap(find.text('America/Los Angeles'));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
