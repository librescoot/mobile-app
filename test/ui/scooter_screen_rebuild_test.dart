import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/screens/scooter_screen.dart';

import '../support/persistence_fakes.dart';

/// Counts how often the card reads a field, which is a proxy for how often the
/// card rebuilt. Used to show that telemetry notifications no longer reach it.
class _CountingScooter extends SavedScooter {
  _CountingScooter({required super.id, required super.name});

  int nameReads = 0;

  @override
  String get name {
    nameReads++;
    return super.name;
  }
}

class _Service extends ChangeNotifier implements ScooterService {
  _Service(this.scooter) {
    savedScooters = {scooter.id: scooter};
    currentScooterId = scooter.id;
  }

  final _CountingScooter scooter;
  @override
  Map<String, SavedScooter> savedScooters = {};
  @override
  String? currentScooterId;
  @override
  ScooterState? state = ScooterState.ready;
  @override
  String? connectingScooterId;
  @override
  int? odometerMeters = 4200;
  @override
  final identity = ScooterIdentity()..isLibrescoot = true;
  @override
  void refreshOdometer() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service call: ${invocation.memberName}');
}

Future<void> _mount(WidgetTester tester, _Service service) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 900);
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

  setUp(() {
    previousPrefs = SharedPreferencesAsyncPlatform.instance;
    prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = previousPrefs);

  testWidgets('telemetry notifications do not rebuild the scooter cards', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service(scooter);
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

  testWidgets('list changes still rebuild the cards', (tester) async {
    final scooter = _CountingScooter(id: 'A', name: 'Alpha');
    final service = _Service(scooter);
    await _mount(tester, service);

    final before = scooter.nameReads;
    // A connection attempt changes what the row shows, so it must get through.
    service.state = ScooterState.linking;
    service.connectingScooterId = scooter.id;
    service.notifyListeners();
    await tester.pump();
    expect(scooter.nameReads, greaterThan(before));
  });
}
