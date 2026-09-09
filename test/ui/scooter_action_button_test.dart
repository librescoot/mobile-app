import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/widgets/scooter_action_button.dart';

void main() {
  testWidgets('relocated action button invokes its callback', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScooterActionButton(
          onPressed: () => calls++,
          icon: Icons.lock_outline,
          label: 'Lock',
        ),
      ),
    ));

    expect(find.text('Lock'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    expect(calls, 1);
  });

  testWidgets('relocated action button remains disabled without a callback',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ScooterActionButton(
          onPressed: null,
          icon: Icons.lock_outline,
          label: 'Lock',
        ),
      ),
    ));

    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
  });
}
