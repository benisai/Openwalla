import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/screens/interfaces_screen.dart';

void main() {
  group('wired interface visibility', () {
    test('defaults to enabled interfaces before selection is initialized', () {
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'lan', 'up': true},
          enabledInterfaces: const {},
          selectionInitialized: false,
        ),
        isTrue,
      );
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'wan', 'up': false},
          enabledInterfaces: const {},
          selectionInitialized: false,
        ),
        isTrue,
      );
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'guest', 'up': true, 'disabled': '1'},
          enabledInterfaces: const {},
          selectionInitialized: false,
        ),
        isFalse,
      );
    });

    test('empty initialized selection explicitly shows all interfaces', () {
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'wan', 'up': false},
          enabledInterfaces: const {},
          selectionInitialized: true,
        ),
        isTrue,
      );
    });

    test('initialized selections only show checked interfaces', () {
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'lan', 'up': true},
          enabledInterfaces: const {'lan'},
          selectionInitialized: true,
        ),
        isTrue,
      );
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'wan', 'up': true},
          enabledInterfaces: const {'lan'},
          selectionInitialized: true,
        ),
        isFalse,
      );
    });
  });
}
