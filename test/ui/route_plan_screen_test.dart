import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/state/vehicle_status.dart';
import 'package:unustasis/ui/screens/navigation_screen.dart';
import 'package:unustasis/ui/screens/route_plan_screen.dart';
import 'package:unustasis/ui/screens/settings_screen.dart';
import 'package:unustasis/ui/widgets/photon_autocomplete.dart';

import '../support/persistence_fakes.dart';

class _PlanService extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  final identity = ScooterIdentity();
  @override
  final vehicle = VehicleStatus();
  @override
  bool demoMode = false;
  @override
  bool otaAvailable = false;
  @override
  bool autoUnlock = false;
  @override
  bool openSeatOnUnlock = false;
  @override
  bool hazardLocking = false;
  @override
  bool get tripCounterSupported => false;
  @override
  int get autoUnlockThreshold => -65;
  @override
  String? get currentScooterId => null;
  @override
  Map<String, SavedScooter> get savedScooters => {};
  @override
  Future<SavedScooter?> getMostRecentScooter() async => null;
  @override
  NavDestination? get pendingNavigation => null;
  @override
  NavDestination? get activeNavigation => null;

  List<NavDestination> stops = [];
  List<NavDestination> favorites = [];
  int step = 0;

  @override
  bool? navigationActive = false;

  final List<int> removed = [];
  final List<List<NavDestination>> reordered = [];
  int skipped = 0;
  int cleared = 0;

  @override
  List<NavDestination> get routePlanStops => List.of(stops);
  @override
  int get routePlanStep => step;
  @override
  bool get hasRoutePlan => stops.isNotEmpty;

  @override
  Future<void> refreshRoutePlan() async {}
  @override
  Future<List<NavDestination>> routePlanFavorites() async => favorites;

  @override
  Future<void> addRouteStop(NavDestination stop) async {
    stops = [...stops, stop];
    notifyListeners();
  }

  @override
  Future<void> removeRouteStop(int index) async {
    removed.add(index);
    final next = List.of(stops)..removeAt(index - 1);
    stops = next;
    notifyListeners();
  }

  @override
  Future<void> skipRouteStop() async {
    skipped++;
    notifyListeners();
  }

  @override
  Future<void> clearRoutePlan() async {
    cleared++;
    stops = [];
    notifyListeners();
  }

  @override
  Future<void> reorderRoutePlan(List<NavDestination> ordered) async {
    reordered.add(List.of(ordered));
    stops = List.of(ordered);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service call: ${invocation.memberName}');
}

NavDestination _stop(String name, double lat) => NavDestination(location: LatLng(lat, 13.4), name: name);

Future<void> _mount(WidgetTester tester, _PlanService service,
    {bool consent = false, Widget home = const RoutePlanScreen(), Size size = const Size(800, 1200)}) async {
  final previousPrefs = SharedPreferencesAsyncPlatform.instance;
  SharedPreferencesAsyncPlatform.instance = MemoryPreferences()..bools['osmConsent'] = consent;
  addTearDown(() => SharedPreferencesAsyncPlatform.instance = previousPrefs);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: EasyDynamicThemeWidget(
      initialThemeMode: ThemeMode.light,
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
        home: home,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty plan offers to add a stop', (tester) async {
    await _mount(tester, _PlanService());

    expect(find.text('No route planned'), findsOneWidget);
    expect(find.text('Add stop'), findsOneWidget);
  });

  testWidgets('online search is hidden in the route planner until consent is enabled', (tester) async {
    await _mount(tester, _PlanService());

    expect(find.text('Online Location Services are off'), findsOneWidget);
    await tester.tap(find.text('Add stop'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotonAutocomplete), findsNothing);
    expect(find.text('Online Location Services are off'), findsNWidgets(2));
  });

  testWidgets('saved destinations remain selectable while online search is off', (tester) async {
    final service = _PlanService()..favorites = [_stop('Home', 52.51)];
    await _mount(tester, service);
    await tester.tap(find.text('Add stop'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(service.stops.single.name, 'Home');
  });

  testWidgets('route-stop picker links to Settings instead of searching while disabled', (tester) async {
    await _mount(tester, _PlanService());
    await tester.tap(find.text('Add stop'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Online Location Services are off').last);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(PhotonAutocomplete), findsNothing);
  });

  testWidgets('notice opens the app setting and search is restored on return', (tester) async {
    await _mount(tester, _PlanService(), size: const Size(393, 852));
    await tester.tap(find.text('Online Location Services are off'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    final toggle = find.widgetWithText(SwitchListTile, 'Online Location Services');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect((SharedPreferencesAsyncPlatform.instance as MemoryPreferences).bools['osmConsent'], true);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Online Location Services are off'), findsNothing);
    await tester.tap(find.text('Add stop'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotonAutocomplete), findsOneWidget);
  });

  testWidgets('navigation notice opens Settings and refreshes search on return', (tester) async {
    final service = _PlanService()..connected = false;
    await _mount(tester, service, home: const NavigationScreen(), size: const Size(393, 852));

    expect(find.text('Online Location Services are off'), findsOneWidget);
    expect(find.byType(PhotonAutocomplete), findsNothing);
    await tester.tap(find.text('Online Location Services are off'));
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, 'Online Location Services');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Online Location Services are off'), findsNothing);
    expect(find.byType(PhotonAutocomplete), findsOneWidget);
  });

  testWidgets('place search remains available when consent is enabled', (tester) async {
    await _mount(tester, _PlanService(), consent: true);

    expect(find.text('Online Location Services are off'), findsNothing);
    await tester.tap(find.text('Add stop'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotonAutocomplete), findsOneWidget);
  });

  testWidgets('lists stops and highlights the current one', (tester) async {
    final service = _PlanService()
      ..stops = [_stop('Home', 52.51), _stop('Work', 52.52), _stop('Gym', 52.53)]
      ..step = 1;
    await _mount(tester, service);

    expect(find.text('Stop 2 of 3'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-stop-line-after-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-stop-line-before-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-destination-marker')), findsOneWidget);
  });

  testWidgets('removing a stop sends its 1-based index', (tester) async {
    final service = _PlanService()..stops = [_stop('Home', 52.51), _stop('Work', 52.52)];
    await _mount(tester, service);

    await tester.tap(find.byTooltip('Remove stop').first);
    await tester.pumpAndSettle();

    expect(service.removed, [1]);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('skip is disabled on the last stop', (tester) async {
    final service = _PlanService()..stops = [_stop('Home', 52.51)];
    await _mount(tester, service);

    final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Skip this stop'));
    expect(button.onPressed, isNull);

    service
      ..stops = [_stop('Home', 52.51), _stop('Work', 52.52)]
      ..step = 0
      ..notifyListeners();
    await tester.pumpAndSettle();

    final enabled = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Skip this stop'));
    expect(enabled.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip this stop'));
    await tester.pumpAndSettle();
    expect(service.skipped, 1);
  });

  testWidgets('clearing asks for confirmation first', (tester) async {
    final service = _PlanService()..stops = [_stop('Home', 52.51)];
    await _mount(tester, service);

    await tester.tap(find.byTooltip('Clear route'));
    await tester.pumpAndSettle();
    expect(service.cleared, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear route'));
    await tester.pumpAndSettle();
    expect(service.cleared, 1);
    expect(find.text('No route planned'), findsOneWidget);
  });

  testWidgets('reorder rebuilds the plan in the new order', (tester) async {
    final service = _PlanService()
      ..stops = [_stop('Home', 52.51), _stop('Work', 52.52)]
      ..step = 0;
    await _mount(tester, service);

    // Drag the second row's handle above the first row.
    final handle = find.byIcon(Icons.drag_handle).last;
    await tester.drag(handle, const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(service.reordered, hasLength(1));
    expect(service.reordered.single.map((stop) => stop.name), ['Work', 'Home']);
  });

  testWidgets('reorder asks before restarting an active guide', (tester) async {
    final service = _PlanService()
      ..stops = [_stop('Home', 52.51), _stop('Work', 52.52)]
      ..navigationActive = true;
    await _mount(tester, service);

    final handle = find.byIcon(Icons.drag_handle).last;
    await tester.drag(handle, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(service.reordered, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Reorder'));
    await tester.pumpAndSettle();
    expect(service.reordered, hasLength(1));
  });
}
