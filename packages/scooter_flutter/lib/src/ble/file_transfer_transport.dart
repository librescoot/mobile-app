import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:scooter_core/file_transfer_protocol.dart';

import '../../file_transfer_client.dart';
import '../runtime/scooter_session.dart';
import 'characteristic_repository.dart';

class BluetoothFileTransport implements FileTransferTransport {
  BluetoothFileTransport(this.connection, this.repository);
  final SessionConnection connection;
  final CharacteristicRepository repository;
  final _responses = StreamController<List<int>>.broadcast(sync: true);
  final _data = StreamController<List<int>>.broadcast(sync: true);
  StreamSubscription<List<int>>? _statusSubscription, _dataSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Future<void>? _ready;
  bool _closed = false;
  @override
  int get payloadBudget =>
      min(FileWire.maxPayload, connection.device.mtuNow - 3);
  @override
  bool get isCurrent => !_closed && connection.isCurrent;
  @override
  Stream<List<int>> get responses => _responses.stream;
  @override
  Stream<List<int>> get data => _data.stream;
  void _check() {
    if (!isCurrent) throw StateError('Bluetooth connection changed');
  }

  @override
  Future<void> ready() async {
    try {
      await (_ready ??= _initialize());
    } catch (_) {
      _ready = null;
      rethrow;
    }
    _check();
    if (Platform.isAndroid) {
      try {
        await connection.device.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high);
      } catch (_) {}
      _check();
    }
  }

  Future<void> _initialize() async {
    _check();
    if (!repository.filesAvailable) {
      throw UnsupportedError('Bluetooth file transfer unavailable');
    }
    if (Platform.isAndroid && connection.device.mtuNow < 247) {
      try {
        await connection.device.requestMtu(247);
      } catch (_) {}
      _check();
    }
    final status = repository.fileStatusCharacteristic!,
        data = repository.fileDataCharacteristic!;
    _statusSubscription ??= status.onValueReceived.listen((value) {
      if (isCurrent) _responses.add(value);
    }, onError: _responses.addError);
    _dataSubscription ??= data.onValueReceived.listen((value) {
      if (isCurrent) _data.add(value);
    }, onError: _data.addError);
    _connectionSubscription ??=
        connection.device.connectionState.listen((state) {
      if (!_closed && state == BluetoothConnectionState.disconnected) {
        _responses.addError(StateError('Bluetooth disconnected'));
      }
    });
    await status.setNotifyValue(true);
    _check();
    await data.setNotifyValue(true);
    _check();
  }

  @override
  Future<void> idle() async {
    if (isCurrent && Platform.isAndroid) {
      await connection.device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.balanced);
    }
  }

  @override
  Future<void> writeControl(Uint8List value) async {
    _check();
    await repository.fileControlCharacteristic!
        .write(value, allowLongWrite: true, timeout: 10);
    _check();
  }

  @override
  Future<void> writeData(Uint8List value) async {
    _check();
    if (value.length > payloadBudget) throw StateError('Bluetooth MTU changed');
    await repository.fileDataCharacteristic!
        .write(value, withoutResponse: true, timeout: 10);
    _check();
  }

  @override
  Future<void> close() async {
    try {
      await idle().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _closed = true;
    await _statusSubscription?.cancel();
    await _dataSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _responses.close();
    await _data.close();
  }
}
