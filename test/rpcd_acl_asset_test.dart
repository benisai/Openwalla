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
      final read = openwalla['read'] as Map<String, dynamic>;
      expect(read['uci'], contains('system'));
      expect((read['ubus'] as Map)['luci'], contains('getTimezones'));
      expect((read['ubus'] as Map)['luci-rpc'], contains('getBoardJSON'));
      expect((write['ubus'] as Map)['uci'], contains('apply'));
    },
  );
}
