import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_session.dart';
import 'package:scooter_flutter/scooter_telemetry.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:scooter_flutter/scooter_actions.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/widget_handler.dart';
import '../domain/statistics_helper.dart';
import 'package:scooter_core/scooter_battery.dart';
import '../domain/scooter_candidate.dart';
import '../domain/nav_destination.dart';
import '../domain/saved_scooter.dart';
import '../flutter/blue_plus_mockable.dart';
import '../infrastructure/characteristic_repository.dart';
import '../service/location_polling.dart' as location;
import '../state/scooter_identity.dart';
import '../service/scooter_storage.dart';
import '../service/ble_commands.dart' as commands;
import '../service/ble_scanner.dart';
import '../service/user_settings.dart';

export 'package:scooter_flutter/scooter_actions.dart'
    show ActionPollingTimer, keylessCooldownSeconds, handlebarCheckSeconds, wakeAndUnlockTimeout;

class ScooterService with ChangeNotifier, WidgetsBindingObserver {
  final log = Logger('ScooterService');

  // Composed modules
  final ScooterStorage store;
  final BluetoothDevice Function(String) _deviceFromId;
  late final ScooterSession _session;
  final Future<LatLng?> Function() _readLocation;
  final bool _runtimeInitialized;
  StreamSubscription<bool>? _scanSubscription;
  late final BleScanner scanner;
  late final UserSettings settings;

  // Observable state
  late final ScooterTelemetry _telemetry;
  BatteryState get battery => _telemetry.battery;
  VehicleStatus get vehicle => _telemetry.vehicle;
  final ScooterIdentity identity = ScooterIdentity();

  Map<String, SavedScooter> get savedScooters => store.scooters;
  set savedScooters(Map<String, SavedScooter> value) => store.scooters = value;

  // Compatibility escape hatches; the shared session owns the actual link.
  BluetoothDevice? get myScooter => _session.device;
  set myScooter(BluetoothDevice? value) => _session.device = value;
  String? get connectingScooterId => _session.connectingScooterId;
  // Set on the *background* isolate's service when the foreground reports a
  // manual connection in progress, so background auto-connect doesn't race it.
  String? _externalManualTargetId;
  DateTime? _externalManualTargetSince;
  NavDestination? _pendingNavigation;
  NavDestination? _activeNavigation;
  late final ScooterActions actions;
  final _actionWarnings = StreamController<HandlebarWarning>.broadcast(sync: true);
  Stream<HandlebarWarning> get actionWarnings => _actionWarnings.stream;
  bool get autoUnlockCoolingDown => actions.coolingDown;
  AppLifecycleState? _lastLifecycleState;
  bool _wasBackgrounded = false;

  late Timer _locationTimer;
  late final Timer _manualTargetHeartbeatTimer;
  late ActionPollingTimer rssiTimer;
  late CharacteristicRepository characteristicRepository;
  late bool isInBackgroundService;
  final FlutterBluePlusMockable flutterBluePlus;

  // Passthrough for optionalAuth (used by home_screen for biometrics)
  bool get optionalAuth => settings.optionalAuth;
  set optionalAuth(bool value) => settings.optionalAuth = value;

  void _telemetryChanged() => notifyListeners();

  void ping() => _pingScooter(myScooter?.remoteId.toString());

  void _pingScooter(String? scooterId) {
    try {
      savedScooters[scooterId]!.lastPing = DateTime.now();
      lastPing = DateTime.now();
      notifyListeners();
    } catch (e, stack) {
      log.severe("Couldn't save ping", e, stack);
    }
  }

  void _loadCachedData() async {
    await store.load();
    log.info(
      "Loaded ${savedScooters.length} saved scooters from SharedPreferences",
    );
    await _seedStreamsWithCache();
    log.info("Seeded streams with cached values");
    settings.restore();
  }

  // On initialization...
  /// Set [initializeRuntime] to false for manually driven tests: settings and
  /// scanner remain available, but cache restore, observers and timers do not run.
  /// In that mode [rssiTimer] is not initialized.
  ScooterService(
    this.flutterBluePlus, {
    this.isInBackgroundService = false,
    ScooterStorage? storage,
    BluetoothDevice Function(String)? deviceFromId,
    CharacteristicRepository Function(BluetoothDevice)? repositoryFactory,
    Future<LatLng?> Function()? pollLocation,
    bool initializeRuntime = true,
  }) : store = storage ?? ScooterStorage(),
       _deviceFromId = deviceFromId ?? BluetoothDevice.fromId,
       _readLocation = pollLocation ?? location.pollLocation,
       _runtimeInitialized = initializeRuntime {
    settings = UserSettings(isInBackgroundService: isInBackgroundService);
    scanner = BleScanner(flutterBluePlus);
    _telemetry = ScooterTelemetry(effects: _ServiceTelemetryEffects(this), identity: identity);
    _session = ScooterSession(
      flutterBluePlus: flutterBluePlus,
      deviceFromId: _deviceFromId,
      repositoryFactory: repositoryFactory,
      effects: _ServiceSessionEffects(this),
      onChanged: notifyListeners,
      findEligibleScooter: () => findEligibleScooter(),
      isScanning: () => scanning,
      onStart: () {
        Future.delayed(const Duration(milliseconds: 1500), FlutterNativeSplash.remove);
      },
    );
    actions = ScooterActions(session: _session, telemetry: _telemetry,
      settings: () => ActionSettings(openSeatOnUnlock: settings.openSeatOnUnlock,
        hazardLocking: settings.hazardLocking, warnOfUnlockedHandlebars: settings.warnOfUnlockedHandlebars,
        autoUnlock: settings.autoUnlock, autoUnlockThreshold: settings.autoUnlockThreshold,
        optionalAuth: settings.optionalAuth),
      location: () => lastLocation == null ? null : ActionLocation(lastLocation!.latitude, lastLocation!.longitude),
      effects: _ServiceActionEffects(this));
    if (!_runtimeInitialized) return;
    _loadCachedData();

    // Register for app lifecycle callbacks (only if not in background service)
    if (!isInBackgroundService) {
      WidgetsBinding.instance.addObserver(this);
      log.info("Registered for app lifecycle callbacks");
    }

    // Keep the background isolate's manual-target gate alive while the
    // user's explicit connection intent is active. The gate expires on its
    // own for safety, and the periodic re-arm also survives a background
    // isolate restart that would have swallowed the one-shot message.
    _manualTargetHeartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final target = _session.manualTargetId;
      if (target != null) updateBackgroundService({"manualConnectionTarget": target});
    });

    // update the "scanning" listener
    _scanSubscription = flutterBluePlus.isScanning.listen((isScanning) {
      scanning = isScanning;
    });

    // start the location polling timer
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (myScooter != null && myScooter!.isConnected) {
        _pollLocation();
      }
    });
    rssiTimer = actions.rssiTimer;
    actions.startPolling();
  }

  Future<SavedScooter?> getMostRecentScooter() async {
    SavedScooter? recent = store.getMostRecent();
    if (recent != null && savedScooters.length == 1 && savedScooters.values.first.autoConnect == true) {
      // store.getMostRecent() may have re-enabled autoConnect for a single scooter
      updateBackgroundService({"updateSavedScooters": true});
    }
    return recent;
  }

  void updateScooterPing(String id) async {
    store.updatePing(id);
    updateBackgroundService({"updateSavedScooters": true});
  }

  void _showCachedScooter(SavedScooter? scooter) {
    identity.lastPing = scooter?.lastPing;
    identity.name = scooter?.name;
    identity.color = scooter?.color;
    identity.lastLocation = scooter?.lastLocation;
    identity.rssi = null;
    _telemetry.seed(_cachedTelemetry(scooter));
    notifyListeners();
  }

  Future<void> _seedStreamsWithCache() async {
    SavedScooter? mostRecentScooter = await getMostRecentScooter();
    log.info("Most recent scooter: $mostRecentScooter");
    // Seed the disconnected home screen with the most likely automatic target.
    _showCachedScooter(mostRecentScooter);

    // Load pending navigation from persistent storage
    final prefs = SharedPreferencesAsync();
    final pendingJson = await prefs.getString('pendingNavigation');
    if (pendingJson != null) {
      try {
        _pendingNavigation = NavDestination.fromJson(
          jsonDecode(pendingJson) as Map<String, dynamic>,
        );
      } catch (_) {
        await prefs.remove('pendingNavigation');
      }
    }
    return;
  }

  void addDemoData() {
    stopAutoRestart(clearManualTarget: false);
    _session.foundScooter = true;
    flutterBluePlus.stopScan();
    savedScooters = {
      "12345": SavedScooter(
        name: "Demo Scooter",
        id: "12345",
        color: 0,
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

    battery.primarySOC = 53;
    battery.secondarySOC = 100;
    battery.cbbSOC = 98;
    battery.cbbVoltage = 3700;
    battery.cbbCapacity = 3000;
    battery.cbbCharging = false;
    battery.auxSOC = 100;
    battery.auxVoltage = 15000;
    battery.auxCharging = AUXChargingState.absorptionCharge;
    battery.primaryCycles = 190;
    battery.secondaryCycles = 75;
    _session.setConnected(true, notify: false);
    _state = ScooterState.parked;
    vehicle.seatClosed = true;
    vehicle.handlebarsLocked = false;
    vehicle.navigationActive = false;
    identity.lastPing = DateTime.now();
    identity.name = "Demo Scooter";

    store.save();
    updateBackgroundService({"updateSavedScooters": true});
    passToWidget(
      scooterId: "12345",
    );
    notifyListeners();
  }

  // PENDING NAVIGATION
  NavDestination? get pendingNavigation => _pendingNavigation;
  NavDestination? get activeNavigation => _activeNavigation;

  void setActiveNavigation(NavDestination? destination) {
    _activeNavigation = destination;
    notifyListeners();
  }

  Future<void> setPendingNavigation(NavDestination? dest) async {
    _pendingNavigation = dest;
    final prefs = SharedPreferencesAsync();
    if (dest != null) {
      await prefs.setString('pendingNavigation', jsonEncode(dest.toJson()));
    } else {
      await prefs.remove('pendingNavigation');
    }
    notifyListeners();
  }

  Future<void> _dispatchPendingNavigation() async {
    if (_pendingNavigation == null || myScooter == null) return;
    try {
      await commands.navigateCommand(
        myScooter!,
        characteristicRepository,
        _pendingNavigation!,
      );

      log.info('Pending navigation dispatched to ${_pendingNavigation!.name}');
      setActiveNavigation(_pendingNavigation);
      await setPendingNavigation(null);
    } catch (e) {
      log.warning('Pending navigation dispatch failed: $e');
    }
  }

  // STATUS STREAMS
  bool get connected => _session.connected;
  set connected(bool connected) => _session.connected = connected;

  ScooterState? get _state => _telemetry.state;
  set _state(ScooterState? value) => _telemetry.state = value;
  ScooterState? get state => _state;
  set state(ScooterState? state) {
    _state = state;
    notifyListeners();
    actions.telemetryChanged();
  }

  // Passthrough getters for vehicle status
  ScooterVehicleState? get vehicleState => vehicle.vehicleState;
  ScooterPowerState? get powerState => vehicle.powerState;
  bool? get seatClosed => vehicle.seatClosed;
  bool? get handlebarsLocked => vehicle.handlebarsLocked;
  bool? get navigationActive => vehicle.navigationActive;

  // Read-only total distance reported by Librescoot, in metres.
  int? get odometerMeters => identity.odometerMeters;

  void refreshOdometer() {
    if (connected) _telemetry.refreshOdometer();
  }

  // Passthrough getters for battery state
  int? get primarySOC => battery.primarySOC;
  int? get secondarySOC => battery.secondarySOC;

  // Passthrough getters for identity
  String? get scooterName => identity.name;
  set scooterName(String? value) {
    identity.name = value;
    notifyListeners();
  }

  DateTime? get lastPing => identity.lastPing;
  set lastPing(DateTime? value) {
    identity.lastPing = value;
    notifyListeners();
  }

  int? get scooterColor => identity.color;
  set scooterColor(int? value) {
    identity.color = value;
    notifyListeners();
    updateBackgroundService({"scooterColor": value});
  }

  LatLng? get lastLocation => identity.lastLocation;

  int? get rssi => identity.rssi;
  set rssi(int? value) {
    identity.rssi = value;
    notifyListeners();
  }

  bool _scanning = false;
  bool get scanning => _scanning;
  set scanning(bool scanning) {
    log.info("Scanning: $scanning");
    _scanning = scanning;
    notifyListeners();
  }

  // MAIN FUNCTIONS

  Future<BluetoothDevice?> findEligibleScooter({
    List<String> excludedScooterIds = const [],
    bool includeSystemScooters = true,
  }) async {
    stopAutoRestart();

    return scanner.findEligibleScooter(
      getIds: getSavedScooterIds,
      excludedScooterIds: excludedScooterIds,
      includeSystemScooters: includeSystemScooters,
    );
  }

  /// Live list of scooters the user could pick from, growing while the scan
  /// runs. Unlike [findEligibleScooter] this reports everything it finds and
  /// leaves the choice to the caller, and it includes scooters this phone has
  /// already bonded, which a scan on its own cannot see.
  Stream<List<ScooterCandidate>> discoverScooters({
    List<String> excludedScooterIds = const [],
    Duration timeout = const Duration(seconds: 30),
    bool androidCheckLocationServices = true,
  }) {
    stopAutoRestart();

    return scanner.discoverScooters(
      getIds: getSavedScooterIds,
      excludedScooterIds: excludedScooterIds,
      timeout: timeout,
      androidCheckLocationServices: androidCheckLocationServices,
    );
  }

  Future<void> connectToScooterId(
    String id, {
    bool automatic = false,
    int? expectedIntentGeneration,
  }) => _session.connectToScooterId(
    id,
    automatic: automatic,
    expectedIntentGeneration: expectedIntentGeneration,
  );

  void start({bool restart = true}) => _session.start(restart: restart);

  void startAutoRestart({String? targetScooterId}) =>
      _session.startAutoRestart(targetScooterId: targetScooterId);

  void stopAutoRestart({bool clearManualTarget = true}) =>
      _session.stopAutoRestart(clearManualTarget: clearManualTarget);

  void setAutoUnlock(bool enabled) {
    settings.setAutoUnlock(enabled);
  }

  void setAutoUnlockThreshold(int threshold) {
    settings.setAutoUnlockThreshold(threshold);
  }

  void setOpenSeatOnUnlock(bool enabled) {
    settings.setOpenSeatOnUnlock(enabled);
  }

  void setHazardLocking(bool enabled) {
    settings.setHazardLocking(enabled);
  }

  bool get autoUnlock => settings.autoUnlock;
  int get autoUnlockThreshold => settings.autoUnlockThreshold;
  bool get openSeatOnUnlock => settings.openSeatOnUnlock;
  bool get hazardLocking => settings.hazardLocking;

  // SCOOTER ACTIONS

  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) =>
      actions.unlock(checkHandlebars: checkHandlebars, source: source);
  Future<void> lock({bool checkHandlebars = true, EventSource source = EventSource.app}) {
    if (vehicle.seatClosed == false) log.warning("Locking with open seatbox!");
    return actions.lock(checkHandlebars: checkHandlebars, source: source);
  }
  Future<void> wakeUpAndUnlock({EventSource? source}) => actions.wakeUpAndUnlock(source: source);
  void autoUnlockCooldown() => actions.autoUnlockCooldown();
  Future<void> openSeat({EventSource source = EventSource.app}) => actions.openSeat(source: source);
  Future<void> blink({required bool left, required bool right}) => actions.blink(left: left, right: right);
  Future<void> hazard({int times = 1}) => actions.hazard(times: times);
  Future<void> wakeUp() => actions.wakeUp();
  Future<void> hibernate() => actions.hibernate();
  Future<void> hibernateFor(Duration wakeAfter) => actions.hibernateFor(wakeAfter);
  Future<String?> getCellularApn() => actions.getSetting(commands.lsKeyCellularApn);
  Future<void> setCellularApn(String apn) => actions.setCellularApn(apn);
  Future<void> clearCellularApn() => actions.clearCellularApn();
  Future<bool?> _getBoolSetting(String key) async {
    final value = await actions.getSetting(key);
    return value == null ? null : value == 'true';
  }
  Future<bool?> getBatteryKeepActive() => _getBoolSetting(commands.lsKeyBatteryKeepActiveOnSeatboxOpen);
  Future<void> setBatteryKeepActive(bool enabled) => actions.setSetting(commands.lsKeyBatteryKeepActiveOnSeatboxOpen, enabled.toString());
  Future<bool?> getAlarmEnabled() => _getBoolSetting(commands.lsKeyAlarmEnabled);
  Future<void> setAlarmEnabled(bool enabled) => actions.setSetting(commands.lsKeyAlarmEnabled, enabled.toString());
  Future<bool?> getAlarmHonk() => _getBoolSetting(commands.lsKeyAlarmHonk);
  Future<void> setAlarmHonk(bool enabled) => actions.setSetting(commands.lsKeyAlarmHonk, enabled.toString());
  Future<void> reboot() => actions.reboot();
  Future<void> hardReboot() => actions.hardReboot();

  void _pollLocation() async {
    final scooter = myScooter;
    final connection = _session.currentConnection;
    if (scooter == null) return;
    final position = await _readLocation();
    if (position != null &&
        connection?.isCurrent == true &&
        connected &&
        scooter.isConnected &&
        myScooter?.remoteId == scooter.remoteId) {
      savedScooters[scooter.remoteId.toString()]?.lastLocation = position;
    }
  }

  static Future<void> sendStaticPowerCommand(String id, String command) async {
    await commands.sendStaticPowerCommand(id, command);
  }

  /// Called on the background isolate's service when the foreground reports
  /// that the user is manually connecting a specific scooter. Empty string
  /// means the manual intent is over.
  void setManualConnectionTarget(String? id) {
    _externalManualTargetId = (id == null || id.isEmpty) ? null : id;
    _externalManualTargetSince = _externalManualTargetId == null ? null : DateTime.now();
    log.info("Background manual connection target: ${_externalManualTargetId ?? "(cleared)"}");
  }

  /// Any message from the foreground is proof of life: extend the suppression
  /// window so a live foreground session doesn't get raced after the expiry,
  /// while a killed foreground's stale flag still lapses.
  void touchManualConnectionTarget() {
    if (_externalManualTargetId != null) _externalManualTargetSince = DateTime.now();
  }

  Future<bool> attemptLatestAutoConnection() async {
    // While the foreground is manually connecting a scooter, the background
    // must not race it with its own auto-connect target. The flag expires so
    // a killed foreground can't suspend background reconnects forever.
    if (_externalManualTargetId != null) {
      final age = DateTime.now().difference(_externalManualTargetSince ?? DateTime.now());
      if (age < const Duration(minutes: 5)) {
        log.info("Skipping background auto-connect: foreground is manually connecting $_externalManualTargetId");
        return false;
      }
      _externalManualTargetId = null;
      _externalManualTargetSince = null;
    }
    SavedScooter? latestScooter = await getMostRecentScooter();
    if (_externalManualTargetId != null) {
      // A manual intent arrived while we were picking a candidate; don't
      // start racing it now.
      log.info("Manual connection target appeared during auto-connect preparation");
      return false;
    }
    if (latestScooter != null) {
      try {
        await connectToScooterId(
          latestScooter.id,
          automatic: true,
          expectedIntentGeneration: _session.intentGeneration,
        );
        if (_deviceFromId(latestScooter.id).isConnected) {
          return true;
        }
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  // SAVED SCOOTER MANAGEMENT

  Future<void> refetchSavedScooters() => _refetchSavedScooters();

  Future<void> _refetchSavedScooters({bool Function()? isCurrent}) async {
    await store.load();
    if (isCurrent?.call() == false) return;
    if (!connected) {
      final mostRecentScooter = await getMostRecentScooter();
      if (isCurrent?.call() == false) return;
      identity.lastPing = mostRecentScooter?.lastPing;
      identity.name = mostRecentScooter?.name;
      identity.color = mostRecentScooter?.color;
      identity.lastLocation = mostRecentScooter?.lastLocation;
      _telemetry.refetchCache(
        mostRecentScooter == null ? null : _cachedTelemetry(mostRecentScooter),
      );
    }
    notifyListeners();
  }

  Future<List<String>> getSavedScooterIds({
    bool onlyAutoConnect = false,
  }) async {
    return store.getIds(onlyAutoConnect: onlyAutoConnect);
  }

  Future<void> forgetSavedScooter(String id) async {
    if (_session.hasPendingConnectionAttempt) return;
    final current = _session.captureOperationFreshness();
    if (!current()) return;
    if (myScooter?.remoteId.toString() == id) {
      await actions.forgetCurrentScooter();
    } else {
      // we're not currently connected to this scooter
      try {
        await _deviceFromId(id).removeBond();
      } catch (e, stack) {
        log.severe("Couldn't forget scooter", e, stack);
      }
    }

    // Do not let completion of an old forget clear a replacement's state.
    if (!current()) return;
    if (savedScooters.isNotEmpty) {
      await store.remove(id);
    }
    if (!current()) return;
    updateBackgroundService({"updateSavedScooters": true});
    if (!current()) return;
    if (myScooter == null || myScooter?.remoteId.toString() == id) connected = false;
    if (!current()) return;
    // The background isolate is told to refetch, but this one was left holding
    // the forgotten scooter's name and battery levels, so the home screen went
    // on showing a scooter that no longer exists. refetchSavedScooters resets
    // the streams when nothing is saved, and notifies for us.
    await _refetchSavedScooters(isCurrent: current);
  }

  void renameSavedScooter({String? id, required String name}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log.warning(
        "Attempted to rename scooter, but no ID was given and we're not connected to anything!",
      );
      return;
    }
    await store.rename(id, name);

    bool isMostRecent = (await getMostRecentScooter())?.id == id;
    if (isMostRecent) {
      scooterName = name;
    }

    updateBackgroundService({
      "updateSavedScooters": true,
      if (isMostRecent) "scooterName": name,
    });
    // let the background service know too right away
    notifyListeners();
  }

  void recolorSavedScooter({String? id, required int color}) async {
    id ??= myScooter?.remoteId.toString();
    if (id == null) {
      log.warning(
        "Attempted to recolor scooter, but no ID was given and we're not connected to anything!",
      );
      return;
    }
    await store.recolor(id, color);

    bool isMostRecent = (await getMostRecentScooter())?.id == id;
    if (isMostRecent) {
      scooterColor = color;
    }
    updateBackgroundService({
      "updateSavedScooters": true,
      if (isMostRecent) "scooterColor": color,
    });
    // let the background service know too right away
    notifyListeners();
  }

  void updateBackgroundService(dynamic data) {
    if (!isInBackgroundService) {
      FlutterBackgroundService().invoke("update", data);
    }
  }

  void addSavedScooter(String id) async {
    final connection = _session.currentConnection;
    bool added = await store.add(id);
    if (!added || _session.isDisposed) return;
    updateBackgroundService({"updateSavedScooters": true});
    if (connection != null && !connection.isCurrent) return;
    scooterName = "Scooter Pro";
    notifyListeners();
  }

  @override
  void dispose() {
    actions.dispose();
    _actionWarnings.close();
    _session.dispose();
    _telemetry.dispose();

    if (_runtimeInitialized) {
      _locationTimer.cancel();
      _manualTargetHeartbeatTimer.cancel();
      rssiTimer.cancel();
    }
    _scanSubscription?.cancel();
    // Unregister lifecycle observer
    if (_runtimeInitialized && !isInBackgroundService) {
      WidgetsBinding.instance.removeObserver(this);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    log.info("App lifecycle state changed: $_lastLifecycleState -> $state");

    // Only paused/hidden count as leaving the app. `inactive -> resumed` also
    // happens without backgrounding (iOS cold start, biometric prompt, system
    // dialogs) and used to fire a second start() that raced the initial
    // connection attempt, leaving a redundant scan running for seconds.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    }

    if (_wasBackgrounded && state == AppLifecycleState.resumed) {
      _wasBackgrounded = false;
      log.info("App resumed from background - checking connection status");
      _handleAppResumedFromBackground();
    }

    _lastLifecycleState = state;
  }

  bool get _connectionAttemptInFlight => scanning || _state == ScooterState.linking;

  void _handleAppResumedFromBackground() async {
    if (savedScooters.isEmpty) return;

    try {
      // Small delay so the platform can deliver events that were queued
      // while the app was suspended (disconnects, scan stops) before we
      // judge any cached state
      await Future.delayed(const Duration(milliseconds: 500));

      // iOS kills an active scan during suspension without a final
      // isScanning event, leaving `scanning` stuck true — which disables
      // the manual reconnect button and blocks every automatic reconnect
      // path until the app is restarted.
      if (_session.isDisposed) return;
      if (scanning != flutterBluePlus.isScanningNow) {
        log.info("App resumed: resync scanning flag (cached: $scanning, platform: $flutterBluePlus.isScanningNow)");
        scanning = flutterBluePlus.isScanningNow;
      }

      // The BLE link can also die during suspension without a disconnect
      // event ever reaching us, so probe the link instead of trusting the
      // cached connected flag.
      if (connected && myScooter != null) {
        final connection = _session.currentConnection;
        final device = myScooter!;
        try {
          await device.readRssi();
        } catch (e, stack) {
          if (_session.isDisposed || !identical(connection, _session.currentConnection) ||
              !identical(device, myScooter)) {
            return;
          }
          log.info("App resumed: connection is stale, marking as disconnected", e, stack);
          connected = false;
          state = ScooterState.disconnected;
        }
      }

      if (_session.isDisposed) return;
      if (!connected && !_connectionAttemptInFlight) {
        log.info("App resumed: attempting automatic reconnection");
        // Try to reconnect to the last known scooter
        start();
      } else {
        log.info(
          "App resumed: no reconnection needed (connected: $connected, scanning: $scanning, saved scooters: ${savedScooters.length})",
        );
      }
    } catch (e, stack) {
      log.warning(
        "Error during automatic reconnection on app resume",
        e,
        stack,
      );
    }
  }
}

class UnavailableCharacteristicsException {}

class HandlebarLockException {}

/// Only model/publication and application integrations cross this boundary.
class _ServiceSessionEffects implements ScooterSessionEffects {
  _ServiceSessionEffects(this.service);
  final ScooterService service;

  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {
    service.updateBackgroundService({
      "manualConnectionTarget": id ?? "",
      if (includeMetadata) "scooterName": service.savedScooters[id]?.name,
      if (includeMetadata) "scooterColor": service.savedScooters[id]?.color,
    });
  }

  @override
  void invalidateTelemetry() {
    service.actions.invalidate();
    service._telemetry.invalidate();
  }

  @override
  void linking(SessionConnection connection) {
    service.state = ScooterState.linking;
    if (!connection.isCurrentAttempt) return;
    service._showCachedScooter(service.savedScooters[connection.id]);
  }

  @override
  void transportConnected(SessionConnection connection) {
    service._telemetry.prepare(_cachedTelemetry(service.savedScooters[connection.id]));
    service.addSavedScooter(connection.id);
  }

  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {
    await HomeWidget.setAppGroupId('group.com.librescoot.app');
    if (!connection.isCurrent) return;
    passToWidget(scooterId: connection.id);
    service.log.info("Saved scooter ID to widget: ${connection.id}");
  }

  @override
  void wireTelemetry(SessionConnection connection, CharacteristicRepository repository) {
    service.characteristicRepository = repository;
    service.actions.bind(connection, repository);
    service._telemetry.bind(connection, repository);
  }

  @override
  void readyMetadata(SessionConnection connection) {
    service.scooterName = service.savedScooters[connection.id]?.name;
    if (!connection.isCurrent) return;
    service.scooterColor = service.savedScooters[connection.id]?.color;
  }

  @override
  void ready(SessionConnection connection) {
    service._pollLocation();
    service.updateBackgroundService({
      "scooterName": service.savedScooters[connection.id]?.name,
      "scooterColor": service.savedScooters[connection.id]?.color,
      "lastPingInt": DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void disconnected(String? id) {
    service.actions.invalidate();
    service._telemetry.invalidate();
    service.state = ScooterState.disconnected;
    if (id != null) service.updateScooterPing(id);
  }
}

CachedTelemetry _cachedTelemetry(SavedScooter? scooter) => CachedTelemetry(
  primarySOC: scooter?.lastPrimarySOC, secondarySOC: scooter?.lastSecondarySOC,
  cbbSOC: scooter?.lastCbbSOC, auxSOC: scooter?.lastAuxSOC,
  handlebarsLocked: scooter?.handlebarsLocked, isLibrescoot: scooter?.isLibrescoot,
  supportsHibernateFor: scooter?.supportsHibernateFor, supportsApnConfig: scooter?.supportsApnConfig);

class _ServiceTelemetryEffects implements ScooterTelemetryEffects {
  _ServiceTelemetryEffects(this.service);
  final ScooterService service;

  @override
  void cachePatch(String scooterId, TelemetryCachePatch patch) {
    final saved = service.savedScooters[scooterId];
    if (saved == null) return;
    if (patch.primarySOC != null) saved.lastPrimarySOC = patch.primarySOC;
    if (patch.secondarySOC != null) saved.lastSecondarySOC = patch.secondarySOC;
    if (patch.cbbSOC != null) saved.lastCbbSOC = patch.cbbSOC;
    if (patch.auxSOC != null) saved.lastAuxSOC = patch.auxSOC;
    if (patch.handlebarsLocked != null) saved.handlebarsLocked = patch.handlebarsLocked;
    if (patch.isLibrescoot != null) saved.isLibrescoot = patch.isLibrescoot;
    if (patch.supportsHibernateFor != null) saved.supportsHibernateFor = patch.supportsHibernateFor;
    if (patch.supportsApnConfig != null) saved.supportsApnConfig = patch.supportsApnConfig;
  }

  @override
  void ping(String scooterId) => service._pingScooter(scooterId);

  @override
  void changed(TelemetrySnapshot snapshot) {
    service._telemetryChanged();
    service.actions.telemetryChanged();
  }

  @override
  void firmwareIdentified(SessionConnection connection, FirmwareSnapshot firmware) {
    if (firmware.isLibrescoot == true && service._pendingNavigation != null) {
      service._dispatchPendingNavigation();
    }
  }

  @override
  void navigationChanged(bool? active) {
    if (active != true) service._activeNavigation = null;
  }

  @override
  void aggregateTransition(ScooterState? previous, ScooterState? next) {
    service.actions.aggregateTransition(previous, next);
  }

  @override
  void probeFailed(String message, Object error, StackTrace stack) =>
      service.log.warning(message, error, stack);
}

class _ServiceActionEffects implements ScooterActionEffects {
  _ServiceActionEffects(this.service);
  final ScooterService service;
  @override
  void acknowledged(ActionEvent event) => acknowledgeAppAction(event);
  @override
  void handlebarWarning(HandlebarWarning warning) {
    service.log.warning(warning.didNotUnlock ? "Handlebars didn't unlock, sending warning" : "Handlebars didn't lock, sending warning");
    final connection = service._session.currentConnection;
    if (connection?.isCurrent != true || connection!.id != warning.action.scooterId ||
        connection.generation != warning.action.generation) {
      return;
    }
    service._actionWarnings.add(warning);
  }
  @override
  void cooldownStarted() {
    // FlutterBackgroundService is the UI-isolate facade, not ServiceInstance.
    // Always retain the local cooldown, but never relay from the service isolate.
    if (!service.isInBackgroundService) {
      try { FlutterBackgroundService().invoke("autoUnlockCooldown"); } catch (_) {}
    }
  }
  @override
  void rssiChanged(int value) => service.rssi = value;
  @override
  void failed(Object error, StackTrace stack) => service.log.warning('Action effect failed', error, stack);
}

void acknowledgeAppAction(ActionEvent event) {
  if (event.kind == EventType.lock || event.kind == EventType.unlock) HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(eventType: event.kind, scooterId: event.scooterId,
    source: event.source, soc1: event.primarySOC, soc2: event.secondarySOC,
    location: event.location == null ? null : LatLng(event.location!.latitude, event.location!.longitude));
}
