import 'dart:convert';

import 'package:flutter/services.dart';

/// Decodes translation assets on the main isolate.
///
/// [AssetBundle.loadString] hands files of 50 KB or more to an isolate, and
/// that future does not complete under the widget-test clock, so a locale file
/// that size would hang `Localizations` and render an empty screen.
class InlineStringBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final data = await load(key);
    return utf8.decode(Uint8List.sublistView(data));
  }
}