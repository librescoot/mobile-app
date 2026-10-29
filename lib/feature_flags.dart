import 'package:flutter/foundation.dart';

const sunshineBatteryRegistrationEnabled = bool.fromEnvironment('SUNSHINE_BATTERY_REGISTRATION_ENABLED');

bool phoneKeyFeatureEnabledFor({required TargetPlatform platform, required bool releaseMode}) =>
    !releaseMode && platform == TargetPlatform.android;

bool get phoneKeyFeatureEnabled =>
    phoneKeyFeatureEnabledFor(platform: defaultTargetPlatform, releaseMode: kReleaseMode);
