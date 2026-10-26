import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';

void main() {
  late Directory directory;
  late RouterSnapshotCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openwalla-snapshot-');
    cache = RouterSnapshotCache(directory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('keeps separate routers even with identical IP addresses', () async {
    await cache.save('uuid-a', 'fp-a', 'dashboard', {
      'ip': '192.168.1.1',
      'name': 'A',
    });
    await cache.save('uuid-b', 'fp-b', 'dashboard', {
      'ip': '192.168.1.1',
      'name': 'B',
    });
    expect(
      (await cache.load(
        'uuid-a',
        'fp-a',
      ))!['sections']['dashboard']['data']['name'],
      'A',
    );
    expect(
      (await cache.load(
        'uuid-b',
        'fp-b',
      ))!['sections']['dashboard']['data']['name'],
      'B',
    );
    expect(await cache.load('uuid-a', 'fp-b'), isNull);
  });

  test(
    'serializes simultaneous section writes without losing either',
    () async {
      final first = cache.save('a', null, 'dashboard', {'cpu': 12});
      final second = cache.save('a', null, 'devices', []);
      await first;
      await second;
      final sections = (await cache.load('a', null))!['sections'] as Map;
      expect(sections.keys, containsAll(['dashboard', 'devices']));
      expect(DateTime.tryParse(sections['devices']['savedAt']), isNotNull);
    },
  );

  test('replaces a section rather than appending history', () async {
    await cache.save('a', null, 'dashboard', {'cpu': 12});
    await cache.save('a', null, 'dashboard', {'cpu': 25});
    final sections = (await cache.load('a', null))!['sections'] as Map;
    expect(sections.length, 1);
    expect(sections['dashboard']['data']['cpu'], 25);
  });

  test(
    'removes nested Wi-Fi and session credentials, retaining display data',
    () async {
      await cache.save('a', null, 'dashboard', {
        'wireless': {
          'radio0': {
            'ssid': 'Home',
            'encryption': 'psk2',
            'key': 'wifi-secret',
            'key1': 'wep-secret',
            'interfaces': [
              {
                'password': 'hidden',
                'private_key': 'private',
                'sysauth': 'session',
                'channel': 6,
              },
            ],
          },
        },
      });
      final data = jsonEncode(await cache.load('a', null));
      for (final secret in [
        'wifi-secret',
        'wep-secret',
        'hidden',
        'private',
        'session',
      ]) {
        expect(data, isNot(contains(secret)));
      }
      expect(data, contains('Home'));
      expect(data, contains('psk2'));
    },
  );

  test('survives a new cache service instance', () async {
    await cache.save('a', null, 'devices', [1]);
    final reopened = RouterSnapshotCache(directory: () async => directory);
    expect((await reopened.load('a', null))!['sections']['devices']['data'], [
      1,
    ]);
  });

  test('oversized write leaves previous valid snapshot intact', () async {
    await cache.save('a', null, 'dashboard', {'cpu': 12});
    await expectLater(
      cache.save('a', null, 'dashboard', 'x' * RouterSnapshotCache.maxBytes),
      throwsStateError,
    );
    expect(
      (await cache.load('a', null))!['sections']['dashboard']['data']['cpu'],
      12,
    );
    await cache.save('a', null, 'devices', []);
    expect((await cache.load('a', null))!['sections']['devices']['data'], []);
  });

  test(
    'ignores malformed JSON, invalid sections and unsupported versions',
    () async {
      await cache.save('a', null, 'dashboard', {});
      final file = (await Directory(
        '${directory.path}/router_snapshots',
      ).list().toList()).whereType<File>().single;
      for (final content in [
        'broken',
        '{"version":2}',
        '{"version":1,"routerId":"a","sections":{"dashboard":"bad"}}',
      ]) {
        await file.writeAsString(content);
        expect(await cache.load('a', null), isNull);
      }
    },
  );

  test(
    'delete removes persisted and temporary files without touching other routers',
    () async {
      await cache.save('a', null, 'dashboard', {});
      await cache.save('b', null, 'dashboard', {});
      await cache.delete('a');
      expect(await cache.load('a', null), isNull);
      expect(await cache.load('b', null), isNotNull);
    },
  );

  test(
    'round-trips device identity, usage, blocked status and connection metadata',
    () {
      final client = Client(
        ipAddress: '192.168.1.4',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Phone',
        connectionType: ConnectionType.wireless,
        ssid: 'Home',
        isBlocked: true,
        isQuarantined: true,
        totalDownloadBytes: 1234,
        totalUploadBytes: 2345,
        ipv6Addresses: ['fd00::4'],
        status: 'offline',
      );
      final restored = RouterSnapshotCache.decodeClient(
        jsonDecode(jsonEncode(RouterSnapshotCache.encodeClient(client))),
      );
      expect(
        RouterSnapshotCache.encodeClient(restored),
        RouterSnapshotCache.encodeClient(client),
      );
    },
  );
}
