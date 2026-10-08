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
      {required this.cacheDirectory, required this.supportsFirmware});
  final Future<Directory> Function() cacheDirectory;
  final bool Function() supportsFirmware;
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
      _connection?.isCurrent == true &&
      supportsFirmware() &&
      _repository?.filesAvailable == true;
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
  Future<RemoteFile> stat(int store, String name) =>
      _run((client) => client.stat(store, name));
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
