import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/widgets/openwalla_toast.dart';

void main() {
  testWidgets('replaces a loading toast with a timed success toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => OpenwallaToast.showLoading(
                    context,
                    key: 'static-ip-test',
                    message: 'Creating static lease...',
                  ),
                  child: const Text('Load'),
                ),
                TextButton(
                  onPressed: () => OpenwallaToast.showSuccess(
                    context,
                    key: 'static-ip-test',
                    message: 'Static lease reserved',
                  ),
                  child: const Text('Success'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Load'));
    await tester.pump();
    expect(find.text('Creating static lease...'), findsOneWidget);

    await tester.tap(find.text('Success'));
    await tester.pump();
    expect(find.text('Creating static lease...'), findsNothing);
    expect(find.text('Static lease reserved'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Static lease reserved'), findsNothing);
  });
}
