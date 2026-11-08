import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'package:scooter_core/ota_protocol.dart';
import 'package:scooter_flutter/update_controller.dart';

import '../../scooter_service.dart';
import '../wide_layout.dart';

/// Pushes firmware artifacts picked from the phone to the scooter, for the
/// cases the release index does not cover: a locally built image, a hand-made
/// delta chain, or a specific artifact a plan would not offer.
///
/// The files are uploaded one after another and left staged on the scooter;
/// nothing is installed until the user asks for a board. That is what makes a
/// delta chain possible — its base image has to be on the scooter before the
/// delta is applied — and it is how an update directory is filled over USB.
class LsOtaFilesScreen extends StatefulWidget {
  const LsOtaFilesScreen({super.key, this.pickFiles});

  /// Injection point for tests; defaults to the platform file picker.
  final Future<List<File>?> Function()? pickFiles;

  @override
  State<LsOtaFilesScreen> createState() => _LsOtaFilesScreenState();
}

class _LsOtaFilesScreenState extends State<LsOtaFilesScreen> {
  late final UpdateController _updates;

  @override
  void initState() {
    super.initState();
    _updates = context.read<ScooterService>().updateController;
    _updates.addListener(_changed);
  }

  @override
  void dispose() {
    _updates.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<List<File>?> _pick() async {
    if (widget.pickFiles != null) return widget.pickFiles!();
    final picked = await FilePicker.platform
        .pickFiles(withData: false, allowMultiple: true);
    if (picked == null) return null;
    return [
      for (final file in picked.files)
        if (file.path != null) File(file.path!),
    ];
  }

  Future<void> _add() async {
    final files = await _pick();
    if (files == null || files.isEmpty || !mounted) return;
    _updates.addManualUploads(files);
  }

  String _t(String key, [Map<String, String> params = const {}]) =>
      FlutterI18n.translate(context, key, translationParams: params);

  String _boardLabel(int component) => _t(
      component == OtaProtocol.componentDbc ? 'ls_ota_board_dbc' : 'ls_ota_board_mdb');

  String _statusLabel(ManualUpload upload) {
    switch (upload.status) {
      case ManualUploadStatus.pending:
        return _t('ls_ota_files_status_pending');
      case ManualUploadStatus.uploading:
        return _t('ls_ota_files_status_uploading',
            {'percent': '${(upload.progress * 100).round()}'});
      case ManualUploadStatus.staged:
        return _t('ls_ota_files_status_staged');
      case ManualUploadStatus.applied:
        return _t('ls_ota_files_status_applied');
      case ManualUploadStatus.failed:
        return upload.error ?? _t('ls_ota_files_status_failed');
    }
  }

  Widget _uploadTile(ManualUpload upload) {
    final busy = _updates.manualUploading;
    return ListTile(
      leading: Icon(upload.isMender ? Icons.system_update_alt : Icons.compress),
      title: Text(upload.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_boardLabel(upload.component)} · ${_statusLabel(upload)}'),
          if (upload.status == ManualUploadStatus.uploading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: upload.progress,
                minHeight: 4,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainer,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!busy && upload.status != ManualUploadStatus.applied)
            IconButton(
              tooltip: _t('ls_ota_files_move', {
                'board': _boardLabel(upload.component == OtaProtocol.componentMdb
                    ? OtaProtocol.componentDbc
                    : OtaProtocol.componentMdb),
              }),
              icon: const Icon(Icons.swap_horiz),
              onPressed: () {
                _updates.removeManualUpload(upload);
                _updates.addManualUploads(
                  [upload.file],
                  fallbackComponent:
                      upload.component == OtaProtocol.componentMdb
                          ? OtaProtocol.componentDbc
                          : OtaProtocol.componentMdb,
                );
              },
            ),
          if (!busy && upload.status != ManualUploadStatus.applied)
            IconButton(
              tooltip: _t('ls_ota_files_remove'),
              icon: const Icon(Icons.close),
              onPressed: () => _updates.removeManualUpload(upload),
            ),
        ],
      ),
    );
  }

  Widget _installRow() {
    final busy = _updates.busy;
    final applying = _updates.manualApplyingComponent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (applying != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const CircularProgressIndicator(),
                title: Text(_t('ls_ota_files_installing',
                    {'board': _boardLabel(applying)})),
                subtitle: _updates.transfer.installPercent > 0
                    ? Text(_t('ls_ota_installing_percent',
                        {'percent': '${_updates.transfer.installPercent}'}))
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: _updates.transfer.installPercent / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainer,
                ),
              ),
            ],
          ),
        for (final component in [
          OtaProtocol.componentMdb,
          OtaProtocol.componentDbc,
        ])
          if (_updates.manualHasStaged(component))
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(_t('ls_ota_files_install', {
                'board': _boardLabel(component),
              })),
              subtitle: Text(_t('ls_ota_files_install_subtitle')),
              onTap: busy
                  ? null
                  : () => _updates.applyManualUploads(component),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final ready = service.connected && _updates.otaAvailable;
    final uploads = _updates.manualUploads;
    final staged = uploads
        .where((u) =>
            u.status == ManualUploadStatus.staged ||
            u.status == ManualUploadStatus.applied)
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(_t('ls_ota_files_title'))),
      body: ListView(
        padding: wideContentPadding(context),
        children: [
          if (!ready)
            ListTile(
              leading: const Icon(Icons.bluetooth_disabled),
              title: Text(_t('ls_ota_files_not_ready')),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _t('ls_ota_files_intro'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(_t('ls_ota_files_add')),
            enabled: ready && !_updates.manualUploading,
            onTap: ready && !_updates.manualUploading ? _add : null,
          ),
          if (uploads.isEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_t('ls_ota_files_empty')),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _t('ls_ota_files_progress',
                    {'done': '$staged', 'total': '${uploads.length}'}),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            for (final upload in uploads) _uploadTile(upload),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: Text(_t('ls_ota_files_upload')),
              subtitle: Text(_t('ls_ota_files_upload_subtitle')),
              enabled: ready && !_updates.busy && staged < uploads.length,
              onTap: ready && !_updates.busy
                  ? () => _updates.uploadManualUploads()
                  : null,
            ),
            _installRow(),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(_t('ls_ota_files_clear')),
              enabled: !_updates.busy,
              onTap: _updates.busy ? null : _updates.clearManualUploads,
            ),
          ],
          if (_updates.manualError != null)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text('${_updates.manualError}'),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _t('ls_ota_files_footer'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
