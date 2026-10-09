import 'dart:convert';
import 'dart:typed_data';

const fileBrowserVersion = 2;
const fileBrowserControlLimit = 128;

abstract final class FileBrowserOp {
  static const openRoot = 0x20, listDirectory = 0x21, openDirectory = 0x22;
  static const resolveName = 0x23, statNode = 0x24, getNode = 0x25;
  static const putNode = 0x26, mkdir = 0x27, closeDirectory = 0x28;
  static const openRootResponse = 0xa0, listDirectoryResponse = 0xa1;
  static const openDirectoryResponse = 0xa2, resolveNameResponse = 0xa3;
  static const statNodeResponse = 0xa4, mkdirResponse = 0xa7;
  static const closeDirectoryResponse = 0xa8;
}

class FileBrowserRequest {
  const FileBrowserRequest(this.op, this.id, this.budget,
      [this.body = const []]);
  final int op, id, budget;
  final List<int> body;

  Uint8List encode() {
    if (id < 1 ||
        id > 0xffffffff ||
        budget < 20 ||
        budget > 244 ||
        body.length + 8 > fileBrowserControlLimit) {
      throw const FormatException('Invalid file-browser request bounds');
    }
    final bytes = Uint8List(8 + body.length);
    final data = ByteData.sublistView(bytes);
    bytes[0] = op;
    bytes[1] = fileBrowserVersion;
    data.setUint32(2, id, Endian.little);
    data.setUint16(6, budget, Endian.little);
    bytes.setRange(8, bytes.length, body);
    return bytes;
  }

  static Uint8List openRoot(int id, int budget) =>
      FileBrowserRequest(FileBrowserOp.openRoot, id, budget).encode();

  static Uint8List listDirectory(
      int id, int budget, List<int> directory, int cursor, int nameOffset) {
    _handle(directory);
    final body = Uint8List(22)..setRange(0, 16, directory);
    final data = ByteData.sublistView(body);
    data.setUint32(16, cursor, Endian.little);
    data.setUint16(20, nameOffset, Endian.little);
    return FileBrowserRequest(FileBrowserOp.listDirectory, id, budget, body)
        .encode();
  }

  static Uint8List nodeOperation(int op, int id, int budget, List<int> node) {
    _handle(node);
    return FileBrowserRequest(op, id, budget, node).encode();
  }

  static Uint8List resolveName(int id, int budget, List<int> directory,
      int offset, int total, List<int> chunk) {
    _handle(directory);
    if (total < 1 ||
        total > 255 ||
        offset < 0 ||
        offset > total ||
        chunk.isEmpty ||
        chunk.length > 100 ||
        offset + chunk.length > total) {
      throw const FormatException('Invalid file-browser name chunk');
    }
    final body = Uint8List(20 + chunk.length)..setRange(0, 16, directory);
    final data = ByteData.sublistView(body);
    data.setUint16(16, offset, Endian.little);
    data.setUint16(18, total, Endian.little);
    body.setRange(20, body.length, chunk);
    return FileBrowserRequest(FileBrowserOp.resolveName, id, budget, body)
        .encode();
  }

  static void _handle(List<int> value) => _fileBrowserHandle(value);
}

class FileBrowserEntry {
  const FileBrowserEntry(
      {required this.name,
      required this.kind,
      required this.size,
      required this.modifiedSeconds,
      required this.cursor,
      this.nameTotal = 0,
      this.nameOffset = 0,
      this.nameChunk = const []});
  final String name;
  final int kind, size, modifiedSeconds, cursor;
  final int nameTotal, nameOffset;
  final List<int> nameChunk;
  bool get isDirectory => kind == 2;
  bool get isFile => kind == 1;
  bool get isSupported => isDirectory || isFile;
}

FileBrowserEntry decodeFileBrowserEntry(List<int> body) {
  if (body.length < 7 ||
      body[0] != FileBrowserOp.listDirectoryResponse ||
      body[1] != 0) {
    throw const FormatException('Invalid directory response');
  }
  final data = ByteData.sublistView(Uint8List.fromList(body));
  final cursor = data.getUint32(2, Endian.little);
  final kind = body[6];
  if (kind == 0) {
    if (body.length != 7) {
      throw const FormatException('Invalid end-of-directory response');
    }
    return FileBrowserEntry(
        name: '', kind: 0, size: 0, modifiedSeconds: 0, cursor: cursor);
  }
  if (body.length < 28) {
    throw const FormatException('Truncated directory entry');
  }
  final size = data.getUint64(7, Endian.little);
  final modified = data.getInt64(15, Endian.little);
  final total = data.getUint16(23, Endian.little);
  final offset = data.getUint16(25, Endian.little);
  final length = body[27];
  if (total < 1 ||
      total > 255 ||
      offset > total ||
      length > 84 ||
      body.length != 28 + length ||
      offset + length > total) {
    throw const FormatException('Invalid directory entry bounds');
  }
  return FileBrowserEntry(
      name: '',
      kind: kind,
      size: size,
      modifiedSeconds: modified,
      cursor: cursor,
      nameTotal: total,
      nameOffset: offset,
      nameChunk: body.sublist(28));
}

List<int> fileBrowserUtf8(String value) {
  final encoded = utf8.encode(value);
  if (encoded.isEmpty ||
      encoded.length > 255 ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains('\u0000') ||
      value == '.partial' ||
      value.startsWith('.ble-transfer')) {
    throw const FormatException('Invalid file-browser name');
  }
  return encoded;
}

String decodeFileBrowserName(List<int> value) {
  final name = utf8.decode(value, allowMalformed: false);
  fileBrowserUtf8(name);
  return name;
}

void _fileBrowserHandle(List<int> value) {
  if (value.length != 16) {
    throw const FormatException('Invalid file-browser handle');
  }
}

Uint8List fileBrowserNodeStatBody(
    List<int> node, int chunk, int size, List<int> hash) {
  FileBrowserRequest._handle(node);
  if (chunk < 1 || chunk > 244 - 12 || size < 0 || hash.length != 32) {
    throw const FormatException('Invalid file-browser transfer parameters');
  }
  final body = Uint8List(99)..setRange(0, 16, node);
  final data = ByteData.sublistView(body);
  data.setUint8(16, 0);
  data.setUint16(17, chunk, Endian.little);
  data.setUint64(19, size, Endian.little);
  body.setRange(27, 59, hash);
  return body;
}

Uint8List fileBrowserPutBody(List<int> node,
    {required int intent,
    required int chunk,
    required int size,
    required List<int> hash,
    int expectedOldSize = 0,
    List<int>? expectedOldHash}) {
  FileBrowserRequest._handle(node);
  final oldHash = expectedOldHash ?? List<int>.filled(32, 0);
  if ((intent != 0 && intent != 1) ||
      chunk < 1 ||
      chunk > 232 ||
      size < 0 ||
      hash.length != 32 ||
      oldHash.length != 32 ||
      (intent == 0 && (expectedOldSize != 0 || oldHash.any((b) => b != 0))) ||
      (intent == 1 && expectedOldSize < 0)) {
    throw const FormatException('Invalid file-browser upload parameters');
  }
  final body = Uint8List(99)..setRange(0, 16, node);
  final data = ByteData.sublistView(body);
  data.setUint8(16, intent);
  data.setUint16(17, chunk, Endian.little);
  data.setUint64(19, size, Endian.little);
  body.setRange(27, 59, hash);
  data.setUint64(59, expectedOldSize, Endian.little);
  body.setRange(67, 99, oldHash);
  return body;
}
