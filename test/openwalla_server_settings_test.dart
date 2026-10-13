import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/openwalla_server_settings.dart';
import 'package:openwalla/services/tunnel_monitor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Tunnel writes are visible to flows and flow writes to Tunnel',
    () async {
      final tunnel = TunnelMonitorService();
      final flows = OpenwallaServerSettingsStore();
      await tunnel.save(
        'router-a',
        const TunnelMonitorSettings(
          serverUrl: 'http://server:2020/',
          apiToken: 'first-token',
        ),
      );
      final shared = await flows.load(
        'router-a',
        legacyServerUrl: 'http://old:2020',
      );
      expect(shared.serverUrl, 'http://server:2020');
      expect(shared.apiToken, 'first-token');
      await flows.save(
        'router-a',
        const OpenwallaServerSettings(
          serverUrl: 'https://new-server',
          apiToken: 'second-token',
        ),
      );
      final updated = await tunnel.load('router-a');
      expect(updated.serverUrl, 'https://new-server');
      expect(updated.apiToken, 'second-token');
      expect((await tunnel.load('router-b')).serverUrl, isEmpty);
    },
  );

  test('migrates existing flow URL and secure token together', () async {
    FlutterSecureStorage.setMockInitialValues({
      'netify_server_token:router-a': 'old-token',
    });
    final store = OpenwallaServerSettingsStore();
    final migrated = await store.load(
      'router-a',
      legacyServerUrl: 'http://existing-server:2020/',
    );
    expect(migrated.apiToken, 'old-token');
    expect(migrated.serverUrl, 'http://existing-server:2020');
    expect(
      (await TunnelMonitorService().load('router-a')).serverUrl,
      migrated.serverUrl,
    );
  });

  test('migrates saved Tunnel settings ahead of legacy flow settings', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tunnelMonitor:router-a':
          '{"serverUrl":"http://tunnel-server:2020","apiToken":"tunnel-token"}',
      'netify_server_token:router-a': 'old-token',
    });
    final store = OpenwallaServerSettingsStore();
    final migrated = await store.load(
      'router-a',
      legacyServerUrl: 'http://old:2020',
    );
    expect(migrated.serverUrl, 'http://tunnel-server:2020');
    expect(migrated.apiToken, 'tunnel-token');
    await store.save(
      'router-a',
      const OpenwallaServerSettings(serverUrl: 'http://new:2020'),
    );
    final updated = await store.load(
      'router-a',
      legacyServerUrl: 'http://old:2020',
    );
    expect(updated.serverUrl, 'http://new:2020');
    expect(updated.apiToken, isEmpty);
  });

  test('empty first load does not prevent later legacy migration', () async {
    final store = OpenwallaServerSettingsStore();
    expect((await store.load('router-a')).serverUrl, isEmpty);
    final migrated = await store.load(
      'router-a',
      legacyServerUrl: 'http://server:2020',
    );
    expect(migrated.serverUrl, 'http://server:2020');
  });

  test('connection writes do not change collector configuration', () async {
    FlutterSecureStorage.setMockInitialValues({
      'collectorMode:router-a': 'local',
    });
    await TunnelMonitorService().save(
      'router-a',
      const TunnelMonitorSettings(
        serverUrl: 'http://server:2020',
        apiToken: 'token',
      ),
    );
    final values = await const FlutterSecureStorage().readAll();
    expect(values['collectorMode:router-a'], 'local');
    expect(values.keys.toSet(), {
      'collectorMode:router-a',
      'openwalla_server:router-a',
    });
  });

  test('flow endpoint uses the same base path validation as Tunnel', () {
    const settings = OpenwallaServerSettings(
      serverUrl: 'https://server/openwalla/',
    );
    expect(
      settings.endpoint('/api/v1/flows').toString(),
      'https://server/openwalla/api/v1/flows',
    );
    expect(
      settings.statusUri.toString(),
      'https://server/openwalla/api/v1/tunnel/status',
    );
  });
}
