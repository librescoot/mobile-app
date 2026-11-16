import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/cloud_pairing.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/cloud_pairing_screen.dart';

import '../support/inline_asset_bundle.dart';

class _Actions implements ScooterActions {
  bool supported = true;
  final calls = <String>[];
  CloudPairingStatus status = const CloudPairingStatus(state: 'not_registered', running: false);
  @override
  Future<bool> supportsCloudPairing() async => supported;
  @override
  Future<CloudPairingStatus> cloudPairing(String action) async {
    calls.add(action);
    if (action == 'start') {
      status = CloudPairingStatus(
          state: 'waiting_for_web_setup',
          running: true,
          code: 'ABCDE-12345',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)));
    }
    if (action == 'stop') status = const CloudPairingStatus(state: 'paused', running: false);
    return status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  String? currentScooterId = 'scooter-a';
  @override
  final Map<String, SavedScooter> savedScooters = {};
  @override
  final _Actions actions = _Actions();
  void changeScooter(String id) {
    currentScooterId = id;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _Service service) async {
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(
                basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('de')))
      ],
      home: const CloudPairingScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('opens only the Connect origin and places the code in the fragment', () {
    final uri = cloudPairingUrl('ABCDE-12345');
    expect(uri.origin, 'https://connect.librescoot.org');
    expect(uri.path, '/pair');
    expect(uri.hasQuery, isFalse);
    expect(uri.fragment, 'code=ABCDE-12345');
  });

  test('all locales provide the Connect pairing strings and scooter placeholder', () {
    final en = jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>;
    final keys = en.keys.where((key) => key.startsWith('connect_pairing_')).toSet();
    expect(keys.length, greaterThan(20));
    for (final locale in ['de', 'en', 'en_GB', 'fr', 'nl', 'pi']) {
      final values = jsonDecode(File('assets/i18n/$locale.json').readAsStringSync()) as Map<String, dynamic>;
      expect(keys.difference(values.keys.toSet()), isEmpty, reason: locale);
      for (final key in keys) {
        expect(values[key], isA<String>(), reason: '$locale: $key');
        expect((values[key] as String).contains('{scooter}'), (en[key] as String).contains('{scooter}'),
            reason: '$locale: $key');
      }
    }
  });

  testWidgets('requires confirmation before starting and can stop pairing', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);
    expect(service.actions.calls, ['status']);
    await tester.tap(find.text('Kopplung starten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('IMEI, ICCID und Seriennummer'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(service.actions.calls, ['status']);
    await tester.tap(find.text('Kopplung starten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopplung starten').last);
    await tester.pump();
    expect(service.actions.calls, ['status', 'start']);
    expect(find.text('ABCDE-12345'), findsOneWidget);
    expect(find.text('Connect öffnen'), findsOneWidget);
    await tester.ensureVisible(find.text('Kopplung anhalten'));
    await tester.tap(find.text('Kopplung anhalten'));
    await tester.pump();
    expect(service.actions.calls, ['status', 'start', 'stop']);
    expect(find.text('ABCDE-12345'), findsNothing);
  });

  testWidgets('polls until the scooter confirms the account connection', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);
    await tester.tap(find.text('Kopplung starten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopplung starten').last);
    await tester.pump();
    service.actions.status = const CloudPairingStatus(state: 'connected', running: false);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(service.actions.calls, ['status', 'start', 'status']);
    expect(find.text('Der Roller ist mit dem Konto verbunden.'), findsOneWidget);
    expect(find.text('Kopplung starten'), findsNothing);
    expect(find.text('ABCDE-12345'), findsNothing);
  });

  testWidgets('does not start on another scooter after confirmation opens', (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await _mount(tester, service);
    await tester.tap(find.text('Kopplung starten'));
    await tester.pumpAndSettle();
    service.changeScooter('scooter-b');
    await tester.pump();
    await tester.tap(find.text('Kopplung starten').last);
    await tester.pumpAndSettle();
    expect(service.actions.calls.where((action) => action == 'start'), isEmpty);
  });

  testWidgets('unsupported firmware cannot start pairing', (tester) async {
    final service = _Service()..actions.supported = false;
    addTearDown(service.dispose);
    await _mount(tester, service);
    expect(find.textContaining('unterstützt die Kopplung über Bluetooth noch nicht'), findsOneWidget);
    expect(service.actions.calls, isEmpty);
    expect(find.text('Kopplung starten'), findsNothing);
  });
}
