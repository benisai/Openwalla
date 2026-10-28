import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/router.dart' as model;
import 'package:openwalla/screens/notifications_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _NotificationsState extends ChangeNotifier implements AppState {
  @override
  model.Router? get selectedRouter => null;
  List<OpenwallaNotification>? preloaded;
  Completer<List<OpenwallaNotification>>? pendingLoad;
  int seenCalls = 0;
  @override
  List<OpenwallaNotification>? get notificationsPageData => preloaded;
  @override
  Future<List<OpenwallaNotification>> loadNotificationsPage({
    bool force = false,
  }) =>
      pendingLoad?.future ??
      (preloaded != null && !force
          ? Future.value(preloaded!)
          : fetchNotifications());
  int fetches = 0;
  final archived = <int>[];
  Completer<void>? pending;
  bool fail = false;
  int count = 20;
  @override
  Future<List<OpenwallaNotification>> fetchNotifications({
    int limit = 200,
    bool includeArchived = false,
    BuildContext? context,
  }) async {
    fetches++;
    return List.generate(
      count,
      (index) => OpenwallaNotification(
        id: index + 1,
        timestamp: DateTime(2026, 10, 26),
        app: 'test',
        message: 'Event $index',
        title: 'Event $index',
        details: 'Details $index',
        archived: false,
        deleted: false,
      ),
    );
  }

  @override
  Future<void> markNotificationsSeen({BuildContext? context}) async {
    seenCalls++;
  }

  @override
  Future<int> refreshNotificationCount({BuildContext? context}) async => count;
  @override
  Future<void> archiveNotification(int id, {BuildContext? context}) async {
    archived.add(id);
    if (pending != null) await pending!.future;
    if (fail) throw StateError('Router unreachable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _NotificationsState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _archive(int id) => find.descendant(
  of: find.byKey(ValueKey('notification-$id')),
  matching: find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'Archive',
  ),
);

void main() {
  testWidgets('late refresh cannot restore a locally archived event', (
    tester,
  ) async {
    final state = _NotificationsState();
    state.preloaded = await state.fetchNotifications();
    final pending = Completer<List<OpenwallaNotification>>();
    state.pendingLoad = pending;
    await _mount(tester, state);
    await tester.tap(_archive(1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-1')), findsNothing);
    pending.complete(state.preloaded!);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-1')), findsNothing);
  });
  testWidgets(
    'preloaded events appear immediately while a quiet refresh waits',
    (tester) async {
      final state = _NotificationsState();
      state.preloaded = await state.fetchNotifications();
      state.fetches = 0;
      final pending = Completer<List<OpenwallaNotification>>();
      state.pendingLoad = pending;
      await _mount(tester, state);
      expect(find.text('Event 0'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(state.seenCalls, 0);
      pending.complete(state.preloaded!);
      await tester.pumpAndSettle();
      expect(state.seenCalls, 1);
      expect(state.fetches, 0);
    },
  );

  testWidgets('removes one card without refetch or scroll reset', (
    tester,
  ) async {
    final state = _NotificationsState();
    await _mount(tester, state);
    final listScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(_archive(5), 200, scrollable: listScroll);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(listScroll);
    final before = scroll.position.pixels;
    final pending = Completer<void>();
    state.pending = pending;
    await tester.tap(_archive(5));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<IconButton>(_archive(5)).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-5')), findsNothing);
    expect(state.fetches, 1);
    expect(state.archived, [5]);
    expect(scroll.position.pixels, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed archive retains the card and enables retry', (
    tester,
  ) async {
    final state = _NotificationsState()..fail = true;
    await _mount(tester, state);
    await tester.tap(_archive(1));
    await tester.pump();
    expect(find.byKey(const ValueKey('notification-1')), findsOneWidget);
    expect(tester.widget<IconButton>(_archive(1)).onPressed, isNotNull);
    expect(state.fetches, 1);
    expect(find.text('Could not archive notification'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('archiving the last result shows the empty state', (
    tester,
  ) async {
    final state = _NotificationsState()..count = 1;
    await _mount(tester, state);
    await tester.tap(_archive(1));
    await tester.pumpAndSettle();
    expect(find.text('No active events'), findsOneWidget);
    expect(state.fetches, 1);
  });
}
