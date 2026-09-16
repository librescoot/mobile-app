import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/trip_counter.dart';
import 'package:scooter_core/trip_expunge.dart';
import 'package:scooter_flutter/trip_commands.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/settings_screen.dart';
import 'package:unustasis/ui/widgets/settings_help_row_theme.dart';

/// Reset, reset policy and history retention live in Settings now, so these
/// tests drive that section directly instead of the old Trip settings screen.
class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  TripCounterSnapshot? tripCounter;
  @override
  TripExpunge? tripExpunge = TripExpunge(TripExpungePolicy.age, '365d');
  @override
  bool? tripExpungeSupported = true;
  @override
  bool tripExpungeLoading = false;
  @override
  bool tripCounterLoading = false;
  int resets = 0;
  Object? resetError;
  final retentionWrites = <String>[];

  @override
  Future<TripCounterSnapshot?> refreshTripCounter() async => tripCounter;
  @override
  Future<TripExpunge?> refreshTripExpunge() async => tripExpunge;
  @override
  Future<void> setTripCounterResetPolicy(TripResetPolicy policy) async {}
  @override
  Future<void> resetTripCounter() async {
    if (resetError != null) throw resetError!;
    resets++;
  }

  @override
  Future<void> setTripExpunge(TripExpunge policy) async {
    retentionWrites.add(policy.wireValue);
    tripExpunge = policy;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service call: ${invocation.memberName}');
}

TripCounterSnapshot _snapshot() => TripCounterSnapshot(
      distanceMeters: 1200,
      ridingSeconds: 600,
      averageSpeedKph: 7,
      resetPolicy: TripResetPolicy.manual,
      lastReset: null,
      lastResetReason: TripResetReason.initial,
      generation: 1,
      status: TripCounterStatus.idle,
    );

Future<void> _mount(WidgetTester tester, _Service service) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider<ScooterService>.value(
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
        // Settings rows assume the help-row ListTile theme and a scrollable
        // parent, exactly as they get inside the real Settings screen.
        home: Scaffold(
          body: SettingsHelpRowTheme(
            child: ListView(children: const [RideStatsSettingsSection()]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows retention units and hides its value for never', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    expect(find.text('History retention'), findsOneWidget);
    expect(find.textContaining('Age'), findsOneWidget);

    await tester.tap(find.text('History retention'));
    await tester.pumpAndSettle();
    expect(find.text('Duration (for example, 168h or 365d)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<TripExpungePolicy>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never delete').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('retention validation does not send partial values', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    await tester.tap(find.text('History retention'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0d');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive duration, such as 168h or 365d.'), findsOneWidget);
    expect(service.retentionWrites, isEmpty);
  });

  testWidgets('saved retention is written with the chosen policy', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    await tester.tap(find.text('History retention'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '30d');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(service.retentionWrites, ['age:30d']);
  });

  testWidgets('retention is absent when the scooter does not report it', (tester) async {
    final service = _Service()
      ..tripCounter = _snapshot()
      ..tripExpungeSupported = false;
    await _mount(tester, service);
    expect(find.text('Reset now'), findsOneWidget);
    expect(find.text('History retention'), findsNothing);
  });

  testWidgets('requires confirmation before resetting', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    expect(find.text('Reset trip counter?'), findsOneWidget);
    expect(find.textContaining('does not delete trip history'), findsOneWidget);
    expect(service.resets, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.resets, 0);

    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Reset now')));
    await tester.pumpAndSettle();
    expect(service.resets, 1);
  });

  testWidgets('a reset transport timeout is reported as a timeout', (tester) async {
    final service = _Service()
      ..tripCounter = _snapshot()
      ..resetError = const TripResetException(TripResetFailure.timeout);
    await _mount(tester, service);
    await tester.tap(find.text('Reset now'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Reset now')));
    await tester.pumpAndSettle();
    expect(find.text('The scooter did not answer in time.'), findsOneWidget);
  });
}
