import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

import '../support/inline_asset_bundle.dart';

class _Actions implements ScooterActions {
  final added = <String>[];

  @override
  Future<void> addKeycard(String uid) async => added.add(uid);

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
  final _actions = _Actions();
  @override
  ScooterActions get actions => _actions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(_Service service, {Locale locale = const Locale('en')}) => ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: locale,
            ),
          ),
        ],
        home: const LsKeycardScreen(),
      ),
    );

Future<void> _mount(WidgetTester tester, _Service service, {Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(_screen(service, locale: locale));
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
    expect(find.text('Enable NFC phone key'), findsNothing);

    await tester.tap(find.text('Use this Android phone as a key'));
    await tester.pumpAndSettle();
    expect(find.text('Enable NFC phone key'), findsNothing);
    expect(find.textContaining('app settings'), findsOneWidget);
    expect(find.textContaining('phone must be unlocked'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone key setup instructions are available in German', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = _Service();
    addTearDown(service.dispose);

    await _mount(tester, service, locale: const Locale('de'));
    await tester.tap(find.text('Dieses Android-Handy als Schlüssel nutzen'));
    await tester.pumpAndSettle();
    expect(find.text('NFC-Handyschlüssel aktivieren'), findsNothing);
    expect(find.textContaining('App-Einstellungen'), findsOneWidget);
    expect(find.textContaining('Handy entsperrt sein'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('canceling card enrollment closes reader mode without changing phone key preference', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const nfc = MethodChannel('flutter_nfc_kit/method');
    const phoneKey = MethodChannel('org.librescoot.mobile/phone_key');
    final poll = Completer<String>();
    final nfcCalls = <String>[];
    var finishes = 0;
    var polls = 0;
    var phoneKeyWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(nfc, (call) async {
      nfcCalls.add(call.method);
      switch (call.method) {
        case 'getNFCAvailability':
          return 'available';
        case 'poll':
          polls++;
          return poll.future;
        case 'finish':
          finishes++;
          return null;
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(phoneKey, (call) async {
      if (call.method == 'serviceEnabled') return true;
      if (call.method == 'setServiceEnabled') phoneKeyWrites++;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(nfc, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(phoneKey, null);
    });
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);
    await tester.tap(find.byType(FloatingActionButton));
    for (var attempt = 0; attempt < 20 && polls == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final errors = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().where((s) => s.contains('Failed to start NFC')).toList();
    expect(polls, 1, reason: 'NFC calls: $nfcCalls; errors: $errors');
    expect(poll.isCompleted, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(finishes, greaterThanOrEqualTo(1));
    expect(phoneKeyWrites, 0);
    poll.completeError(PlatformException(code: 'cancelled'));
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('completed card enrollment closes reader mode without changing phone key preference', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    const nfc = MethodChannel('flutter_nfc_kit/method');
    const phoneKey = MethodChannel('org.librescoot.mobile/phone_key');
    var polls = 0;
    var finishes = 0;
    var phoneKeyWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(nfc, (call) async {
      switch (call.method) {
        case 'getNFCAvailability':
          return 'available';
        case 'poll':
          polls++;
          return jsonEncode({'type': 'iso7816', 'id': 'FEEDCAFE', 'standard': 'ISO 14443-4'});
        case 'finish':
          finishes++;
          return null;
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(phoneKey, (call) async {
      if (call.method == 'serviceEnabled') return true;
      if (call.method == 'setServiceEnabled') phoneKeyWrites++;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(nfc, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(phoneKey, null);
    });
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);
    await tester.tap(find.byType(FloatingActionButton));
    for (var attempt = 0; attempt < 80 && service._actions.added.isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(polls, 2, reason: 'finishes=$finishes, lifecycle=${tester.binding.lifecycleState}, '
        'text=${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList()}');
    expect(finishes, greaterThanOrEqualTo(2));
    expect(phoneKeyWrites, 0);
    expect(service._actions.added, ['FEEDCAFE']);
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
