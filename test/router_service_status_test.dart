import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  test('finds a running procd instance in wrapped service output', () {
    final response = [
      0,
      {
        'openwalla-device-quarantine': {
          'instances': {
            'instance1': {'running': true, 'pid': 2481},
          },
        },
      },
    ];

    expect(routerServiceResponseIsRunning(response), isTrue);
  });

  test('reports stopped when procd has no running instance', () {
    final response = {
      'openwalla-device-quarantine': {
        'instances': {
          'instance1': {'running': false},
        },
      },
    };

    expect(routerServiceResponseIsRunning(response), isFalse);
    expect(routerServiceResponseIsRunning(const {}), isFalse);
  });
}
