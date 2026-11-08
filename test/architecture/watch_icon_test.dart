import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('watch icon has an opaque, visible background', () async {
    final bytes = await File('ios/ScooterWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png').readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    expect(image.width, 1024);
    expect(image.height, 1024);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    final corner = data.sublist(0, 4);
    expect(corner[3], 255);
    expect(corner.take(3).reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(48));
    final Uint8List center = data.sublist((512 * 1024 + 512) * 4, (512 * 1024 + 512) * 4 + 4);
    expect(center[1], greaterThan(corner[1]));
    image.dispose();
    codec.dispose();
  });
}
