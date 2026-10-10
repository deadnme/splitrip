import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitrip/screens/random_pay.dart';

void main() {
  testWidgets('starting another spin clears the confirmed payer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showRandomPayer(context, ['Alice', 'Bob']),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Complete the first result through the wheel's public callback.
    tester.widget<RandomPayWheel>(find.byType(RandomPayWheel)).onWinner(0);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Use Alice as payer'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Spin the wheel'));
    await tester.pump();
    expect(find.text('Use Alice as payer'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Use as payer'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
