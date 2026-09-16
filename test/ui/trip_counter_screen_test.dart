import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/trip_counter.dart';
import 'package:scooter_core/trip_expunge.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/trip_counter_screen.dart';

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  String? currentScooterId;
  @override
  Map<String, SavedScooter> savedScooters = {};
  @override
  SavedScooter? get settingsTargetScooter {
    final current = savedScooters[currentScooterId];
    if (current != null) return current;
    return savedScooters.values.isEmpty ? null : savedScooters.values.first;
  }

  @override
  int? odometerMeters;
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

  @override
  void refreshOdometer() {}
  @override
  Future<TripCounterSnapshot?> refreshTripCounter() async => tripCounter;
  @override
  Future<TripExpunge?> refreshTripExpunge() async => tripExpunge;
  @override
  Future<void> setTripCounterResetPolicy(TripResetPolicy policy) async {}
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
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
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

  testWidgets('shows cached current scooter data and aggregate odometers offline', (tester) async {
    final service = _Service()
      ..connected = false
      ..tripCounterSupported = null
      ..savedScooters = {
        'A': SavedScooter(
          id: 'A',
          name: 'Alpha',
          cachedOdometerMeters: 1200,
          cachedTripCounter: _snapshot(),
        ),
        'B': SavedScooter(id: 'B', name: 'Beta', cachedOdometerMeters: 1800),
      };
    await _mount(tester, service);
    expect(find.text('Offline — showing the latest saved ride data.'), findsOneWidget);
    expect(find.text('1.2 km'), findsOneWidget);
    expect(find.text('All scooters'), findsOneWidget);
    expect(find.text('3.0 km'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    await tester.tap(find.text('Total odometer'));
    await tester.pumpAndSettle();
    expect(find.text('1.2 km'), findsNWidgets(2));
    expect(find.text('Alpha'), findsNWidgets(2));
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('hides live trip controls while only cached data is available', (tester) async {
    final service = _Service()
      ..tripCounterSupported = true
      ..currentScooterId = 'A'
      ..savedScooters = {
        'A': SavedScooter(
          id: 'A',
          name: 'Alpha',
          cachedOdometerMeters: 1200,
          cachedTripCounter: _snapshot(),
        ),
      };
    await _mount(tester, service);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byTooltip('Trip settings'), findsNothing);
    expect(find.byTooltip('Try again'), findsNothing);
  });
}
