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
import 'package:scooter_flutter/file_transfer_controller.dart';
import '../wide_layout.dart';

class BluetoothFileBrowserScreen extends StatefulWidget {
  const BluetoothFileBrowserScreen({super.key, this.pickFile, this.shareFile});

  final Future<FilePickerResult?> Function()? pickFile;
  final Future<void> Function(File file)? shareFile;

  @override
  State<BluetoothFileBrowserScreen> createState() => _BluetoothFileBrowserScreenState();
}

class _DataDirectory {
  _DataDirectory(this.name, this.handle) : cursors = [0];
  final String name;
  final List<int> handle;
  final List<int> cursors;
}

class _BrowserOperation {
  _BrowserOperation({
    required this.generation,
    required this.service,
    required this.controller,
    required this.connectionScope,
    required this.tab,
    required this.owner,
    required this.directory,
  });

  final int generation;
  final ScooterService service;
  final FileTransferController controller;
  final Object? connectionScope;
  final int tab;
  final Object owner;
  List<int>? directory;
}

class _BluetoothFileBrowserScreenState extends State<BluetoothFileBrowserScreen> with SingleTickerProviderStateMixin {
  static const _pageSize = 64;

  late final TabController _tabs = TabController(length: 2, vsync: this);
  final Object _operationOwner = Object();
  final List<_DataDirectory> _stack = [];
  final Map<String, List<int>> _nodes = {};
  List<RemoteFile> _logs = const [];
  List<FileBrowserEntry> _entries = const [];
  FileBrowserDirectoryPage? _dataPage;
  bool _loadedLogs = false, _loadedData = false, _screenBusy = false;
  bool? _lastAvailable;
  Object? _lastConnectionScope;
  Object? _error;
  int _generation = 0;
  int _lastTabIndex = 0;
  ScooterService? _service;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_tabChanged);
  }

  void _invalidateOperation() {
    _generation++;
    _service?.fileTransfers.cancelOwnedOperation(_operationOwner);
    _screenBusy = false;
    _error = null;
  }

  void _cancelOperation() {
    if (!_screenBusy) return;
    _invalidateOperation();
    setState(() {});
  }

  void _tabChanged() {
    if (!mounted || _tabs.index == _lastTabIndex) return;
    _lastTabIndex = _tabs.index;
    if (_screenBusy) {
      _invalidateOperation();
    }
    setState(() {});
    if (_tabs.index == 0 && !_loadedLogs) {
      _refreshLogs();
    } else if (_tabs.index == 1 && !_loadedData && _service?.fileTransfers.dataBrowserAvailable == true) {
      _refreshData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (identical(_service, service)) return;
    _invalidateOperation();
    _service?.fileTransfers.removeListener(_changed);
    _service = service;
    service.fileTransfers.addListener(_changed);
    _observeController(service.fileTransfers);
    if (service.fileTransfers.available) _loadActiveTab();
  }

  void _loadActiveTab() {
    if (_tabs.index == 0) {
      _refreshLogs();
    } else if (_service?.fileTransfers.dataBrowserAvailable == true) {
      _refreshData();
    }
  }

  void _observeController(FileTransferController controller) {
    _lastConnectionScope = controller.connectionScope;
    _lastAvailable = controller.available;
  }

  void _resetRemoteState() {
    _logs = const [];
    _entries = const [];
    _dataPage = null;
    _stack.clear();
    _nodes.clear();
    _loadedLogs = false;
    _loadedData = false;
  }

  void _changed() {
    if (!mounted) return;
    final controller = _service!.fileTransfers;
    final scope = controller.connectionScope;
    final available = controller.available;
    final connectionChanged = !identical(scope, _lastConnectionScope);
    final availabilityChanged = available != _lastAvailable;
    if (connectionChanged || availabilityChanged) {
      _invalidateOperation();
      _resetRemoteState();
      _observeController(controller);
      setState(() {});
      if (available) _loadActiveTab();
      return;
    }
    setState(() {});
  }

  _BrowserOperation _captureOperation() {
    final service = _service!;
    final controller = service.fileTransfers;
    return _BrowserOperation(
      generation: ++_generation,
      service: service,
      controller: controller,
      connectionScope: controller.connectionScope,
      tab: _tabs.index,
      owner: _operationOwner,
      directory: _stack.isEmpty ? null : List<int>.of(_stack.last.handle),
    );
  }

  bool _isCurrent(_BrowserOperation operation, {bool checkPath = true}) {
    if (!mounted ||
        operation.generation != _generation ||
        !identical(_service, operation.service) ||
        !identical(operation.service.fileTransfers, operation.controller) ||
        !identical(operation.connectionScope, operation.controller.connectionScope) ||
        !operation.controller.available ||
        _tabs.index != operation.tab) {
      return false;
    }
    if (!checkPath) return true;
    if (operation.directory == null) return _stack.isEmpty;
    return _stack.isNotEmpty && _sameHandle(operation.directory!, _stack.last.handle);
  }

  bool _sameHandle(List<int> a, List<int> b) => listEquals(a, b);

  Future<void> _run(Future<void> Function(_BrowserOperation operation) action) async {
    if (_screenBusy || _service?.fileTransfers.available != true) return;
    final operation = _captureOperation();
    setState(() {
      _screenBusy = true;
      _error = null;
    });
    try {
      await action(operation);
    } catch (error) {
      if (_isCurrent(operation, checkPath: false)) setState(() => _error = error);
    } finally {
      if (_isCurrent(operation, checkPath: false)) setState(() => _screenBusy = false);
    }
  }

  Future<void> _refreshLogs() => _run((operation) async {
        final values = await operation.controller.list(0, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        setState(() {
          _logs = values;
          _loadedLogs = true;
        });
      });

  Future<void> _refreshData() => _run((operation) async {
        await _loadDataPage(operation);
      });

  Future<void> _loadDataPage(_BrowserOperation operation) async {
    final controller = operation.controller;
    if (!controller.dataBrowserAvailable) return;
    if (_stack.isEmpty) {
      final root = await controller.openDataRoot(owner: operation.owner);
      if (!_isCurrent(operation, checkPath: false) || _stack.isNotEmpty) return;
      setState(() {
        _stack.add(_DataDirectory('data', root));
        _nodes.clear();
      });
      operation.directory = List<int>.of(root);
    }
    if (!_isCurrent(operation)) return;
    final directory = _stack.last;
    final cursor = directory.cursors.last;
    final page =
        await controller.listDataDirectory(directory.handle, cursor: cursor, limit: _pageSize, owner: operation.owner);
    if (!_isCurrent(operation)) return;
    setState(() {
      _dataPage = page;
      _entries = page.entries.where((entry) => entry.isSupported).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _loadedData = true;
      _nodes.clear();
    });
  }

  Future<void> _openDirectory(FileBrowserEntry entry) => _run((operation) async {
        final parent = operation.directory!;
        final resolved = await operation.controller.resolveDataName(parent, entry.name, owner: operation.owner);
        if (!_isCurrent(operation) || resolved.kind != 2) return;
        final handle = await operation.controller.openDataDirectory(resolved.id, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        setState(() {
          _stack.add(_DataDirectory(entry.name, handle));
          _entries = const [];
          _dataPage = null;
          _nodes.clear();
        });
        operation.directory = List<int>.of(handle);
        final page = await operation.controller.listDataDirectory(handle, limit: _pageSize, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        setState(() {
          _dataPage = page;
          _entries = page.entries.where((item) => item.isSupported).toList();
          _loadedData = true;
        });
      });

  Future<void> _showAncestor(int index) => _run((operation) async {
        if (index < 0 || index >= _stack.length - 1) return;
        final closing = _stack.skip(index + 1).map((item) => item.handle).toList();
        final parent = List<int>.of(_stack[index].handle);
        setState(() {
          _stack.removeRange(index + 1, _stack.length);
          _entries = const [];
          _dataPage = null;
          _nodes.clear();
        });
        operation.directory = parent;
        await operation.controller.closeDataDirectories(closing, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        await _loadDataPage(operation);
      });

  Future<List<int>> _resolve(_BrowserOperation operation, String name) async {
    final directory = operation.directory!;
    final key = '${directory.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}:$name';
    final cached = _nodes[key];
    if (cached != null) return cached;
    final result = await operation.controller.resolveDataName(directory, name, owner: operation.owner);
    if (!_isCurrent(operation)) throw StateError('The browser operation is no longer current');
    _nodes[key] = result.id;
    return result.id;
  }

  Future<void> _downloadData(FileBrowserEntry entry) => _run((operation) async {
        final node = await _resolve(operation, entry.name);
        if (!_isCurrent(operation)) return;
        final file = await operation.controller.downloadDataNode(entry.name, node, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        await _share(file);
      });

  Future<void> _shareLog(RemoteFile remote) => _run((operation) async {
        final local = await operation.controller.download(0, remote.name, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        await _share(local);
      });

  Future<void> _share(File file) async {
    if (widget.shareFile != null) {
      await widget.shareFile!(file);
    } else {
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    }
  }

  Future<void> _upload() => _run((operation) async {
        final picked =
            await (widget.pickFile?.call() ?? FilePicker.platform.pickFiles(withData: false, allowMultiple: false));
        if (!mounted || !_isCurrent(operation) || picked == null || picked.files.single.path == null) return;
        final source = File(picked.files.single.path!);
        final nameController = TextEditingController(text: picked.files.single.name);
        String? name;
        try {
          name = await showDialog<String>(
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
            ),
          );
        } finally {
          await WidgetsBinding.instance.endOfFrame;
          nameController.dispose();
        }
        final uploadName = name;
        if (!mounted || !_isCurrent(operation) || uploadName == null) return;
        final directory = operation.directory!;
        final resolved = await operation.controller.resolveDataName(directory, uploadName, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        RemoteFile? replacement;
        if (resolved.kind == 1) {
          final old = await operation.controller.statDataNode(uploadName, resolved.id, owner: operation.owner);
          if (!mounted || !_isCurrent(operation)) return;
          final accepted = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(_t(context, 'file_browser_replace_title')),
              content: Text(_t(context, 'file_browser_replace_body')
                  .replaceAll('{name}', uploadName)
                  .replaceAll('{size}', _formatSize(old.size))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t(context, 'cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true), child: Text(_t(context, 'file_browser_replace'))),
              ],
            ),
          );
          if (!_isCurrent(operation) || accepted != true) return;
          replacement = old;
        } else if (resolved.kind != 0) {
          throw StateError('Remote destination is not a regular file');
        }
        if (!_isCurrent(operation)) return;
        await operation.controller
            .uploadDataNode(uploadName, resolved.id, source, replace: replacement, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        await _loadDataPage(operation);
      });

  Future<void> _nextPage() => _run((operation) async {
        final page = _dataPage;
        if (page == null || !page.hasMore || !_isCurrent(operation)) return;
        final directory = _stack.last;
        final cursor = page.nextCursor;
        final next = await operation.controller
            .listDataDirectory(directory.handle, cursor: cursor, limit: _pageSize, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        setState(() {
          directory.cursors.add(cursor);
          _dataPage = next;
          _entries = next.entries.where((entry) => entry.isSupported).toList();
          _nodes.clear();
        });
      });

  Future<void> _previousPage() => _run((operation) async {
        final directory = _stack.last;
        if (directory.cursors.length < 2) return;
        final cursor = directory.cursors[directory.cursors.length - 2];
        final previous = await operation.controller
            .listDataDirectory(directory.handle, cursor: cursor, limit: _pageSize, owner: operation.owner);
        if (!_isCurrent(operation)) return;
        setState(() {
          directory.cursors.removeLast();
          _dataPage = previous;
          _entries = previous.entries.where((entry) => entry.isSupported).toList();
          _nodes.clear();
        });
      });

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _t(BuildContext context, String key) => FlutterI18n.translate(context, key);

  @override
  void dispose() {
    _generation++;
    if (_screenBusy) {
      _service?.fileTransfers.cancelOwnedOperation(_operationOwner);
    } else if (_stack.isNotEmpty && _service?.fileTransfers.dataBrowserAvailable == true) {
      unawaited(_service!.fileTransfers
          .closeDataDirectories(_stack.map((item) => item.handle).toList(), owner: _operationOwner)
          .catchError((_) {}));
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
            IconButton(tooltip: _t(context, 'cancel'), icon: const Icon(Icons.close), onPressed: _cancelOperation),
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
              Expanded(child: TabBarView(controller: _tabs, children: [_logsView(controller), _dataView(controller)])),
            ]),
    );
  }

  Widget _logsView(FileTransferController? controller) {
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
              icon: const Icon(Icons.share_outlined),
              onPressed: _screenBusy ? null : () => _shareLog(file),
            ),
          );
        },
      ),
    );
  }

  Widget _dataView(FileTransferController? controller) {
    if (controller?.available != true) return Center(child: Text(_t(context, 'file_browser_logs_unavailable')));
    if (controller?.dataBrowserAvailable != true) {
      return Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(_t(context, 'file_browser_data_opt_in'))));
    }
    if (!_loadedData) {
      return Center(child: FilledButton(onPressed: _refreshData, child: Text(_t(context, 'file_browser_open_data'))));
    }
    final currentPage = _stack.isEmpty ? 1 : _stack.last.cursors.length;
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
        ]),
      ),
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
                            onPressed: _screenBusy ? null : () => _downloadData(entry),
                          )
                        : null,
                  );
                },
              ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton.icon(
          onPressed: _screenBusy || _stack.isEmpty || _stack.last.cursors.length < 2 ? null : _previousPage,
          icon: const Icon(Icons.chevron_left),
          label: Text(_t(context, 'file_browser_previous_page')),
        ),
        Text('$currentPage'),
        TextButton.icon(
          onPressed: _screenBusy || _dataPage?.hasMore != true ? null : _nextPage,
          icon: const Icon(Icons.chevron_right),
          label: Text(_t(context, 'file_browser_next_page')),
        ),
      ]),
    ]);
  }
}
