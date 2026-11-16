import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/cloud_pairing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../scooter_service.dart';

@visibleForTesting
Uri cloudPairingUrl(String code) => Uri.parse('https://connect.librescoot.org/pair#code=$code');

class CloudPairingScreen extends StatefulWidget {
  const CloudPairingScreen({super.key});

  @override
  State<CloudPairingScreen> createState() => _CloudPairingScreenState();
}

class _CloudPairingScreenState extends State<CloudPairingScreen> with WidgetsBindingObserver {
  ScooterService? _service;
  String? _scooterId;
  bool _connected = false;
  bool _busy = false;
  bool? _supported;
  String? _error;
  CloudPairingStatus? _status;
  Timer? _timer;
  int _generation = 0;

  String _text(String key, {Map<String, String>? params}) =>
      FlutterI18n.translate(context, key, translationParams: params);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (identical(service, _service)) return;
    _service?.removeListener(_connectionChanged);
    _service = service;
    service.addListener(_connectionChanged);
    _connectionChanged();
  }

  void _connectionChanged() {
    final service = _service!;
    if (_connected == service.connected && _scooterId == service.currentScooterId) return;
    _timer?.cancel();
    _generation++;
    _connected = service.connected;
    _scooterId = service.currentScooterId;
    _supported = null;
    _status = null;
    _error = null;
    _busy = false;
    if (mounted) setState(() {});
    if (_connected) _probe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _connected && _supported == true && !_busy) {
      _request('status');
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _service?.removeListener(_connectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _probe() async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supported = await _service!.actions.supportsCloudPairing();
      if (!mounted || generation != _generation) return;
      setState(() {
        _supported = supported;
        _busy = false;
      });
      if (supported) await _request('status');
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = 'connect_pairing_error';
      });
    }
  }

  Future<void> _request(String action) async {
    if (_busy || !_connected) return;
    _timer?.cancel();
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service!.actions.cloudPairing(action);
      if (!mounted || generation != _generation) return;
      setState(() => _status = result);
      if (result.running) {
        _timer = Timer(const Duration(seconds: 3), () => _request('status'));
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'connect_pairing_error');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final service = _service!;
    final id = _scooterId;
    final generation = _generation;
    final name = service.savedScooters[id]?.name ?? id ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('connect_pairing_confirm_title')),
        content: Text(_text('connect_pairing_confirm_body', params: {'scooter': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_text('connect_pairing_start'))),
        ],
      ),
    );
    if (confirmed == true && mounted && generation == _generation) await _request('start');
  }

  Future<void> _openConnect(String code) async {
    bool opened;
    try {
      opened = await launchUrl(cloudPairingUrl(code), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('connect_pairing_open_error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final code = status?.code;
    final codeValid = code != null && status?.expiresAt?.isAfter(DateTime.now()) == true;
    return Scaffold(
      appBar: AppBar(title: Text(_text('connect_pairing_title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(_text('connect_pairing_intro')),
        const SizedBox(height: 16),
        if (!_connected)
          Text(_text('connect_pairing_disconnected'))
        else if (_supported == false)
          Text(_text('connect_pairing_unsupported'))
        else ...[
          if (_scooterId != null)
            Text(_text('connect_pairing_scooter',
                params: {'scooter': _service!.savedScooters[_scooterId]?.name ?? _scooterId!})),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_text('connect_pairing_state_${status!.state}')),
          ],
          if (codeValid) ...[
            const SizedBox(height: 16),
            SelectableText(code, style: Theme.of(context).textTheme.headlineMedium),
            Text(_text('connect_pairing_code_help')),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('connect_pairing_copied'))));
                }
              },
              icon: const Icon(Icons.copy),
              label: Text(_text('connect_pairing_copy')),
            ),
            FilledButton.icon(
                onPressed: () => _openConnect(code),
                icon: const Icon(Icons.open_in_new),
                label: Text(_text('connect_pairing_open'))),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_text(_error!)),
            TextButton(
                onPressed: _busy ? null : (_supported == null ? _probe : () => _request('status')),
                child: Text(_text('connect_pairing_retry'))),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_supported == true && status != null && status.state != 'connected') ...[
            const SizedBox(height: 16),
            if (!status.running)
              FilledButton(onPressed: _busy ? null : _start, child: Text(_text('connect_pairing_start')))
            else
              OutlinedButton(
                  onPressed: _busy ? null : () => _request('stop'), child: Text(_text('connect_pairing_stop'))),
          ],
        ],
      ]),
    );
  }
}
