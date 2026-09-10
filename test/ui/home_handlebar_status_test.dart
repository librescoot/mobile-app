import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool? locked,
  required double textScale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(
          translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n',
            fallbackFile: 'en',
            forcedLocale: const Locale('en'),
          ),
        ),
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(child: HandlebarStatusLine(locked: locked)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'handlebar status keeps its slot and semantics at ${textScale}x text',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await _pump(tester, locked: false, textScale: textScale);
        final slot = find.byKey(const ValueKey('handlebar-status-slot'));
        final unlockedSize = tester.getSize(slot);
        expect(find.bySemanticsLabel('Handlebar unlocked'), findsOneWidget);
        expect(find.bySemanticsLabel('Handlebar locked'), findsNothing);

        await _pump(tester, locked: null, textScale: textScale);
        expect(tester.getSize(slot), unlockedSize);
        expect(find.bySemanticsLabel('Handlebar unlocked'), findsNothing);
        expect(find.bySemanticsLabel('Handlebar locked'), findsNothing);

        await _pump(tester, locked: true, textScale: textScale);
        expect(tester.getSize(slot), unlockedSize);
        expect(find.bySemanticsLabel('Handlebar locked'), findsOneWidget);
        expect(find.bySemanticsLabel('Handlebar unlocked'), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
