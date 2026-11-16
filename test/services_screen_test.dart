import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/services_screen.dart';
import 'package:openwalla/state/app_state.dart';

OpenwallaServiceStatus service(
  String name, {
  bool installed = true,
  bool running = false,
}) => OpenwallaServiceStatus(
  name: name,
  label: name,
  category: 'Monitoring',
  installed: installed,
  enabled: running,
  running: running,
  statusText: installed ? 'stopped' : 'not installed',
);

class _State extends ChangeNotifier implements AppState {
  List<OpenwallaServiceStatus> services = [];
  bool fail = false;

  @override
  Future<List<OpenwallaServiceStatus>> fetchOpenwallaServices({
    BuildContext? context,
  }) async {
    if (fail) throw StateError('Router unreachable');
    return services;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> mount(WidgetTester tester, _State state) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ServicesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'only installed services appear, including stopped and disabled ones',
    (tester) async {
      final state = _State()
        ..services = [
          service('Missing collector', installed: false),
          service('Running collector', running: true),
          service('Stopped collector'),
        ];
      await mount(tester, state);
      expect(find.text('Missing collector'), findsNothing);
      expect(find.text('Missing'), findsNothing);
      expect(find.text('Running collector'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Stopped collector'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
      final stoppedCard = find
          .ancestor(
            of: find.text('Stopped collector'),
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.widget<InkWell>(stoppedCard).onTap, isNotNull);
    },
  );

  for (final missing in [false, true]) {
    testWidgets('empty visible list shows the empty state (missing=$missing)', (
      tester,
    ) async {
      await mount(
        tester,
        _State()
          ..services = missing
              ? [service('Unavailable helper', installed: false)]
              : [],
      );
      expect(find.text('No services found'), findsOneWidget);
      expect(find.text('Unavailable helper'), findsNothing);
      expect(find.text('Missing'), findsNothing);
    });
  }

  testWidgets(
    'refresh discovers newly installed services and removes uninstalled ones',
    (tester) async {
      final state = _State()
        ..services = [
          service('Old helper'),
          service('New helper', installed: false),
        ];
      await mount(tester, state);
      state.services = [
        service('Old helper', installed: false),
        service('New helper'),
      ];
      await tester.tap(find.byTooltip('Refresh services'));
      await tester.pumpAndSettle();
      expect(find.text('Old helper'), findsNothing);
      expect(find.text('New helper'), findsOneWidget);
    },
  );

  testWidgets('connection errors remain errors, not an empty installed list', (
    tester,
  ) async {
    await mount(tester, _State()..fail = true);
    expect(find.text('Unable to load services'), findsOneWidget);
    expect(find.text('No services found'), findsNothing);
  });
}
