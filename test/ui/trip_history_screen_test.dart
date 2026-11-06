import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:scooter_flutter/trip_history_commands.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/trip_history_screen.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _trip = TripHistoryEntry(
    id: _id,
    startedAtSeconds: 1793343600,
    endedAtSeconds: 1793345280,
    distanceMeters: 8400,
    readyDurationSeconds: 1680,
    pointCount: 2,
    averageSpeedKmh: 18);

class _Actions implements ScooterActions {
  int listCalls = 0;
  bool detailMissing = false;
  @override
  Future<TripHistoryPage> readTripHistory({String? cursor, bool Function()? isActive}) async {
    listCalls++;
    return cursor == null ? const TripHistoryPage([_trip], 'next') : const TripHistoryPage([], null);
  }

  @override
  Future<TripHistoryEntry> readTripHistoryEntry(String id, {bool Function()? isActive}) async {
    if (detailMissing) throw const TripHistoryException('not-found');
    return _trip;
  }

  @override
  Future<TripHistoryPointsPage> readTripHistoryPoints(String id, {int afterId = 0, bool Function()? isActive}) async =>
      const TripHistoryPointsPage(
          [TripHistoryPoint(1, 1000, 52.5, 13.4), TripHistoryPoint(2, 2000, 52.51, 13.42)], null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  String? currentScooterId = 'scooter';
  @override
  final _Actions actions = _Actions();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('explains when a trip was removed', (tester) async {
    final service = _Service()..actions.detailMissing = true;
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
        value: service, child: const MaterialApp(home: TripHistoryScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8.4 km'));
    await tester.pumpAndSettle();
    expect(find.text('This trip is no longer stored'), findsOneWidget);
  });
  testWidgets('loads pages, details and offline GPS trace', (tester) async {
    final service = _Service();
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
        value: service, child: const MaterialApp(home: TripHistoryScreen())));
    await tester.pumpAndSettle();
    expect(find.text('8.4 km'), findsOneWidget);
    expect(find.text('More trips'), findsOneWidget);
    await tester.tap(find.text('More trips'));
    await tester.pumpAndSettle();
    expect(service.actions.listCalls, 2);
    expect(find.text('More trips'), findsNothing);
    await tester.tap(find.text('8.4 km'));
    await tester.pumpAndSettle();
    expect(find.text('View GPS trace'), findsOneWidget);
    await tester.tap(find.text('View GPS trace'));
    await tester.pumpAndSettle();
    expect(find.text('GPS trace without a basemap'), findsOneWidget);
    expect(find.text('Load online map'), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
    await tester.ensureVisible(find.text('Load online map'));
    await tester.tap(find.text('Load online map'));
    await tester.pumpAndSettle();
    expect(find.textContaining('your IP address'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsNothing);
    service.connected = false;
    service.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Trip unavailable'), findsOneWidget);
    expect(find.text('Load online map'), findsNothing);
  });
}
