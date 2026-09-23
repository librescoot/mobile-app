import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';

import '../support/persistence_fakes.dart';

class _Ble extends Fake implements FlutterBluePlusMockable {
  @override
  Stream<bool> get isScanning => const Stream.empty();

  @override
  bool get isScanningNow => true;

  @override
  Future<void> stopScan() async {}
}

void main() {
  late MemoryPreferences prefs;

  setUp(() {
    prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
  });

  test('demo mode leaves saved scooters untouched and restores them on exit', () async {
    prefs.values['savedScooters'] = '{"A":{"name":"Alpha","color":4,"lastPing":1}}';
    final service = ScooterService(
      _Ble(),
      initializeRuntime: false,
      isInBackgroundService: true,
    );
    addTearDown(service.dispose);
    await service.store.load();

    service.addDemoData();

    expect(service.demoMode, isTrue);
    expect(service.connected, isTrue);
    expect(service.savedScooters.keys, {'12345', '678910'});
    expect(service.store.scooters.keys, {'A'});

    await service.store.save();
    await drainPreferenceWrites();
    expect(prefs.saved.keys, {'A'});
    expect(prefs.saved['A']['name'], 'Alpha');

    service.removeDemoData();

    expect(service.demoMode, isFalse);
    expect(service.connected, isFalse);
    expect(service.savedScooters.keys, {'A'});
    expect(service.identity.name, 'Alpha');
  });

  test('demo mode cannot replace a live scooter session', () {
    final service = ScooterService(
      _Ble(),
      initializeRuntime: false,
      isInBackgroundService: true,
    );
    addTearDown(service.dispose);
    service.connected = true;

    service.addDemoData();

    expect(service.demoMode, isFalse);
    expect(service.savedScooters, isEmpty);
  });
}
