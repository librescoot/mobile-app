import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/sms_commands.dart';
import 'package:unustasis/scooter_service.dart';

class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({super.key});
  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> {
  ScooterService? _service;
  String? _scooterId;
  bool _connected = false;
  int _generation = 0;
  bool _loading = false;
  String? _errorKey;

  String _text(String key, {Map<String, String>? params}) =>
      FlutterI18n.translate(context, key, translationParams: params);

  String _forwardStatus(String status) {
    const known = {'queued', 'sending', 'sent', 'unknown', 'expired', 'cancelled'};
    return known.contains(status) ? _text('sms_status_$status') : status;
  }

  SmsInbox? _inbox;
  String? _forward;
  final TextEditingController _forwardController = TextEditingController();

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
    _connected = service.connected;
    _scooterId = service.currentScooterId;
    _generation++;
    _inbox = null;
    _forward = null;
    _errorKey = null;
    _loading = false;
    if (mounted) setState(() {});
    if (_connected) _load();
  }

  @override
  void dispose() {
    _generation++;
    _service?.removeListener(_connectionChanged);
    _forwardController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = _service;
    if (service == null || !service.connected || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final inbox = await service.actions.readSmsInbox();
      final forward = await service.actions.getSetting('sms.forward-to');
      if (!mounted || generation != _generation) return;
      setState(() {
        _inbox = inbox;
        _forward = forward;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _errorKey = e is UnsupportedError ? 'sms_unsupported' : 'sms_read_error');
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _configureForwarding() async {
    final controller = _forwardController..text = _forward == 'off' ? '' : _forward ?? '';
    final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(_text('sms_forwarding')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_text('sms_forwarding_description')),
                TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    decoration:
                        InputDecoration(labelText: _text('sms_international_number'), hintText: '+4915112345678')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_text('cancel'))),
                TextButton(onPressed: () => Navigator.pop(dialogContext, 'off'), child: Text(_text('sms_disable'))),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
                    child: Text(_text('sms_save'))),
              ],
            ));
    if (!mounted || value == null) return;
    if (value != 'off' && !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('sms_invalid_number'))));
      return;
    }
    final generation = _generation;
    try {
      await _service!.actions.setSetting('sms.forward-to', value);
      if (!mounted || generation != _generation) return;
      setState(() => _forward = value);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('sms_save_error'))));
    }
  }

  Future<void> _open(SmsMessage message) async {
    final generation = _generation;
    try {
      await _service!.actions.markSmsRead(message.id);
    } catch (_) {/* Show the message even if the read update fails. */}
    if (!mounted || generation != _generation) return;
    final delete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(message.from.isEmpty ? _text('sms_unknown_sender') : message.from),
              content: SingleChildScrollView(
                  child:
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(message.timestamp),
                const SizedBox(height: 12),
                SelectableText(message.text),
                if (message.forwardStatus.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_text('sms_forwarding_status', params: {'status': _forwardStatus(message.forwardStatus)}))
                ],
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_text('sms_close'))),
                TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_text('sms_delete')))
              ],
            ));
    if (!mounted || generation != _generation) return;
    if (delete == true) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(_text('sms_delete_confirm')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_text('cancel'))),
                  TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_text('sms_delete')))
                ],
              ));
      if (!mounted || generation != _generation || confirmed != true) return;
      try {
        await _service!.actions.deleteSms(message.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('sms_delete_error'))));
        }
      }
    }
    if (mounted && generation == _generation) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_text('sms_title')), actions: [
          IconButton(onPressed: _connected && !_loading ? _load : null, icon: const Icon(Icons.refresh)),
        ]),
        body: !_connected
            ? Center(child: Text(_text('sms_connect')))
            : ListView(children: [
                ListTile(
                    title: Text(_text('sms_forwarding')),
                    subtitle: Text(_forward == null
                        ? _text('sms_unavailable')
                        : _forward == 'off'
                            ? _text('sms_off')
                            : _forward!),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_loading && _forward != null,
                    onTap: _configureForwarding),
                if (_loading) const LinearProgressIndicator(),
                if (_errorKey != null) ListTile(title: Text(_text(_errorKey!))),
                if (_inbox != null && _inbox!.messages.isEmpty) ListTile(title: Text(_text('sms_empty'))),
                for (final message in _inbox?.messages ?? <SmsMessage>[])
                  ListTile(
                      title: Text(message.from.isEmpty ? _text('sms_unknown_sender') : message.from,
                          style: TextStyle(fontWeight: message.read ? FontWeight.normal : FontWeight.bold)),
                      subtitle: Text(message.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _open(message)),
              ]),
      );
}
