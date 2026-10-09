import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:scooter_core/file_transfer_protocol.dart';

import 'file_transfer_client.dart';
import 'src/ble/characteristic_repository.dart';
import 'src/ble/file_transfer_transport.dart';
import 'src/runtime/scooter_session.dart';

class FileTransferController extends ChangeNotifier {
  FileTransferController(
      {required this.cacheDirectory,
      required this.supportsFirmware,
      required this.supportsDataBrowser});
  final Future<Directory> Function() cacheDirectory;
  final bool Function() supportsFirmware;
  final bool Function() supportsDataBrowser;
  SessionConnection? _connection;
  CharacteristicRepository? _repository;
  FileTransferClient? _client;
  FileTransferProgress? _progress;
  bool _disposed = false;
  bool _running = false;
  int _operationGeneration = 0;
  DateTime? _lastProgressNotification;
  bool get available =>
      !_disposed &&
      (kDebugMode || kProfileMode) &&
      _connection?.isCurrent == true &&
      supportsFirmware() &&
      _repository?.filesAvailable == true;
  bool get dataBrowserAvailable => available && supportsDataBrowser();
  bool get busy => _running || (_client?.busy ?? false);
  FileTransferProgress? get progress => _progress;

  void bind(SessionConnection connection, CharacteristicRepository repository) {
    if (identical(_connection, connection) &&
        identical(_repository, repository)) {
      return;
    }
    unbind();
    _connection = connection;
    _repository = repository;
    if (!_disposed) notifyListeners();
  }

  void unbind() {
    final client = _client;
    _client = null;
    _connection = null;
    _repository = null;
    _progress = null;
    _running = false;
    _operationGeneration++;
    _lastProgressNotification = null;
    if (client != null) unawaited(client.close());
    if (!_disposed) notifyListeners();
  }

  FileTransferClient _getClient() {
    if (!available) throw StateError('Bluetooth file transfer unavailable');
    if (_client != null) return _client!;
    late FileTransferClient client;
    client =
        FileTransferClient(BluetoothFileTransport(_connection!, _repository!),
            onProgress: (progress) {
      if (!_disposed && identical(_client, client)) {
        final phaseChanged = _progress?.verifying != progress.verifying;
        _progress = progress;
        final now = DateTime.now();
        if (phaseChanged ||
            progress.bytes == progress.total ||
            _lastProgressNotification == null ||
            now.difference(_lastProgressNotification!).inMilliseconds >= 100) {
          _lastProgressNotification = now;
          notifyListeners();
        }
      }
    });
    _client = client;
    return client;
  }

  Future<T> _run<T>(
      Future<T> Function(FileTransferClient client) action) async {
    final client = _getClient();
    if (busy) throw StateError('Another file operation is active');
    _running = true;
    final generation = ++_operationGeneration;
    _progress = null;
    final future = action(client);
    notifyListeners();
    try {
      final result = await future;
      if (!identical(_client, client)) throw const FileTransferCancelled();
      return result;
    } finally {
      if (generation == _operationGeneration) {
        _running = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<List<RemoteFile>> list(int store) =>
      _run((client) => client.list(store));
  Future<List<int>> openDataRoot() {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) => client.openDataRoot());
  }

  Future<List<FileBrowserEntry>> listDataDirectory(List<int> directory) {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) => client.listDataDirectory(directory));
  }

  Future<void> closeDataDirectories(List<List<int>> directories) {
    if (!dataBrowserAvailable) return Future.value();
    return _run((client) => client.closeDataDirectories(directories));
  }

  Future<List<int>> openDataDirectory(List<int> node) {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) => client.openDataDirectory(node));
  }

  Future<RemoteFile> stat(int store, String name) =>
      _run((client) => client.stat(store, name));
  Future<({List<int> id, int kind})> resolveDataName(
      List<int> directory, String name) {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) => client.resolveDataName(directory, name));
  }

  Future<RemoteFile> statDataNode(String name, List<int> node) {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) => client.statNode(2, name, node));
  }

  Future<File> downloadDataNode(String name, List<int> node) {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) async {
      final connection = _connection!;
      final root = await cacheDirectory();
      if (!identical(client, _client) || !connection.isCurrent) {
        throw const FileTransferCancelled();
      }
      final scope = sha256.convert(utf8.encode(connection.id)).toString();
      return client.download(2, name, Directory('${root.path}/$scope'),
          nodeId: node);
    });
  }

  Future<RemoteFile> uploadDataNode(String name, List<int> node, File source,
      {RemoteFile? replace}) {
    if (!dataBrowserAvailable) {
      throw StateError('Administrative /data access unavailable');
    }
    return _run((client) =>
        client.upload(2, name, source, nodeId: node, replace: replace));
  }

  Future<File> download(int store, String name) => _run((client) async {
        final connection = _connection!;
        final root = await cacheDirectory();
        if (!identical(client, _client) || !connection.isCurrent) {
          throw const FileTransferCancelled();
        }
        final scope = sha256.convert(utf8.encode(connection.id)).toString();
        final future =
            client.download(store, name, Directory('${root.path}/$scope'));
        notifyListeners();
        return future;
      });
  Future<RemoteFile> upload(int store, String name, File source) =>
      _run((client) => client.upload(store, name, source));
  void cancel() => _client?.cancel();
  @override
  void dispose() {
    _disposed = true;
    unbind();
    super.dispose();
  }
}
