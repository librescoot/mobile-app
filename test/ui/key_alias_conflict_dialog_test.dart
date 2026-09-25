import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/key_alias_sync.dart';
import 'package:unustasis/ui/screens/ls_keycard_screen.dart';

void main() {
  testWidgets('name conflict shows both sources and returns the selected one', (tester) async {
    KeyAliasChoice? choice;
    const conflict = KeyAliasConflict(
      uid: '04010203',
      localName: 'Daily card',
      scooterName: 'Spare card',
    );

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(
          translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n',
            fallbackFile: 'en',
            forcedLocale: const Locale('en'),
          ),
        ),
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showKeyAliasConflictDialog(context, conflict);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose key name'), findsOneWidget);
    expect(find.textContaining('Daily card'), findsOneWidget);
    expect(find.textContaining('Spare card'), findsOneWidget);

    await tester.tap(find.text('Use phone name'));
    await tester.pumpAndSettle();
    expect(choice, KeyAliasChoice.local);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use scooter name'));
    await tester.pumpAndSettle();
    expect(choice, KeyAliasChoice.scooter);
  });
}
