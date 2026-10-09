import 'dart:convert';
import 'dart:typed_data';

import 'package:scooter_core/file_transfer_protocol.dart';
import 'package:test/test.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
final handle = List<int>.generate(16, (i) => i);

void main() {
  test('OPEN_ROOT matches backend v2 golden vector', () {
    expect(hex(FileBrowserRequest.openRoot(1, 244)), '200201000000f400');
  });

  test('LIST_DIR matches backend v2 golden vector', () {
    expect(
        hex(FileBrowserRequest.listDirectory(
            2, 128, handle, 0x11223344, 0x5566)),
        '2102020000008000000102030405060708090a0b0c0d0e0f443322116655');
  });

  test('handle operations match backend v2 request vectors', () {
    expect(
        hex(FileBrowserRequest.nodeOperation(
            FileBrowserOp.openDirectory, 3, 20, handle)),
        '2202030000001400000102030405060708090a0b0c0d0e0f');
    expect(
        hex(FileBrowserRequest.nodeOperation(
            FileBrowserOp.statNode, 0x11223344, 128, handle)),
        '2402443322118000000102030405060708090a0b0c0d0e0f');
    expect(
        hex(FileBrowserRequest.nodeOperation(
            FileBrowserOp.mkdir, 4, 20, handle)),
        '2702040000001400000102030405060708090a0b0c0d0e0f');
    expect(
        hex(FileBrowserRequest.nodeOperation(
            FileBrowserOp.closeDirectory, 5, 20, handle)),
        '2802050000001400000102030405060708090a0b0c0d0e0f');
  });

  test('RESOLVE_NAME preserves UTF-8 bytes and exact v2 framing', () {
    final name = utf8.encode('ü📄');
    expect(
        hex(FileBrowserRequest.resolveName(
            4, 128, handle, 0, name.length, name)),
        '2302040000008000000102030405060708090a0b0c0d0e0f00000600c3bcf09f9384');
  });

  test(
      'LIST_DIR response matches the backend golden and assembles UTF-8 chunks',
      () {
    final body = <int>[
      0xa1,
      0,
      1,
      0,
      0,
      0,
      1,
      3,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      4,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      0x78,
    ];
    final entry = decodeFileBrowserEntry(body);
    expect(entry.cursor, 1);
    expect(entry.kind, 1);
    expect(entry.size, 3);
    expect(entry.modifiedSeconds, 4);
    expect(entry.nameTotal, 1);
    expect(decodeFileBrowserName(entry.nameChunk), 'x');
    expect(decodeFileBrowserEntry([0xa1, 0, 1, 0, 0, 0, 0]).kind, 0);
    expect(() => decodeFileBrowserEntry([...body, 0]), throwsFormatException);
  });

  test('v2 STAT response skips signed mtime and returns the verified hash', () {
    final body = <int>[
      0xa4,
      0,
      ...List<int>.filled(8, 0),
      ...List<int>.filled(8, 0xff),
      ...List<int>.generate(32, (i) => i)
    ];
    final metadata = FileResponse(1, Uint8List.fromList(body)).metadata('x');
    expect(metadata.size, 0);
    expect(metadata.hash, List<int>.generate(32, (i) => i));
  });

  test('non-end directory entries reject empty and unsafe fragments', () {
    final emptyFragment = [
      0xa1,
      0,
      1,
      0,
      0,
      0,
      1,
      ...List<int>.filled(8, 0),
      ...List<int>.filled(8, 0),
      1,
      0,
      0,
      0,
      0
    ];
    expect(() => decodeFileBrowserEntry(emptyFragment), throwsFormatException);
    final badKind = [...emptyFragment]..[6] = 9;
    expect(() => decodeFileBrowserEntry(badKind), throwsFormatException);
  });

  test('directory handle and component bounds reject unsafe values', () {
    expect(
        () => FileBrowserRequest.nodeOperation(
            FileBrowserOp.openDirectory, 1, 20, [1]),
        throwsFormatException);
    for (final name in ['.', '..', 'a/b', '.partial', '.ble-transfer0', '']) {
      expect(() => fileBrowserUtf8(name), throwsFormatException);
    }
    expect(fileBrowserUtf8('文件.txt').length, greaterThan('文件.txt'.length));
    expect(fileBrowserUtf8(List.filled(255, 'x').join()).length, 255);
    expect(() => fileBrowserUtf8(List.filled(256, 'x').join()),
        throwsFormatException);
  });

  test('GET_NODE and PUT_NODE match backend operation vectors', () {
    expect(
        hex(FileRequest(
            op: FileWire.getNode,
            id: 0x11223344,
            budget: 244,
            version: 2,
            nodeId: Uint8List.fromList(handle),
            offset: 0x0102030405060708,
            chunk: 128,
            hash: Uint8List.fromList(List.generate(32, (i) => i))).encode()),
        '250244332211f400000102030405060708090a0b0c0d0e0f08070605040302018000000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
    expect(
        hex(FileRequest(
            op: FileWire.putNode,
            id: 0x11223344,
            budget: 20,
            version: 2,
            nodeId: Uint8List.fromList(handle),
            intent: 0,
            chunk: 8,
            size: 3,
            hash: Uint8List.fromList([
              0xba,
              0x78,
              0x16,
              0xbf,
              0x8f,
              0x01,
              0xcf,
              0xea,
              0x41,
              0x41,
              0x40,
              0xde,
              0x5d,
              0xae,
              0x22,
              0x23,
              0xb0,
              0x03,
              0x61,
              0xa3,
              0x96,
              0x17,
              0x7a,
              0x9c,
              0xb4,
              0x10,
              0xff,
              0x61,
              0xf2,
              0x00,
              0x15,
              0xad,
            ])).encode()),
        '2602443322111400000102030405060708090a0b0c0d0e0f0008000300000000000000ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad00000000000000000000000000000000000000000000000000000000000000000000000000000000');
  });

  test('PUT_NODE replacement matches backend expected-content vector', () {
    expect(
        hex(FileRequest(
            op: FileWire.putNode,
            id: 0x11223344,
            budget: 128,
            version: 2,
            nodeId: Uint8List.fromList(handle),
            intent: 1,
            chunk: 8,
            size: 0x0102030405060708,
            hash: Uint8List.fromList(List.generate(32, (i) => i)),
            expectedOldSize: 0x1122334455667788,
            expectedOldHash:
                Uint8List.fromList(List.generate(32, (i) => i + 32))).encode()),
        '2602443322118000000102030405060708090a0b0c0d0e0f0108000807060504030201000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f8877665544332211202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f');
  });

  test('control request and data upload body stay within GATT budget', () {
    final request = FileBrowserRequest(
        FileBrowserOp.putNode,
        1,
        244,
        fileBrowserPutBody(handle,
            intent: 1,
            chunk: 232,
            size: 3,
            hash: List.filled(32, 0),
            expectedOldSize: 5,
            expectedOldHash: List.filled(32, 1)));
    expect(request.encode().length, 107);
    expect(request.encode().length, lessThanOrEqualTo(fileBrowserControlLimit));
    expect(() => FileBrowserRequest(1, 1, 244, List.filled(121, 0)).encode(),
        throwsFormatException);
  });
}
