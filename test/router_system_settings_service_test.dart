import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/router_system_settings_service.dart';

void main() {
  test('hostname cache update preserves dashboard runtime map type', () {
    final original = <dynamic, dynamic>{
      'hostname': 'OpenWrt',
      'model': 'Test router',
      'release': <String, dynamic>{'version': '25.12'},
    };
    final dynamic updated = boardInfoWithHostname(original, ' travel-router ');
    final board = updated as Map<String, dynamic>;
    expect(board['hostname'], 'travel-router');
    expect(board['model'], 'Test router');
    expect(board['release'], original['release']);
    expect(original['hostname'], 'OpenWrt');
  });

  Map<String, dynamic> values = {};
  List<String> methods = [];
  List<Map<String, dynamic>> writes = [];
  String? rejected;

  RouterSystemSettingsService service() => RouterSystemSettingsService(
    call: (object, method, params) async {
      methods.add('$object.$method');
      if (method == rejected) return [6];
      if (object == 'luci') {
        expect(method, 'getTimezones');
        return [
          0,
          {
            'America/Los Angeles': {'tzstring': 'PST8PDT,M3.2.0,M11.1.0'},
            'Europe/London': {'tzstring': 'GMT0BST,M3.5.0/1,M10.5.0'},
            'invalid': {},
          },
        ];
      }
      if (method == 'get') {
        expect(params, {'config': 'system'});
        return [
          0,
          {
            'values': {
              'cfg01': {...values},
              'ntp': {'.type': 'timeserver'},
            },
          },
        ];
      }
      if (method == 'set') {
        expect(params['config'], 'system');
        expect(params['section'], 'cfg01');
        final written = Map<String, dynamic>.from(params['values'] as Map);
        writes.add(written);
        values.addAll(written);
        return [0];
      }
      expect(method, 'apply');
      expect(params, {'rollback': false});
      return [0];
    },
  );

  setUp(() {
    values = {
      '.type': 'system',
      'hostname': 'OpenWrt',
      'zonename': 'UTC',
      'timezone': 'UTC0',
    };
    methods = [];
    writes = [];
    rejected = null;
  });

  test('loads actual system section and current values', () async {
    final settings = await service().load();
    expect(settings.section, 'cfg01');
    expect(settings.hostname, 'OpenWrt');
    expect(settings.zoneName, 'UTC');
  });

  test('hostname writes only hostname then applies and verifies', () async {
    await service().saveHostname(' my-router ');
    expect(writes, [
      {'hostname': 'my-router'},
    ]);
    expect(methods, ['uci.get', 'uci.set', 'uci.apply', 'uci.get']);
    expect(values['timezone'], 'UTC0');
  });

  test(
    'timezone writes LuCI zone name and exact router POSIX string',
    () async {
      await service().saveTimezone('America/Los Angeles');
      expect(writes, [
        {
          'zonename': 'America/Los Angeles',
          'timezone': 'PST8PDT,M3.2.0,M11.1.0',
        },
      ]);
      expect(values['hostname'], 'OpenWrt');
    },
  );

  test('UTC has explicit UTC0 and unsupported zones cannot be saved', () async {
    await service().saveTimezone('UTC');
    expect(writes.single['timezone'], 'UTC0');
    writes.clear();
    await expectLater(
      service().saveTimezone('Unknown/Zone'),
      throwsArgumentError,
    );
    expect(writes, isEmpty);
  });

  test('filters malformed timezone entries', () async {
    expect(
      (await service().timezones()).keys,
      unorderedEquals(['UTC', 'America/Los Angeles', 'Europe/London']),
    );
  });

  for (final invalid in [
    '',
    'two words',
    '-router',
    'router-',
    'a..b',
    'a;reboot',
  ]) {
    test('rejects invalid hostname: $invalid', () async {
      await expectLater(service().saveHostname(invalid), throwsArgumentError);
      expect(methods, isEmpty);
    });
  }

  test('checks hostname label and total lengths', () {
    expect(RouterSystemSettingsService.validHostname('router.lan'), isTrue);
    expect(RouterSystemSettingsService.validHostname('a' * 64), isFalse);
    expect(
      RouterSystemSettingsService.validHostname(
        List.filled(5, 'a' * 60).join('.'),
      ),
      isFalse,
    );
  });

  for (final method in ['get', 'set', 'apply']) {
    test('router rejection at $method is not successful', () async {
      rejected = method;
      await expectLater(service().saveHostname('new-router'), throwsStateError);
      expect(methods.last, 'uci.$method');
    });
  }

  test('missing system section fails without writing', () async {
    values = {'.type': 'timeserver'};
    await expectLater(service().saveHostname('new-router'), throwsStateError);
    expect(writes, isEmpty);
  });

  test('readback mismatch is not reported as success', () async {
    final unchanged = RouterSystemSettingsService(
      call: (_, method, _) async {
        if (method == 'get') {
          return [
            0,
            {
              'values': {'cfg01': values},
            },
          ];
        }
        return [0];
      },
    );
    await expectLater(unchanged.saveHostname('new-router'), throwsStateError);
  });
}
