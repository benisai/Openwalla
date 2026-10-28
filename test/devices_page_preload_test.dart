import 'dart:async';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/screens/clients_screen.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/luci_loading_states.dart';

class _DeviceState extends ChangeNotifier implements AppState {
  final List<Client> preloaded;
  final pending = Completer<List<Client>>();
  _DeviceState(this.preloaded);
  @override
  bool get clientsAggregateAllRouters => false;
  @override
  Router get selectedRouter => Router(
    id: 'router-a',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );
  @override
  String? get dashboardError => null;
  @override
  List<Client>? devicesPageData({bool aggregate = false}) => preloaded;
  @override
  Future<List<Client>> loadDevicesPage({
    bool aggregate = false,
    bool force = false,
  }) => pending.future;
  @override
  bool isInternetPaused(String mac) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final empty in [false, true]) {
    testWidgets('preloaded devices (empty=$empty) render while refresh waits', (
      tester,
    ) async {
      final state = _DeviceState(
        empty
            ? []
            : [
                Client(
                  ipAddress: '192.168.1.2',
                  macAddress: 'AA:BB:CC:DD:EE:FF',
                  hostname: 'Preloaded Phone',
                ),
              ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: const MaterialApp(home: ClientsScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(LuciSkeleton), findsNothing);
      if (!empty) expect(find.text('Preloaded Phone'), findsOneWidget);
      expect(tester.takeException(), isNull);
      state.pending.complete(state.preloaded);
      await tester.pumpAndSettle();
    });
  }
}
