import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';

import '../support/persistence_fakes.dart';

class _Ble extends Fake implements FlutterBluePlusMockable {
  @override
  Stream<bool> get isScanning => const Stream.empty();
}

void main() {
  late MemoryPreferences prefs;

  setUp(() {
    prefs = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = prefs;
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
  });

  test('keyless flags round-trip per scooter and default to off', () {
    final untouched = SavedScooter.fromJson('A', {'name': 'Alpha'});
    expect(untouched.autoUnlock, isFalse);
    expect(untouched.hazardLocking, isFalse);
    expect(untouched.openSeatOnUnlock, isFalse);

    final stored = SavedScooter.fromJson('B', {
      'name': 'Beta',
      'autoUnlock': true,
      'hazardLocking': true,
      'openSeatOnUnlock': true,
    });
    expect(stored.autoUnlock, isTrue);
    expect(stored.toJson()['autoUnlock'], isTrue);
    expect(stored.toJson()['hazardLocking'], isTrue);
    expect(stored.toJson()['openSeatOnUnlock'], isTrue);
  });

  test('migration copies the phone-wide choice onto every scooter once', () async {
    prefs.values['savedScooters'] = '{"A":{"name":"Alpha"},"B":{"name":"Beta"}}';
    prefs.bools['autoUnlock'] = true;
    prefs.bools['openSeatOnUnlock'] = true;
    prefs.bools['hazardLocking'] = false;
    final service = ScooterService(_Ble(), initializeRuntime: false);
    addTearDown(service.dispose);
    await service.settings.restore();
    await service.store.load();

    await service.migrateKeylessSettings();
    expect(service.savedScooters['A']!.autoUnlock, isTrue);
    expect(service.savedScooters['A']!.openSeatOnUnlock, isTrue);
    expect(service.savedScooters['B']!.autoUnlock, isTrue);
    expect(prefs.bools['scooterSettingsMigrated'], isTrue);

    // A later change to the legacy keys must not reach the scooters again.
    service.savedScooters['A']!.autoUnlock = false;
    prefs.bools['autoUnlock'] = true;
    await service.migrateKeylessSettings();
    expect(service.savedScooters['A']!.autoUnlock, isFalse);
  });

  test('settings target the connected scooter, else the most recent one', () async {
    final later = DateTime.now().add(const Duration(hours: 1)).microsecondsSinceEpoch;
    prefs.values['savedScooters'] =
        '{"A":{"name":"Alpha","autoUnlock":true,"lastPing":1},"B":{"name":"Beta","lastPing":$later}}';
    final service = ScooterService(_Ble(), initializeRuntime: false);
    addTearDown(service.dispose);
    await service.settings.restore();
    await service.store.load();

    expect(service.settingsTargetScooter?.name, 'Beta');
    expect(service.autoUnlock, isFalse);
    service.savedScooters['B']!.autoUnlock = true;
    expect(service.autoUnlock, isTrue);
    service.setOpenSeatOnUnlock(true);
    expect(service.savedScooters['B']!.openSeatOnUnlock, isTrue);
    expect(service.savedScooters['A']!.openSeatOnUnlock, isFalse);
  });
}
