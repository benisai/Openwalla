import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/page_preload_cache.dart';

void main() {
  test('warmup and page entry share one in-progress request', () async {
    final cache = PagePreloadCache<List<int>>();
    final pending = Completer<List<int>>();
    var calls = 0;
    Future<List<int>> fetch() {
      calls++;
      return pending.future;
    }

    final warmup = cache.load('router-a', fetch);
    final page = cache.load('router-a', fetch);
    expect(identical(warmup, page), isTrue);
    expect(calls, 1);
    pending.complete([1]);
    expect(await page, [1]);
    expect(cache.peek('router-a'), [1]);
    expect(await cache.load('router-a', fetch), [1]);
    expect(calls, 1);
  });

  test(
    'stale data stays available while refreshing; force bypasses freshness',
    () async {
      var now = DateTime(2026, 10, 28);
      final cache = PagePreloadCache<List<int>>(now: () => now);
      await cache.load('a', () async => [1]);
      now = now.add(const Duration(seconds: 16));
      final pending = Completer<List<int>>();
      final refresh = cache.load('a', () => pending.future);
      expect(cache.peek('a'), [1]);
      pending.complete([2]);
      await refresh;
      expect(await cache.load('a', () async => [3], force: true), [3]);
    },
  );

  test('router, offline and aggregate scopes do not share data', () async {
    final cache = PagePreloadCache<List<int>>();
    await cache.load('uuid-a:live:selected', () async => [1]);
    for (final key in [
      'uuid-b:live:selected',
      'uuid-a:offline:selected',
      'uuid-a:live:aggregate',
    ]) {
      expect(cache.peek(key), isNull);
    }
  });

  test(
    'invalidation prevents a late request from repopulating cache',
    () async {
      final cache = PagePreloadCache<List<int>>();
      final old = Completer<List<int>>();
      final pending = cache.load('a', () => old.future);
      cache.clear();
      await cache.load('a', () async => [2]);
      old.complete([1]);
      await pending;
      expect(cache.peek('a'), [2]);
    },
  );

  test('failed refresh keeps previous data and allows retry', () async {
    final cache = PagePreloadCache<List<int>>();
    await cache.load('a', () async => [1]);
    await expectLater(
      cache.load('a', () async => throw StateError('offline'), force: true),
      throwsStateError,
    );
    expect(cache.peek('a'), [1]);
    expect(await cache.load('a', () async => [2], force: true), [2]);
  });
}
