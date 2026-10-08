import 'dart:convert';
import 'dart:typed_data';

abstract final class FileWire {
  static const version = 1;
  static const maxPayload = 244;
  static const header = 12;
  static const window = 8;
  static const logs = 0;
  static const inbox = 1;
  static const list = 1, stat = 2, put = 3, get = 4;
  static const complete = 5, cancel = 6, ack = 7, status = 8;
  static const listResponse = 0x81, statResponse = 0x82, startResponse = 0x83;
  static const ackResponse = 0x84,
      completeResponse = 0x85,
      cancelResponse = 0x86,
      errorResponse = 0x87;
  static bool validName(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(name);
}

class FileRequest {
  const FileRequest(
      {required this.op,
      required this.id,
      required this.budget,
      this.store = 0,
      this.name = '',
      this.index = 0,
      this.size = 0,
      this.offset = 0,
      this.hash,
      this.chunk = 0,
      this.session = 0,
      this.rewind = false});
  final int op, id, budget, store, index, size, offset, chunk, session;
  final String name;
  final Uint8List? hash;
  final bool rewind;

  Uint8List encode() {
    if (id <= 0 ||
        id > 0xffffffff ||
        budget < 20 ||
        budget > FileWire.maxPayload) {
      throw const FormatException('Invalid file-transfer request');
    }
    final p = _Writer()
      ..u8(op)
      ..u8(FileWire.version)
      ..u32(id)
      ..u16(budget);
    switch (op) {
      case FileWire.list:
        p
          ..u8(store)
          ..u32(index);
      case FileWire.stat:
      case FileWire.put:
      case FileWire.get:
        if (!FileWire.validName(name))
          throw const FormatException('Invalid file name');
        p
          ..u8(store)
          ..u8(name.length)
          ..bytes(ascii.encode(name));
        if (op != FileWire.stat) {
          if (chunk <= 0 ||
              chunk > budget - FileWire.header ||
              hash?.length != 32) {
            throw const FormatException('Invalid transfer parameters');
          }
          p
            ..u16(chunk)
            ..u64(op == FileWire.get ? offset : size)
            ..bytes(hash!);
        }
      case FileWire.complete:
      case FileWire.cancel:
      case FileWire.status:
        p.u32(session);
      case FileWire.ack:
        p
          ..u32(session)
          ..u64(offset)
          ..u8(rewind ? 1 : 0);
      default:
        throw const FormatException('Unknown file-transfer operation');
    }
    return p.result;
  }
}

class FileData {
  FileData(this.session, this.offset, this.bytes);
  final int session, offset;
  final Uint8List bytes;
  Uint8List encode() => (_Writer()
        ..u32(session)
        ..u64(offset)
        ..bytes(bytes))
      .result;
  static FileData decode(List<int> value) {
    if (value.length <= FileWire.header || value.length > FileWire.maxPayload) {
      throw const FormatException('Invalid file-transfer data');
    }
    final p = _Reader(value);
    return FileData(p.u32(), p.u64(), p.rest());
  }
}

class RemoteFile {
  const RemoteFile(
      {required this.name,
      required this.size,
      this.modifiedSeconds = 0,
      this.hash});
  final String name;
  final int size, modifiedSeconds;
  final Uint8List? hash;
  String get hashHex =>
      hash!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class FileStart {
  FileStart(
      this.session, this.offset, this.size, this.hash, this.chunk, this.window);
  final int session, offset, size, chunk, window;
  final Uint8List hash;
}

class FileAck {
  FileAck(this.session, this.offset, this.rewind);
  final int session, offset;
  final bool rewind;
}

class FileResponse {
  FileResponse(this.request, this.body);
  final int request;
  final Uint8List body;
  int get kind => body[0];
  void check() {
    if (body.length < 2)
      throw const FormatException('Incomplete file response');
    if (kind == FileWire.errorResponse) throw FileTransferException(body[1]);
  }

  (int, RemoteFile?) catalog() {
    check();
    if (kind != FileWire.listResponse)
      throw const FormatException('Unexpected catalog response');
    if (body.length == 2 && body[1] == 1) return (0, null);
    final p = _Reader(body)..u8();
    if (p.u8() != 0) throw const FormatException('Invalid catalog response');
    final next = p.u32(), size = p.u64(), modified = p.u64();
    final name = ascii.decode(p.take(p.u8()));
    if (!FileWire.validName(name) || p.remaining != 0)
      throw const FormatException('Invalid catalog entry');
    return (
      next,
      RemoteFile(name: name, size: size, modifiedSeconds: modified)
    );
  }

  RemoteFile metadata(String name) {
    check();
    if (kind != FileWire.statResponse || body.length != 42 || body[1] != 0) {
      throw const FormatException('Invalid metadata response');
    }
    final p = _Reader(body)
      ..u8()
      ..u8();
    return RemoteFile(name: name, size: p.u64(), hash: p.take(32));
  }

  FileStart start() {
    check();
    if (kind != FileWire.startResponse || body.length != 58 || body[1] != 0) {
      throw const FormatException('Invalid start response');
    }
    final p = _Reader(body)
      ..u8()
      ..u8();
    final session = p.u32(), offset = p.u64(), size = p.u64();
    final chunk = p.u16(), window = p.u16(), hash = p.take(32);
    if (session == 0 ||
        offset > size ||
        chunk <= 0 ||
        window <= 0 ||
        window > FileWire.window) {
      throw const FormatException('Invalid negotiated transfer parameters');
    }
    return FileStart(session, offset, size, hash, chunk, window);
  }

  FileAck acknowledgment() {
    check();
    if (kind != FileWire.ackResponse || body.length != 14 || body[13] > 1) {
      throw const FormatException('Invalid acknowledgment');
    }
    final p = _Reader(body)..u8();
    return FileAck(p.u32(), p.u64(), p.u8() == 1);
  }
}

class FileTransferException implements Exception {
  const FileTransferException(this.code);
  final int code;
  @override
  String toString() => switch (code) {
        2 => 'File not found',
        3 => 'Another transfer is active',
        4 => 'File access denied',
        5 => 'Not enough free space',
        6 => 'File changed; retry the transfer',
        7 => 'File checksum mismatch',
        9 => 'Transfer session expired',
        10 => 'Scooter must be awake',
        11 => 'Bluetooth transport busy',
        _ => 'Bluetooth file transfer failed ($code)',
      };
}

class FileResponseAssembler {
  int? _request, _sequence;
  int _total = 0;
  BytesBuilder _body = BytesBuilder(copy: false);
  FileResponse? add(List<int> value) {
    if (value.length <= FileWire.header || value.length > 128)
      throw const FormatException('Invalid response fragment');
    final p = _Reader(value);
    final request = p.u32(),
        sequence = p.u32(),
        offset = p.u16(),
        total = p.u16();
    if (request == 0 ||
        total == 0 ||
        total > 256 ||
        offset + p.remaining > total) {
      throw const FormatException('Invalid response bounds');
    }
    if (offset == 0) {
      _request = request;
      _sequence = sequence;
      _total = total;
      _body = BytesBuilder(copy: false);
    }
    if (_request != request ||
        _sequence != sequence ||
        _total != total ||
        offset != _body.length) return null;
    _body.add(p.rest());
    if (_body.length != total) return null;
    final result = FileResponse(request, _body.takeBytes());
    _request = null;
    if (result.body.length < 2)
      throw const FormatException('Incomplete file response');
    return result;
  }
}

class _Writer {
  final _bytes = BytesBuilder(copy: false);
  void u8(int n) {
    if (n < 0 || n > 255) throw const FormatException('Invalid uint8');
    _bytes.addByte(n);
  }

  void u16(int n) {
    if (n < 0 || n > 0xffff) throw const FormatException('Invalid uint16');
    final p = ByteData(2)..setUint16(0, n, Endian.little);
    bytes(p.buffer.asUint8List());
  }

  void u32(int n) {
    if (n < 0 || n > 0xffffffff) throw const FormatException('Invalid uint32');
    final p = ByteData(4)..setUint32(0, n, Endian.little);
    bytes(p.buffer.asUint8List());
  }

  void u64(int n) {
    if (n < 0) throw const FormatException('Invalid uint64');
    final p = ByteData(8)..setUint64(0, n, Endian.little);
    bytes(p.buffer.asUint8List());
  }

  void bytes(List<int> p) => _bytes.add(p);
  Uint8List get result => _bytes.takeBytes();
}

class _Reader {
  _Reader(List<int> bytes) : _bytes = Uint8List.fromList(bytes) {
    _data = ByteData.sublistView(_bytes);
  }
  final Uint8List _bytes;
  late final ByteData _data;
  int _offset = 0;
  int get remaining => _bytes.length - _offset;
  void _require(int n) {
    if (n < 0 || n > remaining)
      throw const FormatException('Truncated file-transfer message');
  }

  int u8() {
    _require(1);
    return _bytes[_offset++];
  }

  int u16() {
    _require(2);
    final n = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return n;
  }

  int u32() {
    _require(4);
    final n = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return n;
  }

  int u64() {
    _require(8);
    final n = _data.getUint64(_offset, Endian.little);
    _offset += 8;
    if (n < 0) throw const FormatException('File offset out of range');
    return n;
  }

  Uint8List take(int n) {
    _require(n);
    final p = Uint8List.sublistView(_bytes, _offset, _offset + n);
    _offset += n;
    return p;
  }

  Uint8List rest() => take(remaining);
}
