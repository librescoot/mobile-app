import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('front paint uses soft-light shading and one fender shadow', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('images/scooter/custom_artwork_layers.json'),
    ) as Map<String, dynamic>;
    final front = (manifest['views'] as Map<String, dynamic>)['front'] as Map<String, dynamic>;
    final layers = front['paintLayers'] as List<dynamic>;
    final body = layers[0] as Map<String, dynamic>;
    final fender = layers[1] as Map<String, dynamic>;
    final effects = body['effects'] as List<dynamic>;

    expect(front['height'], 1800);
    expect(effects.take(3).map((effect) => effect['blendMode']), everyElement('softLight'));
    expect((fender['before'] as Map<String, dynamic>)['asset'],
        'images/scooter/custom_front_fender_shadow.png');
    expect(layers.where((layer) => layer['before'] != null), hasLength(1));
    expect(await rootBundle.load('images/scooter/custom_front_fender_shadow.png'), isNotNull);
  });
}
