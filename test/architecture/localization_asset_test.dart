import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English fallback translations load synchronously in widget tests', () {
    expect(
      File('assets/i18n/en.json').lengthSync(),
      lessThan(50 * 1024),
      reason: 'AssetBundle.loadString decodes larger assets in an isolate, '
          'outside the widget-test fake-async clock.',
    );
  });
}
