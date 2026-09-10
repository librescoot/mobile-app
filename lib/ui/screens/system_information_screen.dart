import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:unustasis/scooter_service.dart';

/// Read-only presentation of an explicitly sampled version snapshot. No OTA
/// refresh is invoked: opening this screen must not start update planning.
class SystemInformationScreen extends StatefulWidget {
  const SystemInformationScreen({super.key});

  @override
  State<SystemInformationScreen> createState() => _SystemInformationScreenState();
}

class _SystemInformationScreenState extends State<SystemInformationScreen> {
  Map<String, String?> _versions = const {};
  String? _targetId;
  DateTime? _readAt;
  bool _loading = false;
  bool _failed = false;

  String _text(String key) => FlutterI18n.translate(context, key);
  String _version(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty || cleaned.toLowerCase() == 'unknown'
        ? _text('system_info_unavailable')
        : cleaned;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    final service = context.read<ScooterService>();
    if (_loading || !service.connected) return;
    final id = service.currentScooterId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final versions = await service.readInstalledVersions();
      if (!mounted || !service.connected || service.currentScooterId != id) return;
      setState(() {
        _versions = versions;
        _targetId = id;
        _readAt = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    // Retain a clearly labelled offline snapshot, never show scooter A's
    // readings while connecting to or connected to scooter B.
    final showSnapshot = _targetId != null &&
        (service.currentScooterId == null || service.currentScooterId == _targetId) &&
        (service.connectingScooterId == null || service.connectingScooterId == _targetId);
    final versions = showSnapshot ? _versions : const <String, String?>{};
    final rows = <(String, String)>[
      (_text('ls_ota_board_mdb'), _version(versions['mdb'])),
      (_text('ls_ota_board_dbc'), _version(versions['dbc'])),
      (_text('system_info_nrf'), _version(versions['nrf'])),
    ];
    final sampled = showSnapshot && _readAt != null
        ? '${_text('system_info_read_at')} ${MaterialLocalizations.of(context).formatCompactDate(_readAt!)} '
            '${TimeOfDay.fromDateTime(_readAt!).format(context)}'
        : null;
    final cached = showSnapshot && !service.connected;
    return Scaffold(
      appBar: AppBar(title: Text(_text('system_info_title'))),
      body: ListView(
        children: [
          _heading('system_info_boards'),
          for (final row in rows) _row(row),
          if (sampled != null)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(sampled),
              subtitle: cached ? Text(_text('system_info_cached')) : null,
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_text('system_info_failed'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ListTile(
            leading: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            title: Text(_text('system_info_refresh')),
            onTap: service.connected && !_loading ? _refresh : null,
            enabled: service.connected && !_loading,
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(_text('system_info_copy')),
            onTap: () async {
              final lines = [
                _text('system_info_title'),
                for (final row in rows) '${row.$1}: ${row.$2}',
                if (sampled != null) '${_text('system_info_read_at')} ${_readAt!.toUtc().toIso8601String()}',
                if (cached) _text('system_info_cached'),
              ];
              // App build is useful in a bug report, not a scooter setting.
              try {
                final app = await PackageInfo.fromPlatform();
                if (!mounted) return;
                lines.add('${_text('settings_app_version')}: ${app.version} (${app.buildNumber})');
              } catch (_) {
                // Missing package metadata must not prevent copying the
                // scooter's actual version readings.
              }
              if (!mounted) return;
              await Clipboard.setData(ClipboardData(text: lines.join('\n')));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_text('system_info_copied'))));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _heading(String key) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(_text(key), style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _row((String, String) row) => ListTile(title: Text(row.$1), subtitle: SelectableText(row.$2));
}
