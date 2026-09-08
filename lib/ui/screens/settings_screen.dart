import 'dart:async';
import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:unustasis/domain/alarm_status.dart';
import 'package:unustasis/ui/theme/theme_helper.dart';
import 'package:unustasis/domain/scooter_keyless_distance.dart';
import 'package:unustasis/ui/widgets/header.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/ls_keycard_screen.dart';
import 'package:unustasis/ui/screens/ls_ota_screen.dart';
import 'package:unustasis/ui/screens/ls_scheduled_hibernation_screen.dart';
import 'package:unustasis/service/ble_commands.dart';
import 'package:unustasis/state/vehicle_status.dart';
import 'package:unustasis/ui/screens/log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final log = Logger('SettingsScreen');
  bool backgroundScan = false;
  bool biometrics = false;
  bool autoUnlock = false;
  bool seasonal = true;
  ScooterKeylessDistance autoUnlockDistance = ScooterKeylessDistance.regular;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;
  bool osmConsent = true;
  bool _lsDataLoadStarted = false;
  bool _isSendingAutoLock = false;
  int? _autoLockDuration;
  bool _timerDurationsLoaded = false;
  bool _isSendingAutoHibernate = false;
  int? _autoHibernateDuration;
  int? _keycardCount;
  bool _isSendingApn = false;
  bool _isUpdatingUsbMode = false;
  bool _isSendingTime = false;
  bool _apnLoaded = false;
  String? _apn;
  bool _isSendingBatteryKeepActive = false;
  bool? _batteryKeepActive;
  bool _isSendingAlarmEnabled = false;
  bool? _alarmEnabled;
  bool _isSendingAlarmHonk = false;
  bool? _alarmHonk;
  final TextEditingController _apnController = TextEditingController();
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();

  void getInitialSettings() async {
    ScooterService service = context.read<ScooterService>();
    bool initialBackgroundScan = await prefs.getBool("backgroundScan") ?? false;
    bool initialBiometrics = await prefs.getBool("biometrics") ?? false;
    bool initialAutoUnlock = service.autoUnlock;
    ScooterKeylessDistance initialAutoUnlockDistance =
        ScooterKeylessDistance.fromThreshold(service.autoUnlockThreshold);
    bool initialOpenSeatOnUnlock = service.openSeatOnUnlock;
    bool initialHazardLocking = service.hazardLocking;
    bool initialOsmConsent = await prefs.getBool("osmConsent") ?? true;
    bool initialSeasonal = await prefs.getBool("seasonal") ?? true;

    setState(() {
      backgroundScan = initialBackgroundScan;
      biometrics = initialBiometrics;
      autoUnlock = initialAutoUnlock;
      autoUnlockDistance = initialAutoUnlockDistance;
      openSeatOnUnlock = initialOpenSeatOnUnlock;
      hazardLocking = initialHazardLocking;
      osmConsent = initialOsmConsent;
      seasonal = initialSeasonal;
    });
  }

  @override
  void initState() {
    super.initState();
    getInitialSettings();
  }

  @override
  void dispose() {
    _apnController.dispose();
    super.dispose();
  }

  void _ensureLsDataLoaded(bool isLibrescoot) {
    final service = context.read<ScooterService>();
    if (!isLibrescoot || !service.connected || _lsDataLoadStarted) return;
    _lsDataLoadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getKeycardCount();
      _getTimerDurations();
      _getApn();
      _getBatteryKeepActive();
      _getAlarmSettings();
    });
  }

  Future<void> _getKeycardCount() async {
    final count = await context.read<ScooterService>().actions.countKeycards();
    if (mounted) setState(() => _keycardCount = count);
  }

  Future<void> _getBatteryKeepActive() async {
    bool? enabled;
    try {
      enabled = await context.read<ScooterService>().getBatteryKeepActive();
    } catch (_) {
      enabled = null;
    }
    if (mounted) setState(() => _batteryKeepActive = enabled);
  }

  Future<void> _setBatteryKeepActive(bool enabled) async {
    setState(() => _isSendingBatteryKeepActive = true);
    try {
      await context.read<ScooterService>().setBatteryKeepActive(enabled);
      if (!mounted) return;
      setState(() => _batteryKeepActive = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context,
              enabled ? "ls_settings_battery_keep_active_on_success" : "ls_settings_battery_keep_active_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_error",
              translationParams: {"error": e.toString()})),
        ),
      );
      // The scooter kept its old value, so re-read rather than leaving the
      // switch showing something the scooter never accepted.
      unawaited(_getBatteryKeepActive());
    } finally {
      if (mounted) setState(() => _isSendingBatteryKeepActive = false);
    }
  }

  Future<void> _getAlarmSettings() async {
    if (!mounted) return;
    bool? enabled;
    bool? honk;
    try {
      final service = context.read<ScooterService>();
      enabled = await service.getAlarmEnabled();
      honk = await service.getAlarmHonk();
    } catch (e) {
      enabled = null;
      honk = null;
    }
    if (!mounted) return;
    setState(() {
      _alarmEnabled = enabled;
      _alarmHonk = honk;
    });
  }

  Future<void> _setAlarmEnabled(bool enabled) async {
    setState(() {
      _isSendingAlarmEnabled = true;
    });
    try {
      await context.read<ScooterService>().setAlarmEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _alarmEnabled = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
              context, enabled ? "ls_settings_alarm_on_success" : "ls_settings_alarm_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              FlutterI18n.translate(context, "ls_settings_alarm_error", translationParams: {"error": e.toString()})),
        ),
      );
      unawaited(_getAlarmSettings());
    } finally {
      if (mounted) {
        setState(() {
          _isSendingAlarmEnabled = false;
        });
      }
    }
  }

  Future<void> _setAlarmHonk(bool enabled) async {
    setState(() {
      _isSendingAlarmHonk = true;
    });
    try {
      await context.read<ScooterService>().setAlarmHonk(enabled);
      if (!mounted) return;
      setState(() {
        _alarmHonk = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
              context, enabled ? "ls_settings_alarm_honk_on_success" : "ls_settings_alarm_honk_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_error",
              translationParams: {"error": e.toString()})),
        ),
      );
      unawaited(_getAlarmSettings());
    } finally {
      if (mounted) {
        setState(() {
          _isSendingAlarmHonk = false;
        });
      }
    }
  }

  /// Answers "would the scooter notice if someone moved it right now?", plus
  /// the wake timer and last trigger when there are any.
  String _alarmWatchSubtitle(BuildContext context, VehicleStatus vehicle) {
    final sources = vehicle.alarmWakeSources;
    final parts = <String>[];
    if (sources != null) {
      parts.add(FlutterI18n.translate(context,
          sources.motionWouldWake ? "ls_settings_alarm_watch_motion_on" : "ls_settings_alarm_watch_motion_off"));
      if (sources.wakeTimerDuration != null) {
        parts.add(FlutterI18n.translate(context, "ls_settings_alarm_watch_timer",
            translationParams: {"duration": _formatDuration(sources.wakeTimerDuration!)}));
      }
    }
    final trigger = vehicle.alarmLastTrigger;
    if (trigger != null) {
      final source = FlutterI18n.translate(context, "alarm_trigger_${trigger.source}");
      if (trigger.timestamp != null) {
        parts.add(FlutterI18n.translate(context, "ls_settings_alarm_watch_last_trigger",
            translationParams: {"source": source, "when": _formatTimestamp(context, trigger.timestamp!)}));
      } else {
        parts.add(FlutterI18n.translate(context, "ls_settings_alarm_watch_last_trigger_unknown_time",
            translationParams: {"source": source}));
      }
    }
    if (parts.isEmpty) {
      return FlutterI18n.translate(context, "ls_settings_alarm_watch_loading");
    }
    return parts.join(" ");
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final parts = [
      if (hours > 0) "${hours}h",
      if (minutes > 0) "${minutes}m",
    ];
    return parts.isEmpty ? "${duration.inSeconds}s" : parts.join(" ");
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final local = timestamp.toLocal();
    final loc = MaterialLocalizations.of(context);
    final time = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return "${loc.formatMediumDate(local)} $time";
  }

  List<Widget> alarmItems() {
    if (context.watch<ScooterService>().identity.supportsAlarmControl != true) return [];
    final service = context.watch<ScooterService>();
    // The two switches ride the extended channel; everything else needs the
    // alarm service, which older firmware doesn't have.
    final bool live = service.characteristicRepository.alarmAvailable;
    final AlarmStatus? status = service.vehicle.alarmStatus;
    return [
      ListTile(
        leading: Icon(Icons.notifications_active_outlined),
        title: Text(FlutterI18n.translate(context, "ls_settings_alarm_title")),
        subtitle: Text(live && status != null
            ? status.name(context)
            : FlutterI18n.translate(context, "ls_settings_alarm_subtitle")),
        trailing: _alarmEnabled == null
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _alarmEnabled!,
                onChanged: _isSendingAlarmEnabled ? null : _setAlarmEnabled,
              ),
      ),
      ListTile(
        leading: Icon(Icons.campaign_outlined),
        title: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_title")),
        subtitle: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_subtitle")),
        trailing: _alarmHonk == null
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _alarmHonk!,
                onChanged: _isSendingAlarmHonk ? null : _setAlarmHonk,
              ),
      ),
      if (live)
        ListTile(
          leading: Icon(Icons.visibility_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_alarm_watch_title")),
          subtitle: Text(_alarmWatchSubtitle(context, service.vehicle)),
        ),
    ];
  }

  Future<void> _getTimerDurations() async {
    try {
      final service = context.read<ScooterService>();
      final values = await Future.wait([
        service.actions.getSetting(lsKeyAutoStandbySeconds),
        service.actions.getSetting(lsKeyHibernateTimer),
      ]);
      if (!mounted) return;
      setState(() {
        _autoLockDuration = int.tryParse(values[0] ?? "");
        _autoHibernateDuration = int.tryParse(values[1] ?? "");
        _timerDurationsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _timerDurationsLoaded = true);
    }
  }

  Widget _timerLoadingIndicator() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Future<void> _getApn() async {
    String? apn;
    try {
      apn = await context.read<ScooterService>().getCellularApn();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _apn = apn;
        _apnLoaded = true;
      });
    }
  }

  String _apnSubtitle(BuildContext context) {
    if (!_apnLoaded) return FlutterI18n.translate(context, "ls_settings_apn_loading");
    if (_apn == null) return FlutterI18n.translate(context, "ls_settings_apn_unknown");
    return _apn!.isEmpty ? FlutterI18n.translate(context, "ls_settings_apn_unset") : _apn!;
  }

  String? _apnErrorText(BuildContext context, ApnProblem? problem) {
    switch (problem) {
      case null:
      case ApnProblem.empty:
        return null;
      case ApnProblem.invalidCharacters:
        return FlutterI18n.translate(context, "ls_settings_apn_invalid_chars");
      case ApnProblem.tooLong:
        return FlutterI18n.translate(
          context,
          "ls_settings_apn_invalid_length",
          translationParams: {"max": maxApnLength.toString()},
        );
    }
  }

  Future<void> _editApn() async {
    final controller = _apnController..text = _apn ?? "";
    final picked = await showDialog<({bool clear, String value})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final trimmed = controller.text.trim();
          final problem = checkApn(trimmed);
          return AlertDialog(
            title: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_dialog_title")),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_dialog_body")),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  textCapitalization: TextCapitalization.none,
                  maxLength: maxApnLength,
                  decoration: InputDecoration(
                    hintText: FlutterI18n.translate(dialogContext, "ls_settings_apn_hint"),
                    border: const OutlineInputBorder(),
                    errorText: _apnErrorText(dialogContext, problem),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (problem == null) Navigator.of(dialogContext).pop((clear: false, value: trimmed));
                  },
                ),
              ],
            ),
            actions: [
              if (_apn != null && _apn!.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
                  onPressed: () => Navigator.of(dialogContext).pop((clear: true, value: "")),
                  child: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_clear")),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(FlutterI18n.translate(dialogContext, "cancel")),
              ),
              FilledButton(
                onPressed:
                    problem == null ? () => Navigator.of(dialogContext).pop((clear: false, value: trimmed)) : null,
                child: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_save")),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _isSendingApn = true);
    try {
      final service = context.read<ScooterService>();
      if (picked.clear) {
        await service.clearCellularApn();
      } else {
        await service.setCellularApn(picked.value);
      }
      if (!mounted) return;
      setState(() => _apn = picked.value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(
          context,
          picked.clear ? "ls_settings_apn_cleared" : "ls_settings_apn_success",
        ))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(
          context,
          "ls_settings_apn_error",
          translationParams: {"error": e.toString()},
        ))),
      );
    } finally {
      if (mounted) setState(() => _isSendingApn = false);
    }
  }

  List<Widget> _librescootAccessSettingsItems() => [
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text(FlutterI18n.translate(context, "ls_keycard_title")),
          subtitle: Text(_keycardCount != null
              ? FlutterI18n.translate(context, "ls_settings_keycards_count",
                  translationParams: {"count": _keycardCount.toString()})
              : FlutterI18n.translate(context, "ls_settings_keycards_loading")),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsKeycardScreen())),
        ),
      ];

  List<Widget> _librescootPowerSettingsItems({
    required bool supportsScheduledHibernation,
    required bool supportsBatteryKeepActive,
  }) =>
      [
        ListTile(
          leading: const Icon(Icons.hourglass_bottom_rounded),
          title: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_subtitle")),
          trailing: SizedBox(
            width: 128,
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: 144,
              value: _autoLockDuration,
              hint: _timerDurationsLoaded
                  ? Text(FlutterI18n.translate(context, "ls_settings_duration_hint"))
                  : _timerLoadingIndicator(),
              items: [
                DropdownMenuItem(value: 0, child: Text(FlutterI18n.translate(context, "ls_settings_duration_never"))),
                DropdownMenuItem(value: 180, child: Text(FlutterI18n.translate(context, "ls_settings_duration_3_min"))),
                DropdownMenuItem(value: 300, child: Text(FlutterI18n.translate(context, "ls_settings_duration_5_min"))),
                DropdownMenuItem(
                    value: 600, child: Text(FlutterI18n.translate(context, "ls_settings_duration_10_min"))),
                DropdownMenuItem(
                    value: 900, child: Text(FlutterI18n.translate(context, "ls_settings_duration_15_min"))),
              ],
              onChanged: !_timerDurationsLoaded || _isSendingAutoLock
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() => _isSendingAutoLock = true);
                      try {
                        await context.read<ScooterService>().actions.setAutoStandbyTime(Duration(seconds: value),
                        );
                        if (!mounted) return;
                        setState(() => _autoLockDuration = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_success"))),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(FlutterI18n.translate(
                              context,
                              "ls_settings_auto_lock_error",
                              translationParams: {"error": e.toString()},
                            ))),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isSendingAutoLock = false);
                      }
                    },
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_subtitle")),
          trailing: SizedBox(
            width: 128,
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: 144,
              value: _autoHibernateDuration,
              hint: _timerDurationsLoaded
                  ? Text(FlutterI18n.translate(context, "ls_settings_duration_hint"))
                  : _timerLoadingIndicator(),
              items: [
                DropdownMenuItem(value: 0, child: Text(FlutterI18n.translate(context, "ls_settings_duration_never"))),
                DropdownMenuItem(
                    value: 3600, child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_hour"))),
                DropdownMenuItem(
                    value: 86400, child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_day"))),
                DropdownMenuItem(
                    value: 259200, child: Text(FlutterI18n.translate(context, "ls_settings_duration_3_days"))),
                DropdownMenuItem(
                    value: 604800, child: Text(FlutterI18n.translate(context, "ls_settings_duration_7_days"))),
                DropdownMenuItem(
                    value: 1209600, child: Text(FlutterI18n.translate(context, "ls_settings_duration_14_days"))),
              ],
              onChanged: !_timerDurationsLoaded || _isSendingAutoHibernate
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() => _isSendingAutoHibernate = true);
                      try {
                        await context.read<ScooterService>().actions.setAutoHibernateTime(Duration(seconds: value),
                        );
                        if (!mounted) return;
                        setState(() => _autoHibernateDuration = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_success"))),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(FlutterI18n.translate(
                              context,
                              "ls_settings_auto_hibernate_error",
                              translationParams: {"error": e.toString()},
                            ))),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isSendingAutoHibernate = false);
                      }
                    },
            ),
          ),
        ),
        if (supportsScheduledHibernation)
          ListTile(
            leading: const SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                children: [
                  Positioned(left: 0, top: 0, child: Icon(Icons.bedtime_outlined, size: 22)),
                  Positioned(right: 0, top: 0, child: Icon(Icons.access_time_filled, size: 12)),
                ],
              ),
            ),
            title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_scheduled_hibernation_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LsScheduledHibernationScreen()),
            ),
          ),
        if (supportsBatteryKeepActive)
          ListTile(
            leading: const Icon(Icons.battery_charging_full_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_subtitle")),
            trailing: _batteryKeepActive == null
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Switch(
                    value: _batteryKeepActive!,
                    onChanged: _isSendingBatteryKeepActive ? null : _setBatteryKeepActive,
                  ),
          ),
      ];

  List<Widget> _librescootConnectivitySettingsItems({
    required bool supportsApnConfig,
  }) =>
      [
        if (supportsApnConfig)
          ListTile(
            leading: const Icon(Icons.cell_tower_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_apn_title")),
            subtitle: Text(_apnSubtitle(context)),
            trailing: _isSendingApn
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _isSendingApn ? null : _editApn,
          ),
      ];

  Future<void> _syncScooterClock() async {
    setState(() => _isSendingTime = true);
    try {
      final service = context.read<ScooterService>();
      final result = await service.actions.setClock(DateTime.now());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FlutterI18n.translate(
              context,
              result == "time:ok" ? "ls_settings_clock_success" : "ls_settings_clock_error",
              translationParams: result == "time:ok" ? null : {"result": result ?? ""},
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingTime = false);
    }
  }

  List<Widget> _librescootUpdateSettingsItems({
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) =>
      [
        ListTile(
          leading: const Icon(Icons.access_time_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_clock_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_clock_subtitle")),
          trailing: _isSendingTime
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded),
          onTap: connected && !_isSendingTime ? _syncScooterClock : null,
        ),
        if (connected && otaAvailable)
          ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_ota_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_ota_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsOtaScreen())),
          ),
        ListTile(
          leading: const Icon(Icons.usb_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_update_mode_title")),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                usbMode == UsbMode.massStorage
                    ? FlutterI18n.translate(context, "ls_settings_update_mode_on_subtitle")
                    : FlutterI18n.translate(context, "ls_settings_update_mode_off_subtitle"),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => launchUrl(Uri.parse("https://librescoot.org/docs/ums.html")),
                child: Text(FlutterI18n.translate(context, "ls_settings_update_mode_learn_more")),
              ),
            ],
          ),
          trailing: Switch(
            value: usbMode == UsbMode.massStorage,
            onChanged: _isUpdatingUsbMode
                ? null
                : (value) async {
                    setState(() => _isUpdatingUsbMode = true);
                    try {
                      final service = context.read<ScooterService>();
                      if (value) {
                        await service.actions.enterUMSMode();
                      } else {
                        await service.actions.enterNormalUsbMode();
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(FlutterI18n.translate(
                          context,
                          value ? "ls_settings_update_mode_enter_success" : "ls_settings_update_mode_exit_success",
                        ))),
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(FlutterI18n.translate(
                            context,
                            "ls_settings_update_mode_error",
                            translationParams: {"error": e.toString()},
                          ))),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isUpdatingUsbMode = false);
                    }
                  },
          ),
        ),
      ];

  List<Widget> settingsItems({
    required bool isLibrescoot,
    required bool supportsScheduledHibernation,
    required bool supportsBatteryKeepActive,
    required bool supportsAlarmControl,
    required bool supportsApnConfig,
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) =>
      [
        Header(
          FlutterI18n.translate(context, "settings_section_access_parking"),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_open),
          title: Text(FlutterI18n.translate(context, "settings_auto_unlock")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_auto_unlock_description"),
          ),
          value: autoUnlock,
          onChanged: (value) async {
            if (value == true) {
              // Check location permission (required for Bluetooth proximity detection)
              bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled && mounted) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "location_services_disabled"),
                  toastLength: Toast.LENGTH_LONG,
                );
                return;
              }

              LocationPermission permission = await Geolocator.checkPermission();
              if (permission == LocationPermission.denied) {
                permission = await Geolocator.requestPermission();
                if (permission == LocationPermission.denied && mounted) {
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(context, "location_permission_denied"),
                    toastLength: Toast.LENGTH_LONG,
                  );
                  return;
                }
              }

              if (permission == LocationPermission.deniedForever && mounted) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "location_permission_denied_forever"),
                  toastLength: Toast.LENGTH_LONG,
                );
                return;
              }
            }

            if (!mounted) return;

            context.read<ScooterService>().setAutoUnlock(value);
            setState(() {
              autoUnlock = value;
            });
          },
        ),
        if (autoUnlock)
          ListTile(
            title: Text(
              "${FlutterI18n.translate(context, "settings_auto_unlock_threshold")}: ${autoUnlockDistance.name(context)}",
            ),
            subtitle: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: autoUnlockDistance.threshold.toDouble(),
                  min: ScooterKeylessDistance.getMinThresholdDistance().threshold.toDouble(),
                  max: ScooterKeylessDistance.getMaxThresholdDistance().threshold.toDouble(),
                  secondaryTrackValue: context.read<ScooterService>().identity.rssi?.toDouble(),
                  divisions: ScooterKeylessDistance.values.length - 1,
                  label: autoUnlockDistance.getFormattedThreshold(),
                  onChanged: (value) async {
                    var distance = ScooterKeylessDistance.fromThreshold(
                      value.toInt(),
                    );
                    context.read<ScooterService>().setAutoUnlockThreshold(
                          value.toInt(),
                        );
                    setState(() {
                      autoUnlockDistance = distance;
                    });
                  },
                ),
                if (context.read<ScooterService>().identity.rssi != null)
                  Text(
                    FlutterI18n.translate(
                      context,
                      "settings_auto_unlock_threshold_explainer",
                      translationParams: {
                        "rssi": context.read<ScooterService>().identity.rssi.toString(),
                      },
                    ),
                  ),
              ],
            ),
          ),
        SwitchListTile(
          secondary: SvgPicture.asset(
            "assets/icons/librescoot-seatbox-open.svg",
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.primary,
              BlendMode.srcIn,
            ),
          ),
          title: Text(
            FlutterI18n.translate(context, "settings_open_seat_on_unlock"),
          ),
          subtitle: Text(
            FlutterI18n.translate(
              context,
              "settings_open_seat_on_unlock_description",
            ),
          ),
          value: openSeatOnUnlock,
          onChanged: (value) async {
            context.read<ScooterService>().setOpenSeatOnUnlock(value);
            setState(() {
              openSeatOnUnlock = value;
            });
          },
        ),
        SwitchListTile(
          secondary: const ImageIcon(
            AssetImage("assets/icons/librescoot-blinkers.png"),
            size: 24,
          ),
          title: Text(FlutterI18n.translate(context, "settings_hazard_locking")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_hazard_locking_description"),
          ),
          value: hazardLocking,
          onChanged: (value) async {
            context.read<ScooterService>().setHazardLocking(value);
            setState(() {
              hazardLocking = value;
            });
          },
        ),
        if (isLibrescoot) ..._librescootAccessSettingsItems(),
        if (isLibrescoot) ...[
          Header(FlutterI18n.translate(context, "settings_section_power")),
          ..._librescootPowerSettingsItems(
            supportsScheduledHibernation: supportsScheduledHibernation,
            supportsBatteryKeepActive: supportsBatteryKeepActive,
          ),
        ],
        if (isLibrescoot && supportsAlarmControl) ...[
          Header(FlutterI18n.translate(context, "ls_settings_section_alarm")),
          ...alarmItems(),
        ],
        if (Platform.isAndroid || (isLibrescoot && supportsApnConfig)) ...[
          Header(FlutterI18n.translate(context, "settings_section_connectivity")),
          if (isLibrescoot)
            ..._librescootConnectivitySettingsItems(
              supportsApnConfig: supportsApnConfig,
            ),
        ],
        if (Platform.isAndroid)
          SwitchListTile(
            secondary: const Icon(Icons.find_replace_outlined),
            title: Text(FlutterI18n.translate(context, "settings_background_scan")),
            subtitle: Text(
              FlutterI18n.translate(
                context,
                "settings_background_scan_description",
              ),
            ),
            value: backgroundScan,
            onChanged: (value) async {
              bool? confirmed;
              if (value == true) {
                // Request notification permission first
                final notificationPlugin = FlutterLocalNotificationsPlugin();
                final granted = await notificationPlugin
                    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                    ?.requestNotificationsPermission();

                if (granted != true && mounted) {
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(context, "notification_permission_denied"),
                    toastLength: Toast.LENGTH_LONG,
                  );
                  return;
                }

                // warn before turning on
                if (mounted) {
                  confirmed = await showBackgroundScanWarning(context);
                }
              } else {
                // no warning for turning off
                confirmed = true;
              }
              if (confirmed == true) {
                await prefs.setBool("backgroundScan", value);
                // inform the service!
                FlutterBackgroundService().invoke("update", {
                  "backgroundScan": value,
                });
                setState(() {
                  backgroundScan = value;
                });
              }
            },
          ),
        if (isLibrescoot) ...[
          Header(FlutterI18n.translate(context, "settings_section_updates_service")),
          ..._librescootUpdateSettingsItems(
            usbMode: usbMode,
            connected: connected,
            otaAvailable: otaAvailable,
          ),
        ],
        Header(FlutterI18n.translate(context, "stats_settings_section_app")),
        FutureBuilder<List<BiometricType>>(
          future: LocalAuthentication().getAvailableBiometrics(),
          builder: (context, biometricsOptionsSnap) {
            if (biometricsOptionsSnap.hasData && biometricsOptionsSnap.data!.isNotEmpty) {
              return SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: Text(FlutterI18n.translate(context, "settings_biometrics")),
                subtitle: Text(
                  FlutterI18n.translate(context, "settings_biometrics_description"),
                ),
                value: biometrics,
                onChanged: (value) async {
                  final LocalAuthentication auth = LocalAuthentication();
                  try {
                    final bool didAuthenticate = await auth.authenticate(
                      localizedReason: FlutterI18n.translate(
                        context,
                        "biometrics_message",
                      ),
                    );
                    if (didAuthenticate) {
                      await prefs.setBool("biometrics", value);
                      setState(() {
                        biometrics = value;
                      });
                    } else {
                      if (context.mounted) {
                        Fluttertoast.showToast(
                          msg: FlutterI18n.translate(context, "biometrics_failed"),
                        );
                      }
                    }
                  } catch (e, stack) {
                    if (context.mounted) {
                      log.warning("Biometrics error", e, stack);
                      Fluttertoast.showToast(
                        msg: FlutterI18n.translate(context, "biometrics_failed"),
                      );
                    }
                  }
                },
              );
            } else {
              return Container();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: Text(FlutterI18n.translate(context, "settings_theme")),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SegmentedButton<ThemeMode>(
              onSelectionChanged: (newTheme) {
                context.setThemeMode(newTheme.first);
              },
              showSelectedIcon: false,
              selected: {EasyDynamicTheme.of(context).themeMode!},
              style: ButtonStyle(
                iconColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.onTertiary;
                  }
                  return Theme.of(context).colorScheme.onSurface;
                }),
                backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.primary;
                  }
                  return Colors.transparent;
                }),
              ),
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.light
                        ? Icons.light_mode
                        : Icons.light_mode_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_light"),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.dark
                        ? Icons.nights_stay
                        : Icons.nights_stay_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_dark"),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.system
                        ? Icons.brightness_auto
                        : Icons.brightness_auto_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_system"),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(FlutterI18n.translate(context, "settings_language")),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<Locale>(
              initialValue: FlutterI18n.currentLocale(context)!,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(16),
                border: OutlineInputBorder(),
              ),
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
              items: [
                DropdownMenuItem<Locale>(
                  value: const Locale("en"),
                  child: Text(FlutterI18n.translate(context, "language_en")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("en", "GB"),
                  child: Text(FlutterI18n.translate(context, "language_en_gb")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("de"),
                  child: Text(FlutterI18n.translate(context, "language_de")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("fr"),
                  child: Text(FlutterI18n.translate(context, "language_fr")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("nl"),
                  child: Text(FlutterI18n.translate(context, "language_nl")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("pi"),
                  child: Text(FlutterI18n.translate(context, "language_pi")),
                ),
              ],
              onChanged: (Locale? newLanguage) async {
                await FlutterI18n.refresh(context, newLanguage);
                final tag = newLanguage!.countryCode != null
                    ? '${newLanguage.languageCode}_${newLanguage.countryCode}'
                    : newLanguage.languageCode;
                await prefs.setString("savedLocale", tag);
                setState(() {});
              },
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.pin_drop_outlined),
          title: Text(FlutterI18n.translate(context, "settings_osm_consent")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_osm_consent_description"),
          ),
          value: osmConsent,
          onChanged: (value) async {
            await prefs.setBool("osmConsent", value);
            setState(() {
              osmConsent = value;
            });
          },
        ),
        if (DateTime.now().month == 12 ||
            DateTime.now().month == 4 ||
            DateTime.now().month == 10) // All seasonal months
          SwitchListTile(
            secondary: const Icon(Icons.star),
            title: Text(FlutterI18n.translate(context, "settings_seasonal")),
            subtitle: Text(FlutterI18n.translate(context, "settings_seasonal_description")),
            value: seasonal,
            onChanged: (value) async {
              await prefs.setBool("seasonal", value);
              setState(() {
                seasonal = value;
              });
            },
          ),
        if (kDebugMode)
          ListTile(
            title: Text(FlutterI18n.translate(context, "activity_log_title")),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LogScreen(),
                ),
              );
            },
            leading: const Icon(Icons.history_outlined),
            trailing: const Icon(Icons.chevron_right),
          ),
        Container(),
      ];

  @override
  Widget build(BuildContext context) {
    final ls = context.select<
        ScooterService,
        ({
          bool isLibrescoot,
          bool supportsScheduled,
          bool supportsBatteryKeepActive,
          bool supportsAlarmControl,
          bool supportsApn,
          UsbMode? usbMode,
          bool connected,
          bool otaAvailable
        })>(
      (service) => (
        isLibrescoot: service.identity.isLibrescoot == true,
        supportsScheduled: service.identity.supportsScheduledHibernation == true,
        supportsBatteryKeepActive: service.identity.supportsBatteryKeepActive == true,
        supportsAlarmControl: service.identity.supportsAlarmControl == true,
        supportsApn: service.identity.supportsApnConfig == true,
        usbMode: service.vehicle.usbMode,
        connected: service.connected,
        otaAvailable: service.connected && service.characteristicRepository.otaAvailable,
      ),
    );
    _ensureLsDataLoaded(ls.isLibrescoot);
    final items = settingsItems(
      isLibrescoot: ls.isLibrescoot,
      supportsScheduledHibernation: ls.supportsScheduled,
      supportsBatteryKeepActive: ls.supportsBatteryKeepActive,
      supportsAlarmControl: ls.supportsAlarmControl,
      supportsApnConfig: ls.supportsApn,
      usbMode: ls.usbMode,
      connected: ls.connected,
      otaAvailable: ls.otaAvailable,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_settings')),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (context, index) => Divider(
            indent: 16,
            endIndent: 16,
            height: 24,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          itemBuilder: (context, index) => items[index],
        ),
      ),
    );
  }

  Future<bool?> showBackgroundScanWarning(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            FlutterI18n.translate(context, "bgscan_warning_title"),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FlutterI18n.translate(context, "bgscan_warning_intro"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Icon(Icons.battery_alert_outlined, size: 32),
                ),
              ),
              Text(
                FlutterI18n.translate(context, "bgscan_warning_battery"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(child: Icon(Icons.link_off_outlined, size: 32)),
              ),
              Text(
                FlutterI18n.translate(context, "bgscan_warning_lostpairing"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Icon(Icons.power_settings_new_outlined, size: 32),
                ),
              ),
              Text(
                FlutterI18n.translate(
                  context,
                  "bgscan_warning_accidentalturnon",
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                FlutterI18n.translate(context, "forget_alert_cancel"),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(
                FlutterI18n.translate(context, "bgscan_warning_confirm"),
              ),
            ),
          ],
        );
      },
    );
  }
}
