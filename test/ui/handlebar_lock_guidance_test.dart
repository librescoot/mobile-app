import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_flutter.dart' hide HandlebarWarning;
import 'package:scooter_core/scooter_core.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/dialogs/handlebar_lock_guidance.dart';
import 'package:unustasis/ui/dialogs/handlebar_warning.dart';

class _Connection extends Fake implements SessionConnection {
  @override
  bool isCurrent = true;
  @override
  String id = 'A';
  @override
  int generation = 1;
}

class _Session extends Fake implements ScooterSession {
  @override
  SessionConnection? currentConnection = _Connection();
}

class _Actions extends Fake implements ScooterActions {
  @override
  final _Session session = _Session();
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  final _Actions actions = _Actions();
  @override
  final vehicle = VehicleStatus()..handlebarsLocked = false;
  @override
  ScooterVehicleState? get vehicleState => vehicle.vehicleState;
  @override
  bool? get handlebarsLocked => vehicle.handlebarsLocked;
  @override
  ScooterState? state = ScooterState.shuttingDown;
  @override
  bool connected = true;
  int commands = 0;
  @override
  Future<void> lock(
      {bool checkHandlebars = true, bool confirmOpenSeat = false, EventSource source = EventSource.app}) async {
    commands++;
  }

  @override
  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) async {
    commands++;
  }

  void changed() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final end in ['locked', 'timeout', 'disconnect', 'same-id', 'replacement', 'dispose']) {
    testWidgets('passive steering guidance dismisses on $end without commands or success', (tester) async {
      final service = _Service();
      var dismissed = 0;
      await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
          value: service,
          child: MaterialApp(
            localizationsDelegates: [
              FlutterI18nDelegate(
                  translationLoader: FileTranslationLoader(
                      basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))
            ],
            home: Scaffold(
                body: HandlebarLockGuidance(
                    service: service,
                    action:
                        const ActionEvent(scooterId: 'A', generation: 1, kind: EventType.lock, source: EventSource.app),
                    onDismiss: () => dismissed++)),
          )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Turn the handlebars fully left'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('powercycle'), findsNothing);
      if (end == 'locked') service.vehicle.handlebarsLocked = true;
      if (end == 'disconnect') service.connected = false;
      if (end == 'same-id') service.actions.session.currentConnection = _Connection()..generation = 2;
      if (end == 'replacement') service.actions.session.currentConnection = _Connection()..id = 'B';
      if (end == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else if (end == 'timeout') {
        await tester.pump(const Duration(seconds: 44));
        expect(dismissed, 0);
        await tester.pump(const Duration(seconds: 1));
      } else {
        service.changed();
        await tester.pump();
      }
      expect(dismissed, end == 'dispose' ? 0 : 1);
      expect(service.vehicle.handlebarsLocked, end == 'locked');
      expect(service.commands, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
      expect(dismissed, end == 'dispose' ? 0 : 1);
      service.dispose();
    });
  }
  testWidgets('WaitingSeatbox hides steering guidance until shutdown telemetry', (tester) async {
    final service = _Service()..state = ScooterState.waitingSeatbox;
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader:
                  FileTranslationLoader(basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))
        ],
        home: Scaffold(
            body: HandlebarLockGuidance(
                service: service,
                action: const ActionEvent(scooterId: 'A', generation: 1, kind: EventType.lock, source: EventSource.app),
                onDismiss: () {}))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Card), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    service.state = ScooterState.shuttingDown;
    service.changed();
    await tester.pump();
    expect(find.byType(Card), findsOneWidget);
    expect(service.commands, 0);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  testWidgets('unlock failure retains its separate lock action', (tester) async {
    final service = _Service();
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
        value: service,
        child: MaterialApp(localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader:
                  FileTranslationLoader(basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))
        ], home: const Scaffold(body: HandlebarWarning()))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TextButton), findsNWidgets(2));
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    expect(service.commands, 1);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
