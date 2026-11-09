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

  testWidgets('seatbox action fires after its configured hold and cancels on release', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScooterActionButton(
          onPressed: () => calls++,
          icon: Icons.lock_open,
          label: 'Seatbox',
          holdToTrigger: true,
          holdDuration: const Duration(milliseconds: 400),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(OutlinedButton));
    var gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 399));
    expect(calls, 0);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 0);

    gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 401));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await gesture.up();
    await tester.pump();
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
