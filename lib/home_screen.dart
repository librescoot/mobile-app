import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../seat_warning.dart';
import '../helper_widgets/leaves.dart';
import '../helper_widgets/scooter_action_button.dart';
import '../helper_widgets/onboarding_popups.dart';
import '../handlebar_warning.dart';
import '../domain/icomoon.dart';
import '../domain/theme_helper.dart';
import '../onboarding_screen.dart';
import '../scooter_service.dart';
import '../domain/scooter_state.dart';
import '../domain/scooter_vehicle_state.dart';
import '../domain/scooter_power_state.dart';
import '../scooter_visual.dart';
import '../stats/battery_screen.dart';
import '../stats/scooter_screen.dart';
import '../stats/settings_screen.dart';
import '../stats/support_screen.dart';
import '../control_sheet.dart';
import '../helper_widgets/snowfall.dart';
import '../helper_widgets/clouds.dart';
import '../helper_widgets/grassscape.dart';
import '../navigation_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool? forceOpen;
  const HomeScreen({this.forceOpen, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final log = Logger('HomeScreen');
  bool _hazards = false;

  // Seasonal
  bool _snowing = false;
  bool _forceHover = false;
  bool _spring = false;
  bool _fall = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen != true) {
      log.fine("Redirecting or starting");
      redirectOrStart();
    }
  }

  Future<void> _startSeasonal() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    if (await prefs.getBool("seasonal") ?? true) {
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
        case 10:
          // October, it's fall by day and halloween by night
          setState(() => _fall = true);
        // who knows what else might be in the future?
      }
    }
  }

  Future<void> _showNotifications() async {
    // for future reference, this is how to do non-server notifications:
    // SharedPreferencesAsync prefs = SharedPreferencesAsync();
    // if (Platform.isAndroid && await prefs.getBool("widgetOnboarded") != true && mounted) {
    //   await showWidgetOnboarding(context);
    //   await prefs.setBool("widgetOnboarded", true);
    // }
    if (mounted) await showServerNotifications(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                systemNavigationBarColor: Colors.transparent,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
              ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_fall && !context.isDarkMode)
                LeavesBackground(
                  backgroundColor: Colors.transparent,
                  leafColors: const [
                    Color(0xFF8B4000), // brown
                    Color(0xFFFF8C00), // dark orange
                    Color(0xFFFFC107), // amber
                    Color(0xFFB7410E), // russet
                  ],
                  leafCount: 15,
                ),
              if (_snowing)
                SnowfallBackground(
                  backgroundColor: Colors.transparent,
                  snowflakeColor:
                      context.isDarkMode ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
                ),
              if (_fall && context.isDarkMode)
                AnimatedOpacity(
                  opacity: context.watch<ScooterService>().connected == true ? 1.0 : 0.5,
                  duration: Duration(milliseconds: 500),
                  child: Clouds(),
                ),
              if (_spring)
                AnimatedOpacity(
                  opacity: context.watch<ScooterService>().connected == true ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 500),
                  child: GrassScape(),
                ),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 8,
                      child: IconButton(
                        tooltip: FlutterI18n.translate(context, "stats_title_support"),
                        icon: const Icon(Icons.help_outline),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SupportScreen(),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      child: IconButton(
                        tooltip: FlutterI18n.translate(context, "stats_title_settings"),
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 40, bottom: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ScooterScreen(),
                                  ),
                                ),
                                // // Hidden for stable release, but useful for various debugging
                                // onLongPress: () {
                                //   Navigator.push(
                                //     context,
                                //     MaterialPageRoute(
                                //       builder: (context) => const LsKeycardScreen(),
                                //     ),
                                //   );
                                // },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        context.select<ScooterService, String?>(
                                              (service) => service.identity.name,
                                            ) ??
                                            FlutterI18n.translate(
                                              context,
                                              "stats_no_name",
                                            ),
                                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(height: 1.1),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const StatusText(),
                          if (context.select<ScooterService, String?>(
                                    (service) => service.identity.name,
                                  ) !=
                                  null &&
                              context.select<ScooterService, String?>(
                                    (service) => service.identity.name,
                                  ) !=
                                  FlutterI18n.translate(
                                    context,
                                    "stats_no_name",
                                  ) &&
                              (context.select<ScooterService, int?>(
                                        (service) => service.battery.primarySOC,
                                      ) !=
                                      null ||
                                  context.select<ScooterService, int?>(
                                        (service) => service.battery.secondarySOC,
                                      ) !=
                                      null))
                            Material(
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const BatteryScreen(),
                                  ),
                                ),
                                child: DashboardBatterySummary(
                                  primarySOC: context.select<ScooterService, int?>(
                                    (service) => service.battery.primarySOC,
                                  ),
                                  secondarySOC: context.select<ScooterService, int?>(
                                    (service) => service.battery.secondarySOC,
                                  ),
                                  dataIsOld: context.select<ScooterService, DateTime?>(
                                            (service) => service.identity.lastPing,
                                          ) ==
                                          null
                                      ? true
                                      : context
                                              .select<ScooterService, DateTime?>(
                                                (service) => service.identity.lastPing,
                                              )!
                                              .difference(DateTime.now())
                                              .inMinutes
                                              .abs() >
                                          5,
                                ),
                              ),
                            ),
                          Expanded(
                            child: ScooterVisual(
                              color: context.select<ScooterService, int?>(
                                    (service) => service.identity.color,
                                  ) ??
                                  1,
                              state: context.select(
                                (ScooterService service) => service.state,
                              ),
                              scanning: context.select(
                                (ScooterService service) => service.scanning,
                              ),
                              blinkerLeft: _hazards,
                              blinkerRight: _hazards,
                              winter: _snowing,
                              aprilFools: _forceHover,
                              halloween: _fall && context.isDarkMode,
                            ),
                          ),
                          Selector<ScooterService, bool>(
                            selector: (context, service) => service.identity.isLibrescoot == true || kDebugMode,
                            builder: (context, isLibrescoot, child) {
                              if (!isLibrescoot) return const SizedBox(height: 8);
                              return Semantics(
                                button: true,
                                label: FlutterI18n.translate(context, 'nav_title'),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _openNavigationSheet,
                                  onVerticalDragEnd: (details) {
                                    if ((details.primaryVelocity ?? 0) < -150) _openNavigationSheet();
                                  },
                                  child: SizedBox(
                                    height: 32,
                                    width: double.infinity,
                                    child: Center(
                                      child: Icon(
                                        Icons.keyboard_arrow_up_rounded,
                                        size: 24,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              const SeatButton(),
                              Selector<ScooterService, ScooterState?>(
                                selector: (context, service) => service.state,
                                builder: (context, state, _) {
                                  return Expanded(
                                    flex: 2,
                                    child: ScooterPowerButton(
                                      action: state != null && state.isReadyForLockChange
                                          ? (state.isOn
                                              ? () async {
                                                  if (context.read<ScooterService>().vehicle.seatClosed == false) {
                                                    bool overrideSeat = await showSeatWarning() == true;
                                                    if (!overrideSeat) {
                                                      return;
                                                    }
                                                  }
                                                  try {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    await context.read<ScooterService>().lock();
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    if (context.read<ScooterService>().hazardLocking) {
                                                      _flashHazards(1);
                                                    }
                                                  } on HandlebarLockException catch (_) {
                                                    log.warning(
                                                      "Handlebars are still unlocked, showing alert",
                                                    );
                                                    showHandlebarWarning(
                                                      didNotUnlock: false,
                                                    );
                                                  } catch (e, stack) {
                                                    log.severe(
                                                      "Problem opening the seat",
                                                      e,
                                                      stack,
                                                    );
                                                    Fluttertoast.showToast(
                                                      msg: e.toString(),
                                                    );
                                                  }
                                                }
                                              : (state == ScooterState.standby
                                                  ? () async {
                                                      try {
                                                        await context.read<ScooterService>().unlock();
                                                        if (context.mounted &&
                                                            context.read<ScooterService>().hazardLocking) {
                                                          _flashHazards(2);
                                                        }
                                                      } on HandlebarLockException catch (_) {
                                                        log.warning(
                                                          "Handlebars are still locked, showing alert",
                                                        );
                                                        showHandlebarWarning(
                                                          didNotUnlock: true,
                                                        );
                                                      } catch (e, stack) {
                                                        log.warning("Could not unlock scooter", e, stack);
                                                        if (context.mounted) {
                                                          Fluttertoast.showToast(
                                                            msg: FlutterI18n.translate(context, "home_unlock_failed"),
                                                          );
                                                        }
                                                      }
                                                    }
                                                  : () async {
                                                      try {
                                                        await context.read<ScooterService>().wakeUpAndUnlock();
                                                        if (context.mounted &&
                                                            context.read<ScooterService>().hazardLocking) {
                                                          _flashHazards(2);
                                                        }
                                                      } catch (e, stack) {
                                                        log.warning("Could not wake and unlock scooter", e, stack);
                                                        if (context.mounted) {
                                                          Fluttertoast.showToast(
                                                            msg: FlutterI18n.translate(context, "home_unlock_failed"),
                                                          );
                                                        }
                                                      }
                                                    }))
                                          : null,
                                      icon: state != null && state.isOn ? Icons.lock_outline : Icons.lock_open,
                                      label: state != null && state.isOn
                                          ? FlutterI18n.translate(context, "home_lock_button")
                                          : FlutterI18n.translate(context, "home_unlock_button"),
                                      instruction: state != null && state.isOn
                                          ? FlutterI18n.translate(context, "home_hold_to_lock")
                                          : FlutterI18n.translate(context, "home_hold_to_unlock"),
                                    ),
                                  );
                                },
                              ),
                              Selector<ScooterService, ({bool scanning, bool connected})>(
                                selector: (context, service) => (
                                  scanning: service.scanning,
                                  connected: service.connected,
                                ),
                                builder: (context, state, _) {
                                  return Expanded(
                                    child: ScooterActionButton(
                                      onPressed: !state.scanning
                                          ? () {
                                              if (!state.connected) {
                                                log.info(
                                                  "Manually reconnecting...",
                                                );
                                                try {
                                                  context.read<ScooterService>().start();
                                                } catch (e, stack) {
                                                  log.severe(
                                                    "Reconnect button failed",
                                                    e,
                                                    stack,
                                                  );
                                                }
                                              } else {
                                                showModalBottomSheet<void>(
                                                  context: context,
                                                  showDragHandle: true,
                                                  isScrollControlled: true,
                                                  builder: (BuildContext context) {
                                                    return ControlSheet();
                                                  },
                                                );
                                              }
                                            }
                                          : null,
                                      icon: !state.connected ? Icons.refresh_rounded : Icons.tune_rounded,
                                      label: !state.connected
                                          ? FlutterI18n.translate(
                                              context,
                                              "home_reconnect_button",
                                            )
                                          : FlutterI18n.translate(
                                              context,
                                              "home_controls_button",
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNavigationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.9,
        child: NavigationScreen(embedded: true),
      ),
    );
  }

  Future<bool?> showSeatWarning() async {
    HapticFeedback.vibrate();
    return await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SeatWarning(),
    );
  }

  void showHandlebarWarning({required bool didNotUnlock}) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return HandlebarWarning(didNotUnlock: didNotUnlock);
      },
    ).then((dontShowAgain) async {
      if (dontShowAgain == true) {
        Logger("").info("Not showing unlocked handlebar warning again");
        await SharedPreferencesAsync().setBool(
          "unlockedHandlebarsWarning",
          false,
        );
      }
    });
  }

  void redirectOrStart() async {
    List<String> ids = await context.read<ScooterService>().getSavedScooterIds();
    log.info("Saved scooters: $ids");
    if (mounted && ids.isEmpty && !kDebugMode) {
      FlutterNativeSplash.remove();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
    } else {
      // already onboarded, set up and proceed with home page
      _startSeasonal();
      _showNotifications();
      // start the scooter service if we're not coming from onboarding
      if (mounted && context.read<ScooterService>().myScooter == null) {
        context.read<ScooterService>().start();
      }
    }
    if ((await SharedPreferencesAsync().getBool("biometrics") ?? false) && mounted) {
      context.read<ScooterService>().optionalAuth = false;
      final LocalAuthentication auth = LocalAuthentication();
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: FlutterI18n.translate(context, "biometrics_message"),
        );
        if (!mounted) return;
        if (!didAuthenticate) {
          Fluttertoast.showToast(
            msg: FlutterI18n.translate(context, "biometrics_failed"),
          );
          Navigator.of(context).pop();
          SystemNavigator.pop();
        } else {
          context.read<ScooterService>().optionalAuth = true;
        }
      } catch (e, stack) {
        log.info("Biometrics failed", e, stack);

        Fluttertoast.showToast(
          msg: FlutterI18n.translate(context, "biometrics_failed"),
        );
        Navigator.of(context).pop();

        SystemNavigator.pop();
      }
    } else {
      if (mounted) context.read<ScooterService>().optionalAuth = true;
    }
  }
}

class SeatButton extends StatelessWidget {
  const SeatButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({bool? seatClosed, ScooterState? state})>(
      selector: (context, service) => (seatClosed: service.vehicle.seatClosed, state: service.state),
      builder: (context, data, _) {
        return Expanded(
          child: ScooterActionButton(
            onPressed: context.select((ScooterService service) => service.connected) &&
                    data.state != null &&
                    data.seatClosed == true &&
                    context.select(
                          (ScooterService service) => service.scanning,
                        ) ==
                        false &&
                    data.state!.isReadyForSeatOpen == true
                ? context.read<ScooterService>().openSeat
                : null,
            label: data.seatClosed == false
                ? FlutterI18n.translate(context, "home_seat_button_open")
                : FlutterI18n.translate(context, "home_seat_button_closed"),
            icon: data.seatClosed == false ? Icomoon.seat_open : Icomoon.seat_closed,
            iconColor: data.seatClosed == false ? Theme.of(context).colorScheme.error : null,
          ),
        );
      },
    );
  }
}

class DashboardBatterySummary extends StatelessWidget {
  const DashboardBatterySummary({
    required this.primarySOC,
    required this.secondarySOC,
    required this.dataIsOld,
    super.key,
  });

  final int? primarySOC;
  final int? secondarySOC;
  final bool dataIsOld;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totalRange = ((primarySOC ?? 0) * 0.45 + (secondarySOC ?? 0) * 0.45).round();
    final batteryValues = <String>[
      if (primarySOC != null) '${FlutterI18n.translate(context, 'home_primary_battery_short')} $primarySOC%',
      if (secondarySOC != null && secondarySOC! > 0)
        '${FlutterI18n.translate(context, 'home_secondary_battery_short')} $secondarySOC%',
    ];

    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 40).clamp(0.0, 320.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        child: Row(
          children: [
            Icon(
              Icons.battery_charging_full_outlined,
              color: dataIsOld ? colors.onSurfaceVariant : colors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalRange km · ${FlutterI18n.translate(context, 'stats_estimated_range')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    batteryValues.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class BatteryBars extends StatelessWidget {
  const BatteryBars({
    required this.primarySOC,
    required this.secondarySOC,
    required this.dataIsOld,
    this.compact = false,
    this.alignment = WrapAlignment.center,
    super.key,
  });

  final int? primarySOC;
  final int? secondarySOC;
  final bool? dataIsOld;
  final bool compact;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (primarySOC != null) ...[
          SizedBox(
            width: compact ? 40 : MediaQuery.of(context).size.width / 6,
            child: LinearProgressIndicator(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              minHeight: compact ? 6 : 8,
              borderRadius: BorderRadius.circular(8),
              value: primarySOC! / 100.0,
              color: (dataIsOld ?? true) // if null or true, data is old
                  ? Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4)
                  : primarySOC! <= 15
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "$primarySOC%",
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
        ],
        if (primarySOC != null && secondarySOC != null && secondarySOC! > 0) const VerticalDivider(),
        if (secondarySOC != null && secondarySOC! > 0) ...[
          SizedBox(
            width: compact ? 40 : MediaQuery.of(context).size.width / 6,
            child: LinearProgressIndicator(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              minHeight: compact ? 6 : 8,
              borderRadius: BorderRadius.circular(8),
              value: secondarySOC! / 100.0,
              color: (dataIsOld ?? true) // if null or true, data is old
                  ? Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4)
                  : secondarySOC! <= 15
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "$secondarySOC%",
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
        ],
      ],
    );
  }
}

class StatusText extends StatelessWidget {
  const StatusText({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
        ScooterService,
        ({
          bool connected,
          bool scanning,
          ScooterState? state,
          ScooterVehicleState? vehicleState,
          ScooterPowerState? powerState
        })>(
      selector: (context, service) => (
        state: service.state,
        scanning: service.scanning,
        connected: service.connected,
        vehicleState: service.vehicleState,
        powerState: service.powerState,
      ),
      builder: (context, data, _) {
        String stateText;

        if (data.scanning && (data.state == null || data.state == ScooterState.disconnected)) {
          stateText = context.read<ScooterService>().savedScooters.isNotEmpty
              ? FlutterI18n.translate(context, "home_scanning_known")
              : FlutterI18n.translate(context, "home_scanning");
        } else if (data.connected && data.vehicleState != null && data.powerState != null) {
          // Show vehicle state and power state separately (if power state is not running)
          stateText = data.vehicleState!.name(context);
          if (data.powerState != ScooterPowerState.running && data.powerState != ScooterPowerState.unknown) {
            // don't show unknown power states
            stateText += " · ${data.powerState!.name(context)}";
          }
        } else {
          stateText =
              data.state != null ? data.state!.name(context) : FlutterI18n.translate(context, "home_loading_state");
        }

        // Add handlebar unlocked indicator
        if (data.connected &&
            context.select<ScooterService, bool?>(
                  (service) => service.vehicle.handlebarsLocked,
                ) ==
                false) {
          stateText += FlutterI18n.translate(context, "home_unlocked");
        }

        final statusColor = data.connected
            ? Theme.of(context).colorScheme.primary
            : data.scanning
                ? const Color(0xFFEAB308)
                : Theme.of(context).colorScheme.outline;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                stateText,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
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
    required String instruction,
    bool? easterEgg,
  })  : _action = action,
        _icon = icon,
        _label = label,
        _instruction = instruction,
        _easterEgg = easterEgg;

  final void Function()? _action;
  final String _label;
  final String _instruction;
  final IconData _icon;
  final bool? _easterEgg;

  @override
  State<ScooterPowerButton> createState() => _ScooterPowerButtonState();
}

class _ScooterPowerButtonState extends State<ScooterPowerButton> {
  bool loading = false;
  final int randomEgg = Random().nextInt(8);
  double scale = 1.0;

  void _restoreScale() {
    if (!mounted || scale == 1) return;
    setState(() => scale = 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = widget._action == null;
    final mainColor = disabled ? colors.onSurface.withValues(alpha: 0.28) : colors.primary;
    final buttonColor = loading
        ? colors.surface
        : widget._easterEgg == true
            ? disabled
                ? colors.surfaceContainerHighest
                : Colors.white
            : disabled
                ? Colors.transparent
                : colors.primary;
    final foregroundColor = disabled
        ? mainColor
        : widget._easterEgg == true && !context.isDarkMode
            ? Colors.black87
            : colors.onPrimary;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget._label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: (_) {
              if (disabled || loading) return;
              setState(() => scale = 0.94);
            },
            onTapUp: (_) => _restoreScale(),
            onTapCancel: _restoreScale,
            onLongPressCancel: _restoreScale,
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: SizedBox(
                width: 144,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    backgroundColor: buttonColor,
                    disabledBackgroundColor: buttonColor,
                    side: BorderSide(color: mainColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: disabled ? null : () => Fluttertoast.showToast(msg: widget._instruction),
                  onLongPress: disabled
                      ? null
                      : () {
                          setState(() => loading = true);
                          widget._action!();
                          Future.delayed(const Duration(seconds: 5), () {
                            if (!mounted) return;
                            setState(() {
                              loading = false;
                              scale = 1;
                            });
                          });
                        },
                  child: Ink(
                    width: 144,
                    height: 56,
                    decoration: widget._easterEgg == true
                        ? BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage("images/decoration/egg_$randomEgg.webp"),
                              fit: BoxFit.cover,
                              opacity: disabled ? 0.3 : 1,
                            ),
                          )
                        : null,
                    child: Center(
                      child: loading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: mainColor, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(widget._icon, color: foregroundColor, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  widget._label,
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foregroundColor),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget._instruction,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
