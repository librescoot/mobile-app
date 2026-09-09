import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/ui/widgets/header.dart';
import 'package:unustasis/scooter_service.dart';

typedef _BatteryScreenViewData = ({
  int? primarySOC,
  int? primaryCycles,
  int? secondarySOC,
  int? secondaryCycles,
  int? cbbSOC,
  bool? cbbCharging,
  int? auxSOC,
  DateTime? lastPing,
});

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  final log = Logger("BatteryScreen");
  bool nfcScanning = false;
  int? nfcBattery;
  int? nfcCycles;
  bool showNfcNotice = false;

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, _BatteryScreenViewData>(
      selector: (context, service) => (
        primarySOC: service.battery.primarySOC,
        primaryCycles: service.battery.primaryCycles,
        secondarySOC: service.battery.secondarySOC,
        secondaryCycles: service.battery.secondaryCycles,
        cbbSOC: service.battery.cbbSOC,
        cbbCharging: service.battery.cbbCharging,
        auxSOC: service.battery.auxSOC,
        lastPing: service.identity.lastPing,
      ),
      builder: (context, data, _) {
        final int primarySoc = data.primarySOC ?? 0;
        final int secondarySoc = data.secondarySOC ?? 0;
        final bool hasPrimaryBattery = primarySoc > 0;
        final bool hasSecondaryBattery = secondarySoc > 0;
        final int primaryRange = hasPrimaryBattery ? (45 * (primarySoc / 100)).round() : 0;
        final int secondaryRange = hasSecondaryBattery ? (45 * (secondarySoc / 100)).round() : 0;
        final bool dataIsOld = data.lastPing == null || data.lastPing!.difference(DateTime.now()).inMinutes.abs() > 5;

        return Scaffold(
            appBar: AppBar(
              title: Text(FlutterI18n.translate(context, 'stats_title_battery')),
            ),
            body: ListView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewPadding.bottom),
              shrinkWrap: true,
              children: [
                const SizedBox(height: 16),
                _batteryOverview(
                  totalRange: primaryRange + secondaryRange,
                  throttledRange: math.max(0, primaryRange - 9) + math.max(0, secondaryRange - 9),
                  hasBatteries: hasPrimaryBattery || hasSecondaryBattery,
                  old: dataIsOld,
                ),
                Header(FlutterI18n.translate(context, 'stats_drive_batteries')),
                if (!hasPrimaryBattery && !hasSecondaryBattery)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      FlutterI18n.translate(context, 'stats_no_batteries'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                if (hasPrimaryBattery)
                  _batteryCard(
                    type: ScooterBatteryType.primary,
                    soc: primarySoc,
                    cycles: data.primaryCycles,
                    old: dataIsOld,
                  ),
                if (hasSecondaryBattery)
                  _batteryCard(
                    type: ScooterBatteryType.secondary,
                    soc: secondarySoc,
                    cycles: data.secondaryCycles,
                    old: dataIsOld,
                  ),
                Header(FlutterI18n.translate(context, 'stats_system_batteries')),
                _internalBatteryCard(
                  type: ScooterBatteryType.cbb,
                  soc: data.cbbSOC ?? 100,
                  charging: data.cbbCharging,
                  old: dataIsOld,
                  context: context,
                ),
                _internalBatteryCard(
                  type: ScooterBatteryType.aux,
                  soc: data.auxSOC ?? 100,
                  old: dataIsOld,
                  context: context,
                ),

                // only available on Android, hidden right now though
                if (Platform.isWindows)
                  Divider(
                    height: 40,
                    indent: 0,
                    endIndent: 0,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                if (nfcBattery != 0 && nfcBattery != null && !nfcScanning)
                  _batteryCard(
                    type: ScooterBatteryType.nfc,
                    soc: nfcBattery ?? 0,
                    cycles: nfcCycles,
                    old: false,
                  ),
                nfcScanning
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              FlutterI18n.translate(context, "stats_nfc_instructions"),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            if (showNfcNotice)
                              Text(
                                FlutterI18n.translate(context, "stats_nfc_notice"),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ))
                    : (Platform.isWindows)
                        // hiding until it works
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              onPressed: () async {
                                // Check availability
                                final availability = await FlutterNfcKit.nfcAvailability;
                                if (availability == NFCAvailability.not_supported && context.mounted) {
                                  Fluttertoast.showToast(
                                    msg: FlutterI18n.translate(context, "stats_nfc_not_available"),
                                  );
                                  setState(() {
                                    nfcScanning = false;
                                  });
                                  return;
                                } else if (availability == NFCAvailability.disabled && context.mounted) {
                                  Fluttertoast.showToast(
                                    msg: FlutterI18n.translate(context, "stats_nfc_not_enabled"),
                                  );
                                  setState(() {
                                    nfcScanning = false;
                                  });
                                  return;
                                }
                                setState(() {
                                  nfcScanning = true;
                                  showNfcNotice = false;
                                });
                                Timer noticeTimer = Timer(const Duration(seconds: 8), () {
                                  setState(() {
                                    showNfcNotice = true;
                                  });
                                });
                                // Start Session
                                try {
                                  final tag = await FlutterNfcKit.poll(
                                    androidCheckNDEF: false,
                                  );
                                  noticeTimer.cancel();
                                  setState(() {
                                    nfcScanning = false;
                                    nfcBattery = null;
                                    nfcCycles = null;
                                    showNfcNotice = false;
                                  });
                                  try {
                                    Uint8List socData;
                                    Uint8List cycleData;
                                    // Read from battery (Android only — MiFare Ultralight)
                                    if (Platform.isAndroid && tag.type == NFCTagType.mifare_ultralight) {
                                      socData = await FlutterNfcKit.readBlock(23);
                                      cycleData = await FlutterNfcKit.readBlock(20);
                                    } else {
                                      await FlutterNfcKit.finish();
                                      if (context.mounted) {
                                        Fluttertoast.showToast(
                                          msg: FlutterI18n.translate(context, "stats_nfc_invalid"),
                                        );
                                      }
                                      return;
                                    }
                                    await FlutterNfcKit.finish();

                                    // Parse data
                                    log.info("SOC Hex: ${socData.map((e) => e.toRadixString(16))}");
                                    int fullCap = 33000; //(socData[5] << 8) + socData[4];
                                    int remainingCap = (socData[3] << 8) + socData[1];
                                    int cycles = cycleData[0] - 1;
                                    log.info("Remaining: $remainingCap");
                                    log.info("Full: $fullCap");
                                    log.info("Cycles: $cycles");
                                    if (context.mounted) {
                                      setState(() {
                                        nfcBattery = (remainingCap / fullCap * 100).round();
                                        nfcCycles = cycles;
                                      });
                                    }
                                  } catch (e, stack) {
                                    log.severe("Error reading NFC", e, stack);
                                    await FlutterNfcKit.finish();
                                    Fluttertoast.showToast(
                                      msg: "Error reading NFC",
                                    );
                                  }
                                } catch (e) {
                                  noticeTimer.cancel();
                                  setState(() {
                                    nfcScanning = false;
                                    showNfcNotice = false;
                                  });
                                }
                              },
                              child: Text(
                                FlutterI18n.translate(context, "stats_nfc_button"),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          )
                        : Container(),
              ],
            ));
      },
    );
  }

  Widget _batteryOverview({
    required int totalRange,
    required int throttledRange,
    required bool hasBatteries,
    required bool old,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.route_outlined, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBatteries ? '$totalRange km' : '—',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  hasBatteries
                      ? FlutterI18n.translate(context, 'stats_estimated_range')
                      : FlutterI18n.translate(context, 'stats_no_batteries'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
                if (hasBatteries) ...[
                  const SizedBox(height: 4),
                  Text(
                    FlutterI18n.translate(
                      context,
                      'stats_range_until_throttled',
                      translationParams: {'range': '$throttledRange'},
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: old ? colors.onSurfaceVariant : colors.onSurface,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (old) Icon(Icons.history, size: 20, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _internalBatteryCard({
    required ScooterBatteryType type,
    required int soc,
    bool? charging,
    bool old = false,
    required BuildContext context,
  }) {
    final colors = Theme.of(context).colorScheme;
    final indicatorColor = old
        ? colors.onSurface.withValues(alpha: 0.35)
        : soc <= 15
            ? colors.error
            : colors.primary;

    void showDetails() {
      HapticFeedback.mediumImpact();
      switch (type) {
        case ScooterBatteryType.aux:
          showDialog(context: context, builder: (context) => _auxDiagnosticDialog(context));
        case ScooterBatteryType.cbb:
          showDialog(context: context, builder: (context) => _cbbDiagnosticDialog(context));
        default:
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: soc <= 15 && !old ? colors.error : colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: showDetails,
          onLongPress: showDetails,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      type == ScooterBatteryType.cbb ? Icons.memory_outlined : Icons.battery_saver_outlined,
                      color: indicatorColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(type.name(context), style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            type.description(context),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (charging == true) ...[
                      Icon(Icons.bolt, size: 18, color: colors.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(type.socText(soc, context), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: 8),
                    Icon(Icons.info_outline, size: 19, color: colors.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: soc.clamp(0, 100) / 100,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: colors.surfaceContainerHighest,
                  color: indicatorColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AlertDialog _auxDiagnosticDialog(BuildContext context) {
    int? auxSOC = context.select<ScooterService, int?>((service) => service.battery.auxSOC);
    AUXChargingState? auxCharging =
        context.select<ScooterService, AUXChargingState?>((service) => service.battery.auxCharging);
    int? auxVoltage = context.select<ScooterService, int?>((service) => service.battery.auxVoltage);
    DateTime? lastPing = context.select<ScooterService, DateTime?>((service) => service.identity.lastPing);

    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": "AUX"},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SOC: ${auxSOC ?? "Unknown"}%"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_charging_state")}: ${auxCharging?.name(context) ?? "Unknown "}"),
          Text("${FlutterI18n.translate(context, "stats_battery_voltage")}: ${auxVoltage ?? "Unknown "}mV"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_type")}: ${FlutterI18n.translate(context, "stats_aux_desc")}"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_last_update")}: ${lastPing?.toString().split('.').first ?? "Never"}"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(FlutterI18n.translate(context, "stats_diagnostics_close")),
        ),
      ],
    );
  }

  AlertDialog _cbbDiagnosticDialog(BuildContext context) {
    int? cbbSOC = context.select<ScooterService, int?>((service) => service.battery.cbbSOC);
    bool? cbbCharging = context.select<ScooterService, bool?>((service) => service.battery.cbbCharging);
    int? cbbVoltage = context.select<ScooterService, int?>((service) => service.battery.cbbVoltage);
    int? cbbCapacity = context.select<ScooterService, int?>((service) => service.battery.cbbCapacity);
    DateTime? lastPing = context.select<ScooterService, DateTime?>((service) => service.identity.lastPing);

    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": "CBB"},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SOC: ${cbbSOC ?? "Unknown"}%"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_charging_state")}: ${cbbCharging == true ? "Charging" : cbbCharging == false ? "Not charging" : "Unknown"}"),
          Text("${FlutterI18n.translate(context, "stats_battery_voltage")}: ${cbbVoltage ?? "Unknown "}mV"),
          Text("${FlutterI18n.translate(context, "stats_battery_capacity")}: ${cbbCapacity ?? "Unknown "}mAh"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_type")}: ${FlutterI18n.translate(context, "stats_cbb_desc")}"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_last_update")}: ${lastPing?.toString().split('.').first ?? "Never"}"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(FlutterI18n.translate(context, "stats_diagnostics_close")),
        ),
      ],
    );
  }

  Widget _batteryCard({
    required ScooterBatteryType type,
    required int soc,
    int? cycles,
    bool old = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final range = (45 * (soc / 100)).round();
    final indicatorColor = old
        ? colors.onSurface.withValues(alpha: 0.35)
        : soc <= 15
            ? colors.error
            : colors.primary;

    void showDetails() {
      HapticFeedback.mediumImpact();
      switch (type) {
        case ScooterBatteryType.primary:
        case ScooterBatteryType.secondary:
          showDialog(
            context: context,
            builder: (context) => _mainBatteryDiagnosticDialog(context, type, soc, cycles),
          );
        case ScooterBatteryType.nfc:
          showDialog(context: context, builder: (context) => _nfcBatteryDiagnosticDialog(context, soc, cycles));
        default:
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: soc <= 15 && !old ? colors.error : colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: showDetails,
          onLongPress: showDetails,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(type.name(context), style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            type.description(context),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text(type.socText(soc, context), style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: soc.clamp(0, 100) / 100,
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(5),
                  backgroundColor: colors.surfaceContainerHighest,
                  color: indicatorColor,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.route_outlined, size: 17, color: colors.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text('$range km'),
                    if (cycles != null) ...[
                      const SizedBox(width: 20),
                      Icon(Icons.refresh, size: 17, color: colors.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text('${FlutterI18n.translate(context, 'stats_battery_cycles')}: $cycles'),
                    ],
                    const Spacer(),
                    Icon(Icons.info_outline, size: 19, color: colors.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AlertDialog _mainBatteryDiagnosticDialog(BuildContext context, ScooterBatteryType type, int soc, int? cycles) {
    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": type.name(context).toUpperCase()},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SOC: $soc%"),
          if (cycles != null) Text("${FlutterI18n.translate(context, "stats_battery_cycles")}: $cycles"),
          Text("${FlutterI18n.translate(context, "stats_battery_range")}: ${(45 * (soc / 100)).round()} km"),
          Text("${FlutterI18n.translate(context, "stats_battery_capacity")}: ${(soc * 450).round()} Wh / 45000 Wh"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_last_update")}: ${context.select<ScooterService, DateTime?>(
                    (service) => service.identity.lastPing,
                  )?.toString().split('.').first ?? "Never"}"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(FlutterI18n.translate(context, "stats_diagnostics_close")),
        ),
      ],
    );
  }

  AlertDialog _nfcBatteryDiagnosticDialog(BuildContext context, int soc, int? cycles) {
    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": "NFC"},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SOC: $soc%"),
          if (cycles != null) Text("${FlutterI18n.translate(context, "stats_battery_cycles")}: $cycles"),
          Text("${FlutterI18n.translate(context, "stats_battery_range")}: ${(45 * (soc / 100)).round()} km"),
          Text("${FlutterI18n.translate(context, "stats_battery_capacity")}: ${(soc * 450).round()} Wh / 45000 Wh"),
          Text("${FlutterI18n.translate(context, "stats_battery_read_method")}: NFC"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(FlutterI18n.translate(context, "stats_diagnostics_close")),
        ),
      ],
    );
  }
}
