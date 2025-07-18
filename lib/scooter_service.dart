import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_battery.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_keyless_distance.dart';
import '../domain/scooter_state.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';
import 'ble_command_service.dart';
import 'cloud_command_service.dart';
import 'cloud_service.dart';
import 'command_service.dart';

const bootingTimeSeconds = 25;
const keylessCooldownSeconds = 60;
const handlebarCheckSeconds = 5;

typedef ConfirmationCallback = Future<bool> Function();

class ScooterService with ChangeNotifier {
  final log = Logger('ScooterService');
  Map<String, SavedScooter> savedScooters = {};
  BluetoothDevice? myScooter; // reserved for a connected scooter!
  bool _foundSth = false; // whether we've found a scooter yet
  bool _autoRestarting = false;
  bool _autoUnlock = false;
  int _autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool _openSeatOnUnlock = false;
  bool _hazardLocking = false;
  bool _warnOfUnlockedHandlebars = true;
  bool _autoUnlockCooldown = false;
  SharedPreferences? prefs;
  late Timer _locationTimer, _manualRefreshTimer;
  late PausableTimer rssiTimer;
  bool optionalAuth = false;
  late CharacteristicRepository characteristicRepository;
  late ScooterReader _scooterReader;
  // get a random number
  late bool isInBackgroundService;
  // currently selected scooter
  String? _currentScooterId;
  String? get currentScooterId => _currentScooterId;
  BLECommandService? _bleCommands;
  late CloudCommandService _cloudCommands;
  late CloudService _cloudService;
  CloudService get cloudService => _cloudService;

  final FlutterBluePlusMockable flutterBluePlus;

  void ping() {
    try {
      savedScooters[myScooter!.remoteId.toString()]!.lastPing = DateTime.now();
      lastPing = DateTime.now();
      notifyListeners();
      updateBackgroundService({
        "lastPingInt": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e, stack) {
      log.severe("Couldn't save ping", e, stack);
    }
  }

  Future<void> _initializeCurrentScooter() async {
    // Only try to get most recent if we don't already have a current scooter
    if (_currentScooterId == null) {
      SavedScooter? mostRecentScooter = await getMostRecentScooter();
      if (mostRecentScooter != null) {
        _currentScooterId = mostRecentScooter.id;
        notifyListeners();
      }
    }
  }

  // On initialization...
  ScooterService(this.flutterBluePlus, {this.isInBackgroundService = false}) {
    // Load saved scooter ID and cached values from SharedPrefs
    SharedPreferences.getInstance().then((prefs) {
      this.prefs = prefs;

      savedScooters = getSavedScooters();
      log.info(["savedScooters", savedScooters]);

      _initializeCurrentScooter();
      seedStreamsWithCache();
      restoreCachedSettings();
    });

    // _bleCommands inited on BT connect

    _cloudService = CloudService(this);
    _cloudCommands = CloudCommandService(_cloudService, () => getCurrentCloudScooterId());
    log.info(
        ["setting _cloudCommands", _cloudCommands, getCurrentCloudScooterId()]);

    // update the "scanning" listener
    flutterBluePlus.isScanning.listen((isScanning) {
      scanning = isScanning;
    });

    // start the location polling timer
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        _pollLocation();
      }
    });
    rssiTimer = PausableTimer.periodic(const Duration(seconds: 3), () async {
      if (myScooter != null && myScooter!.isConnected && _autoUnlock) {
        try {
          rssi = await myScooter!.readRssi();
        } catch (e) {
          // probably not connected anymore
        }
        if (_autoUnlock &&
            _rssi != null &&
            _rssi! > _autoUnlockThreshold &&
            _state == ScooterState.standby &&
            !_autoUnlockCooldown &&
            optionalAuth) {
          unlock();
          autoUnlockCooldown();
        }
      }
    })
      ..start();
    _manualRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        // only refresh state and seatbox, for now
        log.info("Auto-refresh...");
        characteristicRepository.stateCharacteristic!.read();
        characteristicRepository.seatCharacteristic!.read();
      }
    });
  }

  Future<void> restoreCachedSettings() async {
    _autoUnlock = prefs?.getBool("autoUnlock") ?? false;
    _autoUnlockThreshold = prefs?.getInt("autoUnlockThreshold") ??
        ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(prefs?.getBool("biometrics") ?? false);
    _openSeatOnUnlock = prefs?.getBool("openSeatOnUnlock") ?? false;
    _hazardLocking = prefs?.getBool("hazardLocking") ?? false;
    _warnOfUnlockedHandlebars =
        prefs?.getBool("unlockedHandlebarsWarning") ?? true;
  }

  SavedScooter? getCurrentSavedScooter() {
    log.info(["getCurrentSavedScooter", _currentScooterId]);
    if (_currentScooterId == null) return null;
    return savedScooters[_currentScooterId];
  }

  void setCloudScooterId(int cloudId) {
    if (_currentScooterId != null) {
      savedScooters[_currentScooterId]?.cloudScooterId = cloudId;
      savedScooters[_currentScooterId]?.updateSharedPreferences();
      notifyListeners();
    }
  }

  int? getCurrentCloudScooterId() {
    log.info(["getCurrentCloudScooterId", getCurrentSavedScooter()?.cloudScooterId]);
    return getCurrentSavedScooter()?.cloudScooterId;
  }

  Future<SavedScooter?> getMostRecentScooter() async {
    SavedScooter? mostRecentScooter;
    // don't seed with scooters that have auto-connect disabled
    List<SavedScooter> autoConnectScooters =
        filterAutoConnectScooters(savedScooters).values.toList();
    // get the saved scooter with the most recent ping
    for (var scooter in autoConnectScooters) {
      if (mostRecentScooter == null ||
          scooter.lastPing.isAfter(mostRecentScooter.lastPing)) {
        mostRecentScooter = scooter;
      }
    }
    return mostRecentScooter;
  }

  void setMostRecentScooter(String id) async {
    Map<String, SavedScooter> autoConnectScooters =
        filterAutoConnectScooters(savedScooters);
    if (autoConnectScooters[id] != null) {
      savedScooters[id]!.lastPing = DateTime.now();
      scooterName = savedScooters[id]!.name;
    } else {
      // this may be the most recent, but we'll ignore it since it's not an auto-connect scooter
    }
  }

  Future<void> seedStreamsWithCache() async {
    SavedScooter? mostRecentScooter = await getMostRecentScooter();
    // assume this is the one we'll connect to, and seed the streams
    _lastPing = mostRecentScooter?.lastPing;
    _primarySOC = mostRecentScooter?.lastPrimarySOC;
    _secondarySOC = mostRecentScooter?.lastSecondarySOC;
    _cbbSOC = mostRecentScooter?.lastCbbSOC;
    _auxSOC = mostRecentScooter?.lastAuxSOC;
    _scooterName = mostRecentScooter?.name;
    _scooterColor = mostRecentScooter?.color;
    _lastLocation = mostRecentScooter?.lastLocation;
    print("Last scooter name: ${_scooterName}");
    return;
  }

  void addDemoData() {
    savedScooters = {
      "12345": SavedScooter(
        name: "Demo Scooter",
        id: "12345",
        color: 1,
        lastPing: DateTime.now(),
        lastLocation: const LatLng(0, 0),
        lastPrimarySOC: 53,
        lastSecondarySOC: 100,
        lastCbbSOC: 98,
        lastAuxSOC: 100,
      ),
      "678910": SavedScooter(
        name: "Demo Scooter 2",
        id: "678910",
        color: 2,
        lastPing: DateTime.now(),
        lastLocation: const LatLng(0, 0),
        lastPrimarySOC: 53,
        lastSecondarySOC: 100,
        lastCbbSOC: 98,
        lastAuxSOC: 100,
      ),
    };

    myScooter = BluetoothDevice(remoteId: const DeviceIdentifier("12345"));

    _primarySOC = 53;
    _secondarySOC = 100;
    _cbbSOC = 98;
    _cbbVoltage = 15000;
    _cbbCapacity = 33000;
    _cbbCharging = false;
    _auxSOC = 100;
    _auxVoltage = 15000;
    _auxCharging = AUXChargingState.absorptionCharge;
    _primaryCycles = 190;
    _secondaryCycles = 75;
    _connected = true;
    _state = ScooterState.parked;
    _seatClosed = true;
    _handlebarsLocked = false;
    _lastPing = DateTime.now();
    _scooterName = "Demo Scooter";

    notifyListeners();
  }

  // STATUS STREAMS
  bool _connected = false;
  bool get connected => _connected;
  set connected(bool connected) {
    _connected = connected;
    notifyListeners();
  }

  ScooterState? _state = ScooterState.disconnected;
  ScooterState? get state => _state;
  set state(ScooterState? state) {
    _state = state;
    notifyListeners();
  }

  bool? _seatClosed;
  bool? get seatClosed => _seatClosed;
  set seatClosed(bool? seatClosed) {
    _seatClosed = seatClosed;
    notifyListeners();
  }

  bool? _handlebarsLocked;
  bool? get handlebarsLocked => _handlebarsLocked;
  set handlebarsLocked(bool? handlebarsLocked) {
    _handlebarsLocked = handlebarsLocked;
    notifyListeners();
  }

  int? _auxSOC;
  int? get auxSOC => _auxSOC;
  set auxSOC(int? auxSOC) {
    _auxSOC = auxSOC;
    notifyListeners();
  }

  int? _auxVoltage;
  int? get auxVoltage => _auxVoltage;
  set auxVoltage(int? auxVoltage) {
    _auxVoltage = auxVoltage;
    notifyListeners();
  }

  AUXChargingState? _auxCharging;
  AUXChargingState? get auxCharging => _auxCharging;
  set auxCharging(AUXChargingState? auxCharging) {
    _auxCharging = auxCharging;
    notifyListeners();
  }

  double? _cbbHealth;
  double? get cbbHealth => _cbbHealth;
  set cbbHealth(double? cbbHealth) {
    _cbbHealth = cbbHealth;
    notifyListeners();
  }

  int? _cbbSOC;
  int? get cbbSOC => _cbbSOC;
  set cbbSOC(int? cbbSOC) {
    _cbbSOC = cbbSOC;
    notifyListeners();
  }

  int? _cbbVoltage;
  int? get cbbVoltage => _cbbVoltage;
  set cbbVoltage(int? cbbVoltage) {
    _cbbVoltage = cbbVoltage;
    notifyListeners();
  }

  int? _cbbCapacity;
  int? get cbbCapacity => _cbbCapacity;
  set cbbCapacity(int? cbbCapacity) {
    _cbbCapacity = cbbCapacity;
    notifyListeners();
  }

  bool? _cbbCharging;
  bool? get cbbCharging => _cbbCharging;
  set cbbCharging(bool? cbbCharging) {
    _cbbCharging = cbbCharging;
    notifyListeners();
  }

  int? _primaryCycles;
  int? get primaryCycles => _primaryCycles;
  set primaryCycles(int? primaryCycles) {
    _primaryCycles = primaryCycles;
    notifyListeners();
  }

  int? _primarySOC;
  int? get primarySOC => _primarySOC;
  set primarySOC(int? primarySOC) {
    _primarySOC = primarySOC;
    notifyListeners();
  }

  int? _secondaryCycles;
  int? get secondaryCycles => _secondaryCycles;
  set secondaryCycles(int? secondaryCycles) {
    _secondaryCycles = secondaryCycles;
    notifyListeners();
  }

  int? _secondarySOC;
  int? get secondarySOC => _secondarySOC;
  set secondarySOC(int? secondarySOC) {
    _secondarySOC = secondarySOC;
    notifyListeners();
  }

  String? _scooterName;
  String? get scooterName => _scooterName;
  set scooterName(String? scooterName) {
    _scooterName = scooterName;
    notifyListeners();
  }

  DateTime? _lastPing;
  DateTime? get lastPing => _lastPing;
  set lastPing(DateTime? lastPing) {
    _lastPing = lastPing;
    notifyListeners();
  }

  int? _scooterColor;
  int? get scooterColor => _scooterColor;
  set scooterColor(int? scooterColor) {
    _scooterColor = scooterColor;
    notifyListeners();
    updateBackgroundService({"scooterColor": scooterColor});
  }

  LatLng? _lastLocation;
  LatLng? get lastLocation => _lastLocation;

  bool _scanning = false;
  bool get scanning => _scanning;
  set scanning(bool scanning) {
    log.info("Scanning: $scanning");
    _scanning = scanning;
    notifyListeners();
  }

  int? _rssi;
  int? get rssi => _rssi;
  set rssi(int? rssi) {
    _rssi = rssi;
    notifyListeners();
  }

  // MAIN FUNCTIONS

  Future<BluetoothDevice?> findEligibleScooter({
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
  }) async {
    try {
      stopAutoRestart();
      log.fine("Auto-restart stopped");
    } catch (e) {
      log.info("Didn't stop auto-restart, might not have been running yet");
    }

    if (includeSystemScooters) {
      log.fine("Searching system devices");
      List<BluetoothDevice> foundScooters = await getSystemScooters();
      if (foundScooters.isNotEmpty) {
        log.fine("Found system scooter");
        foundScooters = foundScooters.where(
          (foundScooter) {
            return !excludedScooterIds
                .contains(foundScooter.remoteId.toString());
          },
        ).toList();
        if (foundScooters.isNotEmpty) {
          log.fine("System scooter is not excluded from search, returning!");
          return foundScooters.first;
        }
      }
    }
    log.info("Searching nearby devices");
    await for (BluetoothDevice foundScooter
        in getNearbyScooters(preferSavedScooters: excludedScooterIds.isEmpty)) {
      log.fine("Found scooter: ${foundScooter.remoteId.toString()}");
      if (!excludedScooterIds.contains(foundScooter.remoteId.toString())) {
        log.fine("Scooter's ID is not excluded, stopping scan and returning!");
        flutterBluePlus.stopScan();
        return foundScooter;
      }
    }
    log.info("Scan over, nothing found");
    return null;
  }

  Future<List<BluetoothDevice>> getSystemScooters() async {
    // See if the phone is already connected to a scooter. If so, hook into that.
    List<BluetoothDevice> systemDevices = await flutterBluePlus
        .systemDevices([Guid("9a590000-6e67-5d0d-aab9-ad9126b66f91")]);
    List<BluetoothDevice> systemScooters = [];
    List<String> savedScooterIds =
        await getSavedScooterIds(onlyAutoConnect: true);
    for (var device in systemDevices) {
      // see if this is a scooter we saved and want to (auto-)connect to
      if (savedScooterIds.contains(device.remoteId.toString())) {
        // That's a scooter!
        systemScooters.add(device);
      }
    }
    return systemScooters;
  }

  Stream<BluetoothDevice> getNearbyScooters(
      {bool preferSavedScooters = true}) async* {
    List<BluetoothDevice> foundScooterCache = [];
    List<String> savedScooterIds =
        await getSavedScooterIds(onlyAutoConnect: true);
    if (savedScooterIds.isEmpty && savedScooters.isNotEmpty) {
      log.info(
          "We have ${savedScooters.length} saved scooters, but getSavedScooterIds returned an empty list. Probably no auto-connect enabled scooters, so we're not even scanning.");
      return;
    }
    if (savedScooters.isNotEmpty && preferSavedScooters) {
      log.info(
          "Looking for our scooters, since we have ${savedScooters.length} saved scooters");
      try {
        flutterBluePlus.startScan(
          withRemoteIds: savedScooterIds, // look for OUR scooter
          timeout: const Duration(seconds: 30),
        );
      } catch (e, stack) {
        log.severe("Failed to start scan", e, stack);
      }
    } else {
      log.info("Looking for any scooter, since we have no saved scooters");
      try {
        flutterBluePlus.startScan(
          withNames: [
            "unu Scooter",
          ], // if we don't have a saved scooter, look for ANY scooter
          timeout: const Duration(seconds: 30),
        );
      } catch (e, stack) {
        log.severe("Failed to start scan", e, stack);
      }
    }
    await for (var scanResult in flutterBluePlus.onScanResults) {
      if (scanResult.isNotEmpty) {
        ScanResult r = scanResult.last; // the most recently found device
        if (!foundScooterCache.contains(r.device)) {
          foundScooterCache.add(r.device);
          yield r.device;
        }
      }
    }
  }

  Future<void> connectToScooterId(
    String id, {
    bool initialConnect = false,
  }) async {
    log.info(["connectToScooterId", id, initialConnect]);
    // Set the current scooter ID
    _currentScooterId = id;
    notifyListeners();

    _foundSth = true;
    state = ScooterState.linking;

    try {
      // attempt to connect to what we found
      BluetoothDevice attemptedScooter = BluetoothDevice.fromId(id);
      // wait for the connection to be established
      log.info("Connecting to ${attemptedScooter.remoteId}");
      await attemptedScooter.connect(timeout: const Duration(seconds: 30));
      if (initialConnect && Platform.isAndroid) {
        await attemptedScooter.createBond(timeout: 30);
        log.info("Bond established");
      }
      log.info("Connected to ${attemptedScooter.remoteId}");

      // Set up this scooter as ours
      myScooter = attemptedScooter;
      setMostRecentScooter(id);
      updateBackgroundService({
        "mostRecent": id,
        "scooterName": savedScooters[myScooter!.remoteId.toString()]?.name,
        "lastPing": DateTime.now().millisecondsSinceEpoch,
      });
      addSavedScooter(myScooter!.remoteId.toString());

      try {
        await setUpCharacteristics(myScooter!);
      } on UnavailableCharacteristicsException {
        log.warning(
            "Some characteristics are null, if this turns out to be a rare issue we might display a toast here in the future");
        // Fluttertoast.showToast(
        // msg: "Scooter firmware outdated, some features may not work");
      }

      // save this as the last known location
      _pollLocation();
      // Let everybody know
      connected = true;
      scooterName = savedScooters[myScooter!.remoteId.toString()]?.name;
      scooterColor = savedScooters[myScooter!.remoteId.toString()]?.color;

      // listen for disconnects
      myScooter!.connectionState.listen((BluetoothConnectionState state) async {
        if (state == BluetoothConnectionState.disconnected) {
          connected = false;
          this.state = ScooterState.disconnected;

          log.info("Lost connection to scooter! :(");
          // Restart the process if we're not already doing so
          // start(); // this leads to some conflicts right now if the phone auto-connects, so we're not doing it
        }
      });
    } catch (e, stack) {
      // something went wrong, roll back!
      log.shout("Couldn't connect to scooter!", e, stack);
      _foundSth = false;
      state = ScooterState.disconnected;
      rethrow;
    }
  }

  // spins up the whole connection process, and connects/bonds with the nearest scooter
  void start({bool restart = true}) async {
    log.info("START called on service");
    // GETTING READY
    // Remove the splash screen
    Future.delayed(const Duration(milliseconds: 1500), () {
      FlutterNativeSplash.remove();
    });
    // Try to turn on Bluetooth (Android-Only)
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    // TODO: prompt users to turn on bluetooth manually

    // CLEANUP
    _foundSth = false;
    connected = false;
    state = ScooterState.disconnected;
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // SCAN
    // TODO: replace with getEligibleScooters, why do we still have this duplicated?!

    // First, see if the phone is already actively connected to a scooter
    List<BluetoothDevice> systemScooters = await getSystemScooters();
    if (systemScooters.isNotEmpty) {
      // get the first one, hook into its connection, and remember the ID for future reference
      connectToScooterId(systemScooters.first.remoteId.toString());
    } else {
      try {
        log.fine("Looking for nearby scooters");
        // If not, start scanning for nearby scooters
        getNearbyScooters().listen((foundScooter) async {
          // there's one! Attempt to connect to it
          flutterBluePlus.stopScan();
          connectToScooterId(foundScooter.remoteId.toString());
        });
      } catch (e, stack) {
        // Guess this one is not happy with us
        // TODO: Handle errors more elegantly
        log.severe("Error during search or connect!", e, stack);
        Fluttertoast.showToast(msg: "Error during search or connect!");
      }
    }

    if (restart) {
      startAutoRestart();
    }
  }

  late StreamSubscription<bool> _autoRestartSubscription;
  void startAutoRestart() async {
    if (!_autoRestarting) {
      _autoRestarting = true;
      _autoRestartSubscription =
          flutterBluePlus.isScanning.listen((scanState) async {
        // retry if we stop scanning without having found anything
        if (scanState == false && !_foundSth) {
          await Future.delayed(const Duration(seconds: 3));
          if (!_foundSth && !scanning && _autoRestarting) {
            // make sure nothing happened in these few seconds
            log.info("Auto-restarting...");
            start();
          }
        }
      });
    } else {
      log.info("Auto-restart already running, avoiding duplicate");
    }
  }

  void stopAutoRestart() {
    _autoRestarting = false;
    _autoRestartSubscription.cancel();
    log.fine("Auto-restart stopped.");
  }

  void setAutoUnlock(bool enabled) {
    _autoUnlock = enabled;
    prefs?.setBool("autoUnlock", enabled);
    updateBackgroundService({"autoUnlock": enabled});
  }

  void setAutoUnlockThreshold(int threshold) {
    _autoUnlockThreshold = threshold;
    prefs?.setInt("autoUnlockThreshold", threshold);
    updateBackgroundService({"autoUnlockThreshold": threshold});
  }

  void setOpenSeatOnUnlock(bool enabled) {
    _openSeatOnUnlock = enabled;
    prefs?.setBool("openSeatOnUnlock", enabled);
    updateBackgroundService({"openSeatOnUnlock": enabled});
  }

  void setHazardLocking(bool enabled) {
    _hazardLocking = enabled;
    prefs?.setBool("hazardLocking", enabled);
    updateBackgroundService({"hazardLocking": enabled});
  }

  bool get autoUnlock => _autoUnlock;
  int get autoUnlockThreshold => _autoUnlockThreshold;
  bool get openSeatOnUnlock => _openSeatOnUnlock;
  bool get hazardLocking => _hazardLocking;

  Future<void> setUpCharacteristics(BluetoothDevice scooter) async {
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected, can't set up characteristics!";
    }
    try {
      characteristicRepository = CharacteristicRepository(myScooter!);
      await characteristicRepository.findAll();

      _bleCommands = BLECommandService(myScooter, characteristicRepository);

      log.info(
          "Found all characteristics! StateCharacteristic is: ${characteristicRepository.stateCharacteristic}");
      _scooterReader = ScooterReader(
        characteristicRepository: characteristicRepository,
        service: this,
      );
      _scooterReader.readAndSubscribe();

      // check if any of the characteristics are null, and if so, throw an error
      if (characteristicRepository.anyAreNull()) {
        log.warning(
            "Some characteristics are null, throwing exception to warn further up the chain!");
        throw UnavailableCharacteristicsException();
      }
    } catch (e) {
      rethrow;
    }
  }

  // SCOOTER ACTIONS

  Future<void> unlock() async {
    await executeCommand(CommandType.unlock);
    HapticFeedback.heavyImpact();

    if (_openSeatOnUnlock) {
      await Future.delayed(const Duration(seconds: 1), () {
        openSeat();
      });
    }

    if (_hazardLocking) {
      await Future.delayed(const Duration(seconds: 2), () {
        hazard(times: 2);
      });
    }

    await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
      if (_handlebarsLocked == true) {
        log.warning("Handlebars didn't unlock, sending warning");
        throw HandlebarLockException();
      }
    });
  }

  Future<void> wakeUpAndUnlock() async {
    wakeUp();

    await _waitForScooterState(
        ScooterState.standby, const Duration(seconds: bootingTimeSeconds + 5));

    if (_state == ScooterState.standby) {
      unlock();
    }
  }

  Future<void> lock() async {
    if (_seatClosed == false) {
      log.warning("Seat seems to be open, checking again...");
      // make really sure nothing has changed
      await characteristicRepository.seatCharacteristic!.read();
      if (_seatClosed == false) {
        log.warning("Locking aborted, because seat is open!");

        throw SeatOpenException();
      } else {
        log.info("Seat state was $_seatClosed this time, proceeding...");
      }
    }

    // send the command
    await executeCommand(CommandType.lock);
    HapticFeedback.heavyImpact();

    if (_hazardLocking) {
      Future.delayed(const Duration(seconds: 1), () {
        hazard(times: 1);
      });
    }

    await Future.delayed(const Duration(seconds: handlebarCheckSeconds), () {
      if (_handlebarsLocked == false && _warnOfUnlockedHandlebars) {
        log.warning("Handlebars didn't lock, sending warning");
        throw HandlebarLockException();
      }
    });

    // don't immediately unlock again automatically
    autoUnlockCooldown();
  }

  void autoUnlockCooldown() {
    try {
      FlutterBackgroundService().invoke("autoUnlockCooldown");
    } catch (e) {
      // closing the loop
    }
    _autoUnlockCooldown = true;
    Future.delayed(const Duration(seconds: keylessCooldownSeconds), () {
      _autoUnlockCooldown = false;
    });
  }

  Future<void> openSeat() async {
    await executeCommand(CommandType.openSeat);
  }

  void sendNavigationCommand(String command) {
    _sendCommand(command);
  }

  void sendUpdateCommand(String command) {
    _sendCommand(command);
  }

  Future<void> blink({required bool left, required bool right}) async {
    if (left && !right) {
      await executeCommand(CommandType.blinkerLeft);
    } else if (!left && right) {
      await executeCommand(CommandType.blinkerRight);
    } else if (left && right) {
      await executeCommand(CommandType.blinkerBoth);
    } else {
      await executeCommand(CommandType.blinkerOff);
    }
  }

  Future<void> hazard({int times = 1}) async {
    await executeCommand(CommandType.blinkerBoth);
    await _sleepSeconds(0.6 * times);
    await executeCommand(CommandType.blinkerOff);
  }

  // Future<void> wakeUp() async {
  //   await executeCommand(CommandType.wakeUp);
  // }

  // Future<void> hibernate() async {
  //   await executeCommand(CommandType.hibernate);
  // }

  Future<void> wakeUp() async {
    _sendCommand("wakeup",
        characteristic:
            characteristicRepository.hibernationCommandCharacteristic);
  }

  Future<void> hibernate() async {
    _sendCommand("hibernate",
        characteristic:
            characteristicRepository.hibernationCommandCharacteristic);
  }

  void _pollLocation() async {
    // Test if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      log.warning("Location services are not enabled");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        log.warning("Location permissions are/were denied");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      log.info("Location permissions are denied forever");
      return;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    Position position = await Geolocator.getCurrentPosition();
    savedScooters[myScooter!.remoteId.toString()]!.lastLocation =
        LatLng(position.latitude, position.longitude);
  }

  // HELPER FUNCTIONS

  void _sendCommand(String command, {BluetoothCharacteristic? characteristic}) {
    log.fine("Sending command: $command");
    if (myScooter == null) {
      throw "Scooter not found!";
    }
    if (myScooter!.isDisconnected) {
      throw "Scooter disconnected!";
    }

    var characteristicToSend = characteristicRepository.commandCharacteristic;
    if (characteristic != null) {
      characteristicToSend = characteristic;
    }

    // commandCharcteristic should never be null, so we can assume it's not
    // if the given characteristic is null, we'll "fail" quitely by sending garbage to the default command characteristic instead

    try {
      characteristicToSend!.write(ascii.encode(command));
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> sendStaticPowerCommand(String id, String command) async {
    BluetoothDevice scooter = BluetoothDevice.fromId(id);
    if (scooter.isDisconnected) {
      await scooter.connect();
    }
    await scooter.discoverServices();
    BluetoothCharacteristic? commandCharacteristic =
        CharacteristicRepository.findCharacteristic(
            scooter,
            "9a590000-6e67-5d0d-aab9-ad9126b66f91",
            "9a590001-6e67-5d0d-aab9-ad9126b66f91");
    await commandCharacteristic!.write(ascii.encode(command));
  }

  Future<bool> attemptLatestAutoConnection() async {
    SavedScooter? latestScooter = await getMostRecentScooter();
    if (latestScooter != null) {
      try {
        await connectToScooterId(latestScooter.id);
        if (BluetoothDevice.fromId(latestScooter.id).isConnected) {
          return true;
        }
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  Future<void> _waitForScooterState(
      ScooterState expectedScooterState, Duration limit) async {
    Completer<void> completer = Completer<void>();

    // Check new state every 2s
    var timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      ScooterState? scooterState = _state;
      log.info("Waiting for $expectedScooterState, and got: $scooterState...");
      if (scooterState == expectedScooterState) {
        log.info("Found $expectedScooterState, cancel timer...");
        timer.cancel();
        completer.complete();
      }
    });

    // Clean up
    Future.delayed(limit, () {
      log.info("Timer limit reached after $limit");
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  Map<String, SavedScooter> getSavedScooters() {
    Map<String, SavedScooter> scooters = {};

    try {
      if (prefs!.containsKey("savedScooters")) {
        Map<String, dynamic> savedScooterData =
            jsonDecode(prefs!.getString("savedScooters")!)
                as Map<String, dynamic>;

        for (String id in savedScooterData.keys) {
          if (savedScooterData[id] is Map<String, dynamic>) {
            scooters[id] = SavedScooter.fromJson(id, savedScooterData[id]);

            // Migration stuff
            if (prefs!.containsKey("lastPing")) {
              scooters[id]!.lastPing = DateTime.fromMicrosecondsSinceEpoch(
                  prefs!.getInt("lastPing")!);
            }
            if (prefs!.containsKey("lastLat") &&
                prefs!.containsKey("lastLng")) {
              scooters[id]!.lastLocation = LatLng(
                  prefs!.getDouble("lastLat")!, prefs!.getDouble("lastLng")!);
            }
            if (prefs!.containsKey("color")) {
              scooters[id]!.color = prefs!.getInt("color")!;
            }
            if (prefs!.containsKey("primarySOC")) {
              scooters[id]!.lastPrimarySOC = prefs!.getInt("primarySOC");
            }
            if (prefs!.containsKey("secondarySOC")) {
              scooters[id]!.lastSecondarySOC = prefs!.getInt("secondarySOC");
            }
            if (prefs!.containsKey("cbbSOC")) {
              scooters[id]!.lastCbbSOC = prefs!.getInt("cbbSOC");
            }
            if (prefs!.containsKey("auxSOC")) {
              scooters[id]!.lastAuxSOC = prefs!.getInt("auxSOC");
            }

            // Remove old format
            prefs!.remove("lastPing");
            prefs!.remove("lastLat");
            prefs!.remove("lastLng");
            prefs!.remove("color");
            prefs!.remove("primarySOC");
            prefs!.remove("secondarySOC");
            prefs!.remove("cbbSOC");
            prefs!.remove("auxSOC");
          }
        }
      } else if (prefs!.containsKey("savedScooterId")) {
        // Migrate old caching scheme for the scooter ID
        String id = prefs!.getString("savedScooterId")!;

        SavedScooter newScooter = SavedScooter(
          name: "Scooter Pro",
          id: id,
          color: prefs?.getInt("color"),
          lastPing: prefs!.containsKey("lastPing")
              ? DateTime.fromMicrosecondsSinceEpoch(prefs!.getInt("lastPing")!)
              : null,
          lastLocation: prefs!.containsKey("lastLat")
              ? LatLng(
                  prefs!.getDouble("lastLat")!, prefs!.getDouble("lastLng")!)
              : null,
          lastPrimarySOC: prefs?.getInt("primarySOC"),
          lastSecondarySOC: prefs?.getInt("secondarySOC"),
          lastCbbSOC: prefs?.getInt("cbbSOC"),
          lastAuxSOC: prefs?.getInt("auxSOC"),
        );

        // Merge with existing scooters
        scooters[id] = newScooter;

        // Update the preference storage with the merged data
        prefs!.setString("savedScooters", jsonEncode(scooters));

        // Remove old format
        prefs!.remove("savedScooterId");
      }
    } catch (e, stack) {
      // Handle potential errors gracefully
      log.severe("Error fetching saved scooters", e, stack);
    }

    return scooters;
  }

  Map<String, SavedScooter> filterAutoConnectScooters(
      Map<String, SavedScooter> scooters) {
    // bypass filtering if there is only one scooter
    // (this might happen if the user has removed all but one scooter)
    if (scooters.length == 1) {
      return scooters;
    }
    Map<String, SavedScooter> filteredScooters = scooters;
    filteredScooters.removeWhere((key, value) => !value.autoConnect);
    return filteredScooters;
  }

  Future<List<String>> getSavedScooterIds(
      {bool onlyAutoConnect = false}) async {
    if (savedScooters.isNotEmpty) {
      if (onlyAutoConnect) {
        return filterAutoConnectScooters(savedScooters).keys.toList();
      } else {
        return savedScooters.keys.toList();
      }
    } else {
      // nothing saved locally yet, check prefs
      prefs ??= await SharedPreferences.getInstance();
      if (prefs!.containsKey("savedScooters")) {
        savedScooters = getSavedScooters();
        return savedScooters.keys.toList();
      } else if (prefs!.containsKey("savedScooterId")) {
        return [prefs!.getString("savedScooterId")!];
      } else {
        return [];
      }
    }
  }

  void forgetSavedScooter(String id) async {
    if (myScooter?.remoteId.toString() == id) {
      // this is the currently connected scooter
      stopAutoRestart();
      await myScooter?.disconnect();
      myScooter?.removeBond();
      myScooter = null;
    } else {
      // we're not currently connected to this scooter
      try {
        await BluetoothDevice.fromId(id).removeBond();
      } catch (e, stack) {
        log.severe("Couldn't forget scooter", e, stack);
      }
    }

    // if the ID is not specified, we're forgetting the currently connected scooter
    if (savedScooters.isNotEmpty) {
      savedScooters.remove(id);
      prefs ??= await SharedPreferences.getInstance();
      prefs!.setString("savedScooters", jsonEncode(savedScooters));

      // If the current scooter was forgotten, select a new one
      if (_currentScooterId == id) {
        _currentScooterId = null; // Clear current selection
        await _initializeCurrentScooter();
      }
    }
    connected = false;
    updateBackgroundService({"forgetSavedScooter": id});
    notifyListeners();
    if (Platform.isAndroid) {}
  }

  void renameSavedScooter({String? id, required String name}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log.warning(
          "Attempted to rename scooter, but no ID was given and we're not connected to anything!");
      return;
    }
    if (savedScooters[id] == null) {
      savedScooters[id] = SavedScooter(
        name: name,
        id: id,
      );
    } else {
      savedScooters[id]!.name = name;
    }

    prefs ??= await SharedPreferences.getInstance();
    prefs!.setString("savedScooters", jsonEncode(savedScooters));
    if ((await getMostRecentScooter())?.id == id) {
      // if we're renaming the most recent scooter, update the name immediately
      scooterName = name;
      updateBackgroundService({"scooterName": name});
    }
    // let the background service know too right away
    notifyListeners();
  }

  void updateBackgroundService(dynamic data) {
    if (!isInBackgroundService) {
      FlutterBackgroundService().invoke("update", data);
    }
  }

  void addSavedScooter(String id) async {
    if (savedScooters.containsKey(id)) {
      // we already know this scooter!
      return;
    }
    savedScooters[id] = SavedScooter(
      name: "Scooter Pro",
      id: id,
      color: 1,
      lastPing: DateTime.now(),
    );
    prefs ??= await SharedPreferences.getInstance();
    prefs!.setString("savedScooters", jsonEncode(savedScooters));
    scooterName = "Scooter Pro";
    updateBackgroundService({"addSavedScooter": id});

    // If this is the first scooter or we don't have a current selection,
    // set it as the current scooter
    if (savedScooters.length == 1 || _currentScooterId == null) {
      _currentScooterId = id;
      notifyListeners();
    }
  }

  Future<bool> isCommandAvailable(CommandType command) async {
    // Check BLE first if initialized
    if (_bleCommands != null && await _bleCommands!.isAvailable(command)) {
      return true;
    }
    // Check cloud availability
    return await _cloudCommands.isAvailable(command);
  }

  Future<void> executeCommand(
    CommandType command, {
    ConfirmationCallback? onNeedConfirmation,
  }) async {
    log.info("Executing command: $command");

    if (_bleCommands != null && await _bleCommands!.isAvailable(command)) {
      log.info("BLE exec: $command");
      if (!await _bleCommands!.execute(command)) {
        throw Exception("BLE command failed: $command");
      }
      return;
    }

    // Fall back to cloud if available
    if (await _cloudCommands.isAvailable(command)) {
      log.info("Cloud exec: $command");
      if (await _cloudCommands.needsConfirmation(command)) {
        // If confirmation callback provided, use it
        if (onNeedConfirmation != null) {
          bool confirmed = await onNeedConfirmation();
          if (!confirmed) {
            return;
          }
        } else {
          // No confirmation callback = deny command
          throw Exception(
              "Command requires confirmation but no callback provided");
        }
      }

      log.info("exec 2");

      if (!await _cloudCommands.execute(command)) {
        throw Exception("Cloud command failed: $command");
      }
      return;
    }

    throw Exception("Command not available: $command");
  }

  @override
  void dispose() {
    _locationTimer.cancel();
    rssiTimer.cancel();
    _manualRefreshTimer.cancel();
    super.dispose();
  }

  Future<void> _sleepSeconds(double seconds) {
    return Future.delayed(Duration(milliseconds: (seconds * 1000).floor()));
  }
}

class SeatOpenException {}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}
