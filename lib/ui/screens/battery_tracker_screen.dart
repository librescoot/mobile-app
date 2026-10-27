import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../scooter_service.dart';
import '../../service/battery_nfc_reader.dart';
import '../../service/battery_tracker_store.dart';
import '../wide_layout.dart';

class BatteryTrackerScreen extends StatefulWidget {
  const BatteryTrackerScreen({
    super.key,
    this.store,
    this.readBluetooth,
    this.readNfc,
    this.openRegistration,
  });

  final BatteryTrackerStore? store;
  final Future<List<BatteryIdentity>> Function()? readBluetooth;
  final Future<BatteryIdentity> Function()? readNfc;
  final Future<bool> Function(Uri)? openRegistration;

  @override
  State<BatteryTrackerScreen> createState() => _BatteryTrackerScreenState();
}

class _BatteryTrackerScreenState extends State<BatteryTrackerScreen> {
  late final BatteryTrackerStore _store;
  final _nfc = BatteryNfcReader();
  List<BatteryIdentity> _latest = [];
  bool _busy = true;
  bool _scanningNfc = false;

  String _text(String key) => FlutterI18n.translate(context, 'battery_tracker_$key');

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? BatteryTrackerStore();
    _store.addListener(_changed);
    _run(() => _store.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    if (widget.store == null) _store.dispose();
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
        final identities = await read();
        if (!mounted) return;
        await _store.remember(identities);
        if (!mounted) return;
        setState(() => _latest = identities);
        if (identities.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('empty'))));
        }
      });

  Future<void> _readNfc() async {
    setState(() => _scanningNfc = true);
    try {
      await _read(() async => [await (widget.readNfc?.call() ?? _nfc.read())]);
    } finally {
      if (mounted) setState(() => _scanningNfc = false);
    }
  }

  Future<void> _register(BatteryIdentity identity) async {
    var verified = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
                title: Text(_text('register')),
                content: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(identity.serialNumber),
                    const SizedBox(height: 16),
                    Text(_text('upload_consent')),
                    const SizedBox(height: 12),
                    Text(_text('claim_notice')),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: verified,
                      title: Text(_text('verify')),
                      onChanged: (value) => setDialogState(() => verified = value ?? false),
                    ),
                  ],
                )),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_text('cancel'))),
                  FilledButton(
                    onPressed: verified ? () => Navigator.pop(context, true) : null,
                    child: Text(_text('continue')),
                  ),
                ],
              )),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final uri = batteryRegistrationUri(identity);
      final opened = await (widget.openRegistration?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Browser unavailable');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('finish_browser'))));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.readBluetooth != null || context.watch<ScooterService>().connected;
    final nfcSupported = widget.readNfc != null || Platform.isAndroid || Platform.isIOS;
    final batteries = <String, BatteryIdentity>{
      for (final battery in _store.batteries) battery.serialNumber: battery,
      for (final battery in _latest) battery.serialNumber: battery,
    }.values.toList()
      ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    return Scaffold(
      appBar: AppBar(title: Text(_text('title'))),
      body: ListView(
        padding: wideContentPadding(context, base: const EdgeInsets.all(16)),
        children: [
          Text(_text('description')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_text('remember')),
            subtitle: Text(_text('local_notice')),
            value: _store.enabled,
            onChanged: _busy ? null : (value) => _run(() => _store.setEnabled(value)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.bluetooth),
            label: Text(_text('read_ble')),
            onPressed: _busy || !connected
                ? null
                : () => _read(widget.readBluetooth ?? context.read<ScooterService>().actions.readBatteryIdentities),
          ),
          Text(_text('ble_notice'), style: Theme.of(context).textTheme.bodySmall),
          OutlinedButton.icon(
            icon: const Icon(Icons.nfc),
            label: Text(_text('read_nfc')),
            onPressed: _busy || !nfcSupported ? null : _readNfc,
          ),
          Text(_text('nfc_notice'), style: Theme.of(context).textTheme.bodySmall),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_scanningNfc) TextButton(onPressed: () => _nfc.cancel(), child: Text(_text('cancel'))),
          const SizedBox(height: 16),
          if (batteries.isEmpty && !_busy) Text(_text('empty')),
          for (final battery in batteries)
            Card(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(battery.serialNumber, style: Theme.of(context).textTheme.titleMedium),
                Text('${battery.source.name.toUpperCase()} · ${_text('checked')}: ${battery.checkedAt.toLocal()}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton(onPressed: _busy ? null : () => _register(battery), child: Text(_text('register'))),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await _store.forget(battery.serialNumber);
                                if (mounted) {
                                  setState(
                                      () => _latest.removeWhere((entry) => entry.serialNumber == battery.serialNumber));
                                }
                              }),
                      child: Text(_text('forget'))),
                ]),
              ]),
            )),
          const SizedBox(height: 16),
          Text(_text('delete_notice'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
