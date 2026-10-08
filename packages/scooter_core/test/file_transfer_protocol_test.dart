import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:scooter_core/file_transfer_protocol.dart';

Uint8List hex(String value) => Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16)
    ]);
String encoded(List<int> value) =>
    value.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
const putVector =
    '030144332211f400010a73616d706c652e62696e8000b80b000000000000000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const dataVector = 'ddccbbaa0500000001000000000102feff';
const startVector =
    '8300ddccbbaa0001000000000000b80b00000000000080000800000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
List<int> fragment(int id, int sequence, int offset, List<int> body,
    {int count = 8}) {
  final header = ByteData(12)
    ..setUint32(0, id, Endian.little)
    ..setUint32(4, sequence, Endian.little)
    ..setUint16(8, offset, Endian.little)
    ..setUint16(10, body.length, Endian.little);
  return [...header.buffer.asUint8List(), ...body.skip(offset).take(count)];
}

void main() {
  test('PUT and data match the Go wire vectors', () {
    final request = FileRequest(
        op: FileWire.put,
        id: 0x11223344,
        budget: 244,
        store: 1,
        name: 'sample.bin',
        size: 3000,
        chunk: 128,
        hash: Uint8List.fromList(List.generate(32, (n) => n)));
    expect(encoded(request.encode()), putVector);
    final data = FileData.decode(hex(dataVector));
    expect(data.session, 0xaabbccdd);
    expect(data.offset, 0x100000005);
    expect(data.bytes, [0, 1, 2, 254, 255]);
    expect(encoded(data.encode()), dataVector);
  });
  test('small-MTU fragments reassemble the negotiated start', () {
    final assembler = FileResponseAssembler(), body = hex(startVector);
    FileResponse? result;
    for (var offset = 0; offset < body.length; offset += 8) {
      result = assembler.add(fragment(7, 9, offset, body));
    }
    expect(result!.request, 7);
    final start = result.start();
    expect(start.session, 0xaabbccdd);
    expect(start.offset, 256);
    expect(start.size, 3000);
    expect(start.chunk, 128);
    expect(start.window, 8);
    expect(start.hash, List.generate(32, (n) => n));
  });
  test('missing fragments cannot join a different response', () {
    final assembler = FileResponseAssembler(), body = hex(startVector);
    expect(assembler.add(fragment(7, 9, 0, body)), isNull);
    expect(assembler.add(fragment(7, 9, 16, body)), isNull);
    expect(assembler.add(fragment(7, 10, 8, body)), isNull);
    expect(assembler.add(fragment(8, 9, 8, body)), isNull);
    FileResponse? result;
    for (var offset = 0; offset < body.length; offset += 8) {
      result = assembler.add(fragment(7, 10, offset, body));
    }
    expect(result!.kind, FileWire.startResponse);
  });
  test('errors retain correlation rather than throwing inside the assembler',
      () {
    final result = FileResponseAssembler()
        .add(fragment(77, 0, 0, [FileWire.errorResponse, 10]));
    expect(result!.request, 77);
    expect(
        () => result.check(),
        throwsA(
            isA<FileTransferException>().having((e) => e.code, 'code', 10)));
  });
  test('unbounded and malformed response fragments reject', () {
    for (final value in [
      <int>[],
      List.filled(129, 0),
      fragment(1, 1, 0, List.filled(257, 0)),
      fragment(0, 1, 0, [0x85, 0])
    ]) {
      expect(() => FileResponseAssembler().add(value), throwsFormatException);
    }
  });
  test('names cannot reference paths or hidden staging files', () {
    for (final name in [
      '',
      '../secret',
      '/etc/passwd',
      '.partial',
      'a/b',
      'a\\b',
      'naïve',
      'a' * 65
    ]) {
      expect(FileWire.validName(name), isFalse);
      expect(
          () => FileRequest(op: FileWire.stat, id: 1, budget: 244, name: name)
              .encode(),
          throwsFormatException);
    }
    for (final name in [
      'logs-2026-10-07.tar.gz',
      'map.mbtiles',
      'firmware.zip'
    ]) {
      expect(FileWire.validName(name), isTrue);
    }
  });
  test('invalid budgets and chunks reject before transport', () {
    expect(
        () => const FileRequest(op: FileWire.list, id: 0, budget: 244).encode(),
        throwsFormatException);
    expect(
        () => const FileRequest(op: FileWire.list, id: 1, budget: 19).encode(),
        throwsFormatException);
    expect(
        () => FileRequest(
                op: FileWire.put,
                id: 1,
                budget: 20,
                name: 'file.bin',
                chunk: 9,
                hash: Uint8List(32))
            .encode(),
        throwsFormatException);
  });
}
