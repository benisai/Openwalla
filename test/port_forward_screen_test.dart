import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/models/router.dart' as model;
import 'package:openwalla/screens/port_forward_screen.dart';
import 'package:openwalla/state/app_state.dart';

const existingForward = OpenwrtPortForward(
  section: 'rule1',
  name: 'Home server',
  source: 'wan',
  wanPort: '4859',
  protocol: 'tcp',
  destinationZone: 'lan',
  destinationIp: '192.168.1.20',
  destinationPort: '443',
  enabled: true,
);

class _ForwardState extends ChangeNotifier implements AppState {
  Map<String, dynamic>? saved;
  bool deleted = false;
  bool fail = false;
  Completer<void>? gate;
  int writes = 0;
  bool failDiscovery = false;
  bool? closedResult;
  List<Client> devices = [];

  @override
  model.Router? get selectedRouter => null;
  @override
  Future<List<Client>> loadDevicesPage({
    bool aggregate = false,
    bool force = false,
  }) async {
    if (failDiscovery) throw StateError('Offline');
    return devices;
  }

  @override
  Future<void> setPortForwardEnabled(
    OpenwrtPortForward forward,
    bool enabled,
  ) => record({'section': forward.section, 'enabled': enabled});
  Future<void> record(Map<String, dynamic> values) async {
    writes++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('Router rejected the change');
    saved = values;
  }

  @override
  Future<void> addPortForward({
    required String name,
    required String sourceZone,
    required String externalPort,
    required String protocol,
    required String destinationZone,
    required String destinationIp,
    required String internalPort,
    bool enabled = true,
  }) => record({
    'name': name,
    'external': externalPort,
    'internal': internalPort,
    'protocol': protocol,
    'source': sourceZone,
    'zone': destinationZone,
    'ip': destinationIp,
    'enabled': enabled,
    'new': true,
  });
  @override
  Future<void> updatePortForward(
    OpenwrtPortForward forward, {
    required String name,
    required String sourceZone,
    required String externalPort,
    required String protocol,
    required String destinationZone,
    required String destinationIp,
    required String internalPort,
    bool? enabled,
  }) => record({
    'name': name,
    'external': externalPort,
    'internal': internalPort,
    'protocol': protocol,
    'source': sourceZone,
    'zone': destinationZone,
    'ip': destinationIp,
    'enabled': enabled,
    'section': forward.section,
  });
  @override
  Future<void> deletePortForward(OpenwrtPortForward forward) async {
    if (fail) throw StateError('Delete failed');
    deleted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    _ForwardState state, {
    OpenwrtPortForward? forward,
    ThemeMode mode = ThemeMode.dark,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    state.closedResult = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => PortForwardScreen(
                          forward: forward,
                          routerIp: '192.168.1.1',
                        ),
                      ),
                    ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    double delta = 200,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find
          .descendant(
            of: find.byType(PortForwardScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creates a range forward on a full page with equal internal ports by default',
    (tester) async {
      final state = _ForwardState();
      await mount(tester, state);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('internal-port')), findsNothing);
      expect(find.text('Delete port forward'), findsNothing);
      await enter(tester, 'port-name', 'Game server');
      await enter(tester, 'external-port', '8000 - 8010');
      await enter(tester, 'destination-ip', '192.168.1.20');
      await save(tester);
      expect(state.saved?['external'], '8000-8010');
      expect(state.saved?['internal'], '8000-8010');
      expect(state.saved?['enabled'], isTrue);
      expect(find.byType(PortForwardScreen), findsNothing);
    },
  );

  testWidgets('toggle saves immediately without saving other pending edits', (
    tester,
  ) async {
    final state = _ForwardState();
    await mount(tester, state, forward: existingForward);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('internal-port')))
          .controller
          ?.text,
      '443',
    );
    await enter(tester, 'internal-port', '8443');
    await tester.ensureVisible(find.text('UDP').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UDP').last);
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, 'Port forward');
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.saved, {'section': 'rule1', 'enabled': false});
    expect(find.byType(PortForwardScreen), findsOneWidget);
    await save(tester);
    expect(state.saved?['internal'], '8443');
    expect(state.saved?['external'], '4859');
    expect(state.saved?['protocol'], 'udp');
    expect(state.saved?['enabled'], isFalse);
    expect(state.saved?['section'], 'rule1');
  });

  testWidgets(
    'destination picker fills router or device and remains editable',
    (tester) async {
      final state = _ForwardState()
        ..devices = [
          Client(
            ipAddress: '192.168.1.163',
            macAddress: 'aa',
            hostname: 'Pixel-9a',
          ),
          Client(
            ipAddress: '192.168.1.163',
            macAddress: 'aa',
            hostname: 'Pixel-9a',
          ),
          Client(ipAddress: '', macAddress: 'bb', hostname: 'No address'),
        ];
      await mount(tester, state, forward: existingForward);
      expect(find.text('Advanced'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Choose device'));
      await tester.tap(find.byTooltip('Choose device'));
      await tester.pumpAndSettle();
      expect(find.text('Pixel-9a'), findsOneWidget);
      expect(find.text('No address'), findsNothing);
      await tester.tap(find.text('Pixel-9a'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('destination-ip')))
            .controller!
            .text,
        '192.168.1.163',
      );
      await tester.tap(find.byTooltip('Choose device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Router'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('destination-ip')))
            .controller!
            .text,
        '192.168.1.1',
      );
      await enter(tester, 'destination-ip', '192.168.1.99');
      await save(tester);
      expect(state.saved?['ip'], '192.168.1.99');
    },
  );

  testWidgets(
    'device discovery failure leaves manual destination entry working',
    (tester) async {
      final state = _ForwardState()..failDiscovery = true;
      await mount(tester, state, forward: existingForward);
      await enter(tester, 'destination-ip', '192.168.1.99');
      await save(tester);
      expect(state.saved?['ip'], '192.168.1.99');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed immediate toggle keeps its old state and edits', (
    tester,
  ) async {
    final state = _ForwardState()..fail = true;
    await mount(tester, state, forward: existingForward);
    await enter(tester, 'port-name', 'Pending name');
    final toggle = find.widgetWithText(SwitchListTile, 'Port forward');
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(state.saved, isNull);
    expect(find.byType(PortForwardScreen), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('port-name')), delta: -200);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('port-name')))
          .controller!
          .text,
      'Pending name',
    );
  });

  testWidgets('new rule switch validates before auto-saving creation', (
    tester,
  ) async {
    final state = _ForwardState();
    await mount(tester, state);
    final toggle = find.widgetWithText(SwitchListTile, 'Port forward');
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.writes, 0);
    await reveal(tester, find.byKey(const ValueKey('port-name')), delta: -200);
    await enter(tester, 'port-name', 'New disabled');
    await enter(tester, 'external-port', '443');
    await enter(tester, 'destination-ip', '192.168.1.20');
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.saved?['enabled'], isFalse);
    expect(state.saved?['new'], isTrue);
  });

  testWidgets(
    'pending toggle locks controls and closing returns refresh result',
    (tester) async {
      final state = _ForwardState()..gate = Completer<void>();
      await mount(tester, state, forward: existingForward);
      final toggle = find.widgetWithText(SwitchListTile, 'Port forward');
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(state.writes, 1);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      state.gate!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PortForwardScreen), findsNothing);
      expect(find.text('Discard Changes?'), findsNothing);
      expect(state.closedResult, isTrue);
    },
  );

  testWidgets('invalid ports and addresses cannot be saved', (tester) async {
    final state = _ForwardState();
    await mount(tester, state);
    await enter(tester, 'port-name', 'Bad rule');
    await enter(tester, 'destination-ip', 'not-an-ip');
    for (final value in ['0', '65536', '9000-8000', 'abc']) {
      await enter(tester, 'external-port', value);
      await save(tester);
      expect(state.saved, isNull);
      expect(find.byType(PortForwardScreen), findsOneWidget);
    }
    expect(state.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delete requires confirmation and successful deletion closes the page',
    (tester) async {
      final state = _ForwardState();
      await mount(tester, state, forward: existingForward);
      await tester.scrollUntilVisible(
        find.text('Delete port forward'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(PortForwardScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Delete port forward'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.deleted, isFalse);
      await tester.tap(find.text('Delete port forward'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(state.deleted, isTrue);
      expect(find.byType(PortForwardScreen), findsNothing);
    },
  );

  testWidgets('failed save preserves edits and keeps the editor open', (
    tester,
  ) async {
    final state = _ForwardState()..fail = true;
    await mount(tester, state, forward: existingForward);
    await enter(tester, 'port-name', 'Changed name');
    await save(tester);
    expect(find.byType(PortForwardScreen), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('port-name')))
          .controller
          ?.text,
      'Changed name',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('back asks before discarding unsaved changes', (tester) async {
    await mount(tester, _ForwardState(), forward: existingForward);
    await enter(tester, 'port-name', 'Changed name');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard Changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(PortForwardScreen), findsNothing);
  });

  for (final width in [320.0, 430.0, 1200.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'full page fits $width width in $mode with large text and keyboard',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(tester.view.resetViewInsets);
          await mount(
            tester,
            _ForwardState(),
            forward: existingForward,
            mode: mode,
          );
          await enter(tester, 'port-name', 'Home server');
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Delete port forward'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(PortForwardScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'custom zones, combined protocol and disabled state survive edits',
    (tester) async {
      final state = _ForwardState();
      await mount(
        tester,
        state,
        forward: const OpenwrtPortForward(
          section: 'custom',
          name: 'Custom',
          source: 'vpn',
          wanPort: '8000-8010',
          protocol: 'udp, tcp',
          destinationZone: 'guest',
          destinationIp: '192.168.10.20',
          destinationPort: '9000-9010',
          enabled: false,
        ),
      );
      await enter(tester, 'port-name', 'Updated custom');
      await save(tester);
      expect(state.saved?['source'], 'vpn');
      expect(state.saved?['zone'], 'guest');
      expect(state.saved?['protocol'], 'tcp udp');
      expect(state.saved?['enabled'], isFalse);
      expect(state.saved?['internal'], '9000-9010');
    },
  );

  testWidgets('router destination keeps the local address and LAN zone', (
    tester,
  ) async {
    final state = _ForwardState();
    await mount(
      tester,
      state,
      forward: const OpenwrtPortForward(
        section: 'router',
        name: 'Router',
        source: 'wan',
        wanPort: '8443',
        protocol: 'tcp',
        destinationZone: 'lan',
        destinationIp: '192.168.1.1',
        destinationPort: '443',
        enabled: true,
      ),
    );
    await enter(tester, 'port-name', 'Updated router');
    await save(tester);
    expect(state.saved?['ip'], '192.168.1.1');
    expect(state.saved?['zone'], 'lan');
  });

  testWidgets('pending save locks controls and does not submit twice', (
    tester,
  ) async {
    final state = _ForwardState()..gate = Completer<void>();
    await mount(tester, state, forward: existingForward);
    await enter(tester, 'port-name', 'Pending rule');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(state.writes, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    state.gate!.complete();
    await tester.pumpAndSettle();
    expect(state.writes, 1);
    expect(find.byType(PortForwardScreen), findsNothing);
  });
}
