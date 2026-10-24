import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  String quote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String> sqlite(File db, String sql) async {
    final result = await Process.run('/usr/bin/sqlite3', [db.path, sql]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return result.stdout.toString().trim();
  }

  for (final enriched in [true, false]) {
    test('Delete All matches Recent Events, enriched schema: $enriched', () async {
      final dir = await Directory.systemTemp.createTemp(
        'openwalla-notifications-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final db = File('${dir.path}/notifications.sqlite');
      await sqlite(db, '''CREATE TABLE notifications (
        id INTEGER PRIMARY KEY, timestamp INTEGER, app TEXT, msg TEXT,
        archived INTEGER, "delete" INTEGER
        ${enriched ? ', category TEXT' : ''});''');

      final sources = <(String, String, String)>[
        ('ping-monitor', 'Ping outage', ''),
        ('NETWORK-MONITOR', 'Latency alert', ''),
        ('interface-monitor', 'Link lost', ''),
        ('system', 'Ethernet port connected', ''),
        ('dns-monitor', 'DNS failed', 'dns'),
        ('speedtest', 'Speedtest done', 'speedtest'),
        ('custom', 'Network issue', ' NETWORK_HEALTH '),
        ('custom', 'Interface issue', 'interface'),
        ('device-quarantine', 'New device quarantined', 'device'),
        ('system', 'Package installed', ''),
        ('wireguard-monitor', 'Peer connected', 'vpn'),
        ('ping-monitor', 'Explicit system event', 'system'),
        ('custom', 'Custom notification', 'other'),
        ('custom', 'DNS issue', 'DNS'),
        ('custom', 'Whitespace category', '\tDNS\n'),
      ];
      final events = <OpenwallaNotification>[];
      var id = 0;
      for (final archived in [false, true]) {
        for (final source in sources) {
          final event = OpenwallaNotification(
            id: ++id,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              1000000,
              isUtc: true,
            ),
            app: source.$1,
            message: source.$2,
            category: enriched ? source.$3 : '',
            archived: archived,
            deleted: false,
          );
          events.add(event);
          await sqlite(
            db,
            'INSERT INTO notifications VALUES ('
            '${event.id},1000,${quote(event.app)},${quote(event.message)},'
            '${archived ? 1 : 0},0${enriched ? ',${quote(event.category)}' : ''});',
          );
        }
      }
      // An already-deleted network event must not be restored.
      await sqlite(
        db,
        'INSERT INTO notifications VALUES ('
        '999,1000,\'ping-monitor\',\'Old outage\',0,1${enriched ? ",''" : ''});',
      );
      final sql = OpenwallaNotification.deleteNonNetworkNotificationsSql(
        hasCategory: enriched,
      );
      expect(await sqlite(db, sql), 'OPENWALLA_NOTIFICATIONS_DELETED');
      final rows = (await sqlite(
        db,
        'SELECT id, archived, "delete" FROM notifications ORDER BY id;',
      )).split('\n').map((row) => row.split('|')).toList();
      for (final event in events) {
        final row = rows.firstWhere((row) => row.first == '${event.id}');
        expect(row[1], event.archived ? '1' : '0');
        expect(
          row[2],
          event.isNetworkPerformanceEvent ? '0' : '1',
          reason: '${event.app}: ${event.category}',
        );
      }
      expect(rows.last, ['999', '0', '1']);
      // Repeated bulk deletion preserves exactly the same rows.
      await sqlite(db, sql);
      final kept = await sqlite(
        db,
        'SELECT count(*) FROM notifications WHERE "delete"=0;',
      );
      expect(
        int.parse(kept),
        events.where((e) => e.isNetworkPerformanceEvent).length,
      );
    });
  }

  test('bulk deletion has no display-page limit', () async {
    final dir = await Directory.systemTemp.createTemp(
      'openwalla-notifications-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final db = File('${dir.path}/notifications.sqlite');
    await sqlite(db, '''CREATE TABLE notifications (
      id INTEGER PRIMARY KEY, app TEXT, msg TEXT, "delete" INTEGER, category TEXT);
      WITH RECURSIVE ids(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM ids WHERE n<600)
      INSERT INTO notifications SELECT n,'system','event',0,'system' FROM ids;
      INSERT INTO notifications VALUES (601,'custom','DNS event',0,'dns');''');
    await sqlite(
      db,
      OpenwallaNotification.deleteNonNetworkNotificationsSql(hasCategory: true),
    );
    expect(
      await sqlite(db, 'SELECT id FROM notifications WHERE "delete"=0;'),
      '601',
    );
  });
}
