import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/screens/tunnel_settings_screen.dart';
import 'package:openwalla/services/tunnel_monitor_service.dart';

Map<String, dynamic> statusResponse({bool available = true}) => {
  'connected': available,
  'host': 'tunnel-gateway',
  'luci': {'available': available, 'port': 18080},
  'ssh': {'available': false, 'port': 10022},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('server URL supports LAN, HTTPS, and reverse proxy base paths', () {
    for (final entry in {
      'http://10.10.10.2:2020/': 'http://10.10.10.2:2020/api/v1/tunnel/status',
      'https://example.com/openwalla///':
          'https://example.com/openwalla/api/v1/tunnel/status',
      'http://[::1]:2020': 'http://[::1]:2020/api/v1/tunnel/status',
    }.entries) {
      expect(
        TunnelMonitorSettings(serverUrl: entry.key).statusUri.toString(),
        entry.value,
      );
    }
  });

  test('rejects invalid URLs and embedded credentials', () {
    for (final url in [
      '',
      'server:2020',
      'ftp://example.com',
      'https://',
      'http://user:password@example.com',
      'http://example.com?token=secret',
      'http://example.com#fragment',
    ]) {
      expect(
        () => TunnelMonitorSettings(serverUrl: url).statusUri,
        throwsFormatException,
      );
    }
  });

  test('settings persist securely and independently for each router', () async {
    final service = TunnelMonitorService();
    await service.save(
      'router-a',
      const TunnelMonitorSettings(
        serverUrl: 'http://server:2020',
        apiToken: 'secret',
      ),
    );
    expect((await service.load('router-a')).apiToken, 'secret');
    expect((await service.load('router-b')).serverUrl, isEmpty);
    expect(
      (await TunnelMonitorService().load('router-a')).serverUrl,
      'http://server:2020',
    );
  });

  test('parses individual endpoint states and rejects malformed data', () {
    final status = TunnelMonitorStatus.fromJson(statusResponse());
    expect(status.host, 'tunnel-gateway');
    expect(status.luciAvailable, isTrue);
    expect(status.sshAvailable, isFalse);
    expect(status.sshPort, 10022);
    for (final response in [
      null,
      '<html>Login</html>',
      {},
      {
        'host': 'gateway',
        'luci': {'available': 'yes', 'port': 80},
        'ssh': {'available': true, 'port': 22},
      },
    ]) {
      expect(
        () => TunnelMonitorStatus.fromJson(response),
        throwsFormatException,
      );
    }
  });

  test('sends API token and disables redirects', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(
            request.uri.toString(),
            'http://server:2020/api/v1/tunnel/status',
          );
          expect(request.headers['Authorization'], 'Bearer secret');
          expect(request.followRedirects, isFalse);
          handler.resolve(
            Response(requestOptions: request, data: statusResponse()),
          );
        },
      ),
    );
    final status = await TunnelMonitorService(client: dio).fetch(
      const TunnelMonitorSettings(
        serverUrl: 'http://server:2020',
        apiToken: 'secret',
      ),
    );
    expect(status.luciAvailable, isTrue);
  });

  testWidgets('saved server loads and refresh distinguishes API from tunnel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests++;
          handler.resolve(
            Response(
              requestOptions: request,
              data: statusResponse(available: false),
            ),
          );
        },
      ),
    );
    final service = TunnelMonitorService(client: dio);
    await service.save(
      'router-a',
      const TunnelMonitorSettings(serverUrl: 'http://server:2020'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TunnelSettingsScreen(routerId: 'router-a', service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reachable'), findsOneWidget);
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('tunnel-gateway:10022'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh tunnel status'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save validates, persists, and connects with the entered token', (
    tester,
  ) async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests++;
          expect(request.headers['Authorization'], 'Bearer test-token');
          handler.resolve(
            Response(requestOptions: request, data: statusResponse()),
          );
        },
      ),
    );
    final service = TunnelMonitorService(client: dio);
    await tester.pumpWidget(
      MaterialApp(
        home: TunnelSettingsScreen(routerId: 'router-a', service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & Connect'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(
      find.text('Enter a valid HTTP or HTTPS server URL.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://server:2020',
    );
    await tester.enterText(find.byType(TextFormField).last, 'test-token');
    await tester.tap(find.text('Save & Connect'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect((await service.load('router-a')).apiToken, 'test-token');
    expect(find.text('Reachable'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('authentication failure does not claim endpoints are offline', (
    tester,
  ) async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.reject(
            DioException(
              requestOptions: request,
              response: Response(requestOptions: request, statusCode: 401),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );
    final service = TunnelMonitorService(client: dio);
    await service.save(
      'router-a',
      const TunnelMonitorSettings(serverUrl: 'http://server:2020'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TunnelSettingsScreen(routerId: 'router-a', service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Access denied. Check the server API token.'),
      findsWidgets,
    );
    expect(find.text('Not checked'), findsNWidgets(2));
    expect(find.text('Reachable'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('first Tunnel visit prefills an existing flow connection', (
    tester,
  ) async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.uri.host, 'existing-server');
          expect(request.headers['Authorization'], 'Bearer existing-token');
          handler.resolve(
            Response(requestOptions: request, data: statusResponse()),
          );
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TunnelSettingsScreen(
          routerId: 'router-a',
          service: TunnelMonitorService(client: dio),
          loadInitialSettings: () async => const TunnelMonitorSettings(
            serverUrl: 'http://existing-server:2020',
            apiToken: 'existing-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields.first.controller!.text, 'http://existing-server:2020');
    expect(fields.last.controller!.text, 'existing-token');
    expect(find.text('Reachable'), findsNWidgets(2));
  });
}
