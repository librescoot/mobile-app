import 'package:flutter/foundation.dart';

const sunshineBatteryRegistrationEnabled = bool.fromEnvironment('SUNSHINE_BATTERY_REGISTRATION_ENABLED');

bool phoneKeyFeatureEnabledFor({required TargetPlatform platform}) => platform == TargetPlatform.android;

bool get phoneKeyFeatureEnabled => phoneKeyFeatureEnabledFor(platform: defaultTargetPlatform);
