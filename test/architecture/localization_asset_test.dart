import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replacement warning is translated and retains filename and size fields', () {
    for (final locale in ['en', 'en_GB', 'de', 'fr', 'nl', 'pi']) {
      final translations = jsonDecode(File('assets/i18n/$locale.json').readAsStringSync()) as Map<String, dynamic>;
      final warning = translations['file_browser_replace_body'] as String;
      expect(warning, contains('{name}'), reason: locale);
      expect(warning, contains('{size}'), reason: locale);
      expect(warning.toLowerCase(), anyOf(contains('service'), contains('dienst'), contains('services')),
          reason: locale);
    }
  });
}
