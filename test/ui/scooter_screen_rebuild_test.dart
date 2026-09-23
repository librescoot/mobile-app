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
  int pauseConnectionCalls = 0;
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
  Future<void> pauseConnections() async => pauseConnectionCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service call: ${invocation.memberName}');
}

Future<void> _mount(
  WidgetTester tester,
  _Service service, {
  VoidCallback? onNavigateBack,
  Brightness brightness = Brightness.light,
}) async {
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
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: [
          FlutterI18nDelegate(
            translationLoader: FileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: const Locale('en'),
            ),
          ),
        ],
        home: ScooterScreen(onNavigateBack: onNavigateBack),
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

  testWidgets('card hierarchy stays stable and labels disconnected scooters', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    await _mount(tester, service);

    expect(find.text('Scooters'), findsOneWidget);
    expect(find.text('Your scooter is in drive mode! Vroom vroom!'), findsOneWidget);
    final visual = find.byType(ScooterSideVisual);
    expect(
      find.ancestor(
        of: visual,
        matching: find.byWidgetPredicate(
          (widget) => widget is Positioned && widget.top == 16 && widget.left == 0 && widget.right == 0,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: visual,
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onLongPress != null,
        ),
      ),
      findsOneWidget,
    );

    final card = find.byType(SavedScooterCard);
    final connectedHeight = tester.getSize(card).height;
    service.connected = false;
    service.state = ScooterState.disconnected;
    service.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Disconnected'), findsOneWidget);
    expect(tester.getSize(card).height, connectedHeight);
  });

  testWidgets('tapping the connected scooter returns to the main page without disconnecting', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    var navigations = 0;
    await _mount(tester, service, onNavigateBack: () => navigations++);

    await tester.tap(find.byType(SavedScooterCard));
    await tester.pump();

    expect(navigations, 1);
    expect(service.connected, isTrue);
    expect(service.currentScooterId, 'A');

    final second = _CountingScooter(id: 'B', name: 'Beta');
    service.savedScooters[second.id] = second;
    service.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.list));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SavedScooterListItem).first);
    await tester.pump();

    expect(navigations, 2);
    expect(service.connected, isTrue);
    expect(service.currentScooterId, 'A');
  });

  testWidgets('connected scooter disconnects from long press and the actions sheet', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    await _mount(tester, service);

    await tester.longPress(find.byType(SavedScooterCard));
    await tester.pump();
    expect(service.pauseConnectionCalls, 1);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(service.pauseConnectionCalls, 2);
  });

  testWidgets('animates a newly connected scooter to the top', (tester) async {
    final alpha = _CountingScooter(id: 'A', name: 'Alpha');
    final beta = _CountingScooter(id: 'B', name: 'Beta');
    final service = _Service([alpha, beta]);
    await _mount(tester, service);

    expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Beta')).dy));

    service.currentScooterId = 'B';
    service.notifyListeners();
    await tester.pump();

    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Beta')).dy, lessThan(tester.getTopLeft(find.text('Alpha')).dy));
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

    expect(find.text('Your scooter is in drive mode! Vroom vroom!'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.list));
    await tester.pumpAndSettle();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Your scooter is in drive mode! Vroom vroom!'), findsNothing);

    final listItems = find.byType(SavedScooterListItem);
    expect(
      find.ancestor(
        of: find.text('Live'),
        matching: find.byWidgetPredicate((widget) => widget is SizedBox && widget.height == 40),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(ScooterSideVisual),
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onLongPress != null,
        ),
      ),
      findsOneWidget,
    );
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
    expect(liveVisual.backdropColor, const Color(0xFFB8DCDD));
    expect(cachedVisual.backdropColor, const Color(0xFFB8DCDD));
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

  testWidgets('Eclipse artwork replaces the solid card and list backdrops', (tester) async {
    final eclipse = _CountingScooter(id: 'A', name: 'Eclipse', color: 7);
    final other = _CountingScooter(id: 'B', name: 'Other', color: 1);
    final service = _Service([eclipse, other]);
    await _mount(tester, service);

    ScooterSideVisual eclipseVisual() => tester
        .widgetList<ScooterSideVisual>(find.byType(ScooterSideVisual))
        .singleWhere((visual) => visual.imagePath.endsWith('side_7.webp'));
    expect(eclipseVisual().eclipseBackdrop, isTrue);
    await tester.tap(find.byIcon(Icons.list));
    await tester.pumpAndSettle();
    expect(eclipseVisual().eclipseBackdrop, isTrue);
  });

  testWidgets('confirmed Librescoot artwork keeps its subdued backdrop in dark mode', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service([scooter]);
    await _mount(tester, service, brightness: Brightness.dark);

    expect(tester.widget<ScooterSideVisual>(find.byType(ScooterSideVisual)).backdropColor,
        const Color(0xFF225661));
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
