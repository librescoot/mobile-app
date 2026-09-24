import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/animation/blinker_curve.dart';
import 'package:unustasis/ui/widgets/scooter_visual.dart';

void main() {
  test('matches the vehicle 800 ms blinker cycle', () {
    expect(blinkerBrightness(Duration.zero), 0);
    expect(blinkerBrightness(const Duration(milliseconds: 248)), 1);
    expect(blinkerBrightness(const Duration(milliseconds: 504)), 0);
    expect(blinkerBrightness(const Duration(milliseconds: 799)), 0);
    expect(blinkerBrightness(const Duration(milliseconds: 800)), 0);
    expect(
      blinkerBrightness(const Duration(milliseconds: 1000)),
      blinkerBrightness(const Duration(milliseconds: 200)),
    );
  });

  testWidgets('fades only the selected front blinker', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BlinkerWidget(blinkerLeft: true, blinkerRight: false)),
    );

    await tester.pump(const Duration(milliseconds: 248));
    expect(tester.widget<Opacity>(find.byKey(const ValueKey('left-blinker'))).opacity, closeTo(1, 0.001));
    expect(tester.widget<Opacity>(find.byKey(const ValueKey('right-blinker'))).opacity, 0);

    await tester.pump(const Duration(milliseconds: 256));
    expect(tester.widget<Opacity>(find.byKey(const ValueKey('left-blinker'))).opacity, 0);
  });
}
