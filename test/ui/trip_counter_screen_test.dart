import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/trip_counter.dart';
import 'package:scooter_core/trip_expunge.dart';
import 'package:scooter_flutter/trip_commands.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/trip_counter_screen.dart';

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  bool? tripCounterSupported = true;
  @override
  bool tripCounterLoading = false;
  @override
  TripCounterSnapshot? tripCounter;
  @override
  bool? tripExpungeSupported = true;
  @override
  bool tripExpungeLoading = false;
  @override
  TripExpunge? tripExpunge = TripExpunge(TripExpungePolicy.age, '365d');
  var resets = 0;
  Object? resetError;
  final retentionWrites = <String>[];
  bool rejectRetentionWrite = false;

  @override
  Future<TripCounterSnapshot?> refreshTripCounter() async => tripCounter;
  @override
  Future<TripExpunge?> refreshTripExpunge() async => tripExpunge;
  @override
  Future<void> resetTripCounter() async {
    if (resetError != null) throw resetError!;
    resets++;
  }

  @override
  Future<void> setTripCounterResetPolicy(TripResetPolicy policy) async {}
  @override
  Future<void> setTripExpunge(TripExpunge policy) async {
    retentionWrites.add(policy.wireValue);
    if (rejectRetentionWrite) throw StateError('rejected');
    tripExpunge = policy;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service call: ${invocation.memberName}');
}

TripCounterSnapshot _snapshot() => TripCounterSnapshot(
      distanceMeters: 0,
      ridingSeconds: 0,
      averageSpeedKph: 0,
      resetPolicy: TripResetPolicy.manual,
      lastReset: TripTimestamp(DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000),
      lastResetReason: TripResetReason.manual,
      generation: 1,
      status: TripCounterStatus.idle,
    );

Future<void> _mount(WidgetTester tester, _Service service) async {
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
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
      home: const TripCounterScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows unsupported and disconnected states', (tester) async {
    final service = _Service()..tripCounterSupported = false;
    await _mount(tester, service);
    expect(find.text('This scooter does not support a trip counter.'), findsOneWidget);
    service
      ..connected = false
      ..notifyListeners();
    await tester.pump();
    expect(find.text('Connect to the scooter to view the trip counter.'), findsOneWidget);
  });

  testWidgets('shows genuine zero data and localized reset reason semantics', (tester) async {
    await _mount(tester, _Service()..tripCounter = _snapshot());
    expect(find.text('0.0 km'), findsOneWidget);
    expect(find.text('0h 0m'), findsOneWidget);
    expect(find.textContaining('Manual reset'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final semantics = tester.getSemantics(find.bySemanticsLabel('Reset now').last);
    expect(semantics.label, 'Reset now');
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('shows unsupported history retention separately from the trip counter', (tester) async {
    final service = _Service()
      ..tripCounter = _snapshot()
      ..tripExpungeSupported = false;
    await _mount(tester, service);
    expect(find.text('This scooter does not support history retention.'), findsOneWidget);
    expect(find.text('0.0 km'), findsOneWidget);
  });

  testWidgets('shows retention units and hides its value for never', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    expect(find.text('History retention'), findsOneWidget);
    expect(find.text('Duration (for example, 168h or 365d)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<TripExpungePolicy>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never delete').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('retention validation does not send partial values', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    await tester.enterText(find.byType(TextField), '0d');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive duration, such as 168h or 365d.'), findsOneWidget);
    expect(service.retentionWrites, isEmpty);
  });

  testWidgets('shows a reset transport timeout as a timeout', (tester) async {
    final service = _Service()
      ..tripCounter = _snapshot()
      ..resetError = const TripResetException(TripResetFailure.timeout);
    await _mount(tester, service);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Reset now').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset now').last);
    await tester.pumpAndSettle();
    expect(find.text('The scooter did not answer in time.'), findsOneWidget);
  });

  testWidgets('requires confirmation before resetting', (tester) async {
    final service = _Service()..tripCounter = _snapshot();
    await _mount(tester, service);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Reset now').last);
    await tester.pumpAndSettle();
    expect(find.text('Reset trip counter?'), findsOneWidget);
    expect(find.textContaining('does not delete trip history'), findsOneWidget);
    expect(service.resets, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.resets, 0);
  });
}
