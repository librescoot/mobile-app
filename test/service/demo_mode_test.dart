import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:latlong2/latlong.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/nav_destination.dart';
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

  test('demo mode advertises Librescoot capabilities and restores the live action owner', () async {
    final service = ScooterService(_Ble(), initializeRuntime: false, isInBackgroundService: true);
    addTearDown(service.dispose);
    final liveActions = service.actions;

    service.addDemoData();

    expect(service.identity.isLibrescoot, isTrue);
    expect(service.identity.supportsRoutePlans, isTrue);
    expect(service.identity.navigationCapabilityVersion, 2);
    expect(service.identity.supportsHibernateFor, isTrue);
    expect(service.identity.supportsScheduledHibernation, isTrue);
    expect(service.identity.supportsBatteryKeepActive, isTrue);
    expect(service.identity.supportsApnConfig, isTrue);
    expect(service.identity.supportsBondForget, isTrue);
    expect(service.identity.supportsAlarmControl, isTrue);
    expect(service.alarmAvailable, isTrue);
    expect(service.vehicle.alarmStatus, AlarmStatus.disarmed);
    expect(service.identity.supportsServiceMode, isTrue);
    expect(service.identity.supportsClockSync, isTrue);
    expect(service.identity.supportsUsbMode, isTrue);
    expect(service.identity.supportsTripCounter, isTrue);
    expect(service.identity.supportsTripExpunge, isTrue);
    expect(service.identity.supportsPhoneKeyManagement, isTrue);
    expect(service.identity.supportsKeyAliases, isTrue);
    expect(service.actions, isNot(same(liveActions)));
    expect(service.savedScooters.values.every((scooter) => scooter.isLibrescoot == true), isTrue);

    service.removeDemoData();
    expect(service.actions, same(liveActions));
    expect(service.identity.supportsKeyAliases, isNull);
    expect(service.identity.supportsRoutePlans, isFalse);
  });

  test('demo controls change only simulated scooter state and credentials', () async {
    final service = ScooterService(_Ble(), initializeRuntime: false, isInBackgroundService: true);
    addTearDown(service.dispose);
    service.addDemoData();
    final actions = service.actions;

    expect(await actions.listKeycards(), ['D3A00001', 'D3A00002']);
    final uid = service.addDemoKeycard();
    expect(uid, 'D3A00003');
    await actions.setKeyAlias('card', uid, 'Guest');
    expect((await actions.listKeyAliases())['card:$uid'], 'Guest');
    await actions.deleteKeycard(uid);
    expect(await actions.listKeycards(), ['D3A00001', 'D3A00002']);
    expect(await actions.listKeyAliases(), isEmpty);
    expect(await actions.listPhoneKeys(), hasLength(1));
    await actions.deletePhoneKey((await actions.listPhoneKeys()).single);
    expect(await actions.listPhoneKeys(), isEmpty);

    await actions.setCellularApn('demo.example');
    expect(await service.getCellularApn(), 'demo.example');
    await actions.setServiceMode(true);
    expect(await actions.getBoolSetting('dashboard.service-mode-active'), isTrue);
    await service.openSeat();
    expect(service.seatClosed, isFalse);
    await service.lock();
    expect(service.state, ScooterState.standby);
    await service.unlock();
    expect(service.state, ScooterState.parked);
    await service.setAlarmEnabled(false);
    expect(service.vehicle.alarmStatus, AlarmStatus.disabled);
    await service.setAlarmEnabled(true);
    expect(service.vehicle.alarmStatus, AlarmStatus.disarmed);
    await actions.enterUMSMode();
    expect(service.vehicle.usbMode, UsbMode.massStorage);
    await service.hibernate();
    expect(service.state, ScooterState.hibernating);
    await service.wakeUp();
    expect(service.state, ScooterState.standby);

    expect((await service.refreshTripCounter())?.distanceMeters, 12500);
    await service.setTripCounterResetPolicy(TripResetPolicy.day);
    expect(service.tripCounter?.resetPolicy, TripResetPolicy.day);
    await service.resetTripCounter();
    expect(service.tripCounter?.distanceMeters, 0);
    await service.setTripExpunge(TripExpunge(TripExpungePolicy.count, '5'));
    expect((await service.refreshTripExpunge())?.value, '5');
    final destination = NavDestination(location: const LatLng(52.5, 13.4), name: 'Demo destination');
    final favoriteId = await service.navigation.saveFavorite(destination);
    expect((await service.routePlanFavorites()).single.name, 'Demo destination');
    await service.navigation.navigate(destination);
    expect(service.activeNavigation?.name, 'Demo destination');
    expect(service.navigationActive, isTrue);
    await service.addRouteStop(destination);
    expect(service.routePlanStops.single.name, 'Demo destination');
    await service.navigation.cancel();
    expect(service.navigationActive, isFalse);
    await service.navigation.deleteFavorite(favoriteId);
    expect(await service.routePlanFavorites(), isEmpty);
    service.renameSavedScooter(id: '12345', name: 'Preview scooter');
    service.recolorSavedScooter(id: '12345', color: 5);
    expect(service.savedScooters['12345']?.name, 'Preview scooter');
    expect(service.savedScooters['12345']?.color, 5);
    service.setManualConnectionTarget('678910');
    expect(service.currentScooterId, '678910');
    expect(service.identity.supportsKeyAliases, isTrue);
    await service.forgetSavedScooter('678910');
    expect(service.currentScooterId, '12345');
    expect(await service.getSavedScooterIds(), ['12345']);
    final realThreshold = service.settings.autoUnlockThreshold;
    service.setAutoUnlockThreshold(realThreshold - 5);
    expect(service.autoUnlockThreshold, realThreshold - 5);
    expect(service.settings.autoUnlockThreshold, realThreshold);
    expect(service.store.scooters, isEmpty);
    expect(prefs.values, isEmpty);

    service.removeDemoData();
    expect(service.autoUnlockThreshold, realThreshold);
    service.addDemoData();
    expect(await service.actions.listKeycards(), ['D3A00001', 'D3A00002']);
    expect(await service.getCellularApn(), isEmpty);
    expect(service.tripCounter?.distanceMeters, 12500);
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
