import 'dart:convert';

import 'package:flutter/services.dart';

/// Decodes translation assets on the main isolate.
///
/// [AssetBundle.loadString] hands files of 50 KB or more to an isolate, whose
/// future never completes under the widget-test clock.
class InlineStringBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final data = await load(key);
    return utf8.decode(Uint8List.sublistView(data));
  }
}