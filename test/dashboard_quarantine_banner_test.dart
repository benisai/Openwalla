import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/widgets/dashboard_quarantine_banner.dart';
import 'package:openwalla/models/quarantine_notice_state.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Set<String> macs, {
    String router = 'router-a',
    bool known = true,
    VoidCallback? onView,
    double scale = 1,
    QuarantineNoticeState? noticeState,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Column(
            children: [
              DashboardQuarantineBanner(
                routerKey: router,
                quarantinedMacs: macs,
                statusKnown: known,
                onView: onView ?? () {},
                noticeState: noticeState,
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('only shows quarantined devices and opens the requested view', (
    tester,
  ) async {
    await mount(tester, {});
    expect(find.text('New Device Quarantine'), findsNothing);
    var opened = false;
    await mount(tester, {'a'}, onView: () => opened = true);
    expect(
      find.text('1 device has been quarantined on your network.'),
      findsOneWidget,
    );
    await tester.tap(find.text('View Quarantined Devices'));
    expect(opened, isTrue);
  });

  testWidgets(
    'dismiss hides current devices but newly quarantined MACs reappear',
    (tester) async {
      await mount(tester, {'a', 'b'});
      expect(
        find.text('2 devices have been quarantined on your network.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(find.text('New Device Quarantine'), findsNothing);
      await mount(tester, {'a', 'b'});
      expect(find.text('New Device Quarantine'), findsNothing);
      await mount(tester, {'a', 'b', 'c'});
      expect(
        find.text('1 device has been quarantined on your network.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('dismissals stay isolated by router and survive unknown status', (
    tester,
  ) async {
    await mount(tester, {'a'});
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await mount(tester, {}, known: false);
    await mount(tester, {'a'});
    expect(find.text('New Device Quarantine'), findsNothing);
    await mount(tester, {'a'}, router: 'router-b');
    expect(find.text('New Device Quarantine'), findsOneWidget);
    await mount(tester, {'a'});
    expect(find.text('New Device Quarantine'), findsNothing);
  });

  testWidgets(
    'clearing the rule removes the banner and re-quarantine notifies again',
    (tester) async {
      await mount(tester, {'a'});
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      await mount(tester, {});
      await mount(tester, {'a'});
      expect(find.text('New Device Quarantine'), findsOneWidget);
      await mount(tester, {});
      expect(find.text('New Device Quarantine'), findsNothing);
    },
  );

  testWidgets('dismissal survives dashboard remount during the app session', (
    tester,
  ) async {
    final notices = QuarantineNoticeState();
    await mount(tester, {'a'}, noticeState: notices);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await mount(tester, {'a'}, noticeState: notices);
    expect(find.text('New Device Quarantine'), findsNothing);
    notices.clear();
    await mount(tester, {'a'}, noticeState: notices);
    expect(find.text('New Device Quarantine'), findsOneWidget);
  });

  for (final width in [320.0, 430.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('banner fits width $width at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, {'a', 'b'}, scale: scale);
        await tester.pumpAndSettle();
        expect(find.text('View Quarantined Devices'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
