import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/widgets/dashboard_network_panel.dart';

Map<String, dynamic> sample() => {
  'interfaceDump': {
    'interface': [
      {'interface': 'loopback', 'up': true},
      {'interface': 'lan', 'up': true},
      {'interface': 'wan', 'up': true},
      {'interface': 'wwan', 'up': false},
      {'interface': 'vpn'},
      {'interface': 'lan', 'up': true},
    ],
  },
  'wireless': {
    'radio0': {
      'up': true,
      'interfaces': [
        {
          'section': 'ap0',
          'config': {'mode': 'ap', 'ssid': 'Openwalla'},
        },
        {
          'section': 'ap0',
          'config': {'mode': 'ap', 'ssid': 'Openwalla'},
        },
        {
          'section': 'uplink',
          'config': {'mode': 'sta'},
        },
        {
          'section': 'disabled',
          'config': {'mode': 'ap', 'disabled': '1'},
        },
      ],
    },
    'radio1': {
      'up': true,
      'interfaces': [
        {
          'section': 'ap1',
          'iwinfo': {'mode': 'Master', 'ssid': 'Openwalla'},
        },
      ],
    },
    'radio2': {
      'up': false,
      'interfaces': [
        {
          'section': 'ap2',
          'config': {'mode': 'ap'},
        },
      ],
    },
  },
};

void main() {
  final captureKey = GlobalKey();
  setUpAll(() async {
    final dir = Platform.environment['NETWORK_PANEL_FONT_DIR'];
    if (dir == null) return;
    for (final entry in {
      'NetworkTest': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final font = FontLoader(entry.key)
        ..addFont(
          File('$dir/${entry.value}').readAsBytes().then(ByteData.sublistView),
        );
      await font.load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> data, {
    double width = 390,
    double scale = 1,
    bool dark = true,
    VoidCallback? onNetwork,
    VoidCallback? onWifi,
  }) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = dark ? ThemeData.dark() : ThemeData.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(
            fontFamily: Platform.environment['NETWORK_PANEL_FONT_DIR'] == null
                ? null
                : 'NetworkTest',
          ),
        ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: RepaintBoundary(
              key: captureKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(color: const Color(0xFF313C52)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: DashboardNetworkPanel(
                        data: data,
                        onNetwork: onNetwork ?? () {},
                        onWifi: onWifi ?? () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'counts logical networks and active APs, not loopback or repeaters',
    (tester) async {
      await mount(tester, sample());
      expect(find.text('4 Networks'), findsOneWidget);
      expect(find.text('2 Wi-Fi'), findsOneWidget);
      expect(find.byTooltip('wwan: Down'), findsOneWidget);
      expect(find.byTooltip('vpn: Unknown'), findsOneWidget);
      expect(find.byTooltip('lan: Up'), findsOneWidget);
      expect(find.byTooltip('loopback: Up'), findsNothing);
    },
  );

  testWidgets('network and Wi-Fi actions navigate separately', (tester) async {
    var network = 0;
    var wifi = 0;
    await mount(
      tester,
      sample(),
      onNetwork: () => network++,
      onWifi: () => wifi++,
    );
    await tester.tap(find.byKey(const ValueKey('dashboard-network-open')));
    await tester.tap(find.byKey(const ValueKey('dashboard-network-Networks')));
    await tester.tap(find.byKey(const ValueKey('dashboard-network-Wi-Fi')));
    expect(network, 2);
    expect(wifi, 1);
  });

  testWidgets('unknown data differs from reported zero on wired-only routers', (
    tester,
  ) async {
    await mount(tester, {});
    expect(find.text('-- Networks'), findsOneWidget);
    expect(find.text('-- Wi-Fi'), findsOneWidget);
    await mount(tester, {
      'interfaceDump': {'interface': []},
      'wireless': {},
    });
    expect(find.text('0 Networks'), findsOneWidget);
    expect(find.text('0 Wi-Fi'), findsOneWidget);
  });

  testWidgets(
    'malformed optional data is safe and many interfaces are bounded',
    (tester) async {
      await mount(tester, {
        'interfaceDump': {
          'interface': [
            null,
            'bad',
            {},
            for (var i = 0; i < 20; i++)
              {'interface': 'very-long-network-$i', 'up': i.isEven},
          ],
        },
        'wireless': {
          'radio0': null,
          'radio1': {
            'interfaces': [null, 1, {}],
          },
        },
      });
      expect(find.text('20 Networks'), findsOneWidget);
      expect(find.text('+16'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 430.0, 1000.0]) {
    for (final dark in [true, false]) {
      testWidgets(
        'panel fits $width in ${dark ? 'dark' : 'light'} theme at large text',
        (tester) async {
          await mount(tester, sample(), width: width, scale: 1.5, dark: dark);
          expect(tester.takeException(), isNull);
          final panel = tester.getRect(
            find.byKey(const ValueKey('dashboard-network-panel')),
          );
          expect(panel.height, lessThan(110));
          final network = tester.getRect(
            find.byKey(const ValueKey('dashboard-network-open')),
          );
          final counts = tester.getRect(
            find.byKey(const ValueKey('dashboard-network-Networks')),
          );
          final wifi = tester.getRect(
            find.byKey(const ValueKey('dashboard-network-Wi-Fi')),
          );
          expect(network.right, lessThanOrEqualTo(counts.left));
          expect(counts.right, lessThan(wifi.left));
          expect(wifi.right, lessThanOrEqualTo(panel.right));
          final path = Platform.environment['NETWORK_PANEL_SCREENSHOT'];
          if (width == 320 && dark && path != null) {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(path).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
