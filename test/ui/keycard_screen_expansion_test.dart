import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/feature_flags.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/presentation/keycard_colors.dart';
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
  bool get demoMode => false;
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

Future<void> _mount(WidgetTester tester, _Service service) async {
  await tester.pumpWidget(_screen(service));
  for (var attempt = 0; attempt < 20 && find.byType(LsKeycardScreen).evaluate().isEmpty; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

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

    await _mount(tester, service);

    expect(phoneKeyFeatureEnabled, isTrue);
    expect(find.byType(LsKeycardScreen), findsOneWidget);
    final panel = find.byKey(const ValueKey('phone-key-expansion'));
    expect(panel, findsOneWidget);
    expect(tester.widget<ExpansionTile>(panel).initiallyExpanded, isFalse);
    expect(find.text('Provide NFC phone key'), findsNothing);

    await tester.tap(find.text('Use this Android phone as a key'));
    await tester.pumpAndSettle();
    expect(find.text('Provide NFC phone key'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('keycard has a twelve-pixel corner radius', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);

    final containers = tester.widgetList<Container>(find.descendant(
      of: find.byType(KeycardCard).first,
      matching: find.byType(Container),
    ));
    final card = containers
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.gradient != null);
    expect(card.borderRadius, BorderRadius.circular(12));
  });

  test('card palette covers common hues and keeps readable ink', () {
    expect(keycardColors, hasLength(12));
    expect(keycardColors[9], const Color(0xFFFFD54F));
    expect(keycardColors[10], const Color(0xFFF6F4EF));
    for (final color in keycardColors) {
      final ink = keycardInkColor(color);
      for (final background in [color, Color.lerp(color, Colors.black, 0.08)!]) {
        final light = ink.computeLuminance() > background.computeLuminance() ? ink : background;
        final dark = ink == light ? background : ink;
        final contrast = (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: 'Color $color on $background');
      }
    }
  });

  testWidgets('card places UID, icon and name on the left with a contrasting wordmark', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);

    final card = find.byType(KeycardCard).first;
    final uid = find.descendant(of: card, matching: find.byKey(const ValueKey('keycard-uid')));
    final icon = find.descendant(of: card, matching: find.byKey(const ValueKey('keycard-icon')));
    final name = find.descendant(of: card, matching: find.byKey(const ValueKey('keycard-name')));
    final wordmark = find.descendant(of: card, matching: find.byKey(const ValueKey('keycard-wordmark')));
    expect(tester.getTopLeft(uid).dy, lessThan(tester.getTopLeft(icon).dy));
    expect(tester.getTopLeft(icon).dy, lessThan(tester.getTopLeft(name).dy));
    expect(tester.getTopLeft(uid).dx, closeTo(tester.getTopLeft(icon).dx, 1));
    expect(tester.getTopLeft(icon).dx, closeTo(tester.getTopLeft(name).dx, 1));
    expect(tester.getTopLeft(wordmark).dx, greaterThan(tester.getTopRight(name).dx));
    expect(tester.widget<Text>(uid).style!.fontSize, 14);
    expect(tester.widget<Text>(name).style!.fontSize, 26);

    await tester.tap(find.descendant(of: card, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keycard-color-10')));
    await tester.pumpAndSettle();

    final logo = tester.widget<Image>(wordmark);
    expect((logo.image as AssetImage).assetName, 'assets/icons/librescoot-wordmark.png');
    expect(logo.color, Colors.black);
    expect(tester.widget<Text>(uid).style!.color, Colors.black);
    final decoration = tester
        .widgetList<Container>(find.descendant(of: card, matching: find.byType(Container)))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.gradient != null);
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, [keycardColors[10], Color.lerp(keycardColors[10], Colors.black, 0.08)]);

    await tester.tap(find.descendant(of: card, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keycard-color-3')));
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(wordmark).color, Colors.white);
  });

  testWidgets('card colour choice persists for its UID', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final preferences = SharedPreferencesAsyncPlatform.instance as MemoryPreferences;
    await _mount(tester, service);

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
    await _mount(tester, service);
    expect(tester.widget<KeycardCard>(find.byType(KeycardCard).first).colorIndex, 9);
  });

  testWidgets('card icon choice persists and renders the Librescoot flame', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final preferences = SharedPreferencesAsyncPlatform.instance as MemoryPreferences;
    await _mount(tester, service);

    final card = find.byType(KeycardCard).first;
    expect(tester.widget<KeycardCard>(card).iconId, isNull);
    await tester.tap(find.descendant(of: card, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card icon'));
    await tester.pumpAndSettle();
    for (final id in ['contactless', 'flame', 'scooter', 'bolt', 'star', 'heart']) {
      expect(find.byKey(ValueKey('keycard-icon-$id')), findsOneWidget);
    }
    expect(find.text('Librescoot flame'), findsNothing);
    final flameOption = find.byKey(const ValueKey('keycard-icon-flame'));
    final semantics = tester.widget<Semantics>(find.ancestor(of: flameOption, matching: find.byType(Semantics)).first);
    expect(semantics.properties.label, 'Librescoot flame');
    await tester.tap(flameOption);
    await tester.pumpAndSettle();

    expect(jsonDecode(preferences.values['keycard_icons']!), {'AABBCCDD': 'flame'});
    expect(tester.widget<KeycardCard>(card).iconId, 'flame');
    final flame = tester.widget<Image>(find.descendant(
      of: find.descendant(of: card, matching: find.byKey(const ValueKey('keycard-icon'))),
      matching: find.byType(Image),
    ));
    expect((flame.image as AssetImage).assetName, 'assets/icons/librescoot-flame.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, service);
    expect(tester.widget<KeycardCard>(find.byType(KeycardCard).first).iconId, 'flame');
  });
}
