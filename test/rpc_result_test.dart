import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/rpc_result.dart';

void main() {
  group('rpcUbusStatusCode', () {
    test('reads successful and denied ubus statuses', () {
      expect(
        rpcUbusStatusCode([
          0,
          {'stdout': 'OK'},
        ]),
        0,
      );
      expect(rpcUbusStatusCode([6]), 6);
    });

    test('returns null for values without a ubus envelope', () {
      expect(rpcUbusStatusCode({'stdout': 'OK'}), isNull);
      expect(rpcUbusStatusCode([]), isNull);
    });
  });

  group('rpcBooleanResultSucceeded', () {
    test('accepts a direct LuCI result', () {
      expect(rpcBooleanResultSucceeded({'result': true}), isTrue);
    });

    test('accepts a standard ubus response', () {
      expect(
        rpcBooleanResultSucceeded([
          0,
          {'result': true},
        ]),
        isTrue,
      );
    });

    test('accepts a nested LuCI ubus response', () {
      expect(
        rpcBooleanResultSucceeded([
          0,
          [
            0,
            {'result': 1},
          ],
        ]),
        isTrue,
      );
    });

    test('rejects a failed password result', () {
      expect(
        rpcBooleanResultSucceeded([
          0,
          {'result': false},
        ]),
        isFalse,
      );
    });

    test('rejects a failed ubus status', () {
      expect(
        rpcBooleanResultSucceeded([
          6,
          {'result': true},
        ]),
        isFalse,
      );
    });
  });
}
