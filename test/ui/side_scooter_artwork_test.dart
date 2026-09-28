import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('side paint shading uses Soft Light on the shared canvas', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('images/scooter/custom_artwork_layers.json'),
    ) as Map<String, dynamic>;
    final side = (manifest['views'] as Map<String, dynamic>)['side'] as Map<String, dynamic>;
    final layers = side['paintLayers'] as List<dynamic>;

    expect((side['width'], side['height']), (2110, 1738));
    expect(layers, hasLength(3));
    for (final layer in layers) {
      final effects = (layer as Map<String, dynamic>)['effects'] as List<dynamic>;
      expect((effects.first as Map<String, dynamic>)['blendMode'], 'softLight');
      expect(effects.map((effect) => (effect as Map<String, dynamic>)['blendMode']),
          isNot(contains('luminosity')));
    }
  });
}
