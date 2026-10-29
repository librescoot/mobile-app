import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../scooter_service.dart';
import '../../feature_flags.dart';
import '../../service/battery_nfc_reader.dart';
import '../wide_layout.dart';
import '../widgets/battery_tracking_intro.dart';

enum _BatterySource { bluetooth, nfc }

class BatteryTrackerScreen extends StatefulWidget {
  const BatteryTrackerScreen({
    super.key,
    this.readBluetooth,
    this.readNfc,
    this.openBrowser,
    this.bluetoothSupported,
    this.registrationEnabled = sunshineBatteryRegistrationEnabled,
  });

  final Future<List<BatteryIdentity>> Function()? readBluetooth;
  final Future<BatteryIdentity> Function()? readNfc;
  final Future<bool> Function(Uri)? openBrowser;
  final bool? bluetoothSupported;
  final bool registrationEnabled;

  @override
  State<BatteryTrackerScreen> createState() => _BatteryTrackerScreenState();
}

class _BatteryTrackerScreenState extends State<BatteryTrackerScreen> {
  final _nfc = BatteryNfcReader();
  List<BatteryIdentity> _latest = [];
  bool _busy = false;
  bool _scanningNfc = false;
  bool _dialogOpen = false;

  String _text(String key) => FlutterI18n.translate(context, 'battery_tracker_$key');

  @override
  void dispose() {
    unawaited(_nfc.cancel().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (mounted) setState(() => _busy = true);
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('error'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read(Future<List<BatteryIdentity>> Function() read) => _run(() async {
        setState(() => _latest = []);
        final identities = await read();
        if (!mounted) return;
        setState(() => _latest = identities);
        if (identities.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('no_readings'))));
        }
      });

  Future<void> _addBattery({required bool connected, required bool? supported}) async {
    if (_busy || _dialogOpen) return;
    _dialogOpen = true;
    final canReadBluetooth = connected && supported == true;
    final canReadNfc = widget.readNfc != null || Platform.isAndroid || Platform.isIOS;
    final source = await showModalBottomSheet<_BatterySource>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final bluetooth = ListTile(
          key: const ValueKey('battery-source-bluetooth'),
          enabled: canReadBluetooth,
          leading: const Icon(Icons.bluetooth),
          title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_text('read_ble')),
            const BatteryFirmwareBadge(),
          ]),
          subtitle: Text(_text(!connected
              ? 'ble_connect'
              : supported == null
                  ? 'ble_checking'
                  : supported
                      ? 'ble_ready'
                      : 'ble_unsupported')),
          trailing: const Icon(Icons.chevron_right),
          onTap: canReadBluetooth ? () => Navigator.pop(context, _BatterySource.bluetooth) : null,
        );
        final nfc = ListTile(
          key: const ValueKey('battery-source-nfc'),
          enabled: canReadNfc,
          leading: const Icon(Icons.nfc),
          title: Text(_text('read_nfc')),
          subtitle: Text(_text(canReadNfc ? 'nfc_short' : 'nfc_unavailable')),
          trailing: const Icon(Icons.chevron_right),
          onTap: canReadNfc ? () => Navigator.pop(context, _BatterySource.nfc) : null,
        );
        return SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_text('add'), style: Theme.of(context).textTheme.headlineSmall)),
            if (canReadBluetooth) ...[bluetooth, nfc] else ...[nfc, bluetooth],
            const SizedBox(height: 12),
            Text(_text('check_privacy'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ));
      },
    );
    _dialogOpen = false;
    if (!mounted || source == null) return;
    if (source == _BatterySource.bluetooth) {
      await _read(widget.readBluetooth ?? context.read<ScooterService>().actions.readBatteryIdentities);
    } else {
      setState(() => _scanningNfc = true);
      try {
        await _read(() async => [await (widget.readNfc?.call() ?? _nfc.read())]);
      } finally {
        if (mounted) setState(() => _scanningNfc = false);
      }
    }
  }

  Future<void> _openBrowser(Uri uri, {bool registration = false}) => _run(() async {
        final opened = await (widget.openBrowser?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
        if (!opened) throw StateError('Browser unavailable');
        if (mounted && registration) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('finish_browser'))));
        }
      });

  Future<void> _register(BatteryIdentity identity) async {
    if (_busy || _dialogOpen || !widget.registrationEnabled) return;
    _dialogOpen = true;
    var verified = false;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child:
                      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(_text('register_title'), style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    _serialPanel(identity),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const ValueKey('battery-label-verification'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: verified,
                      title: Text(_text('verify')),
                      onChanged: (value) => setDialogState(() => verified = value ?? false),
                    ),
                    const Divider(height: 32),
                    Text(_text('upload_consent')),
                    const SizedBox(height: 12),
                    Text(_text('claim_short'), style: Theme.of(context).textTheme.bodySmall),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(_text('how_registration_works')),
                      children: [
                        Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_text('claim_notice')))
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('battery-register-continue'),
                      onPressed: verified ? () => Navigator.pop(context, true) : null,
                      icon: const Icon(Icons.open_in_browser),
                      label: Text(_text('continue')),
                    ),
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_text('not_now'))),
                  ]),
                ),
              )),
    );
    _dialogOpen = false;
    if (confirmed != true || !mounted) return;
    await _openBrowser(batteryRegistrationUri(identity), registration: true);
  }

  Widget _serialPanel(BatteryIdentity identity) => DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_text('serial'), style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(identity.serialNumber,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: 'monospace')),
              const SizedBox(height: 4),
              Text(_text(identity.source == BatteryIdentitySource.ble ? 'source_ble' : 'source_nfc'),
                  style: Theme.of(context).textTheme.bodySmall),
            ])),
      );

  Widget _batteryCard(BatteryIdentity battery, int index) {
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.battery_5_bar, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      FlutterI18n.translate(context, 'battery_tracker_battery_number',
                          translationParams: {'number': '${index + 1}'}),
                      style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: _text('dismiss_reading'),
                icon: const Icon(Icons.close),
                onPressed: _busy
                    ? null
                    : () => setState(() => _latest.removeWhere((entry) => entry.serialNumber == battery.serialNumber)),
              ),
            ]),
            const SizedBox(height: 8),
            _serialPanel(battery),
            const SizedBox(height: 12),
            Text(_text('not_registered'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _busy || !widget.registrationEnabled ? null : () => _register(battery),
              icon: const Icon(Icons.wb_sunny_outlined),
              label: Text(_text('register')),
            ),
          ]),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.readBluetooth == null ? context.watch<ScooterService>() : null;
    final connected = widget.readBluetooth != null || service!.connected;
    final supported =
        widget.readBluetooth != null ? (widget.bluetoothSupported ?? true) : service!.identity.supportsBatteryIdentity;
    final colors = Theme.of(context).colorScheme;
    final batteries = <String, BatteryIdentity>{
      for (final battery in _latest) battery.serialNumber: battery,
    }.values.toList();
    return Scaffold(
      appBar: AppBar(title: Text(_text('title'))),
      body: ListView(
        padding: wideContentPadding(context, base: const EdgeInsets.fromLTRB(16, 8, 16, 24)),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [colors.primaryContainer, colors.surfaceContainerHigh],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: Image.asset('images/battery/batt_full.webp', height: 96, excludeFromSemantics: true)),
              const SizedBox(height: 12),
              Text(_text('hero_title'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(_text('description')),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('join-battery-tracker'),
                onPressed: _busy || !widget.registrationEnabled ? null : () => _openBrowser(batteryTrackerJoinUri()),
                icon: const Icon(Icons.group_add_outlined),
                label: Text(_text('join')),
              ),
              if (widget.registrationEnabled)
                TextButton(
                  onPressed: _busy ? null : () => _openBrowser(batteryTrackerRegistrationsUri()),
                  child: Text(_text('manage_account')),
                ),
              const SizedBox(height: 12),
              Text(_text(widget.registrationEnabled ? 'account_body' : 'account_unavailable'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
          if (_scanningNfc) ...[
            Padding(padding: const EdgeInsets.all(16), child: Text(_text('nfc_notice'), textAlign: TextAlign.center)),
            TextButton(onPressed: () => _nfc.cancel(), child: Text(_text('cancel'))),
          ],
          const SizedBox(height: 24),
          Text(_text('register_title'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_text('read_for_registration')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('add-battery'),
            onPressed: _busy ? null : () => _addBattery(connected: connected, supported: supported),
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(_text('add')),
          ),
          for (var index = 0; index < batteries.length; index++) _batteryCard(batteries[index], index),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(_text('privacy_title')),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_text('email_verification_notice')),
                  const SizedBox(height: 12),
                  Text(_text('delete_notice')),
                ]),
              )
            ],
          ),
        ],
      ),
    );
  }
}
