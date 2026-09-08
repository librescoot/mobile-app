import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';

import '../support/persistence_fakes.dart';

class _Storage extends Fake implements ScooterStorage {
  @override
  Map<String, SavedScooter> scooters = {
    'A': SavedScooter(id: 'A', name: 'Alpha', color: 1),
    'B': SavedScooter(id: 'B', name: 'Beta', color: 2),
  };
  int loads = 0;
  final List<String> additions = [];

  @override
  Future<void> load() async {
    loads++;
  }

  @override
  Future<bool> add(String id) async {
    additions.add(id);
    return false; // Both test scooters are already saved; no plugin writes.
  }
}

class _Bluetooth extends Fake implements FlutterBluePlusMockable {
  int stops = 0;
  int scanStreamReads = 0;

  @override
  Stream<bool> get isScanning {
    scanStreamReads++;
    throw StateError('Runtime-disabled services must not subscribe to scanning');
  }

  @override
  Future<void> stopScan() async {
    stops++;
  }
}

class _Device extends Fake implements BluetoothDevice {
  _Device(String id) : remoteId = DeviceIdentifier(id);
  @override
  final DeviceIdentifier remoteId;
  final Completer<void> connection = Completer<void>();
  final List<Duration> timeouts = [];
  bool linked = false;
  int disconnects = 0;

  @override
  bool get isConnected => linked;
  @override
  bool get isDisconnected => !linked;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 35),
    int? mtu = 512,
    bool autoConnect = false,
  }) async {
    timeouts.add(timeout);
    await connection.future;
    linked = true;
  }

  @override
  Future<void> disconnect({int timeout = 35, bool queue = true, int androidDelay = 2000}) async {
    disconnects++;
    linked = false;
  }
}

class _Repository extends Fake implements CharacteristicRepository {
  final Completer<void> discovery = Completer<void>();
  final List<bool> requests = [];

  @override
  Future<void> findAll({bool additionalLibrescootFeatures = false}) {
    requests.add(additionalLibrescootFeatures);
    return discovery.future;
  }
}

class _Service extends ScooterService {
  _Service(super.flutterBluePlus, _Storage storage, Map<String, _Device> devices, List<String> deviceRequests,
      _Repository repository, List<BluetoothDevice> repositories)
      : super(
          storage: storage,
          initializeRuntime: false,
          deviceFromId: (id) {
            deviceRequests.add(id);
            return devices[id]!;
          },
          repositoryFactory: (device) {
            repositories.add(device);
            return repository;
          },
        );

  final List<Map<String, dynamic>> updates = [];
  @override
  void updateBackgroundService(dynamic data) {
    updates.add(Map<String, dynamic>.from(data as Map));
  }
}

// Linux exercises the actual connection method but not Android bonding/priority
// or iOS widgets. Stop at controlled connect/discovery failures, before live
// characteristic subscriptions, location polling and other native effects.
void main() {
  late SharedPreferencesAsyncPlatform? previousPreferences;
  late MemoryPreferences preferences;
  late _Storage storage;
  late _Bluetooth bluetooth;
  late Map<String, _Device> devices;
  late _Repository repository;
  late List<String> deviceRequests;
  late List<BluetoothDevice> repositories;
  late _Service service;
  late List<Future<Object?>> attempts;

  Future<void> drain() => Future<void>.delayed(Duration.zero);
  Future<Object?> connect(String id) {
    // Install an error handler immediately, including for teardown failures.
    final result =
        service.connectToScooterId(id).then<Object?>((_) => null, onError: (Object error, StackTrace _) => error);
    attempts.add(result);
    return result;
  }

  setUp(() {
    previousPreferences = SharedPreferencesAsyncPlatform.instance;
    preferences = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = preferences;
    storage = _Storage();
    bluetooth = _Bluetooth();
    devices = {'A': _Device('A'), 'B': _Device('B')};
    repository = _Repository();
    deviceRequests = [];
    repositories = [];
    attempts = [];
  });

  tearDown(() async {
    // Resolve only futures that have listeners. Drain before disposing so even
    // assertion failures cannot strand a connection or notify after disposal.
    for (final device in devices.values) {
      if (device.timeouts.isNotEmpty && !device.connection.isCompleted) {
        device.connection.completeError(StateError('teardown connection'));
      }
    }
    if (repository.requests.isNotEmpty && !repository.discovery.isCompleted) {
      repository.discovery.completeError(StateError('teardown discovery'));
    }
    await Future.wait(attempts);
    await drain();
    service.dispose();
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
  });

  void createService() {
    service = _Service(bluetooth, storage, devices, deviceRequests, repository, repositories);
  }

  test('runtime-disabled construction does not restore, scan or create timers', () async {
    int timers = 0;
    runZoned(createService,
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            timers++;
            return parent.createTimer(zone, duration, callback);
          },
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            timers++;
            return parent.createPeriodicTimer(zone, duration, callback);
          },
        ));
    await drain();
    expect(service.store, same(storage));
    expect(service.settings, isNotNull);
    expect(service.scanner, isNotNull);
    expect(storage.loads, 0);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    expect(bluetooth.scanStreamReads, 0);
    expect(bluetooth.stops, 0);
    expect(deviceRequests, isEmpty);
    expect(timers, 0);
    expect(service.state, ScooterState.disconnected);
    // tearDown also verifies disposal without initialized runtime timers.
  });

  test('manual target publishes intent and linking for the selected row', () async {
    createService();
    devices['A']!.linked = true;
    service.myScooter = devices['A'];
    service.connected = true;
    final linkingRows = <String?>[];
    service.addListener(() {
      if (service.state == ScooterState.linking) {
        linkingRows.add(service.connectingScooterId);
        expect(service.myScooter, isNull);
      }
    });
    final attempt = connect('B');
    await drain();
    expect(
        service.updates,
        contains(equals({
          'manualConnectionTarget': 'B',
          'scooterName': 'Beta',
          'scooterColor': 2,
        })));
    expect(linkingRows, isNotEmpty);
    expect(linkingRows, everyElement('B'));
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(service.scooterName, 'Beta');
    expect(service.connected, isFalse);
    expect(devices['A']!.disconnects, 1);
    expect(devices['B']!.timeouts, [const Duration(seconds: 30)]);
    expect(bluetooth.stops, 1);
    final failure = StateError('B unavailable');
    devices['B']!.connection.completeError(failure);
    expect(await attempt, same(failure));
    expect(service.state, ScooterState.disconnected);
    expect(service.connectingScooterId, isNull);
  });

  test('obsolete automatic generation is rejected after a manual intent', () async {
    createService();
    final manual = connect('B');
    await drain();
    final updates = service.updates.length;
    // A newly constructed service starts at generation zero; a manual request
    // invalidates a startup auto-connect carrying that original generation.
    await service.connectToScooterId('A', automatic: true, expectedIntentGeneration: 0);
    expect(deviceRequests, ['B']);
    expect(devices['A']!.timeouts, isEmpty);
    expect(service.updates.length, updates);
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(service.myScooter, isNull);
    devices['B']!.connection.completeError(StateError('B unavailable'));
    expect(await manual, isA<StateError>());
  });

  test('late older failure preserves newer linking attempt', () async {
    createService();
    final older = connect('A');
    await drain();
    final newer = connect('B');
    await drain();
    final failure = StateError('late A failure');
    devices['A']!.connection.completeError(failure);
    expect(await older, same(failure));
    expect(deviceRequests, ['A', 'B']);
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(service.myScooter, isNull);
    expect(devices['B']!.disconnects, 0);
    devices['B']!.connection.completeError(StateError('B unavailable'));
    expect(await newer, isA<StateError>());
    expect(service.state, ScooterState.disconnected);
  });

  test('late older failure preserves newer device during repository discovery', () async {
    createService();
    final older = connect('A');
    await drain();
    final newer = connect('B');
    await drain();
    devices['B']!.connection.complete();
    await drain();
    expect(repositories, [same(devices['B'])]);
    expect(repository.requests, [true]);
    expect(storage.additions, ['B']);
    expect(service.myScooter, same(devices['B']));
    devices['A']!.connection.completeError(StateError('late A failure'));
    expect(await older, isA<StateError>());
    expect(service.myScooter, same(devices['B']));
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(devices['B']!.disconnects, 0);
    final failure = StateError('controlled discovery failure');
    repository.discovery.completeError(failure);
    expect(await newer, same(failure));
    expect(service.myScooter, isNull);
    expect(service.state, ScooterState.disconnected);
    expect(preferences.writes, 0);
  });
}
