import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:unustasis/ui/screens/support_screen.dart';
import 'package:unustasis/ui/widgets/header.dart';

import 'settings_help_row_theme_test.dart' show renderedStyle, rowTestTheme;

class _FaqBundle extends CachingAssetBundle {
  _FaqBundle(this.faq);
  final String faq;
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key.startsWith('assets/faq_') ? Future.value(faq) : rootBundle.loadString(key, cache: cache);
}

void main() {
  test('support keeps GitHub issues and log-attached email as separate options', () {
    final source = File('lib/ui/screens/support_screen.dart').readAsStringSync();
    expect(source, contains("'support_send_debug_logs'"));
    expect(source, contains('LogHelper.startBugReport(context)'));
    expect(source, contains("'support_github_issues'"));
    expect(source, contains('url: _issuesUrl'));
  });

  for (final (width, scale, brightness) in [
    (412.0, 1.0, Brightness.light),
    (320.0, 2.0, Brightness.dark),
  ]) {
    testWidgets('Help anchor and expanded FAQ hierarchy at $width dp / $scale', (tester) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final faq = await tester.runAsync(() => rootBundle.loadString('assets/faq_en.json'));
      PackageInfo.setMockInitialValues(
          appName: 'Librescoot', packageName: 'app.test', version: '1.0', buildNumber: '1', buildSignature: 'test');
      await tester.pumpWidget(MaterialApp(
        theme: rowTestTheme(brightness),
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n',
            fallbackFile: 'en',
            forcedLocale: const Locale('en'),
          ))
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: DefaultAssetBundle(bundle: _FaqBundle(faq!), child: const SupportScreen()),
      ));
      await tester.pumpAndSettle();
      expect(renderedStyle(tester, 'Librescoot handbook').fontSize, 18);
      expect(renderedStyle(tester, 'Librescoot handbook').fontWeight, FontWeight.w400);
      expect(renderedStyle(tester, 'Setup, riding, updates, and maintenance.').fontSize, 14);
      expect(renderedStyle(tester, 'Setup, riding, updates, and maintenance.').color,
          rowTestTheme(brightness).colorScheme.onSurfaceVariant);
      expect(tester.getBottomLeft(find.byType(Header).first).dy,
          tester.getTopLeft(find.ancestor(of: find.text('Librescoot handbook'), matching: find.byType(ListTile))).dy);
      await tester.scrollUntilVisible(find.text('Getting started'), 180);
      await tester.pumpAndSettle();
      expect(renderedStyle(tester, 'Getting started').fontSize, 18);
      await tester.tap(find.text('Getting started'));
      await tester.pumpAndSettle();
      final category = find.ancestor(of: find.text('Getting started'), matching: find.byType(ExpansionTile));
      final question =
          tester.widget<ExpansionTile>(find.descendant(of: category, matching: find.byType(ExpansionTile)).first);
      final questionText = (question.title as Text).data!;
      expect(renderedStyle(tester, questionText).fontSize, 14);
      await tester.tap(find.text(questionText));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
