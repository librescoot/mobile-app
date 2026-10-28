import 'package:flutter/material.dart';
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
  String? _error;
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
    _error = null;
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
      _error = null;
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
      setState(() => _error = e is UnsupportedError
          ? 'Messages are not supported by this scooter firmware.'
          : 'Could not read messages. Check the Bluetooth connection.');
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _configureForwarding() async {
    final controller = _forwardController..text = _forward == 'off' ? '' : _forward ?? '';
    final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('SMS forwarding'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Forward new messages to this number. Carrier charges may apply. Forwarding is limited to 10 SMS segments per day and is disabled while roaming.'),
                TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'International number', hintText: '+4915112345678')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dialogContext, 'off'), child: const Text('Disable')),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
              ],
            ));
    if (!mounted || value == null) return;
    if (value != 'off' && !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a full international number.')));
      return;
    }
    final generation = _generation;
    try {
      await _service!.actions.setSetting('sms.forward-to', value);
      if (!mounted || generation != _generation) return;
      setState(() => _forward = value);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save forwarding.')));
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
              title: Text(message.from.isEmpty ? 'Unknown sender' : message.from),
              content: SingleChildScrollView(
                  child:
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(message.timestamp),
                const SizedBox(height: 12),
                SelectableText(message.text),
                if (message.forwardStatus.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Forwarding: ${message.forwardStatus}')
                ],
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Close')),
                TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))
              ],
            ));
    if (!mounted || generation != _generation) return;
    if (delete == true) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Delete message?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))
                ],
              ));
      if (!mounted || generation != _generation || confirmed != true) return;
      try {
        await _service!.actions.deleteSms(message.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete message.')));
        }
      }
    }
    if (mounted && generation == _generation) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Messages'), actions: [
          IconButton(onPressed: _connected && !_loading ? _load : null, icon: const Icon(Icons.refresh)),
        ]),
        body: !_connected
            ? const Center(child: Text('Connect to the scooter to read messages.'))
            : ListView(children: [
                ListTile(
                    title: const Text('SMS forwarding'),
                    subtitle: Text(_forward == null
                        ? 'Unavailable'
                        : _forward == 'off'
                            ? 'Off'
                            : _forward!),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_loading && _forward != null,
                    onTap: _configureForwarding),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) ListTile(title: Text(_error!)),
                if (_inbox != null && _inbox!.messages.isEmpty) const ListTile(title: Text('No messages')),
                for (final message in _inbox?.messages ?? <SmsMessage>[])
                  ListTile(
                      title: Text(message.from.isEmpty ? 'Unknown sender' : message.from,
                          style: TextStyle(fontWeight: message.read ? FontWeight.normal : FontWeight.bold)),
                      subtitle: Text(message.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _open(message)),
              ]),
      );
}
