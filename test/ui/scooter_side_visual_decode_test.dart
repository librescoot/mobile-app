import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';

void main() {
  testWidgets('card art decodes near the painted size, not the 2110px source', (tester) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ScooterSideVisual(
          imagePath: 'images/scooter/side_1.webp',
          height: 160,
          backdropDiameter: 264,
        ),
      ),
    ));
    // Precache exactly what the widget asks for, so the assertion follows the
    // widget rather than a separate provider built by the test.
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final context = tester.element(find.byType(ScooterSideVisual));
    await tester.runAsync(() async {
      await precacheImage(provider, context);
    });

    final cache = PaintingBinding.instance.imageCache;
    // The source is 2110x1738, about 14 MB decoded. A card paints ~508x160 at
    // this density, so anything close to the source means the resize was lost.
    expect(cache.currentSizeBytes, lessThan(2 * 1024 * 1024));
    expect(cache.currentSizeBytes, greaterThan(100 * 1024));
  });
}
