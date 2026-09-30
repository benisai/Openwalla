import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled Openwalla rpcd ACL is valid and grants file execution',
    () async {
      final source = await rootBundle.loadString('openwrt-setup/rpcd-acl.json');
      final decoded = jsonDecode(source) as Map<String, dynamic>;
      final openwalla = decoded['openwalla'] as Map<String, dynamic>;
      final write = openwalla['write'] as Map<String, dynamic>;
      final file = write['file'] as Map<String, dynamic>;

      expect(file['/bin/sh'], contains('exec'));
      expect(openwalla['read'], isA<Map<String, dynamic>>());
    },
  );
}
