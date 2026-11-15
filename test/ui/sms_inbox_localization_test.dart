import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:scooter_flutter/sms_commands.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/sms_inbox_screen.dart';

import '../support/inline_asset_bundle.dart';

class _Actions implements ScooterActions {
  String forward = 'off';
  final writes = <String>[];
  final deleted = <String>[];
  final read = <String>[];
  Object? error;
  final messages = <SmsMessage>[
    const SmsMessage(
        id: 'a', from: '', text: 'Hallo Welt', timestamp: '2026-01-01', read: false, forwardStatus: 'unknown'),
  ];

  @override
  Future<SmsInbox> readSmsInbox() async {
    if (error != null) throw error!;
    return SmsInbox(List.of(messages), 1);
  }

  @override
  Future<String?> getSetting(String key) async => forward;
  @override
  Future<void> setSetting(String key, String value) async {
    writes.add(value);
    forward = value;
  }

  @override
  Future<void> markSmsRead(String id) async => read.add(id);
  @override
  Future<void> deleteSms(String id) async {
    deleted.add(id);
    messages.removeWhere((message) => message.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  String? currentScooterId = 'demo';
  @override
  final _Actions actions = _Actions();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _Service service, Locale locale) async {
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(
          basePath: 'assets/i18n',
          fallbackFile: 'en',
          forcedLocale: locale,
        ))
      ],
      home: const SmsInboxScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('all supported locales contain complete SMS translations', () {
    final english = jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>;
    final keys = english.keys.where((key) => key.startsWith('sms_')).toSet();
    expect(keys.length, greaterThan(20));
    for (final locale in ['de', 'en', 'en_GB', 'fr', 'nl', 'pi']) {
      final strings = jsonDecode(File('assets/i18n/$locale.json').readAsStringSync()) as Map<String, dynamic>;
      expect(keys.difference(strings.keys.toSet()), isEmpty, reason: locale);
      for (final key in keys) {
        expect(strings[key], isA<String>(), reason: '$locale: $key');
        expect((strings[key] as String).isNotEmpty, isTrue, reason: '$locale: $key');
        expect((strings[key] as String).contains('{status}'), (english[key] as String).contains('{status}'),
            reason: '$locale: $key parameters');
      }
    }
  });

  for (final (locale, title, forwarding) in [
    (const Locale('de'), 'Nachrichten', 'SMS-Weiterleitung'),
    (const Locale('en'), 'Messages', 'SMS forwarding'),
    (const Locale('en', 'GB'), 'Messages', 'SMS forwarding'),
    (const Locale('fr'), 'Messages', 'Transfert des SMS'),
    (const Locale('nl'), 'Berichten', 'Sms doorsturen'),
    (const Locale('pi'), 'Messages', 'Forward SMS'),
  ]) {
    testWidgets('message screen uses $locale strings', (tester) async {
      final service = _Service();
      addTearDown(service.dispose);
      await _mount(tester, service, locale);
      expect(find.text(title), findsOneWidget);
      expect(find.text(forwarding), findsOneWidget);
    });
  }

  testWidgets('German messages and forwarding preserve actions and validation', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service, const Locale('de'));
    expect(find.text('Nachrichten'), findsOneWidget);
    expect(find.text('SMS-Weiterleitung'), findsOneWidget);
    expect(find.text('Aus'), findsOneWidget);
    expect(find.text('Unbekannter Absender'), findsOneWidget);

    await tester.tap(find.text('Hallo Welt'));
    await tester.pumpAndSettle();
    expect(service.actions.read, ['a']);
    expect(find.text('Weiterleitung: Ergebnis unbekannt'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Nachricht löschen?'), findsOneWidget);
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    expect(service.actions.deleted, ['a']);
    expect(find.text('Keine Nachrichten'), findsOneWidget);

    await tester.tap(find.text('SMS-Weiterleitung'));
    await tester.pumpAndSettle();
    expect(find.text('Internationale Telefonnummer'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Gib eine vollständige internationale Telefonnummer ein.'), findsOneWidget);
    expect(service.actions.writes, isEmpty);
    await tester.tap(find.text('SMS-Weiterleitung'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '+4915112345678');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(service.actions.writes, ['+4915112345678']);
    expect(find.text('+4915112345678'), findsOneWidget);
  });

  testWidgets('unsupported firmware displays a localized error', (tester) async {
    final service = _Service()..actions.error = UnsupportedError('unsupported');
    addTearDown(service.dispose);
    await _mount(tester, service, const Locale('de'));
    expect(find.text('Die Firmware dieses Rollers unterstützt keine Nachrichten.'), findsOneWidget);
  });
}
