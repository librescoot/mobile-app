import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../feature_flags.dart';
import '../../scooter_service.dart';
import '../../service/battery_nfc_reader.dart';
import '../../service/battery_read_failure.dart';
import '../widgets/battery_tracking_intro.dart';

enum _TrackerStep { welcome, read, verify, share, browser }

class BatteryTrackerScreen extends StatefulWidget {
  const BatteryTrackerScreen({
    super.key,
    this.readBluetooth,
    this.readNfc,
    this.openBrowser,
    this.bluetoothSupported,
    this.startWithScan = false,
    this.registrationEnabled = sunshineBatteryRegistrationEnabled,
  });

  final Future<List<BatteryIdentity>> Function()? readBluetooth;
  final Future<BatteryIdentity> Function()? readNfc;
  final Future<bool> Function(Uri)? openBrowser;
  final bool? bluetoothSupported;
  final bool startWithScan;
  final bool registrationEnabled;

  @override
  State<BatteryTrackerScreen> createState() => _BatteryTrackerScreenState();
}

class _BatteryTrackerScreenState extends State<BatteryTrackerScreen> {
  final _nfc = BatteryNfcReader();
  late _TrackerStep _step = widget.startWithScan ? _TrackerStep.read : _TrackerStep.welcome;
  List<BatteryIdentity> _readings = [];
  BatteryIdentity? _selected;
  bool _busy = false;
  bool _scanningNfc = false;
  String? _error;
  int _readGeneration = 0;

  String _text(String key) => FlutterI18n.translate(context, 'battery_tracker_$key');

  @override
  void dispose() {
    _readGeneration++;
    unawaited(_nfc.cancel().catchError((Object _) {}));
    super.dispose();
  }

  void _startReading() {
    setState(() {
      _step = _TrackerStep.read;
      _readings = [];
      _selected = null;
      _error = null;
    });
  }

  void _back() {
    _readGeneration++;
    if (_scanningNfc) unawaited(_nfc.cancel().catchError((Object _) {}));
    setState(() {
      _busy = false;
      _scanningNfc = false;
      _error = null;
      _step = switch (_step) {
        _TrackerStep.verify => _TrackerStep.read,
        _TrackerStep.share => _TrackerStep.verify,
        _ => _TrackerStep.welcome,
      };
      if (_step == _TrackerStep.read || _step == _TrackerStep.welcome) {
        _readings = [];
        _selected = null;
      }
    });
  }

  Future<void> _read({required bool nfc}) async {
    if (_busy) return;
    final generation = ++_readGeneration;
    setState(() {
      _busy = true;
      _scanningNfc = nfc;
      _readings = [];
      _selected = null;
      _error = null;
    });
    try {
      final readings = nfc
          ? [await (widget.readNfc?.call() ?? _nfc.read())]
          : await (widget.readBluetooth?.call() ?? context.read<ScooterService>().actions.readBatteryIdentities());
      if (!mounted || generation != _readGeneration) return;
      final unique = <String, BatteryIdentity>{for (final reading in readings) reading.serialNumber: reading};
      setState(() {
        _readings = unique.values.toList();
        if (_readings.isEmpty) {
          _error = 'no_readings';
        } else {
          _selected = _readings.first;
          _step = _TrackerStep.verify;
        }
      });
    } catch (error) {
      if (mounted && generation == _readGeneration) {
        final reason = batteryReadFailureReason(error);
        Logger('BatteryTracker').warning('Battery read failed: source=${nfc ? 'nfc' : 'ble'} reason=$reason');
        setState(() => _error = batteryReadFailureMessage(reason, nfc: nfc));
      }
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() {
          _busy = false;
          _scanningNfc = false;
        });
      }
    }
  }

  Future<void> _openBrowser(Uri uri, {bool registration = false}) async {
    if (_busy || !widget.registrationEnabled) return;
    final generation = _readGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await (widget.openBrowser?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Browser unavailable');
      if (mounted && generation == _readGeneration && registration) setState(() => _step = _TrackerStep.browser);
    } catch (_) {
      if (mounted && generation == _readGeneration) setState(() => _error = 'account_open_error');
    } finally {
      if (mounted && generation == _readGeneration) setState(() => _busy = false);
    }
  }

  Widget _primary(String label, VoidCallback? action, {Key? key, IconData icon = Icons.arrow_forward}) =>
      FilledButton.icon(
        key: key,
        onPressed: _busy ? null : action,
        icon: Icon(icon, size: 20),
        label: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_text(label))),
      );

  Widget _heading(String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_text(title), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(_text(body), style: Theme.of(context).textTheme.bodyLarge),
        ]),
      );

  Widget _progress() {
    final current = switch (_step) {
      _TrackerStep.read => 0,
      _TrackerStep.verify => 1,
      _ => 2,
    };
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: FlutterI18n.translate(context, 'battery_tracker_step', translationParams: {'number': '${current + 1}'}),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: Container(height: 3, color: i <= current ? colors.primary : colors.outlineVariant)),
          ],
        ]),
        const SizedBox(height: 12),
        Text(_text(['step_read', 'step_verify', 'step_share'][current]),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.primary)),
      ]),
    );
  }

  Widget _details() => ExpansionTile(
        key: const ValueKey('battery-tracker-details'),
        tilePadding: EdgeInsets.zero,
        title: Text(_text('how_it_works'), style: Theme.of(context).textTheme.bodyMedium),
        childrenPadding: const EdgeInsets.only(bottom: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text('how_it_works_body')),
          const SizedBox(height: 12),
          Text(_text('claim_short')),
        ],
      );

  Widget _manage() => TextButton(
        key: const ValueKey('manage-battery-tracker'),
        onPressed: _busy ? null : () => _openBrowser(batteryTrackerRegistrationsUri()),
        child: Text(_text('manage_account')),
      );

  List<Widget> _welcome() => [
        const SizedBox(height: 16),
        BatteryTrackingIntro(registrationEnabled: widget.registrationEnabled),
        const SizedBox(height: 32),
        _primary('add', _startReading, key: const ValueKey('add-battery'), icon: Icons.add),
        const SizedBox(height: 8),
        if (widget.registrationEnabled) _manage(),
        const SizedBox(height: 28),
        _details(),
      ];

  Widget _source({required bool nfc, required bool enabled, required String subtitle}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: BorderSide(color: colors.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('battery-source-${nfc ? 'nfc' : 'bluetooth'}'),
          enabled: enabled && !_busy,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: Icon(nfc ? Icons.nfc : Icons.bluetooth, color: enabled ? colors.primary : colors.onSurfaceVariant),
          title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_text(nfc ? 'read_nfc' : 'read_ble')),
            if (!nfc) const BatteryFirmwareBadge(),
          ]),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(_text(subtitle))),
          trailing: enabled ? const Icon(Icons.chevron_right) : null,
          onTap: enabled && !_busy ? () => _read(nfc: nfc) : null,
        ),
      ),
    );
  }

  List<Widget> _chooseSource() {
    final service = widget.readBluetooth == null ? context.watch<ScooterService>() : null;
    final connected = widget.readBluetooth != null || service!.connected;
    final supported =
        widget.readBluetooth != null ? widget.bluetoothSupported ?? true : service!.identity.supportsBatteryIdentity;
    final bluetooth = _source(
        nfc: false,
        enabled: connected && supported == true,
        subtitle: !connected
            ? 'ble_connect'
            : supported == null
                ? 'ble_checking'
                : supported
                    ? 'ble_ready'
                    : 'ble_unsupported');
    final nfc = _source(
        nfc: true, enabled: widget.readNfc != null || Platform.isAndroid || Platform.isIOS, subtitle: 'nfc_short');
    return [
      _progress(),
      _heading('read_title', 'read_body'),
      if (_busy) ...[
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(_text(_scanningNfc ? 'nfc_notice' : 'reading_ble'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextButton(onPressed: _back, child: Text(_text('cancel'))),
      ] else ...[
        if (connected && supported == true) ...[bluetooth, nfc] else ...[nfc, bluetooth],
        const SizedBox(height: 12),
        Text(_text('check_privacy'), style: Theme.of(context).textTheme.bodySmall),
      ],
    ];
  }

  Widget _serialPanel(BatteryIdentity battery, {bool selected = true, bool selectable = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? colors.primary.withValues(alpha: 0.6) : colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_text('serial'), style: Theme.of(context).textTheme.labelMedium)),
          if (selectable) Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
        ]),
        const SizedBox(height: 10),
        if (selectable)
          Text(battery.serialNumber, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'monospace'))
        else
          SelectableText(battery.serialNumber,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 10),
        Text(_text(battery.source == BatteryIdentitySource.ble ? 'source_ble' : 'source_nfc'),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  List<Widget> _verify() => [
        _progress(),
        _heading('verify_title', _readings.length > 1 ? 'verify_multiple' : 'verify_body'),
        for (final battery in _readings)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _readings.length == 1
                ? _serialPanel(battery)
                : Semantics(
                    selected: identical(battery, _selected),
                    button: true,
                    child: InkWell(
                      key: ValueKey('battery-reading-${battery.serialNumber}'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _selected = battery),
                      child: _serialPanel(battery, selected: identical(battery, _selected), selectable: true),
                    ),
                  ),
          ),
        const SizedBox(height: 12),
        _primary('verify_match', () => setState(() => _step = _TrackerStep.share),
            key: const ValueKey('battery-label-verification'), icon: Icons.check),
        const SizedBox(height: 8),
        TextButton(onPressed: _startReading, child: Text(_text('verify_mismatch'))),
      ];

  List<Widget> _share() => [
        _progress(),
        _heading('share_title', 'share_body'),
        _serialPanel(_selected!),
        const SizedBox(height: 24),
        Text(_text('upload_consent'), key: const ValueKey('battery-sharing-disclosure')),
        const SizedBox(height: 24),
        _primary(
            'continue',
            widget.registrationEnabled
                ? () => _openBrowser(batteryRegistrationUri(_selected!), registration: true)
                : null,
            key: const ValueKey('battery-register-continue'),
            icon: Icons.open_in_browser),
        if (!widget.registrationEnabled) ...[
          const SizedBox(height: 12),
          Text(_text('account_unavailable')),
        ],
        const SizedBox(height: 16),
        _details(),
      ];

  List<Widget> _browser() => [
        const SizedBox(height: 32),
        Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.open_in_browser, size: 48, color: Theme.of(context).colorScheme.primary)),
        _heading('finish_title', 'finish_browser'),
        _serialPanel(_selected!),
        const SizedBox(height: 24),
        _primary('return_browser', () => _openBrowser(batteryRegistrationUri(_selected!), registration: true),
            icon: Icons.open_in_browser),
        const SizedBox(height: 8),
        TextButton(onPressed: _startReading, child: Text(_text('add_another'))),
        const SizedBox(height: 12),
        if (widget.registrationEnabled) _manage(),
      ];

  @override
  Widget build(BuildContext context) {
    final children = switch (_step) {
      _TrackerStep.welcome => _welcome(),
      _TrackerStep.read => _chooseSource(),
      _TrackerStep.verify => _verify(),
      _TrackerStep.share => _share(),
      _TrackerStep.browser => _browser(),
    };
    return PopScope(
      canPop: _step == _TrackerStep.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_text('title')),
          leading: _step == _TrackerStep.welcome ? null : BackButton(onPressed: _back),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              key: ValueKey(_step),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                ...children,
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Semantics(
                        liveRegion: true,
                        child: Text(_text(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
