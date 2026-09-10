import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/bundled_font_licenses.dart';
import 'package:unustasis/ui/theme/librescoot_theme.dart';

void main() {
  testWidgets('every UI font is available from bundled assets', (tester) async {
    const assets = {
      'assets/fonts/Inter-Regular.ttf': 303384,
      'assets/fonts/Abel-Regular.ttf': 32648,
      'assets/fonts/KodeMono-Regular.ttf': 43452,
    };
    for (final MapEntry(key: path, value: expectedLength) in assets.entries) {
      final bytes = await rootBundle.load(path);
      expect(bytes.lengthInBytes, expectedLength, reason: path);
    }

    final theme = buildLibrescootTheme(Brightness.light);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(theme.textTheme.displayLarge?.fontFamily, 'Abel');

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Text('A1 B2', style: TextStyle(fontFamily: 'KodeMono')),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bundled font licenses are registered', (tester) async {
    registerBundledFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((entry) => entry.packages).toSet();

    expect(packages, containsAll(['Inter', 'Abel', 'Kode Mono']));
  });

  test('runtime font downloading is absent from the application', () async {
    expect(await File('pubspec.yaml').readAsString(), isNot(contains('google_fonts:')));
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = await file.readAsString();
      expect(source, isNot(contains('GoogleFonts.')), reason: file.path);
      expect(source, isNot(contains('fonts.gstatic.com')), reason: file.path);
    }
  });
}
