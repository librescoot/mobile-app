import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/screens/scooter_screen.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';

import '../support/persistence_fakes.dart';

/// Counts how often the card reads a field, which is a proxy for how often the
/// card rebuilt. Used to show that telemetry notifications no longer reach it.
class _CountingScooter extends SavedScooter {
  _CountingScooter({
    required super.id,
    required super.name,
    super.color,
    super.isLibrescoot,
    super.supportsHibernateFor,
  });

  int nameReads = 0;

  @override
  String get name {
    nameReads++;
    return super.name;
  }
}

class _Service extends ChangeNotifier implements ScooterService {
  _Service(List<_CountingScooter> scooters) {
    savedScooters = {for (final scooter in scooters) scooter.id: scooter};
    currentScooterId = scooters.first.id;
  }

  @override
  Map<String, SavedScooter> savedScooters = {};
  @override
  String? currentScooterId;
  @override
  bool connected = true;
  @override
  String? get selectedScooterId => currentScooterId;
  @override
  ScooterState? state = ScooterState.ready;
  @override
  String? connectingScooterId;
  @override
  Set<String> scootersInRange = {};
  @override
  bool scooterPresenceKnown = false;
  @override
  String? autoConnectPriorityId;
  @override
  Future<void> refreshScooterPresence() async {}
  @override
  int? odometerMeters = 4200;
  @override
  bool? handlebarsLocked = true;
  @override
  final identity = ScooterIdentity()
    ..isLibrescoot = true
    ..supportsHibernateFor = true;
  @override
  void refreshOdometer() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service call: ${invocation.memberName}');
}

Future<void> _mount(WidgetTester tester, _Service service) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 1600);
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
        home: const ScooterScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MemoryPreferences prefs;
  SharedPreferencesAsyncPlatform? previousPrefs;
  FlutterBackgroundServicePlatform? previousService;

  setUp(() {
    previousPrefs = SharedPreferencesAsyncPlatform.instance;
    try {
      previousService = FlutterBackgroundServicePlatform.instance;
    } catch (_) {
      previousService = null;
    }
    prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previousPrefs;
    if (previousService != null) FlutterBackgroundServicePlatform.instance = previousService!;
  });

  testWidgets('telemetry notifications do not rebuild the scooter cards', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    await _mount(tester, service);
    expect(find.text('Alpha'), findsOneWidget);

    final readsAfterFirstBuild = scooter.nameReads;
    expect(readsAfterFirstBuild, greaterThan(0));

    // A telemetry packet: the service notifies, nothing about the list changed.
    for (var i = 0; i < 5; i++) {
      service.notifyListeners();
      await tester.pump();
    }
    expect(scooter.nameReads, readsAfterFirstBuild);
  });

  testWidgets('card height stays stable across connection state changes', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    await _mount(tester, service);

    final card = find.byType(SavedScooterCard);
    final connectedHeight = tester.getSize(card).height;
    service.connected = false;
    service.state = ScooterState.disconnected;
    service.notifyListeners();
    await tester.pumpAndSettle();

    expect(tester.getSize(card).height, connectedHeight);
  });

  testWidgets('a card-local edit rebuilds only that card', (tester) async {
    final alpha = _CountingScooter(id: 'A', name: 'Alpha');
    final beta = _CountingScooter(id: 'B', name: 'Beta');
    final service = _Service([alpha, beta]);
    await _mount(tester, service);
    expect(find.text('Beta'), findsOneWidget);

    final alphaBefore = alpha.nameReads;
    final betaBefore = beta.nameReads;
    final betaCard = find.ancestor(of: find.text('Beta'), matching: find.byType(SavedScooterCard));
    final betaActions = find.descendant(of: betaCard, matching: find.byIcon(Icons.more_horiz));
    await tester.ensureVisible(betaActions);
    await tester.tap(betaActions);
    await tester.pumpAndSettle();
    final alphaAfterSheet = alpha.nameReads;
    final betaAfterSheet = beta.nameReads;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(beta.nameReads, greaterThan(betaAfterSheet));
    expect(alpha.nameReads, alphaAfterSheet);
    expect(betaAfterSheet, greaterThanOrEqualTo(betaBefore));
    expect(alphaAfterSheet, greaterThanOrEqualTo(alphaBefore));
  });

  testWidgets('list enlarges artwork and marks confirmed Librescoot identity with its backdrop', (tester) async {
    final live = _CountingScooter(id: 'A', name: 'Live', color: 1);
    final cached = _CountingScooter(
      id: 'B',
      name: 'Cached',
      color: 2,
      isLibrescoot: true,
      supportsHibernateFor: false,
    );
    final stock = _CountingScooter(id: 'C', name: 'Stock', color: 3, isLibrescoot: false);
    final service = _Service([live, cached, stock]);
    await _mount(tester, service);

    await tester.tap(find.byIcon(Icons.list));
    await tester.pumpAndSettle();

    final listItems = find.byType(SavedScooterListItem);
    expect(
      find.ancestor(
        of: listItems.first,
        matching: find.byWidgetPredicate(
          (widget) => widget is Padding && widget.padding == const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: listItems.first,
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.padding == const EdgeInsets.all(8),
        ),
      ),
      findsOneWidget,
    );

    final visuals = tester.widgetList<ScooterSideVisual>(find.byType(ScooterSideVisual)).toList();
    expect(visuals, hasLength(3));
    final liveVisual = visuals.singleWhere((visual) => visual.imagePath.endsWith('side_1.webp'));
    final cachedVisual = visuals.singleWhere((visual) => visual.imagePath.endsWith('side_2.webp'));
    final stockVisual = visuals.singleWhere((visual) => visual.imagePath.endsWith('side_3.webp'));
    expect(liveVisual.height, closeTo(412 * 0.18, 0.01));
    expect(liveVisual.backdropColor, const Color(0xFF33474B));
    expect(cachedVisual.backdropColor, const Color(0xFF33474B));
    expect(stockVisual.backdropColor, isNull);

    live.isLibrescoot = true;
    service.identity
      ..isLibrescoot = true
      ..supportsHibernateFor = null;
    service.notifyListeners();
    await tester.pump();
    final unconfirmedLiveVisual = tester
        .widgetList<ScooterSideVisual>(find.byType(ScooterSideVisual))
        .singleWhere((visual) => visual.imagePath.endsWith('side_1.webp'));
    expect(unconfirmedLiveVisual.backdropColor, isNull);

    service.identity
      ..isLibrescoot = false
      ..supportsHibernateFor = false;
    service.notifyListeners();
    await tester.pump();
    final stockLiveVisual = tester
        .widgetList<ScooterSideVisual>(find.byType(ScooterSideVisual))
        .singleWhere((visual) => visual.imagePath.endsWith('side_1.webp'));
    expect(stockLiveVisual.backdropColor, isNull);

    for (final icon in tester.widgetList<Icon>(find.byIcon(Icons.more_horiz))) {
      expect(icon.size, 22);
    }
    for (final icon in tester.widgetList<Icon>(find.byIcon(Icons.radio_button_unchecked))) {
      expect(icon.size, 16);
    }
  });

  testWidgets('stale Bluetooth warning stays compact and opens guidance', (tester) async {
    final alpha = _CountingScooter(id: 'A', name: 'Alpha');
    final beta = _CountingScooter(id: 'B', name: 'Beta');
    final service = _Service([alpha, beta]);
    service.identity.bluetoothTableOutOfDate = true;
    await _mount(tester, service);

    expect(find.text('Refresh Bluetooth pairing'), findsOneWidget);
    expect(find.textContaining('Unlock the scooter before forgetting it'), findsNothing);

    await tester.tap(find.text('Refresh Bluetooth pairing'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unlock the scooter before forgetting it'), findsOneWidget);
    expect(find.text('Unlock scooter'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.list));
    await tester.pumpAndSettle();
    expect(find.text('Refresh Bluetooth pairing'), findsOneWidget);
  });

  testWidgets('list changes still rebuild the cards', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    await _mount(tester, service);

    final before = scooter.nameReads;
    // A connection attempt changes what the row shows, so it must get through.
    service.connected = false;
    service.state = ScooterState.linking;
    service.connectingScooterId = scooter.id;
    service.notifyListeners();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(scooter.nameReads, greaterThan(before));
  });
}
