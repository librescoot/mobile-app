import 'package:flutter/foundation.dart';

bool phoneKeyFeatureEnabledFor({required TargetPlatform platform, required bool releaseMode}) =>
    !releaseMode && platform == TargetPlatform.android;

bool get phoneKeyFeatureEnabled =>
    phoneKeyFeatureEnabledFor(platform: defaultTargetPlatform, releaseMode: kReleaseMode);
