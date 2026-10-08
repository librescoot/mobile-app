import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/file_transfer_protocol.dart';
import 'package:scooter_flutter/file_transfer_client.dart';

class _Storage {
  final files = <String, Uint8List>{};
  Uint8List? partial, expectedHash;
  String? partialName;
  int received = 0;
}

class _Port implements FileTransferTransport {
  _Port(this.storage,
      {this.payloadBudget = 244,
      this.dropDownloadOffset,
      this.delayStart = false});
  final _Storage storage;
  @override
  final int payloadBudget;
  int? dropDownloadOffset;
  final bool delayStart;
  final _responses = StreamController<List<int>>.broadcast(sync: true),
      _data = StreamController<List<int>>.broadcast(sync: true);
  @override
  bool isCurrent = true;
  int request = 0,
      session = 313,
      chunk = 0,
      size = 0,
      sent = 0,
      acknowledged = 0,
      sequence = 0;
  int? mode;
  Uint8List? content;
  bool completed = false;
  @override
  Stream<List<int>> get responses => _responses.stream;
  @override
  Stream<List<int>> get data => _data.stream;
  @override
  Future<void> ready() async {}
  @override
  Future<void> idle() async {}
  void _reply(List<int> body) {
    final seq = ++sequence, limit = min(payloadBudget, 128) - 12;
    for (var offset = 0; offset < body.length; offset += limit) {
      final header = ByteData(12)
        ..setUint32(0, request, Endian.little)
        ..setUint32(4, seq, Endian.little)
        ..setUint16(8, offset, Endian.little)
        ..setUint16(10, body.length, Endian.little);
      _responses.add(
          [...header.buffer.asUint8List(), ...body.skip(offset).take(limit)]);
    }
  }

  void _error(int code) => _reply([FileWire.errorResponse, code]);
  List<int> _u32(int n) =>
      (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List();
  List<int> _u64(int n) =>
      (ByteData(8)..setUint64(0, n, Endian.little)).buffer.asUint8List();
  List<int> _u16(int n) =>
      (ByteData(2)..setUint16(0, n, Endian.little)).buffer.asUint8List();
  void _ack({bool rewind = false}) => _reply([
        FileWire.ackResponse,
        ..._u32(session),
        ..._u64(storage.received),
        rewind ? 1 : 0
      ]);
  void _pump() {
    final limit = min(size, acknowledged + 8 * chunk);
    while (sent < limit) {
      final offset = sent, end = min(size, sent + chunk);
      sent = end;
      if (dropDownloadOffset == offset) {
        dropDownloadOffset = null;
        continue;
      }
      _data.add(FileData(
              session, offset, Uint8List.sublistView(content!, offset, end))
          .encode());
    }
  }

  @override
  Future<void> writeControl(Uint8List value) async {
    final b = ByteData.sublistView(value), op = value[0];
    request = b.getUint32(2, Endian.little);
    switch (op) {
      case FileWire.list:
        final entries = storage.files.entries.toList();
        final index = b.getUint32(9, Endian.little);
        if (index >= entries.length) {
          _reply([FileWire.listResponse, 1]);
          return;
        }
        final entry = entries[index];
        _reply([
          FileWire.listResponse,
          0,
          ..._u32(index + 1),
          ..._u64(entry.value.length),
          ..._u64(1700000000),
          entry.key.length,
          ...ascii.encode(entry.key)
        ]);
      case FileWire.stat:
        final name = ascii.decode(value.sublist(10, 10 + value[9]));
        final file = storage.files[name];
        if (file == null) {
          _error(2);
          return;
        }
        _reply([
          FileWire.statResponse,
          0,
          ..._u64(file.length),
          ...sha256.convert(file).bytes
        ]);
      case FileWire.put:
      case FileWire.get:
        final store = value[8],
            n = value[9],
            name = ascii.decode(value.sublist(10, 10 + value[9])),
            pos = 10 + n;
        chunk = b.getUint16(pos, Endian.little);
        final hash = Uint8List.sublistView(value, pos + 10, pos + 42);
        mode = op;
        session++;
        completed = false;
        if (op == FileWire.put) {
          if (store == FileWire.logs) {
            _error(4);
            mode = null;
            return;
          }
          if (storage.files.containsKey(name)) {
            _error(6);
            mode = null;
            return;
          }
          size = b.getUint64(pos + 2, Endian.little);
          if (storage.partialName != name ||
              storage.partial?.length != size ||
              !_equal(storage.expectedHash, hash)) {
            storage.partial = Uint8List(size);
            storage.partialName = name;
            storage.expectedHash = Uint8List.fromList(hash);
            storage.received = 0;
          }
          storage.received -= storage.received % chunk;
          acknowledged = storage.received;
        } else {
          content = storage.files[name];
          if (content == null) {
            _error(2);
            mode = null;
            return;
          }
          size = content!.length;
          acknowledged = b.getUint64(pos + 2, Endian.little);
        }
        sent = acknowledged;
        if (delayStart) return;
        _reply([
          FileWire.startResponse,
          0,
          ..._u32(session),
          ..._u64(acknowledged),
          ..._u64(size),
          ..._u16(chunk),
          ..._u16(8),
          ...hash
        ]);
        if (op == FileWire.get) _pump();
      case FileWire.ack:
        final offset = b.getUint64(12, Endian.little);
        acknowledged = offset;
        if (value[20] == 1) sent = offset;
        _pump();
      case FileWire.status:
        _ack();
      case FileWire.cancel:
        mode = null;
        _reply([FileWire.cancelResponse, 0]);
      case FileWire.complete:
        if (mode == FileWire.put) {
          if (!_equal(
              sha256.convert(storage.partial!).bytes, storage.expectedHash)) {
            _error(7);
            return;
          }
          storage.files[storage.partialName!] =
              Uint8List.fromList(storage.partial!);
        }
        mode = null;
        completed = true;
        _reply([FileWire.completeResponse, 0]);
    }
  }

  @override
  Future<void> writeData(Uint8List value) async {
    final packet = FileData.decode(value);
    if (packet.session != session || mode != FileWire.put) return;
    if (packet.offset != storage.received) {
      _ack(rewind: true);
      return;
    }
    storage.partial!.setRange(
        packet.offset, packet.offset + packet.bytes.length, packet.bytes);
    storage.received += packet.bytes.length;
    if (storage.received == size || storage.received % (chunk * 4) == 0) _ack();
  }

  @override
  Future<void> close() async {
    isCurrent = false;
    await _responses.close();
    await _data.close();
  }

  bool _equal(List<int>? a, List<int>? b) =>
      a != null &&
      b != null &&
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
}

void main() {
  late Directory root;
  late _Storage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ble-file-client-');
    storage = _Storage();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Uint8List payload(int n) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 7) & 255));
  test('list and verified download with a missing chunk and small MTU',
      () async {
    final original = payload(1027);
    storage.files['logs-test.tar.gz'] = original;
    final port = _Port(storage, payloadBudget: 20, dropDownloadOffset: 16),
        client = FileTransferClient(_Port(storage));
    await client.close();
    final receiver = FileTransferClient(port);
    addTearDown(receiver.close);
    expect(
        (await receiver.list(FileWire.logs)).single.name, 'logs-test.tar.gz');
    final file = await receiver.download(
        FileWire.logs, 'logs-test.tar.gz', Directory('${root.path}/cache'));
    expect(await file.readAsBytes(), original);
    expect(port.completed, isTrue);
    expect(await File('${file.path}.part').exists(), isFalse);
  });
  test('download cancellation preserves a resumable private partial', () async {
    final original = payload(5003);
    storage.files['logs-test.tar.gz'] = original;
    final cache = Directory('${root.path}/cache');
    late FileTransferClient client;
    client = FileTransferClient(_Port(storage), onProgress: (p) {
      if (p.bytes >= 928) client.cancel();
    });
    await expectLater(client.download(FileWire.logs, 'logs-test.tar.gz', cache),
        throwsA(isA<FileTransferCancelled>()));
    await client.close();
    final port = _Port(storage), retry = FileTransferClient(port);
    addTearDown(retry.close);
    final file = await retry.download(FileWire.logs, 'logs-test.tar.gz', cache);
    expect(await file.readAsBytes(), original);
    expect(port.completed, isTrue);
  });
  test('upload stages, resumes and confirms an existing identical artifact',
      () async {
    final original = payload(5003), source = File('${root.path}/source.bin');
    await source.writeAsBytes(original);
    late FileTransferClient client;
    client = FileTransferClient(_Port(storage), onProgress: (p) {
      if (p.bytes >= 928 && !p.verifying) client.cancel();
    });
    await expectLater(client.upload(FileWire.inbox, 'map.bin', source),
        throwsA(isA<FileTransferCancelled>()));
    expect(storage.received, greaterThanOrEqualTo(928));
    expect(storage.files.containsKey('map.bin'), isFalse);
    await client.close();
    final retry = FileTransferClient(_Port(storage));
    addTearDown(retry.close);
    final file = await retry.upload(FileWire.inbox, 'map.bin', source);
    expect(file.hashHex, sha256.convert(original).toString());
    expect(storage.files['map.bin'], original);
    expect((await retry.upload(FileWire.inbox, 'map.bin', source)).hashHex,
        file.hashHex);
  });
  test(
      'logs are read-only and named uploads cannot overwrite different content',
      () async {
    final source = File('${root.path}/source.bin');
    await source.writeAsBytes(payload(20));
    storage.files['existing.bin'] = payload(21);
    final client = FileTransferClient(_Port(storage));
    addTearDown(client.close);
    await expectLater(client.upload(FileWire.logs, 'logs-test.tar.gz', source),
        throwsA(isA<FileTransferException>().having((e) => e.code, 'code', 4)));
    await expectLater(client.upload(FileWire.inbox, 'existing.bin', source),
        throwsA(isA<FileTransferException>().having((e) => e.code, 'code', 6)));
    expect(storage.files['existing.bin'], payload(21));
  });
  test('cancel before the START reply still cancels the correlated request',
      () async {
    storage.files['logs-test.tar.gz'] = payload(20);
    final port = _Port(storage, delayStart: true),
        client = FileTransferClient(_Port(storage));
    await client.close();
    final receiver = FileTransferClient(port);
    addTearDown(receiver.close);
    final download = receiver.download(
        FileWire.logs, 'logs-test.tar.gz', Directory('${root.path}/cache'));
    while (port.mode != FileWire.get) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    receiver.cancel();
    await expectLater(download, throwsA(isA<FileTransferCancelled>()));
    expect(port.mode, isNull);
  });
}
