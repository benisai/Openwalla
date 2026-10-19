import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const mac = '5a:c1:1a:0b:bb:36';
const secondMac = '7a:ff:de:3c:15:96';

String quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

class EngineHarness {
  late Directory root;
  late File config;
  late String engine;

  Future<void> init() async {
    root = await Directory.systemTemp.createTemp('openwalla-access-test-');
    await Directory('${root.path}/bin').create();
    await Directory('${root.path}/config').create();
    config = await File('${root.path}/config/firewall').writeAsString('');
    engine = File(
      'openwrt-setup/files/openwalla-device-access.sh',
    ).absolute.path;
    await executable('uci', r'''
dir="$OPENWALLA_ACCESS_CONFIG_DIR"
while [ "$#" -gt 0 ]; do
  case "$1" in -c) dir="$2"; shift 2 ;; -t|-P) shift 2 ;; -q) shift ;; *) break ;; esac
done
file="$dir/firewall"; cmd="$1"; arg="${2:-}"
key="${arg%%=*}"; value="${arg#*=}"
case "$cmd" in
show) cat "$file" ;;
get) awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1); found=1} END {exit !found}' "$file" ;;
set|add_list)
  [ "${FAKE_SET_FAIL:-0}" != 1 ] || exit 1
  if [ "$cmd" = add_list ]; then old="$(awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1)}' "$file")"; value="${old:+$old }$value"; fi
  awk -F= -v key="$key" '$1!=key' "$file" >"$file.new"
  printf '%s=%s\n' "$key" "$value" >>"$file.new"
  mv "$file.new" "$file"
  ;;
delete)
  awk -F= -v key="$key" '$1!=key && index($1,key".")!=1' "$file" >"$file.new"
  mv "$file.new" "$file"
  ;;
add)
  counter="$(cat "$FAKE_ROOT/counter" 2>/dev/null || echo 0)"; counter=$((counter+1)); echo "$counter" >"$FAKE_ROOT/counter"
  echo "firewall.cfg$counter=rule" >>"$file"; echo "cfg$counter"
  ;;
commit) ;;
*) exit 1 ;;
esac
''');
    await executable('firewall', r'''
[ "${FAKE_RELOAD_FAIL:-0}" != 1 ] || exit 1
awk -F= '
  $1 ~ /\.name$/ {s=$1; sub(/\.name$/,"",s); names[s]=$2}
  $1 ~ /\.src_mac$/ {s=$1; sub(/\.src_mac$/,"",s); macs[s]=$2}
  $1 ~ /\.enabled$/ {s=$1; sub(/\.enabled$/,"",s); enabled[s]=$2}
  END {for(s in names) if(enabled[s]!="0") {
    n=split(macs[s],m," "); for(i=1;i<=n;i++) print "ether saddr "m[i]" drop comment \""names[s]"\""
  }}' "$OPENWALLA_ACCESS_CONFIG_DIR/firewall" >"$FAKE_ROOT/runtime"
''');
    await executable('nft', r'''
[ "${FAKE_NFT_FAIL:-0}" != 1 ] || exit 1
if [ "${FAKE_RUNTIME_STALE:-0}" = 1 ]; then cat "$FAKE_ROOT/stale"; else cat "$FAKE_ROOT/runtime"; fi
''');
  }

  Future<void> executable(String name, String contents) async {
    final file = await File(
      '${root.path}/bin/$name',
    ).writeAsString('#!/bin/sh\n$contents');
    await Process.run('chmod', ['755', file.path]);
  }

  Future<ProcessResult> run(
    String action,
    String reason, {
    String address = mac,
    String operation = '',
    Map<String, String> extra = const {},
  }) => Process.run(
    'sh',
    [
      '-c',
      '. ${quote(engine)}; openwalla_device_access "\$1" "\$2" "\$3" "\$4"',
      'engine-test',
      action,
      reason,
      address,
      operation,
    ],
    environment: {
      'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
      'FAKE_ROOT': root.path,
      'OPENWALLA_ACCESS_RUNTIME_DIR': '${root.path}/run',
      'OPENWALLA_ACCESS_CONFIG_DIR': '${root.path}/config',
      'OPENWALLA_ACCESS_FIREWALL_INIT': '${root.path}/bin/firewall',
      ...extra,
    },
  );
}

void main() {
  late EngineHarness harness;
  setUp(() async {
    harness = EngineHarness();
    await harness.init();
  });
  tearDown(() async {
    await harness.root.delete(recursive: true);
  });

  test(
    'manual and automatic blocking use MAC names and both IP families',
    () async {
      final result = await harness.run('block', 'quarantine');
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final config = await harness.config.readAsString();
      expect(config, contains('openwalla_quarantine_5ac11a0bbb36_forward'));
      expect(config, contains('family=any'));
      expect(config, isNot(contains('_router')));
      expect(
        result.stdout,
        contains('OPENWALLA_DEVICE_ACCESS_OK|block|quarantine|$mac'),
      );
    },
  );

  test('releasing quarantine preserves an independent manual block', () async {
    expect((await harness.run('block', 'manual')).exitCode, 0);
    expect((await harness.run('block', 'quarantine')).exitCode, 0);
    final result = await harness.run('release', 'quarantine');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final config = await harness.config.readAsString();
    expect(config, contains('owrt_device_block_5ac11a0bbb36_forward'));
    expect(config, contains('owrt_device_block_5ac11a0bbb36_router'));
    expect(config, isNot(contains('openwalla_quarantine_')));
  });

  test(
    'current release resolves reason from rules instead of stale UI flags',
    () async {
      expect((await harness.run('block', 'manual')).exitCode, 0);
      expect((await harness.run('block', 'quarantine')).exitCode, 0);
      expect((await harness.run('release', 'current')).exitCode, 0);
      expect(
        await harness.config.readAsString(),
        contains('owrt_device_block_'),
      );
      expect((await harness.run('release', 'current')).exitCode, 0);
      expect((await harness.config.readAsString()).trim(), isEmpty);
    },
  );

  test('repeated block requests do not accumulate duplicate rules', () async {
    await harness.run('block', 'manual');
    final result = await harness.run('block', 'manual');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final config = await harness.config.readAsString();
    expect(RegExp(r'\.name=').allMatches(config).length, 2);
  });

  test('same-hostname devices receive independent MAC-based rules', () async {
    expect((await harness.run('block', 'quarantine')).exitCode, 0);
    expect(
      (await harness.run('block', 'quarantine', address: secondMac)).exitCode,
      0,
    );
    final config = await harness.config.readAsString();
    expect(config, contains('openwalla_quarantine_5ac11a0bbb36_forward'));
    expect(config, contains('openwalla_quarantine_7affde3c1596_forward'));
  });

  test(
    'reload failures restore the original firewall and never report success',
    () async {
      const original =
          'firewall.admin=rule\nfirewall.admin.name=Administrator\n';
      await harness.config.writeAsString(original);
      final result = await harness.run(
        'block',
        'manual',
        extra: {'FAKE_RELOAD_FAIL': '1'},
      );
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout.toString(),
        isNot(contains('OPENWALLA_DEVICE_ACCESS_OK')),
      );
      expect(await harness.config.readAsString(), original);
    },
  );

  test('failed staging leaves the real configuration untouched', () async {
    final result = await harness.run(
      'block',
      'manual',
      extra: {'FAKE_SET_FAIL': '1'},
    );
    expect(result.exitCode, isNot(0));
    expect(await harness.config.readAsString(), isEmpty);
  });

  test('runtime verification failure rolls back a release', () async {
    await harness.run('block', 'manual');
    final original = await harness.config.readAsString();
    await File(
      '${harness.root.path}/stale',
    ).writeAsString(await File('${harness.root.path}/runtime').readAsString());
    final result = await harness.run(
      'release',
      'manual',
      extra: {'FAKE_RUNTIME_STALE': '1'},
    );
    expect(result.exitCode, isNot(0));
    expect(await harness.config.readAsString(), original);
  });

  test('legacy multi-device rule releases only the requested MAC', () async {
    await harness.config.writeAsString('''firewall.legacy=rule
firewall.legacy.name=openwalla_quarantine_samehost_lan
firewall.legacy.src_mac=$mac $secondMac
firewall.legacy.enabled=1
firewall.admin=rule
firewall.admin.name=Administrator
firewall.admin.src_mac=$mac
firewall.admin.enabled=1
''');
    final result = await harness.run('release', 'quarantine');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final config = await harness.config.readAsString();
    expect(config, contains('firewall.legacy.src_mac=$secondMac'));
    expect(config, contains('firewall.admin.src_mac=$mac'));
  });

  test(
    'concurrent requests are serialized without losing either block',
    () async {
      final results = await Future.wait([
        harness.run('block', 'quarantine'),
        harness.run('block', 'manual', address: secondMac),
      ]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }
      final config = await harness.config.readAsString();
      expect(config, contains('openwalla_quarantine_5ac11a0bbb36_forward'));
      expect(config, contains('owrt_device_block_7affde3c1596_forward'));
    },
  );

  test('malformed and multicast MAC addresses cannot create rules', () async {
    for (final invalid in [
      'garbage',
      '01:00:5e:00:00:01',
      '00:00:00:00:00:00',
    ]) {
      expect(
        (await harness.run('block', 'manual', address: invalid)).exitCode,
        isNot(0),
      );
    }
    expect(await harness.config.readAsString(), isEmpty);
  });

  test(
    'retrying a timed-out release cannot remove an independent manual block',
    () async {
      await harness.run('block', 'manual');
      await harness.run('block', 'quarantine');
      expect(
        (await harness.run(
          'release',
          'current',
          operation: 'same-request',
        )).exitCode,
        0,
      );
      expect(
        (await harness.run(
          'release',
          'current',
          operation: 'same-request',
        )).exitCode,
        0,
      );
      final config = await harness.config.readAsString();
      expect(config, contains('owrt_device_block_'));
      expect(config, isNot(contains('openwalla_quarantine_')));
    },
  );
}
