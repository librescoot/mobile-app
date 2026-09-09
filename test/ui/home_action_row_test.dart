import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/screens/home_screen.dart';
import 'package:unustasis/ui/widgets/home_action_row.dart';
import 'package:unustasis/ui/widgets/scooter_action_button.dart';

void main() {
  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('actual power button stays on nav centerline at $width/$scale', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Column(children: [
              HomeActionRow(
                leading: ScooterActionButton(onPressed: () {}, icon: Icons.warning, label: 'Seat is open!'),
                primary: const ScooterPowerButton(
                  action: null,
                  icon: Icons.lock_open,
                  label: 'Unlock',
                  instruction: 'Hold to unlock',
                ),
                trailing: ScooterActionButton(onPressed: () {}, icon: Icons.tune, label: 'Controls'),
              ),
              const Center(child: Icon(Icons.keyboard_arrow_up, key: ValueKey('nav-cue'))),
            ]),
          ),
        ));
        await tester.pump();
        expect(tester.getCenter(find.byType(ElevatedButton)).dx, width / 2);
        expect(tester.getSize(find.byType(ElevatedButton)).width, 136);
        expect(find.text('Hold to unlock'), findsNothing);
        final spacer = find.descendant(
          of: find.byType(ScooterPowerButton),
          matching: find.byKey(const ValueKey('power-label-spacer')),
        );
        expect(spacer, findsOneWidget);
        expect(tester.getTopLeft(spacer).dy, tester.getBottomLeft(find.byType(ElevatedButton)).dy + 8);
        final sideButtons = find.byType(OutlinedButton);
        final primaryY = tester.getCenter(find.byType(ElevatedButton)).dy;
        expect(tester.getCenter(sideButtons.first).dy, primaryY);
        expect(tester.getCenter(sideButtons.last).dy, primaryY);
        expect(tester.getCenter(sideButtons.first).dx, greaterThan(width / 8));
        expect(tester.getCenter(sideButtons.last).dx, lessThan(width * 7 / 8));
        expect(tester.getCenter(find.byKey(const ValueKey('nav-cue'))).dx, width / 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
