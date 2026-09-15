import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';

void main() {
  Widget buildVisual(Brightness brightness) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: ScooterSideVisual(
            imagePath: 'images/scooter/side_1.webp',
            height: 160,
            backdropDiameter: 264,
          ),
        ),
      );

  testWidgets('shows a circular contrast backdrop in dark mode', (tester) async {
    await tester.pumpWidget(buildVisual(Brightness.dark));

    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('scooter-side-dark-backdrop')));
    expect(backdrop.constraints!.maxWidth, 264);
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, const Color(0xFF303437));
  });

  testWidgets('does not add the dark backdrop in light mode', (tester) async {
    await tester.pumpWidget(buildVisual(Brightness.light));

    expect(find.byKey(const ValueKey('scooter-side-dark-backdrop')), findsNothing);
  });
}
