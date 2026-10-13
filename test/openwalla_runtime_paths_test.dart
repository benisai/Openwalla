import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Openwalla runtime files stay inside the shared runtime directory', () {
    final roots = [Directory('lib'), Directory('openwrt-setup')];
    final legacyPath = RegExp(r'/tmp/(?:openwalla-|\.openwalla)');
    final violations = <String>[];

    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File ||
            !const [
              '.dart',
              '.json',
              '.sh',
              '.config',
            ].any(entity.path.endsWith)) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (line.contains('/tmp/openwalla-*|/tmp/.openwalla*)')) {
            continue;
          }
          if (legacyPath.hasMatch(line)) {
            violations.add('${entity.path}:${index + 1}: $line');
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('router defaults use the shared Openwalla runtime directory', () {
    final config = File(
      'openwrt-setup/files/openwalla.config',
    ).readAsStringSync();
    final runtimePaths = RegExp(
      r"option (?:db_path|output_file|state_file|interface_state_file|wireguard_state_file) '(/tmp/[^']+)'",
    ).allMatches(config).map((match) => match.group(1)!);

    expect(runtimePaths, isNotEmpty);
    expect(
      runtimePaths.every((path) => path.startsWith('/tmp/openwalla/')),
      isTrue,
    );
  });
}
