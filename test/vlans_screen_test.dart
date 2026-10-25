import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/manage_device_screen.dart';
import 'package:openwalla/screens/vlans_screen.dart';
import 'package:openwalla/services/vlan_discovery_service.dart';
import 'package:openwalla/state/app_state.dart';

class _VlanState extends ChangeNotifier implements AppState {
  bool fail;
  int reads = 0;
  final VlanTopology topology;
  _VlanState(this.topology, {this.fail = false});

  @override
  Future<VlanTopology> fetchVlanTopology() async {
    reads++;
    if (fail) throw StateError('Router unavailable');
    return topology;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  VlanTopology fixture() => VlanDiscoveryService.parse(
    {
      'br': {
        '.type': 'device',
        'type': 'bridge',
        'name': 'br-lan',
        'ports': ['lan1', 'lan2'],
        'vlan_filtering': '1',
      },
      'vlan': {
        '.type': 'bridge-vlan',
        'device': 'br-lan',
        'vlan': '20',
        'ports': ['lan1:u*', 'lan2:t'],
      },
      'iot': {'.type': 'interface', 'device': 'br-lan.20'},
    },
    {
      'lan1': {'devtype': 'dsa', 'link': true},
      'lan2': {'devtype': 'dsa', 'link': false},
      'wan': {'devtype': 'dsa', 'link': true},
    },
    {},
  );

  Future<void> show(
    WidgetTester tester,
    _VlanState state, {
    bool manage = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((_) => state)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: manage ? const ManageDeviceScreen() : const VlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Manage Device VLANs row opens discovery', (tester) async {
    final state = _VlanState(fixture());
    await show(tester, state, manage: true);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VLANs'));
    await tester.pumpAndSettle();
    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('DSA switch ports detected'), findsOneWidget);
    expect(state.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VLAN details and ports fit a phone viewport', (tester) async {
    await show(tester, _VlanState(fixture()));
    await tester.tap(find.text('VLAN 20'));
    await tester.pumpAndSettle();
    expect(find.text('Untagged · PVID'), findsOneWidget);
    expect(find.text('Tagged'), findsOneWidget);
    expect(find.text('iot'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Ports & Bridges'));
    await tester.pumpAndSettle();
    expect(find.text('br-lan'), findsOneWidget);
    expect(find.text('wan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'errors offer retry and do not masquerade as an empty VLAN list',
    (tester) async {
      final state = _VlanState(fixture(), fail: true);
      await show(tester, state);
      expect(find.text('Router unavailable'), findsOneWidget);
      expect(find.text('No configured VLANs'), findsNothing);
      state.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('VLAN 20'), findsOneWidget);
      expect(state.reads, 2);
    },
  );

  testWidgets('empty inventory and unavailable board metadata are explicit', (
    tester,
  ) async {
    await show(
      tester,
      _VlanState(
        const VlanTopology(
          vlans: [],
          bridges: [],
          ports: [],
          warnings: ['Board port mapping unavailable'],
        ),
      ),
    );
    expect(find.text('No configured VLANs'), findsOneWidget);
    expect(find.text('Board port mapping unavailable'), findsOneWidget);
    await tester.tap(find.text('Ports & Bridges'));
    await tester.pumpAndSettle();
    expect(find.text('No port mapping reported'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh reloads topology without configuration writes', (
    tester,
  ) async {
    final state = _VlanState(fixture());
    await show(tester, state);
    await tester.tap(find.byTooltip('Refresh VLANs'));
    await tester.pumpAndSettle();
    expect(state.reads, 2);
  });
}
