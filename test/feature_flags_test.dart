import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/feature_flags.dart';

void main() {
  test('phone keys are limited to Android debug and profile builds', () {
    expect(phoneKeyFeatureEnabledFor(platform: TargetPlatform.android, releaseMode: false), isTrue);
    expect(phoneKeyFeatureEnabledFor(platform: TargetPlatform.android, releaseMode: true), isFalse);

    for (final platform in TargetPlatform.values.where((value) => value != TargetPlatform.android)) {
      expect(phoneKeyFeatureEnabledFor(platform: platform, releaseMode: false), isFalse);
      expect(phoneKeyFeatureEnabledFor(platform: platform, releaseMode: true), isFalse);
    }
  });
}
