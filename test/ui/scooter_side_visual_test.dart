import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';

void main() {
  Widget buildVisual(
    Brightness brightness, {
    Color? backdropColor,
  }) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: ScooterSideVisual(
            imagePath: 'images/scooter/side_1.webp',
            height: 160,
            backdropDiameter: 264,
            backdropColor: backdropColor,
          ),
        ),
      );

  testWidgets('shows a circular contrast backdrop in dark mode', (tester) async {
    await tester.pumpWidget(buildVisual(Brightness.dark));

    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('scooter-side-dark-backdrop')));
    expect(backdrop.constraints!.maxWidth, 264);
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, const Color(0xFF3E4549));
  });

  testWidgets('uses a supplied dark backdrop colour', (tester) async {
    const customColor = Color(0xFF33474B);
    await tester.pumpWidget(buildVisual(Brightness.dark, backdropColor: customColor));

    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('scooter-side-dark-backdrop')));
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.color, customColor);
  });

  testWidgets('shows a supplied Librescoot backdrop without an outline in either theme', (tester) async {
    const librescootColor = Color(0xFF33474B);
    await tester.pumpWidget(buildVisual(Brightness.light, backdropColor: librescootColor));

    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('scooter-side-dark-backdrop')));
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.color, librescootColor);
    expect(decoration.border, isNull);
  });

  testWidgets('does not add the dark backdrop in light mode', (tester) async {
    await tester.pumpWidget(buildVisual(Brightness.light));

    expect(find.byKey(const ValueKey('scooter-side-dark-backdrop')), findsNothing);
  });
}
