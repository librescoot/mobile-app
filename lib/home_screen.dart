import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:home_widget/home_widget.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../handlebar_warning.dart';

import '../cloud_service.dart';
import '../control_screen.dart';
import '../domain/icomoon.dart';
import '../domain/scooter_state.dart';
import '../domain/theme_helper.dart';
import '../onboarding_screen.dart';
import '../scooter_service.dart';
import '../scooter_visual.dart';
import '../stats/stats_screen.dart';
import '../helper_widgets/snowfall.dart';
import '../helper_widgets/grassscape.dart';
import '../command_service.dart';

class HomeScreen extends StatefulWidget {
  final bool? forceOpen;
  const HomeScreen({
    this.forceOpen,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _PowerButton extends StatefulWidget {
  const _PowerButton({super.key});

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool? _isCloudAuthenticated;
  CloudService? _cloudService;
  final log = Logger('_PowerButton');
  Timer? _authCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkCloudAuth();
    // Poll for auth status changes
    _authCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkCloudAuth();
    });
  }
  
  @override
  void dispose() {
    _authCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCloudAuth() async {
    final service = context.read<ScooterService>();
    _cloudService = service.cloudService;
    final isAuth = await _cloudService!.isAuthenticated;
    final cloudScooterId = service.getCurrentCloudScooterId();
    log.info('Auth check: isAuth=$isAuth, cloudScooterId=$cloudScooterId');
    if (mounted) {
      setState(() {
        _isCloudAuthenticated = isAuth;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({ScooterState? state, int? cloudScooterId})>(
      selector: (context, service) => (
        state: service.state,
        cloudScooterId: service.getCurrentCloudScooterId(),
      ),
      builder: (context, data, _) {
        final hasCloudScooter = data.cloudScooterId != null;
        final canUseCloudCommands = (_isCloudAuthenticated ?? false) && hasCloudScooter;
        
        // Enable button if connected via BT OR if we have cloud access
        final isEnabled = (data.state != null && data.state!.isReadyForLockChange) || 
                         canUseCloudCommands;
        
        log.info('PowerButton build: isCloudAuth=${_isCloudAuthenticated}, hasCloudScooter=$hasCloudScooter, canUseCloud=$canUseCloudCommands, isEnabled=$isEnabled, state=${data.state}');
        
        return ScooterPowerButton(
          action: isEnabled
              ? () => _handlePowerButtonPress(context, data.state)
              : null,
          icon: data.state != null && data.state!.isOn
              ? Icons.lock_open
              : Icons.lock_outline,
          label: data.state != null && data.state!.isOn
              ? FlutterI18n.translate(context, "home_lock_button")
              : FlutterI18n.translate(context, "home_unlock_button"),
        );
      },
    );
  }

  Future<void> _handlePowerButtonPress(BuildContext context, ScooterState? state) async {
    final homeState = context.findAncestorStateOfType<_HomeScreenState>();
    if (homeState != null) {
      await homeState._handlePowerButtonPress(state);
    }
  }
}

class _ControlsButton extends StatefulWidget {
  const _ControlsButton({super.key});

  @override
  State<_ControlsButton> createState() => _ControlsButtonState();
}

class _ControlsButtonState extends State<_ControlsButton> {
  bool? _isCloudAuthenticated;
  CloudService? _cloudService;
  final log = Logger('HomeScreen');
  Timer? _authCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkCloudAuth();
    // Poll for auth status changes
    _authCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkCloudAuth();
    });
  }
  
  @override
  void dispose() {
    _authCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCloudAuth() async {
    final service = context.read<ScooterService>();
    _cloudService = service.cloudService;
    final isAuth = await _cloudService!.isAuthenticated;
    final cloudScooterId = service.getCurrentCloudScooterId();
    log.info('Auth check: isAuth=$isAuth, cloudScooterId=$cloudScooterId');
    if (mounted) {
      setState(() {
        _isCloudAuthenticated = isAuth;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({bool scanning, bool connected, int? cloudScooterId})>(
      selector: (context, service) => (
        scanning: service.scanning,
        connected: service.connected,
        cloudScooterId: service.getCurrentCloudScooterId(),
      ),
      builder: (context, data, _) {
        final hasCloudScooter = data.cloudScooterId != null;
        final canUseCloudCommands = (_isCloudAuthenticated ?? false) && hasCloudScooter;
        
        // Show controls if connected via BT OR if we have cloud access
        final showControls = data.connected || canUseCloudCommands;
        
        return ScooterActionButton(
          onPressed: !data.scanning
              ? () {
                  if (showControls) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ControlScreen(),
                      ),
                    );
                  } else {
                    log.info("Manually reconnecting...");
                    try {
                      context.read<ScooterService>().start();
                    } catch (e, stack) {
                      log.severe("Reconnect button failed", e, stack);
                    }
                  }
                }
              : null,
          icon: showControls
              ? Icons.more_vert_rounded
              : Icons.refresh_rounded,
          label: showControls
              ? FlutterI18n.translate(context, "home_controls_button")
              : FlutterI18n.translate(context, "home_reconnect_button"),
        );
      },
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final log = Logger('HomeScreen');
  bool _hazards = false;

  // Seasonal
  bool _snowing = false;
  bool _forceHover = false;
  bool _spring = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen != true) {
      log.fine("Redirecting or starting");
      redirectOrStart();
    }
  }

  Future<void> _startSeasonal() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool("seasonal") ?? true) {
      switch (DateTime.now().month) {
        case 12:
          // December, snow season!
          setState(() => _snowing = true);
        case 4:
          if (DateTime.now().day == 1) {
            // April fools calls for flying scooters!
            setState(() => _forceHover = true);
          } else {
            // Easter season, place some easter eggs!
            setState(() => _spring = true);
          }
        // who knows what else might be in the future?
      }
    }
  }

  Future<void> _showOnboardings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (Platform.isAndroid && prefs.getBool("widgetOnboarded") != true) {
      await showWidgetOnboarding();
      prefs.setBool("widgetOnboarded", true);
    }
  }

  Future<void> showWidgetOnboarding() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title:
              Text(FlutterI18n.translate(context, "widget_onboarding_title")),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(FlutterI18n.translate(context, "widget_onboarding_body")),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                  FlutterI18n.translate(context, "widget_onboarding_place")),
              onPressed: () async {
                if ((await HomeWidget.isRequestPinWidgetSupported()) == true) {
                  HomeWidget.requestPinWidget(
                    name: 'HomeWidgetReceiver',
                    androidName: 'HomeWidgetReceiver',
                    qualifiedAndroidName:
                        'de.freal.unustasis.HomeWidgetReceiver',
                  );
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(
                  FlutterI18n.translate(context, "widget_onboarding_dismiss")),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _flashHazards(int times) async {
    setState(() {
      _hazards = true;
    });
    await Future.delayed(Duration(milliseconds: 600 * times));
    setState(() {
      _hazards = false;
    });
  }

  Future<void> _handleSeatButtonPress() async {
    try {
      await context.read<ScooterService>().executeCommand(
            CommandType.openSeat,
            onNeedConfirmation: () => showCloudConfirmationDialog(context),
          );
    } catch (e, stack) {
      log.severe("Problem opening the seat", e, stack);
      Fluttertoast.showToast(msg: e.toString());
    }
  }

  Future<void> _handlePowerButtonPress(ScooterState? state) async {
    // Check if we have cloud access
    final scooterService = context.read<ScooterService>();
    final cloudService = scooterService.cloudService;
    final hasCloudScooter = scooterService.getCurrentCloudScooterId() != null;
    final isCloudAuthenticated = await cloudService.isAuthenticated;
    final canUseCloudCommands = isCloudAuthenticated && hasCloudScooter;
    
    // Allow execution if either BT connected or cloud available
    if (state == null || (!state.isReadyForLockChange && !canUseCloudCommands)) return;

    try {
      // For cloud commands when disconnected, we can't know the exact state
      // so we'll let the user toggle between lock/unlock
      if (canUseCloudCommands && state == ScooterState.disconnected) {
        // Show confirmation dialog and let user choose action
        final confirmed = await showCloudConfirmationDialog(context);
        if (!confirmed) return;
        
        // Since we don't know the state, try unlock (most common action)
        // The cloud API will handle the actual state appropriately
        await context.read<ScooterService>().executeCommand(
              CommandType.unlock,
              onNeedConfirmation: () => Future.value(true), // Already confirmed
            );
      } else if (state.isOn) {
        // Lock flow
        await context.read<ScooterService>().executeCommand(
              CommandType.lock,
              onNeedConfirmation: () => showCloudConfirmationDialog(context),
            );

        if (context.read<ScooterService>().hazardLocking) {
          _flashHazards(1);
        }
      } else if (state == ScooterState.standby) {
        // Unlock flow
        await context.read<ScooterService>().executeCommand(
              CommandType.unlock,
              onNeedConfirmation: () => showCloudConfirmationDialog(context),
            );

        if (context.read<ScooterService>().hazardLocking) {
          _flashHazards(2);
        }
      } else {
        // Wake up flow
        await context.read<ScooterService>().executeCommand(CommandType.wakeUp);
        // Wait for standby state
        await context.read<ScooterService>().executeCommand(CommandType.unlock);
      }
    } on SeatOpenException catch (_) {
      log.warning("Seat is open, showing alert");
      showSeatWarning();
    } on HandlebarLockException catch (_) {
      log.warning("Handlebars issue, showing alert");
      showHandlebarWarning(
        didNotUnlock: state.isOn, // true if we were trying to unlock
      );
    } catch (e, stack) {
      log.severe("Power button action failed", e, stack);
      Fluttertoast.showToast(msg: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                systemNavigationBarColor: Colors.transparent)
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              StateCircle(
                connected: context
                    .select((ScooterService service) => service.connected),
                scooterState:
                    context.select((ScooterService service) => service.state),
                scanning: context
                    .select((ScooterService service) => service.scanning),
              ),
              if (_snowing)
                SnowfallBackground(
                  backgroundColor: Colors.transparent,
                  snowflakeColor: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              if (_spring)
                AnimatedOpacity(
                  opacity: context.watch<ScooterService>().connected == true
                      ? 1.0
                      : 0.0,
                  duration: Duration(milliseconds: 500),
                  child: GrassScape(),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StatsScreen(),
                          ),
                        ),
                        // Hidden for stable release, but useful for various debugging
                        // onLongPress: () =>
                        //     showHandlebarWarning(didNotUnlock: false),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: context.select(
                                        (ScooterService service) =>
                                            service.connected)
                                    ? 32
                                    : 0),
                            Text(
                              context.select<ScooterService, String?>(
                                      (service) => service.scooterName) ??
                                  FlutterI18n.translate(
                                      context, "stats_no_name"),
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                      const StatusText(),
                      const SizedBox(height: 16),
                      if (context.select<ScooterService, int?>(
                              (service) => service.primarySOC) !=
                          null)
                        const BatteryBars(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ScooterVisual(
                          color: context.select<ScooterService, int?>(
                                  (service) => service.scooterColor) ??
                              1,
                          state: context.select(
                              (ScooterService service) => service.state),
                          scanning: context.select(
                              (ScooterService service) => service.scanning),
                          blinkerLeft: _hazards,
                          blinkerRight: _hazards,
                          winter: _snowing,
                          aprilFools: _forceHover,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // main action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          SeatButton(onPressed: _handleSeatButtonPress),
                          Expanded(
                            child: _PowerButton(),
                          ),
                          Expanded(
                            child: _ControlsButton(),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showSeatWarning() {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "seat_alert_title")),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(FlutterI18n.translate(context, "seat_alert_body")),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void showHandlebarWarning({required bool didNotUnlock}) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return HandlebarWarning(
          didNotUnlock: didNotUnlock,
        );
      },
    ).then((dontShowAgain) async {
      if (dontShowAgain == true) {
        Logger("").info("Not showing unlocked handlebar warning again");
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setBool("unlockedHandlebarsWarning", false);
      }
    });
  }

  Future<bool> showCloudConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
                FlutterI18n.translate(context, "cloud_command_confirm_title")),
            content: Text(
                FlutterI18n.translate(context, "cloud_command_confirm_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(FlutterI18n.translate(context, "cloud_command_confirm_cancel")),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(FlutterI18n.translate(context, "cloud_command_confirm_confirm")),
              ),
            ],
          ),
        ) ??
        false;
  }

  void redirectOrStart() async {
    List<String> ids =
        await context.read<ScooterService>().getSavedScooterIds();
    log.info("Saved scooters: $ids");
    if (mounted && ids.isEmpty && !kDebugMode) {
      FlutterNativeSplash.remove();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingScreen(),
        ),
      );
    } else {
      // already onboarded, set up and proceed with home page
      _startSeasonal();
      _showOnboardings();
      // start the scooter service if we're not coming from onboarding
      if (mounted && context.read<ScooterService>().myScooter == null) {
        context.read<ScooterService>().start();
      }
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool("biometrics") ?? false) && mounted) {
      context.read<ScooterService>().optionalAuth = false;
      final LocalAuthentication auth = LocalAuthentication();
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: FlutterI18n.translate(context, "biometrics_message"),
        );
        if (!mounted) return;
        if (!didAuthenticate) {
          Fluttertoast.showToast(
              msg: FlutterI18n.translate(context, "biometrics_failed"));
          Navigator.of(context).pop();
          SystemNavigator.pop();
        } else {
          context.read<ScooterService>().optionalAuth = true;
        }
      } catch (e, stack) {
        log.info("Biometrics failed", e, stack);

        Fluttertoast.showToast(
            msg: FlutterI18n.translate(context, "biometrics_failed"));
        Navigator.of(context).pop();

        SystemNavigator.pop();
      }
    } else {
      if (mounted) context.read<ScooterService>().optionalAuth = true;
    }
  }
}

class SeatButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const SeatButton({
    super.key,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({bool? seatClosed, ScooterState? state})>(
        selector: (context, service) =>
            (seatClosed: service.seatClosed, state: service.state),
        builder: (context, data, _) {
          return Expanded(
              child: FutureBuilder<bool>(
                  future: context
                      .read<ScooterService>()
                      .isCommandAvailable(CommandType.openSeat),
                  builder: (context, snapshot) {
                    final bool enabled = true ||
                        (snapshot.data == true) &&
                            data.state != null &&
                            data.seatClosed == true &&
                            data.state!.isReadyForSeatOpen == true;

                    return ScooterActionButton(
                      onPressed: enabled ? onPressed : null,
                      label: data.seatClosed == false
                          ? FlutterI18n.translate(
                              context, "home_seat_button_open")
                          : FlutterI18n.translate(
                              context, "home_seat_button_closed"),
                      icon: data.seatClosed == false
                          ? Icomoon.seat_open
                          : Icomoon.seat_closed,
                      iconColor: data.seatClosed == false
                          ? Theme.of(context).colorScheme.error
                          : null,
                    );
                  }));
        });
  }
}

class BatteryBars extends StatelessWidget {
  const BatteryBars({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService,
            ({DateTime? lastPing, int? primarySOC, int? secondarySOC})>(
        selector: (context, service) => (
              lastPing: service.lastPing,
              primarySOC: service.primarySOC,
              secondarySOC: service.secondarySOC
            ),
        builder: (context, data, _) {
          bool dataIsOld = data.lastPing == null ||
              data.lastPing!.difference(DateTime.now()).inMinutes.abs() > 5;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: MediaQuery.of(context).size.width / 6,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.black26,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                    value: data.primarySOC! / 100.0,
                    color: dataIsOld
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4)
                        : data.primarySOC! <= 15
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                  )),
              const SizedBox(width: 8),
              Text("${data.primarySOC}%"),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                const VerticalDivider(),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                SizedBox(
                    width: MediaQuery.of(context).size.width / 6,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.black26,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      value: data.secondarySOC! / 100.0,
                      color: dataIsOld
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4)
                          : data.secondarySOC! <= 15
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                    )),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                const SizedBox(width: 8),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                Text("${data.secondarySOC}%"),
            ],
          );
        });
  }
}

class StatusText extends StatelessWidget {
  const StatusText({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Selector<ScooterService, String?>(
          selector: (_, service) => service.currentScooterId,
          builder: (context, currentScooterId, _) => _buildCloudStatus(context),
        ),
        Selector<ScooterService,
                ({bool connected, bool scanning, ScooterState? state})>(
            selector: (context, service) => (
                  state: service.state,
                  scanning: service.scanning,
                  connected: service.connected
                ),
            builder: (context, data, _) {
              return Text(
                data.scanning &&
                        (data.state == null ||
                            data.state == ScooterState.disconnected)
                    ? (context.read<ScooterService>().savedScooters.isNotEmpty
                        ? FlutterI18n.translate(context, "home_scanning_known")
                        : FlutterI18n.translate(context, "home_scanning"))
                    : ((data.state != null
                            ? data.state!.name(context)
                            : FlutterI18n.translate(
                                context, "home_loading_state")) +
                        (data.connected &&
                                context.select<ScooterService, bool?>(
                                        (service) =>
                                            service.handlebarsLocked) ==
                                    false
                            ? FlutterI18n.translate(context, "home_unlocked")
                            : "")),
                style: Theme.of(context).textTheme.titleMedium,
              );
            }),
      ],
    );
  }

  Widget _buildCloudStatus(BuildContext context) {
    final cloudService = context.read<ScooterService>().cloudService;
    final log = Logger('HomeScreen/CloudStatus');

    return StreamBuilder<bool>(
      stream: Stream.periodic(const Duration(seconds: 5))
          .asyncMap((_) => cloudService.isAuthenticated),
      initialData: false,
      builder: (context, authSnapshot) {
        if (!authSnapshot.hasData || !authSnapshot.data!) return Container();

        return FutureBuilder<Map<String, dynamic>?>(
          future: _getCurrentCloudScooter(context, cloudService),
          builder: (context, AsyncSnapshot<Map<String, dynamic>?> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            return Text(
              FlutterI18n.translate(
                  context,
                  (!snapshot.hasData || snapshot.data == null)
                      ? "cloud_no_linked_scooter"
                      : "cloud_scooter_linked"),
              style: Theme.of(context).textTheme.titleMedium,
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _getCurrentCloudScooter(
      BuildContext context, CloudService cloudService) async {
    if (!await cloudService.isAuthenticated) return null;

    final cloudScooters = await cloudService.getScooters();
    final currentCloudId =
        context.read<ScooterService>().getCurrentCloudScooterId();

    try {
      return cloudScooters.firstWhere(
        (s) => s['id'] == currentCloudId,
        orElse: () => {
          'name': 'Unknown',
          'last_seen_at': DateTime.now().toIso8601String(),
          'color_id': 1
        },
      );
    } catch (e) {
      return null;
    }
  }
}

class StateCircle extends StatelessWidget {
  const StateCircle({
    super.key,
    required bool scanning,
    required bool connected,
    required ScooterState? scooterState,
  })  : _scanning = scanning,
        _connected = connected,
        _scooterState = scooterState;

  final bool _scanning;
  final bool _connected;
  final ScooterState? _scooterState;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutBack,
      scale: _connected
          ? _scooterState == ScooterState.parked
              ? 1.5
              : (_scooterState == ScooterState.ready)
                  ? 3
                  : 1.2
          : _scanning
              ? 1.5
              : 0,
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _scooterState?.isOn == true
              ? context.isDarkMode
                  ? HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                      .withLightness(0.18)
                      .toColor()
                  : HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                      .withAlpha(0.3)
                      .toColor()
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainer
                  .withValues(alpha: context.isDarkMode ? 0.5 : 0.7),
        ),
      ),
    );
  }
}

class ScooterPowerButton extends StatefulWidget {
  const ScooterPowerButton({
    super.key,
    required void Function()? action,
    Widget? child,
    required IconData icon,
    required String label,
    bool? easterEgg,
  })  : _action = action,
        _icon = icon,
        _label = label,
        _easterEgg = easterEgg;

  final void Function()? _action;
  final String _label;
  final IconData _icon;
  final bool? _easterEgg;

  @override
  State<ScooterPowerButton> createState() => _ScooterPowerButtonState();
}

class _ScooterPowerButtonState extends State<ScooterPowerButton> {
  bool loading = false;
  bool disabled = false;
  int? randomEgg = Random().nextInt(8);

  @override
  Widget build(BuildContext context) {
    Color mainColor = widget._action == null
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)
        : Theme.of(context).colorScheme.primary;
    disabled = widget._action == null;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(width: 2, color: mainColor),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: EdgeInsets.zero,
                backgroundColor: loading
                    ? Theme.of(context).colorScheme.surface
                    : (widget._easterEgg == true
                        ? disabled
                            ? Colors.white38
                            : Colors.white
                        : mainColor),
              ),
              onPressed: () {
                Fluttertoast.showToast(msg: widget._label);
              },
              onLongPress: disabled
                  ? null
                  : () {
                      setState(() {
                        loading = true;
                      });
                      widget._action!();
                      Future.delayed(const Duration(seconds: 5), () {
                        setState(() {
                          loading = false;
                        });
                      });
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                decoration: widget._easterEgg == true
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            width: 2,
                            color: !disabled && widget._easterEgg == true
                                ? mainColor
                                : Colors.transparent),
                        image: DecorationImage(
                            image: AssetImage(
                                "images/decoration/egg_$randomEgg.webp"),
                            fit: BoxFit.cover,
                            opacity: disabled ? 0.3 : 1),
                      )
                    : null,
                child: loading
                    ? SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          color: mainColor,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        widget._icon,
                        color: widget._easterEgg == true && !context.isDarkMode
                            ? (disabled ? Colors.black26 : Colors.black87)
                            : Theme.of(context).colorScheme.surface,
                        size: 28,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget._label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: mainColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class ScooterActionButton extends StatelessWidget {
  const ScooterActionButton({
    super.key,
    required void Function()? onPressed,
    required IconData icon,
    Color? iconColor,
    required String label,
  })  : _onPressed = onPressed,
        _icon = icon,
        _iconColor = iconColor,
        _label = label;

  final void Function()? _onPressed;
  final IconData _icon;
  final String _label;
  final Color? _iconColor;

  @override
  Widget build(BuildContext context) {
    Color mainColor = _iconColor ??
        (_onPressed == null
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)
            : Theme.of(context).colorScheme.onSurface);
    return Column(
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(24),
            side: BorderSide(
              color: mainColor,
            ),
          ),
          onPressed: _onPressed,
          child: Icon(
            _icon,
            color: mainColor,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: mainColor),
        ),
      ],
    );
  }
}
