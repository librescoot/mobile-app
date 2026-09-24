import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/background_i18n.dart';
import '../background/tasker_bridge.dart';
import '../background/widget_handler.dart';
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';
import '../background/notification_handler.dart';

bool backgroundScanEnabled = true;
PausableTimer? _rescanTimer;
AndroidServiceInstance? _androidServiceInstance;
bool _widgetActionInProgress = false;
Timer? _foregroundDemoteTimer;
const Duration _foregroundTimeout = Duration(minutes: 15);

late FlutterBluePlusMockable fbp;
late ScooterService scooterService;

void _initializeScooterService({
  bool allowAutomaticActions = true,
  bool connectionsPaused = false,
}) {
  fbp = FlutterBluePlusMockable();
  scooterService = ScooterService(
    fbp,
    isInBackgroundService: true,
    allowAutomaticActions: allowAutomaticActions,
    connectionsPaused: connectionsPaused,
  );
}

Future<void> setupBackgroundService() async {
  final log = Logger("setupBackgroundService");
  final service = FlutterBackgroundService();

  HomeWidget.registerInteractivityCallback(backgroundCallback);

  backgroundScanEnabled = await SharedPreferencesAsync().getBool("backgroundScan") ?? false;
  log.info("Background scan: $backgroundScanEnabled");

  if (Platform.isAndroid) {
    await setupNotifications();
  }

  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      // Starting a disabled service creates a second Flutter engine. Its
      // FlutterBluePlus plugin detaches moments later and can tear down the
      // foreground engine's GATT connection. Widget callbacks and the setting
      // that enables background scanning start the configured service explicitly.
      autoStart: backgroundScanEnabled,
      onStart: onStart,
      isForegroundMode: true, // Must start as foreground so Android allows restarts from widget callbacks
      autoStartOnBoot: true,
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
      notificationChannelId: serviceChannelId, // silent channel for the mandatory foreground service notification
      initialNotificationTitle: 'Unu Scooter',
      initialNotificationContent: 'You can dismiss this notification.',
      foregroundServiceNotificationId: notificationId,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // this will be updated occasionally by the system
  Logger("bgservice").info("Background service started on iOS!");
  // Ensure that the Flutter engine is initialized.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await BackgroundI18n.instance.init();
  // Set up a scooter service instance.
  final connectionsPaused = await SharedPreferencesAsync().getBool(connectionPausedPreferenceKey) ?? false;
  _initializeScooterService(connectionsPaused: connectionsPaused);
  // Make sure scooterService has time to initialize all values
  await Future.delayed(const Duration(seconds: 5));
  // update the widget
  passToWidget(
    connected: scooterService.connected,
    lastPing: scooterService.identity.lastPing,
    scooterState: scooterService.state,
    primarySOC: scooterService.battery.primarySOC,
    secondarySOC: scooterService.battery.secondarySOC,
    scooterName: scooterService.identity.name,
    scooterColor: scooterService.identity.color,
    lastLocation: scooterService.identity.lastLocation,
    seatClosed: scooterService.vehicle.seatClosed,
    scooterId: scooterService.currentScooterId,
  );
  return true;
}

Future<void> attemptConnectionCycle() async {
  if (_widgetActionInProgress) return;
  await scooterService.attemptLatestAutoConnection();
  setWidgetScanning(false);
  return;
}

void _enableScanning() {
  backgroundScanEnabled = true;
  scooterService.setAutomaticActionsAllowed(true);
  _foregroundDemoteTimer?.cancel();
  _androidServiceInstance?.setAsForegroundService();
  _rescanTimer?.start();
  scooterService.rssiTimer.start();
  updateNotification();
  attemptConnectionCycle();
}

void _disableScanning({bool stopService = false}) {
  backgroundScanEnabled = false;
  scooterService.setAutomaticActionsAllowed(false);
  _rescanTimer
    ?..pause()
    ..reset();
  scooterService.rssiTimer.pause();
  if (stopService) {
    scooterService.disconnectAndClearDevice();
    _foregroundDemoteTimer?.cancel();
    dismissNotification();
    _androidServiceInstance?.stopSelf();
  } else {
    demoteToBackground();
  }
}

/// Checks SharedPreferences for a pending widget action that was persisted
/// but never executed (e.g. because invoke() was lost).  Called from the
/// scooterService listener and the rescan timer as a fallback.
Future<void> _checkPendingWidgetAction() async {
  if (_widgetActionInProgress) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final pending = await _nextPendingAction(prefs);
    if (pending != null) {
      Logger("bgservice").info("Found lost pending action: ${pending.actionName}");
      await executeWidgetAction(pending.actionName, requestId: pending.requestId);
    }
  } catch (e) {
    Logger("bgservice").warning("Error checking pending action", e);
  }
}

Future<({String actionName, String? requestId})?> _nextPendingAction(SharedPreferences prefs) async {
  await prefs.reload();
  if (prefs.getBool("pendingWidgetAction") == true) {
    final actionName = prefs.getString("pendingWidgetActionName");
    if (actionName != null) return (actionName: actionName, requestId: null);
  }
  final taskerActions = await pendingTaskerActions(prefs);
  if (taskerActions.isEmpty) return null;
  return (actionName: taskerActions.first.action, requestId: taskerActions.first.requestId);
}

bool _matchesPendingAction(SharedPreferences prefs, String actionName, String? requestId) => requestId == null
    ? prefs.getBool("pendingWidgetAction") == true && prefs.getString("pendingWidgetActionName") == actionName
    : prefs.getString(pendingTaskerActionKey(requestId)) == actionName;

/// Connects to the scooter if needed, then performs the given action.
/// Handles foreground promotion, scanning UI, and post-action cleanup.
Future<void> executeWidgetAction(String actionName, {String? requestId}) async {
  if (_widgetActionInProgress) return;
  _widgetActionInProgress = true;

  final log = Logger("bgservice");
  log.info("Executing action: $actionName");

  try {
    promoteToForeground();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool matchesRequest() => _matchesPendingAction(prefs, actionName, requestId);
    // All producers persist first. A delayed invoke after a successful action
    // must not replay an already consumed slot (or an unrelated action name).
    if (!matchesRequest()) return;

    if (scooterService.connectionsPaused) {
      await scooterService.setConnectionsPaused(false, publish: false);
    }
    if (!scooterService.connected) await setWidgetScanning(true);

    // Tasker only. Nothing could ever satisfy this, so answer it now: preparing
    // would retain the request for a target that can never appear and leave
    // Tasker to sit out its whole timeout.
    if (requestId != null && await _noSavedScooters()) {
      await dropAndReport(requestId, taskerResultNoScooterSaved);
      return;
    }

    // The disconnected widget's Scan button is a reconnect request, not an
    // implicit unlock command. Connect and consume it without issuing any
    // vehicle-control write.
    if (actionName == "connect") {
      // Startup cache restoration owns the saved-scooter target. A newer
      // request may also have replaced this one while restoration waited.
      await scooterService.runtimeReady;
      await prefs.reload();
      if (!matchesRequest()) return;
      if (!scooterService.connected) {
        final targetId = scooterService.mostRecentSavedScooterId;
        if (targetId != null) {
          await scooterService.connectToScooterId(targetId);
        }
      }
      if (_androidServiceInstance != null) updateNotification();
      await prefs.reload();
      if (matchesRequest()) {
        if (requestId == null) {
          await prefs.setBool("pendingWidgetAction", false);
          await prefs.remove("pendingWidgetActionName");
        } else {
          await prefs.remove(pendingTaskerActionKey(requestId));
        }
      }
      return;
    }

    final dispatch = await scooterService.prepareWidgetAction(actionName);
    if (dispatch == null) return; // Pending connection/pin change: retain request.
    await setWidgetScanning(false);
    if (actionName == "lock" || actionName == "unlock") {
      await setWidgetUnlocking(true);
    }

    await prefs.reload();
    if (!matchesRequest()) return; // A newer different request won during connect.
    if (!dispatch.isReady()) return;
    // Claim only once the captured target is usable, immediately before issuing.
    // Preference APIs update their local cache even on failure: recovery must
    // reload disk, not infer durability from that optimistic cache.
    var mayHaveIssued = false;
    try {
      if (requestId == null) {
        if (!await prefs.setBool("pendingWidgetAction", false)) {
          throw StateError("Pending action claim was not persisted");
        }
        if (!dispatch.isReady()) return;
        await prefs.reload();
        if (!dispatch.isReady() ||
            prefs.getBool("pendingWidgetAction") == true ||
            prefs.getString("pendingWidgetActionName") != actionName) {
          return;
        }
        if (!await prefs.remove("pendingWidgetActionName")) {
          throw StateError("Pending action name removal was not persisted");
        }
        await prefs.reload();
        if (prefs.getBool("pendingWidgetAction") == true || prefs.getString("pendingWidgetActionName") != null) {
          return; // A newer widget request arrived during the issued removal.
        }
      } else {
        if (!await prefs.remove(pendingTaskerActionKey(requestId))) {
          throw StateError("Tasker action claim was not persisted");
        }
        await prefs.reload();
        if (!dispatch.isReady() || prefs.containsKey(pendingTaskerActionKey(requestId))) return;
      }
      if (!dispatch.isReady()) return;
      if (actionName == "lock") scooterService.warnIfLockingWithOpenSeatbox();
      // App log listeners can reenter and invalidate the captured target.
      if (!dispatch.isReady()) return;
      // An unclassified dispatch exception is conservatively ambiguous. The
      // shared action boundary returns false only before any native write call.
      mayHaveIssued = true;
      final issued = await dispatch();
      if (issued) {
        if (requestId != null) await publishActionResult(requestId, taskerResultOk);
      } else {
        // A definite non-write: the request is restored below and a later pass
        // runs it, so there is no outcome to report yet.
        mayHaveIssued = false;
      }
    } finally {
      if (!mayHaveIssued) await _restoreUnissuedWidgetAction(prefs, actionName, requestId: requestId);
    }
  } catch (e, stack) {
    log.severe("Action '$actionName' failed", e, stack);
    if (requestId != null) await dropAndReport(requestId, taskerResultForError(e));
  } finally {
    try {
      await setWidgetScanning(false);
      await setWidgetUnlocking(false);
      // Flush the real scooterService state to the widget. While scanning
      // was active, passToWidget calls from the scooterService listener
      // were blocked by _widgetIsScanning. Now that scanning is off, push
      // the current state so the widget doesn't stay stuck on "Connecting…".
      passToWidget(
        connected: scooterService.connected,
        lastPing: scooterService.lastPing,
        scooterState: scooterService.state,
        primarySOC: scooterService.primarySOC,
        secondarySOC: scooterService.secondarySOC,
        scooterName: scooterService.scooterName,
        scooterColor: scooterService.scooterColor,
        lastLocation: scooterService.lastLocation,
        seatClosed: scooterService.seatClosed,
        scooterLocked: scooterService.handlebarsLocked,
        scooterId: scooterService.currentScooterId,
      );
    } finally {
      _widgetActionInProgress = false;
    }
  }
}

/// Whether there is no scooter that could satisfy an action. Tasker only: widget
/// taps reach this before the saved-scooter store has loaded.
Future<bool> _noSavedScooters() async {
  await scooterService.runtimeReady;
  return (await scooterService.getSavedScooterIds()).isEmpty;
}

/// One best-effort recovery pass, never an automatic actuation retry. Tasker
/// requests restore their own atomic entry; the widget compatibility slot still
/// has two keys and cannot safely distinguish concurrent same-name requests.
Future<void> _restoreUnissuedWidgetAction(
  SharedPreferences prefs,
  String actionName, {
  String? requestId,
}) async {
  try {
    await prefs.reload();
    if (requestId != null) {
      final key = pendingTaskerActionKey(requestId);
      if (!prefs.containsKey(key) && !await prefs.setString(key, actionName)) {
        throw StateError("Unissued Tasker action was not restored");
      }
      return;
    }
    if (prefs.getBool("pendingWidgetAction") == true) return;
    final name = prefs.getString("pendingWidgetActionName");
    if (name != null && name != actionName) return;
    if (!await prefs.setString("pendingWidgetActionName", actionName)) {
      throw StateError("Unissued action name was not restored");
    }
    await prefs.reload();
    if (prefs.getBool("pendingWidgetAction") == true || prefs.getString("pendingWidgetActionName") != actionName) {
      return;
    }
    if (!await prefs.setBool("pendingWidgetAction", true)) {
      throw StateError("Unissued action flag was not restored");
    }
  } catch (e, stack) {
    Logger("bgservice")
        .warning("Could not restore unissued action '$actionName'; pending persistence is uncertain", e, stack);
  }
}

/// Temporarily promotes the Android service to foreground mode.
/// If [temporary] is true and background scanning is disabled,
/// the service will automatically demote back to background after [_foregroundTimeout].
void promoteToForeground({bool temporary = true}) {
  if (_androidServiceInstance == null) return;

  _foregroundDemoteTimer?.cancel();
  _androidServiceInstance!.setAsForegroundService();

  if (temporary && !backgroundScanEnabled) {
    _scheduleDemoteTimer();
  }
}

/// Schedules the foreground demotion timer.
/// If the scooter is still connected when it fires, restarts for another cycle.
void _scheduleDemoteTimer() {
  _foregroundDemoteTimer?.cancel();
  _foregroundDemoteTimer = Timer(_foregroundTimeout, () {
    if (scooterService.connected) {
      Logger("bgservice").info("Scooter still connected, extending foreground timeout");
      _scheduleDemoteTimer();
    } else {
      demoteToBackground();
    }
  });
}

/// Stops the Android service entirely to save battery.
/// Only stops if background scanning is disabled and no scooter is connected.
void demoteToBackground() {
  if (_androidServiceInstance == null || backgroundScanEnabled) return;
  if (scooterService.connected) {
    _scheduleDemoteTimer();
    return;
  }

  _foregroundDemoteTimer?.cancel();
  dismissNotification();
  _androidServiceInstance!.stopSelf();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Logger("bgservice").onRecord.listen((record) {
    // ignore: avoid_print
    print("[${record.level.name}] ${record.time}: ${record.message} ${record.error ?? ""} ${record.stackTrace ?? ""}");
  });
  Logger("bgservice").info("Background service started!");
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await BackgroundI18n.instance.init();

  // Localize notification channels and replace initial notification
  if (Platform.isAndroid && service is AndroidServiceInstance) {
    await localizeNotificationChannels();
    service.setForegroundNotificationInfo(
      title: 'Unu Scooter',
      content: BackgroundI18n.instance.translate('notification_service_content'),
    );
  }

  backgroundScanEnabled = await SharedPreferencesAsync().getBool("backgroundScan") ?? false;
  final connectionsPaused = await SharedPreferencesAsync().getBool(connectionPausedPreferenceKey) ?? false;

  // Check if we were started by a widget action.
  final prefs = await SharedPreferences.getInstance();
  final pendingAction = await _nextPendingAction(prefs);
  final pendingWidgetAction = pendingAction != null;

  if (service is AndroidServiceInstance) {
    _androidServiceInstance = service;
    // Do not construct FlutterBluePlus or ScooterService merely because the
    // configured service auto-started with the app. Attaching a second Flutter
    // engine to FlutterBluePlus disconnects the foreground engine's GATT
    // client. A disabled, actionless service has no Bluetooth work to own.
    if (!backgroundScanEnabled && !pendingWidgetAction) {
      Logger("bgservice").info("No background work requested, stopping service before Bluetooth initialization");
      await HomeWidget.setAppGroupId("group.org.librescoot.mobile.unu");
      await setWidgetScanning(false);
      dismissNotification();
      service.stopSelf();
      return;
    }
  }

  _initializeScooterService(
    allowAutomaticActions: backgroundScanEnabled,
    connectionsPaused: connectionsPaused,
  );

  // Seed widget caches and clear stale spinner BEFORE any code path
  // that might stop the service (e.g. _disableScanning → stopSelf).
  Logger("bgservice").info("Seeding widget with initial data");
  await HomeWidget.setAppGroupId("group.org.librescoot.mobile.unu");
  await seedCachesFromWidget();
  if (!pendingWidgetAction) {
    await setWidgetScanning(false);
  }
  Logger("bgservice").info("Widget seeded with initial data. ScooterName: ${scooterService.scooterName}");

  if (service is AndroidServiceInstance) {
    if (backgroundScanEnabled) {
      Logger("bgservice").info("Running first connection cycle");
      _enableScanning();
    } else if (pendingWidgetAction) {
      // _executeAction will promote to foreground itself
    } else {
      Logger("bgservice").info("Background scanning disabled, stopping service");
      _disableScanning();
    }
  }

  Logger("bgservice").info("Seeding widget with initial data");
  // Seed the widget with scooterService data once it's had time to load caches.
  // Skip if we were restarted by a widget action — the widget already has valid data.
  if (!pendingWidgetAction) {
    Future.delayed(const Duration(seconds: 5), () {
      passToWidget(
          connected: scooterService.connected,
          lastPing: scooterService.lastPing,
          scooterState: scooterService.state,
          primarySOC: scooterService.primarySOC,
          secondarySOC: scooterService.secondarySOC,
          scooterName: scooterService.scooterName,
          scooterColor: scooterService.scooterColor,
          lastLocation: scooterService.lastLocation,
          seatClosed: scooterService.seatClosed,
          scooterId: scooterService.currentScooterId);
    });
  }
  Logger("bgservice").info("Widget seeded with initial data. ScooterName: ${scooterService.identity.name}");

  service.on("autoUnlockCooldown").listen((data) async {
    Logger("bgservice").info("Received autoUnlockCooldown command");
    scooterService.autoUnlockCooldown();
  });

  // listen for commands
  service.on("update").listen((data) async {
    Logger("bgservice").info("Received update command: $data");
    try {
      if (data?["connectionPaused"] != null) {
        await scooterService.setConnectionsPaused(data!["connectionPaused"] == true, publish: false);
      }
      if (data?["autoUnlock"] != null) {
        scooterService.setAutoUnlock(data!["autoUnlock"]);
      }
      if (data?["autoUnlockThreshold"] != null) {
        scooterService.setAutoUnlockThreshold(data!["autoUnlockThreshold"]);
      }
      if (data?["openSeatOnUnlock"] != null) {
        scooterService.setOpenSeatOnUnlock(data!["openSeatOnUnlock"]);
      }
      if (data?["hazardLocking"] != null) {
        scooterService.setHazardLocking(data!["hazardLocking"]);
      }
      if (data?["scooterName"] != null) {
        scooterService.scooterName = data!["scooterName"];
      }
      if (data?["scooterColor"] != null) {
        scooterService.scooterColor = data!["scooterColor"];
      }
      if (data?["lastPingInt"] != null) {
        scooterService.lastPing = DateTime.fromMillisecondsSinceEpoch(data!["lastPingInt"]);
      }
      if (data?["backgroundScan"] != null) {
        if (data!["backgroundScan"] == false) {
          // An explicit off request always tears down a temporary widget-action
          // service too, even if persistent background scanning was never on.
          _disableScanning(stopService: true);
        } else if (data["backgroundScan"] == true && !backgroundScanEnabled) {
          // was false, now is true. Start it up!
          Logger("bgservice").info("Enabling BG scanning");
          _enableScanning();
        }
      }
      if (data?["updateSavedScooters"] == true) {
        await scooterService.refetchSavedScooters();
      }
      handleForegroundConnectionUpdate(scooterService, data);

      Future.delayed(const Duration(seconds: 3), () {
        passToWidget(
          connected: scooterService.connected,
          lastPing: scooterService.identity.lastPing,
          scooterState: scooterService.state,
          primarySOC: scooterService.battery.primarySOC,
          secondarySOC: scooterService.battery.secondarySOC,
          scooterName: scooterService.identity.name,
          scooterColor: scooterService.identity.color,
          lastLocation: scooterService.identity.lastLocation,
          seatClosed: scooterService.vehicle.seatClosed,
          scooterId: scooterService.currentScooterId,
        );
      });
    } catch (e, stack) {
      Logger("bgservice").severe("Something bad happened on command: $e", e, stack);
    }
  });

  String? requestId(dynamic data) => data?["requestId"] as String?;
  service.on("connect").listen((data) async => executeWidgetAction("connect", requestId: requestId(data)));
  service.on("lock").listen((data) async => executeWidgetAction("lock", requestId: requestId(data)));
  service.on("unlock").listen((data) async => executeWidgetAction("unlock", requestId: requestId(data)));
  service.on("openseat").listen((data) async => executeWidgetAction("openseat", requestId: requestId(data)));

  service.on("test").listen((data) async {
    Logger("bgservice").info("Test command received by background service! Data: $data");
  });

  // listen to changes
  scooterService.addListener(() async {
    passToWidget(
      connected: scooterService.connected,
      lastPing: scooterService.identity.lastPing,
      scooterState: scooterService.state,
      primarySOC: scooterService.battery.primarySOC,
      secondarySOC: scooterService.battery.secondarySOC,
      scooterName: scooterService.identity.name,
      scooterColor: scooterService.identity.color,
      lastLocation: scooterService.identity.lastLocation,
      seatClosed: scooterService.vehicle.seatClosed,
      scooterLocked: scooterService.vehicle.handlebarsLocked,
      scooterId: scooterService.currentScooterId,
    );
    if (backgroundScanEnabled) {
      updateNotification();
    }
    // Fallback: pick up widget actions whose invoke() was lost
    // (e.g. Dart isolate was suspended when the widget tap arrived).
    if (scooterService.connected) {
      _checkPendingWidgetAction();
    }
  });

  // If the service was started by a widget action, execute it now that
  // everything is initialized and all listeners are registered.
  // Wait for scooterService to load cached data (saved scooter IDs, etc.)
  if (pendingAction != null) {
    await Future.delayed(const Duration(seconds: 3));
    executeWidgetAction(pendingAction.actionName, requestId: pendingAction.requestId);
  }

  _rescanTimer = PausableTimer.periodic(const Duration(seconds: 35), () async {
    // Fallback: pick up widget actions that were persisted but never executed.
    _checkPendingWidgetAction();

    if (!backgroundScanEnabled) {
      Logger("bgservice").info("Oh boy, the timer must've killed itself/been killed. Resetting!");
      _rescanTimer
        ?..pause()
        ..reset();
      return;
    }
    if (backgroundScanEnabled &&
        service is AndroidServiceInstance &&
        await service.isForegroundService() &&
        (await scooterService.getSavedScooterIds(onlyAutoConnect: true)).isNotEmpty &&
        !scooterService.scanning &&
        !scooterService.connected) {
      attemptConnectionCycle();
    } else {
      Logger("bgservice").info(
          "Some conditions for rescanning not met. backgroundScanEnabled: $backgroundScanEnabled, scooterService.scanning: ${scooterService.scanning}, scooterService.connected: ${scooterService.connected}");
    }
  });

  _rescanTimer!.start();
}

/// Foreground proof-of-life refreshes only an already active manual-target gate.
/// An explicit empty target releases it; ordinary legacy metadata never arms it.
void handleForegroundConnectionUpdate(ScooterService scooterService, Map<String, dynamic>? data) {
  if (data?.containsKey("manualConnectionTarget") == true) {
    scooterService.setManualConnectionTarget(data!["manualConnectionTarget"] as String?);
  } else {
    scooterService.touchManualConnectionTarget();
  }
}
