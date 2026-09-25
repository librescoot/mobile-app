import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/theme/scooter_colors.dart';
import 'package:unustasis/ui/widgets/rendered_scooter_artwork.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';

void main() {
  test('uses the established coral swatch and darker matte black', () {
    expect(layeredScooterColor(0), '#0F0F0F');
    expect(scooterColors[0]!.displayColor, const Color(0xFF0F0F0F));
    expect(layeredScooterColor(4), '#E87962');
    expect(scooterColors[4]!.displayColor, const Color(0xFFE87962));
  });

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
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final artworkFinder = find.byType(RenderedScooterArtwork);
    final artwork = tester.widget<RenderedScooterArtwork>(artworkFinder);
    expect(tester.getSize(artworkFinder).height, 160);
    expect(tester.getSize(artworkFinder).width, closeTo(160 * 2110 / 1738, 0.1));
    expect(artwork.color, '#123456');
    expect(artwork.matte, isFalse);
    expect(find.byKey(const ValueKey('custom-paint-gloss-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-paint-matte-layer')), findsNothing);
    expect(
      tester.widget<CustomPaint>(find.byKey(const ValueKey('custom-paint-gloss-layer'))).painter,
      isNotNull,
    );
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('keeps matte texture and details in source order', (tester) async {
    final encoded = await tester.runAsync(
      () => File('images/scooter/custom_artwork_layers.json').readAsString(),
    );
    final manifest = jsonDecode(encoded!) as Map<String, dynamic>;
    final views = manifest['views'] as Map<String, dynamic>;
    final front = views['front'] as Map<String, dynamic>;
    final paintLayers = front['paintLayers'] as List<dynamic>;
    final finalPaint = paintLayers.last as Map<String, dynamic>;
    final effects = finalPaint['effects'] as List<dynamic>;

    expect((effects.first as Map<String, dynamic>)['blendMode'], 'overlay');
    expect((effects[1] as Map<String, dynamic>)['matteOnly'], isTrue);
    expect((effects.last as Map<String, dynamic>)['blendMode'], 'srcOver');
  });

  test('adds directional gloss before foreground details', () async {
    final encoded = await File('images/scooter/custom_artwork_layers.json').readAsString();
    final manifest = jsonDecode(encoded) as Map<String, dynamic>;
    final views = manifest['views'] as Map<String, dynamic>;
    final front = views['front'] as Map<String, dynamic>;
    final glossLayers = front['glossLayers'] as List<dynamic>;
    final paintLayers = front['paintLayers'] as List<dynamic>;
    final foregroundEffects = (paintLayers.last as Map<String, dynamic>)['effects'] as List<dynamic>;

    expect(glossLayers, hasLength(3));
    expect(
      glossLayers.map((value) => (value as Map<String, dynamic>)['blendMode']),
      everyElement('screen'),
    );
    expect(
      glossLayers.map((value) => (value as Map<String, dynamic>)['asset']),
      containsAll(<String>[
        'images/scooter/custom_front_gloss_bloom.png',
        'images/scooter/custom_front_gloss_contour.png',
        'images/scooter/custom_front_gloss_sweep.png',
      ]),
    );
    expect(
      front['glossBefore'],
      (foregroundEffects.last as Map<String, dynamic>)['asset'],
    );
    expect(
      paintLayers
          .expand(
            (value) => (value as Map<String, dynamic>)['effects'] as List<dynamic>,
          )
          .map((value) => (value as Map<String, dynamic>)['blendMode']),
      isNot(contains('softLight')),
    );
    final side = views['side'] as Map<String, dynamic>;
    final sideGlossLayers = side['glossLayers'] as List<dynamic>;
    final sidePaintLayers = side['paintLayers'] as List<dynamic>;
    final sideForegroundEffects = (sidePaintLayers.last as Map<String, dynamic>)['effects'] as List<dynamic>;
    expect(sideGlossLayers, hasLength(3));
    expect(
      sideGlossLayers.map(
        (value) => (value as Map<String, dynamic>)['blendMode'],
      ),
      everyElement('screen'),
    );
    expect(
      side['glossBefore'],
      (sideForegroundEffects.last as Map<String, dynamic>)['asset'],
    );
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

    expect(tester.widget<RenderedScooterArtwork>(find.byType(RenderedScooterArtwork)).showShadow, isFalse);

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
    expect(tester.widget<RenderedScooterArtwork>(find.byType(RenderedScooterArtwork)).showShadow, isTrue);
  });

  testWidgets('does not add the dark backdrop in light mode', (tester) async {
    await tester.pumpWidget(buildVisual(Brightness.light));

    expect(find.byKey(const ValueKey('scooter-side-dark-backdrop')), findsNothing);
  });
}
