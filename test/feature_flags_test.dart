import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/feature_flags.dart';

void main() {
  test('battery registration matches the explicitly selected build gate', () {
    const expected = bool.fromEnvironment('EXPECT_BATTERY_REGISTRATION_ENABLED');
    expect(sunshineBatteryRegistrationEnabled, expected);
  });

  test('phone keys are available on Android only', () {
    expect(phoneKeyFeatureEnabledFor(platform: TargetPlatform.android), isTrue);

    for (final platform in TargetPlatform.values.where((value) => value != TargetPlatform.android)) {
      expect(phoneKeyFeatureEnabledFor(platform: platform), isFalse);
    }
  });
}
