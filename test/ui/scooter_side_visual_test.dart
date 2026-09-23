import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/widgets/rendered_scooter_artwork.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';

void main() {
  Widget buildVisual(
    Brightness brightness, {
    Color? backdropColor,
    bool eclipseBackdrop = false,
    String? renderedColor,
    bool renderedColorMatte = true,
  }) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: ScooterSideVisual(
            imagePath: 'images/scooter/side_1.webp',
            height: 160,
            backdropDiameter: 264,
            backdropColor: backdropColor,
            eclipseBackdrop: eclipseBackdrop,
            renderedColor: renderedColor,
            renderedColorMatte: renderedColorMatte,
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
    const librescootColor = Color(0xFF225661);
    await tester.pumpWidget(buildVisual(Brightness.light, backdropColor: librescootColor));

    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('scooter-side-dark-backdrop')));
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.color, librescootColor);
    expect(decoration.border, isNull);
  });

  testWidgets('Eclipse replaces the solid disk with a radial ring in either theme', (tester) async {
    await tester.pumpWidget(
      buildVisual(
        Brightness.light,
        backdropColor: const Color(0xFFB8DCDD),
        eclipseBackdrop: true,
      ),
    );

    expect(find.byKey(const ValueKey('scooter-side-dark-backdrop')), findsNothing);
    final backdrop = tester.widget<Container>(find.byKey(const ValueKey('eclipse-backdrop')));
    final decoration = backdrop.decoration! as BoxDecoration;
    expect(decoration.gradient, isA<RadialGradient>());
    expect(decoration.color, isNull);
  });

  testWidgets('uses cached rendered artwork for a custom finish', (tester) async {
    await tester.pumpWidget(
      buildVisual(
        Brightness.light,
        renderedColor: '#123456',
        renderedColorMatte: false,
      ),
    );

    final artworkFinder = find.byType(RenderedScooterArtwork);
    final artwork = tester.widget<RenderedScooterArtwork>(artworkFinder);
    expect(tester.getSize(artworkFinder).height, 160);
    expect(tester.getSize(artworkFinder).width, closeTo(160 * 2110 / 1738, 0.1));
    expect(artwork.color, '#123456');
    expect(artwork.matte, isFalse);
    expect(find.byKey(const ValueKey('custom-paint-gloss-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-paint-matte-layer')), findsNothing);
  });

  testWidgets('can omit the independently rendered ground shadow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RenderedScooterArtwork(
          view: ScooterArtworkView.side,
          color: '#123456',
          matte: true,
          showShadow: false,
          height: 160,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('scooter-ground-shadow')), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: RenderedScooterArtwork(
          view: ScooterArtworkView.side,
          color: '#123456',
          matte: true,
          height: 160,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('scooter-ground-shadow')), findsOneWidget);
  });

  testWidgets('does not add the dark backdrop in light mode', (tester) async {
    await tester.pumpWidget(buildVisual(Brightness.light));

    expect(find.byKey(const ValueKey('scooter-side-dark-backdrop')), findsNothing);
  });
}
