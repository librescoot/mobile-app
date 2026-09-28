import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _loadImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('limited scooter exports retain their shared master scale', () async {
    final fronts = <ui.Image>[];
    final sides = <ui.Image>[];
    addTearDown(() {
      for (final image in [...fronts, ...sides]) {
        image.dispose();
      }
    });

    for (final index in [7, 8, 9]) {
      fronts.add(await _loadImage('images/scooter/base_$index.webp'));
      sides.add(await _loadImage('images/scooter/side_$index.webp'));
    }

    expect(fronts.map((image) => (image.width, image.height)), everyElement((866, 1800)));
    expect(sides.map((image) => (image.width, image.height)), everyElement((2110, 1738)));
  });
}
