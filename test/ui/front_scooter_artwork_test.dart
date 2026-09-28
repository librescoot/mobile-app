import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('front paint uses soft-light shading without a displaced fender shadow', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('images/scooter/custom_artwork_layers.json'),
    ) as Map<String, dynamic>;
    final front = (manifest['views'] as Map<String, dynamic>)['front'] as Map<String, dynamic>;
    final layers = front['paintLayers'] as List<dynamic>;
    final body = layers[0] as Map<String, dynamic>;
    final effects = body['effects'] as List<dynamic>;

    expect(front['height'], 1800);
    expect(effects.take(3).map((effect) => effect['blendMode']), everyElement('softLight'));
    expect(layers.where((layer) => layer['before'] != null), isEmpty);
    expect(manifest.toString(), isNot(contains('custom_front_fender_shadow')));
  });
}
