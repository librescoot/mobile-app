import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> load(String locale) =>
    jsonDecode(File('assets/i18n/$locale.json').readAsStringSync())
        as Map<String, dynamic>;

final placeholder = RegExp(r'\{\w+\}');

Set<String> placeholders(Object? value) =>
    placeholder.allMatches(jsonEncode(value)).map((m) => m.group(0)!).toSet();

void main() {
  final english = load('en');

  // en_GB only overrides spelling and falls back to en for the rest.
  for (final locale in ['de', 'fr', 'nl', 'pi']) {
    group(locale, () {
      final strings = load(locale);

      test('has every key English has', () {
        final missing = english.keys.where((k) => !strings.containsKey(k));
        expect(missing, isEmpty);
      });

      test('has no key English lacks', () {
        final extra = strings.keys.where((k) => !english.containsKey(k));
        expect(extra, isEmpty);
      });

      test('keeps the placeholders of the English text', () {
        final changed = [
          for (final entry in english.entries)
            if (strings.containsKey(entry.key) &&
                !setEquals(placeholders(entry.value),
                    placeholders(strings[entry.key])))
              entry.key
        ];
        expect(changed, isEmpty);
      });
    });
  }
}
