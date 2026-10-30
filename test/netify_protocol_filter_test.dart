import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final collector = File(
    'openwrt-setup/files/openwalla-netify-collector.sh',
  ).absolute.path;

  Future<bool> skipped(
    String? protocol, {
    String? include,
    String? exclude,
  }) async {
    final result = await Process.run(
      '/bin/sh',
      [
        '-c',
        r'''
. "$COLLECTOR"
[ -z "$TEST_INCLUDE" ] || INCLUDE_PROTOCOLS="$TEST_INCLUDE"
[ -z "$TEST_EXCLUDE" ] || EXCLUDE_PROTOCOLS="$TEST_EXCLUDE"
if should_skip_protocol "$PAYLOAD"; then echo skip; else echo keep; fi
''',
      ],
      environment: {
        'COLLECTOR': collector,
        'OPENWALLA_NETIFY_COLLECTOR_SOURCE_ONLY': '1',
        'PAYLOAD': jsonEncode({
          'type': 'flow',
          'flow': {
            if (protocol != null) 'detected_protocol_name': protocol,
            'other_port': 443,
          },
        }),
        'TEST_INCLUDE': include ?? '',
        'TEST_EXCLUDE': exclude ?? '',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout.toString().trim() == 'skip';
  }

  test(
    'default includes only HTTP and HTTP/S names, case insensitive',
    () async {
      for (final protocol in ['HTTP', 'HTTP/S', 'http', 'http/s', 'HTTPS']) {
        expect(await skipped(protocol), isFalse, reason: protocol);
      }
      for (final protocol in [
        'TLS',
        'QUIC',
        'DNS',
        'SSH',
        'HTTP2',
        'HTTPPROXY',
        'Unknown',
        '',
        null,
      ]) {
        expect(await skipped(protocol), isTrue, reason: '$protocol');
      }
    },
  );

  test(
    'custom include list is exact and exclusion still takes precedence',
    () async {
      expect(await skipped('HTTP', include: ' HTTP/S , SSH '), isTrue);
      expect(await skipped('SSH', include: ' HTTP/S , SSH '), isFalse);
      expect(await skipped('HTTP/S', exclude: 'HTTPS'), isTrue);
    },
  );

  test(
    'explicit wildcard restores broad collection with existing exclusions',
    () async {
      expect(await skipped('SSH', include: '*'), isFalse);
      expect(await skipped('DNS', include: '*'), isTrue);
    },
  );

  test(
    'UCI include list is loaded and missing setting uses the new default',
    () async {
      final result = await Process.run(
        '/bin/sh',
        [
          '-c',
          r'''
. "$COLLECTOR"
uci() {
 case "$3" in
  openwalla.collector.include_protocols) printf '%s' "$SETTING" ;;
  openwalla.flow_stats.retention_seconds) printf '2592000' ;;
  *) return 1 ;;
 esac
}
SETTING=SSH
load_config
[ "$INCLUDE_PROTOCOLS" = SSH ] || exit 2
SETTING=''
load_config
[ "$INCLUDE_PROTOCOLS" = 'HTTP,HTTP/S' ] || exit 3
''',
        ],
        environment: {
          'COLLECTOR': collector,
          'OPENWALLA_NETIFY_COLLECTOR_SOURCE_ONLY': '1',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
