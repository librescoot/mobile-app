import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/ls_keycard_screen.dart';

import '../support/persistence_fakes.dart';

class _Actions implements ScooterActions {
  @override
  Future<List<String>> listKeycards() async => ['AABBCCDD', '11223344'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool get connected => false;
  @override
  String? get currentScooterId => null;
  @override
  bool? get phoneKeyManagementSupported => false;
  @override
  bool? get keyAliasesSupported => false;
  @override
  ScooterActions get actions => _Actions();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(_Service service) => ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
            translationLoader: FileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: const Locale('en'),
            ),
          ),
        ],
        home: const LsKeycardScreen(),
      ),
    );

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });

  testWidgets('Android phone key instructions start collapsed and can be expanded', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final service = _Service();
    addTearDown(service.dispose);

    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('phone-key-expansion'));
    expect(panel, findsOneWidget);
    expect(tester.widget<ExpansionTile>(panel).initiallyExpanded, isFalse);
    expect(find.text('Provide NFC phone key'), findsNothing);

    await tester.tap(find.text('Use this Android phone as a key'));
    await tester.pumpAndSettle();
    expect(find.text('Provide NFC phone key'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('card colour choice persists for its UID', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final preferences = SharedPreferencesAsyncPlatform.instance as MemoryPreferences;
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();

    final card = find.byType(KeycardCard).first;
    expect(tester.widget<KeycardCard>(card).colorIndex, isNull);
    await tester.tap(find.descendant(of: card, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card color'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 12; index++) {
      expect(find.byKey(ValueKey('keycard-color-$index')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('keycard-color-9')));
    await tester.pumpAndSettle();

    expect(jsonDecode(preferences.values['keycard_colors']!), {'AABBCCDD': 9});
    expect(tester.widget<KeycardCard>(card).colorIndex, 9);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    expect(tester.widget<KeycardCard>(find.byType(KeycardCard).first).colorIndex, 9);
  });
}
