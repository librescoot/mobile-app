import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:scooter_core/file_transfer_protocol.dart';

import '../../scooter_service.dart';
import '../wide_layout.dart';

class BluetoothFileBrowserScreen extends StatefulWidget {
  const BluetoothFileBrowserScreen({super.key});
  @override
  State<BluetoothFileBrowserScreen> createState() => _BluetoothFileBrowserScreenState();
}

class _DataDirectory {
  const _DataDirectory(this.name, this.handle);
  final String name;
  final List<int> handle;
}

class _BluetoothFileBrowserScreenState extends State<BluetoothFileBrowserScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final List<_DataDirectory> _stack = [];
  final Map<String, List<int>> _nodes = {};
  List<RemoteFile> _logs = const [];
  List<FileBrowserEntry> _entries = const [];
  bool _loadedLogs = false, _loadedData = false, _screenBusy = false;
  Object? _error;
  int _generation = 0;
  ScooterService? _service;

  String _t(BuildContext context, String key) => FlutterI18n.translate(context, key);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_tabChanged);
  }

  void _tabChanged() {
    if (!mounted) return;
    if (_screenBusy) {
      _generation++;
      _service?.fileTransfers.cancel();
      _screenBusy = false;
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (!identical(_service, service)) {
      _service?.fileTransfers.removeListener(_changed);
      _service = service;
      service.fileTransfers.addListener(_changed);
      _refreshLogs();
      if (service.fileTransfers.dataBrowserAvailable) _refreshData();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_service!.fileTransfers.available) {
      _generation++;
      setState(() {
        _logs = const [];
        _entries = const [];
        _stack.clear();
        _nodes.clear();
        _loadedLogs = false;
        _loadedData = false;
      });
    }
  }

  Future<void> _run(Future<void> Function(int generation) action) async {
    if (_screenBusy) return;
    final generation = ++_generation;
    setState(() {
      _screenBusy = true;
      _error = null;
    });
    try {
      await action(generation);
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _screenBusy = false);
    }
  }

  Future<void> _refreshLogs() => _run((generation) async {
        final values = await _service!.fileTransfers.list(0);
        if (!mounted || generation != _generation) return;
        setState(() {
          _logs = values;
          _loadedLogs = true;
        });
      });

  Future<void> _refreshData() => _run((generation) async {
        final controller = _service!.fileTransfers;
        if (!controller.dataBrowserAvailable) return;
        if (_stack.isEmpty) _stack.add(_DataDirectory('data', await controller.openDataRoot()));
        final entries = await controller.listDataDirectory(_stack.last.handle);
        if (!mounted || generation != _generation) return;
        setState(() {
          _entries = entries.where((e) => e.isSupported).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          _loadedData = true;
          _nodes.clear();
        });
      });

  Future<void> _openDirectory(FileBrowserEntry entry) => _run((generation) async {
        final parent = _stack.last.handle;
        final resolved = await _service!.fileTransfers.resolveDataName(parent, entry.name);
        if (resolved.kind != 2) throw StateError('Remote item is not a directory');
        final handle = await _service!.fileTransfers.openDataDirectory(resolved.id);
        if (!mounted || generation != _generation) return;
        setState(() {
          _stack.add(_DataDirectory(entry.name, handle));
          _entries = const [];
          _nodes.clear();
        });
        final entries = await _service!.fileTransfers.listDataDirectory(handle);
        if (!mounted || generation != _generation) return;
        setState(() {
          _entries = entries.where((e) => e.isSupported).toList();
          _nodes.clear();
        });
      });

  Future<void> _showAncestor(int index) => _run((generation) async {
        final closing = _stack.skip(index + 1).map((item) => item.handle).toList();
        setState(() {
          _stack.removeRange(index + 1, _stack.length);
          _entries = const [];
          _nodes.clear();
        });
        await _service!.fileTransfers.closeDataDirectories(closing);
        final entries = await _service!.fileTransfers.listDataDirectory(_stack.last.handle);
        if (!mounted || generation != _generation) return;
        setState(() => _entries = entries.where((entry) => entry.isSupported).toList());
      });

  Future<List<int>> _resolve(String name) async {
    final key = '${_stack.length}:${_stack.last.name}/$name';
    final cached = _nodes[key];
    if (cached != null) return cached;
    final node = await _service!.fileTransfers.resolveDataName(_stack.last.handle, name);
    _nodes[key] = node.id;
    return node.id;
  }

  Future<void> _downloadData(FileBrowserEntry entry) => _run((generation) async {
        final node = await _resolve(entry.name);
        final file = await _service!.fileTransfers.downloadDataNode(entry.name, node);
        if (!mounted || generation != _generation) return;
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      });

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(withData: false, allowMultiple: false);
    if (picked == null || picked.files.single.path == null || !mounted) return;
    final source = File(picked.files.single.path!);
    final nameController = TextEditingController(text: picked.files.single.name);
    final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(_t(context, 'file_browser_upload_name')),
              content: TextField(controller: nameController, autofocus: true),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(context, 'cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, nameController.text),
                    child: Text(_t(context, 'file_browser_upload'))),
              ],
            ));
    nameController.dispose();
    if (name == null || !mounted) return;
    await _run((generation) async {
      final resolved = await _service!.fileTransfers.resolveDataName(_stack.last.handle, name);
      RemoteFile? replacement;
      if (resolved.kind == 1) {
        final old = await _service!.fileTransfers.statDataNode(name, resolved.id);
        if (!mounted || generation != _generation) return;
        final accepted = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(_t(context, 'file_browser_replace_title')),
                  content: Text(_t(context, 'file_browser_replace_body')
                      .replaceAll('{name}', name)
                      .replaceAll('{size}', _formatSize(old.size))),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t(context, 'cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(_t(context, 'file_browser_replace'))),
                  ],
                ));
        if (accepted != true) return;
        replacement = old;
      } else if (resolved.kind != 0) {
        throw StateError('Remote destination is not a regular file');
      }
      await _service!.fileTransfers.uploadDataNode(name, resolved.id, source, replace: replacement);
      if (!mounted || generation != _generation) return;
    });
    if (mounted) await _refreshData();
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _shareLog(RemoteFile file) => _run((generation) async {
        final local = await _service!.fileTransfers.download(0, file.name);
        if (!mounted || generation != _generation) return;
        await SharePlus.instance.share(ShareParams(files: [XFile(local.path)]));
      });

  @override
  void dispose() {
    _generation++;
    if (_screenBusy) {
      _service?.fileTransfers.cancel();
    } else if (_stack.isNotEmpty && _service?.fileTransfers.dataBrowserAvailable == true) {
      unawaited(
          _service!.fileTransfers.closeDataDirectories(_stack.map((item) => item.handle).toList()).catchError((_) {}));
    }
    _tabs.removeListener(_tabChanged);
    _service?.fileTransfers.removeListener(_changed);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _service?.fileTransfers;
    final isDebugProfile = kDebugMode || kProfileMode;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'file_browser_title')),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: _t(context, 'file_browser_logs')),
          Tab(text: _t(context, 'file_browser_data')),
        ]),
        actions: [
          IconButton(
              tooltip: _t(context, 'file_browser_refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: _screenBusy ? null : () => _tabs.index == 0 ? _refreshLogs() : _refreshData()),
          if (_screenBusy)
            IconButton(
                tooltip: _t(context, 'cancel'), icon: const Icon(Icons.close), onPressed: () => controller?.cancel()),
          if (_tabs.index == 1 && controller?.dataBrowserAvailable == true)
            IconButton(
                tooltip: _t(context, 'file_browser_upload'),
                icon: const Icon(Icons.upload_file),
                onPressed: _screenBusy ? null : _upload),
        ],
      ),
      body: !isDebugProfile
          ? Center(child: Text(_t(context, 'file_browser_debug_only')))
          : Column(children: [
              if (_screenBusy) const LinearProgressIndicator(),
              if (controller?.progress case final progress?) LinearProgressIndicator(value: progress.fraction),
              if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text('$_error')),
              Expanded(
                  child: TabBarView(controller: _tabs, children: [
                _logsView(controller),
                _dataView(controller),
              ])),
            ]),
    );
  }

  Widget _logsView(controller) {
    if (controller?.available != true) return Center(child: Text(_t(context, 'file_browser_logs_unavailable')));
    if (!_loadedLogs) {
      return Center(child: FilledButton(onPressed: _refreshLogs, child: Text(_t(context, 'file_browser_load_logs'))));
    }
    if (_logs.isEmpty) return Center(child: Text(_t(context, 'file_browser_empty')));
    return RefreshIndicator(
        onRefresh: _refreshLogs,
        child: ListView.builder(
          padding: wideContentPadding(context),
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            final file = _logs[index];
            return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(file.name),
                subtitle: Text(_formatSize(file.size)),
                trailing: IconButton(
                    icon: const Icon(Icons.share_outlined), onPressed: _screenBusy ? null : () => _shareLog(file)));
          },
        ));
  }

  Widget _dataView(controller) {
    if (controller?.available != true) return Center(child: Text(_t(context, 'file_browser_logs_unavailable')));
    if (controller?.dataBrowserAvailable != true) {
      return Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(_t(context, 'file_browser_data_opt_in'))));
    }
    if (!_loadedData) {
      return Center(child: FilledButton(onPressed: _refreshData, child: Text(_t(context, 'file_browser_open_data'))));
    }
    return Column(children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < _stack.length; i++) ...[
              if (i > 0) const Icon(Icons.chevron_right, size: 18),
              TextButton(
                  onPressed: i == _stack.length - 1 || _screenBusy ? null : () => _showAncestor(i),
                  child: Text(_stack[i].name)),
            ],
          ])),
      Expanded(
          child: _entries.isEmpty
              ? Center(child: Text(_t(context, 'file_browser_empty')))
              : ListView.builder(
                  padding: wideContentPadding(context),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return ListTile(
                      leading: Icon(entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                      title: Text(entry.name),
                      subtitle: Text(entry.isFile ? _formatSize(entry.size) : _t(context, 'file_browser_folder')),
                      onTap: entry.isDirectory ? (_screenBusy ? null : () => _openDirectory(entry)) : null,
                      trailing: entry.isFile
                          ? IconButton(
                              tooltip: _t(context, 'file_browser_download_share'),
                              icon: const Icon(Icons.share_outlined),
                              onPressed: _screenBusy ? null : () => _downloadData(entry))
                          : null,
                    );
                  })),
    ]);
  }
}
