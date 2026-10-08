import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:scooter_core/file_transfer_protocol.dart';

abstract interface class FileTransferTransport {
  int get payloadBudget;
  bool get isCurrent;
  Stream<List<int>> get responses;
  Stream<List<int>> get data;
  Future<void> ready();
  Future<void> idle();
  Future<void> writeControl(Uint8List value);
  Future<void> writeData(Uint8List value);
  Future<void> close();
}

class FileTransferCancelled implements Exception {
  const FileTransferCancelled();
  @override
  String toString() => 'File transfer cancelled';
}

class FileTransferProgress {
  const FileTransferProgress(this.bytes, this.total, {this.verifying = false});
  final int bytes, total;
  final bool verifying;
  double get fraction => total == 0 ? 0 : bytes / total;
}

class FileTransferClient {
  FileTransferClient(this.transport, {this.onProgress});
  final FileTransferTransport transport;
  final void Function(FileTransferProgress)? onProgress;
  final _messages = StreamController<FileResponse>.broadcast(sync: true);
  final _assembler = FileResponseAssembler();
  StreamSubscription<List<int>>? _statusSubscription, _dataSubscription;
  void Function(FileData)? _onData;
  bool _busy = false, _cancelled = false, _closed = false;
  bool _transferRequested = false;
  int _request = 0, _session = 0;
  int _nextId = Random.secure().nextInt(0x7ffffffe) + 1;
  Completer<void>? _interrupted;
  bool get busy => _busy;

  void _check() {
    if (_cancelled || _closed) throw const FileTransferCancelled();
    if (!transport.isCurrent) throw StateError('Bluetooth connection changed');
  }

  int _id() {
    _nextId = (_nextId + 1) & 0x7fffffff;
    return _nextId == 0 ? ++_nextId : _nextId;
  }

  int get _budget => min(FileWire.maxPayload, transport.payloadBudget);
  Future<void> _begin() async {
    if (_busy) throw StateError('Another file operation is active');
    _busy = true;
    _cancelled = false;
    _session = 0;
    _transferRequested = false;
    _request = _id();
    _interrupted = Completer<void>();
    _check();
    _statusSubscription ??= transport.responses.listen((value) {
      try {
        final response = _assembler.add(value);
        if (response != null) _messages.add(response);
      } on FormatException {
        /* Incomplete notifications are recovered by request retries. */
      }
    }, onError: _messages.addError);
    _dataSubscription ??= transport.data.listen((value) {
      try {
        _onData?.call(FileData.decode(value));
      } on FormatException {/* A missing chunk is recovered by rewind. */}
    }, onError: _messages.addError);
    await _wait(transport.ready(), const Duration(seconds: 15));
    _check();
    if (_budget < 20) throw StateError('Bluetooth MTU is too small');
  }

  Future<T> _operation<T>(Future<T> Function() run) async {
    if (_busy) throw StateError('Another file operation is active');
    try {
      await _begin();
      return await run();
    } finally {
      _onData = null;
      if ((_transferRequested || _cancelled) &&
          transport.isCurrent &&
          !_closed) {
        try {
          await transport
              .writeControl(FileRequest(
                      op: FileWire.cancel,
                      id: _request,
                      budget: _budget,
                      session: 0)
                  .encode())
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      try {
        await transport.idle().timeout(const Duration(seconds: 3));
      } catch (_) {}
      _session = 0;
      _busy = false;
      _interrupted = null;
    }
  }

  Future<T> _wait<T>(Future<T> future, Duration timeout) async {
    final stopped = _interrupted;
    return Future.any<T>([
      future.timeout(timeout),
      if (stopped != null)
        stopped.future.then<T>((_) => throw const FileTransferCancelled()),
    ]);
  }

  Future<FileResponse> _rpc(FileRequest request, int expected,
      {Duration timeout = const Duration(seconds: 10)}) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      _check();
      final reply = Completer<FileResponse>();
      final subscription = _messages.stream.listen((response) {
        if (response.request == request.id &&
            (response.kind == expected ||
                response.kind == FileWire.errorResponse) &&
            !reply.isCompleted) {
          reply.complete(response);
        }
      }, onError: (Object error, StackTrace stack) {
        if (!reply.isCompleted) reply.completeError(error, stack);
      });
      try {
        final results = await Future.wait<Object?>([
          _wait(
              Future<void>.sync(() => transport.writeControl(request.encode())),
              const Duration(seconds: 15)),
          _wait(reply.future, timeout),
        ], eagerError: true);
        _check();
        final response = results[1] as FileResponse;
        response.check();
        return response;
      } on TimeoutException {
        if (attempt == 2) rethrow;
      } finally {
        if (!reply.isCompleted) {
          reply.completeError(const FileTransferCancelled());
        }
        await subscription.cancel();
      }
    }
    throw StateError('No response');
  }

  FileRequest _command(int op, {int offset = 0, bool rewind = false}) =>
      FileRequest(
          op: op,
          id: _request,
          budget: _budget,
          session: _session,
          offset: offset,
          rewind: rewind);

  Future<List<RemoteFile>> list(int store) => _operation(() async {
        final files = <RemoteFile>[];
        var index = 0;
        for (var page = 0; page <= 2048; page++) {
          final response = await _rpc(
              FileRequest(
                  op: FileWire.list,
                  id: _request,
                  budget: _budget,
                  store: store,
                  index: index),
              FileWire.listResponse);
          final (next, file) = response.catalog();
          if (file == null) return files;
          if (next <= index) {
            throw const FormatException('Catalog did not advance');
          }
          files.add(file);
          index = next;
        }
        throw const FormatException('Catalog exceeds limit');
      });

  Future<RemoteFile> stat(int store, String name) =>
      _operation(() => _stat(store, name));
  Future<RemoteFile> _stat(int store, String name) async {
    final response = await _rpc(
        FileRequest(
            op: FileWire.stat,
            id: _request,
            budget: _budget,
            store: store,
            name: name),
        FileWire.statResponse,
        timeout: const Duration(minutes: 2));
    final metadata = response.metadata(name);
    if (metadata.size > 4 * 1024 * 1024 * 1024) {
      throw const FormatException('File exceeds transfer size limit');
    }
    return metadata;
  }

  Future<File> download(int store, String name, Directory cache) =>
      _operation(() async {
        final metadata = await _stat(store, name);
        _check();
        final directory = Directory('${cache.path}/$store/${metadata.hashHex}');
        await directory.create(recursive: true);
        _check();
        final finalFile = File('${directory.path}/$name');
        if (await finalFile.exists() &&
            await finalFile.length() == metadata.size &&
            await _hash(finalFile) == metadata.hashHex) {
          _check();
          onProgress?.call(FileTransferProgress(metadata.size, metadata.size));
          return finalFile;
        }
        final partial = File('${finalFile.path}.part');
        final chunk = _budget - FileWire.header;
        var offset = await partial.exists() ? await partial.length() : 0;
        offset = min(offset, metadata.size);
        offset -= offset % chunk;
        final output = await partial.open(mode: FileMode.append);
        await output.truncate(offset);
        await output.setPosition(offset);
        final done = Completer<void>();
        var tail = Future<void>.value(), queued = 0, lastAck = offset;
        int? rewindRequested;
        final early = <FileData>[];
        FileStart? start;
        void receive(FileData packet) {
          if (start == null) {
            if (early.length < FileWire.window * 2) early.add(packet);
            return;
          }
          if (packet.session != _session || done.isCompleted) return;
          if (++queued > FileWire.window * 2) {
            if (!done.isCompleted) {
              done.completeError(StateError('Receive queue overflow'));
            }
            return;
          }
          tail = tail.then((_) async {
            _check();
            if (packet.offset < offset) return;
            if (packet.offset != offset) {
              if (rewindRequested != offset) {
                rewindRequested = offset;
                await transport.writeControl(
                    _command(FileWire.ack, offset: offset, rewind: true)
                        .encode());
              }
              return;
            }
            rewindRequested = null;
            final amount = min(start!.chunk, metadata.size - offset);
            if (packet.bytes.length != amount) {
              throw const FormatException('Invalid download chunk size');
            }
            await output.writeFrom(packet.bytes);
            offset += packet.bytes.length;
            onProgress?.call(FileTransferProgress(offset, metadata.size));
            if (offset == metadata.size ||
                offset - lastAck >= start!.chunk * max(1, start.window ~/ 2)) {
              await output.flush();
              _check();
              await transport.writeControl(
                  _command(FileWire.ack, offset: offset).encode());
              lastAck = offset;
            }
            if (offset == metadata.size && !done.isCompleted) done.complete();
          }).catchError((Object error, StackTrace stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          }).whenComplete(() {
            queued--;
          });
        }

        _onData = receive;
        StreamSubscription<FileResponse>? errors;
        try {
          _transferRequested = true;
          start = (await _rpc(
                  FileRequest(
                      op: FileWire.get,
                      id: _request,
                      budget: _budget,
                      store: store,
                      name: name,
                      offset: offset,
                      hash: metadata.hash,
                      chunk: chunk),
                  FileWire.startResponse,
                  timeout: const Duration(minutes: 2)))
              .start();
          _session = start.session;
          if (start.offset != offset ||
              start.size != metadata.size ||
              start.chunk != chunk ||
              _hex(start.hash) != metadata.hashHex) {
            throw const FormatException('Download identity mismatch');
          }
          errors = _messages.stream.listen((response) {
            if (response.request == _request &&
                response.kind == FileWire.errorResponse &&
                !done.isCompleted) {
              done.completeError(FileTransferException(response.body[1]));
            }
          }, onError: (Object e, StackTrace s) {
            if (!done.isCompleted) done.completeError(e, s);
          });
          for (final packet in early) {
            receive(packet);
          }
          early.clear();
          if (offset == metadata.size && !done.isCompleted) done.complete();
          var retries = 0;
          while (!done.isCompleted) {
            final previous = offset;
            try {
              await _wait(done.future, const Duration(seconds: 5));
            } on TimeoutException {
              _check();
              if (offset == previous) {
                retries++;
              } else {
                retries = 0;
              }
              if (retries >= 12) rethrow;
              await transport.writeControl(
                  _command(FileWire.ack, offset: offset, rewind: true)
                      .encode());
            }
          }
          await done.future;
          await tail;
          _check();
          onProgress?.call(
              FileTransferProgress(offset, metadata.size, verifying: true));
          await output.flush();
        } finally {
          _onData = null;
          await errors?.cancel();
          await tail;
          await output.close();
        }
        _check();
        if (await _hash(partial) != metadata.hashHex) {
          await partial.delete();
          throw const FileTransferException(7);
        }
        _check();
        try {
          await _rpc(_command(FileWire.complete), FileWire.completeResponse);
        } on FileTransferException catch (e) {
          if (e.code != 9) rethrow;
        }
        _session = 0;
        _transferRequested = false;
        if (await finalFile.exists()) await finalFile.delete();
        await partial.rename(finalFile.path);
        _check();
        onProgress?.call(FileTransferProgress(metadata.size, metadata.size));
        return finalFile;
      });

  Future<RemoteFile> upload(int store, String name, File source) =>
      _operation(() async {
        if (!FileWire.validName(name)) {
          throw const FormatException('Invalid file name');
        }
        final size = await source.length();
        if (size > 4 * 1024 * 1024 * 1024) {
          throw const FormatException('File exceeds transfer size limit');
        }
        onProgress?.call(FileTransferProgress(0, size, verifying: true));
        final digest = await _digest(source);
        _check();
        final hash = Uint8List.fromList(digest.bytes),
            chunk = _budget - FileWire.header;
        _transferRequested = true;
        late FileStart start;
        try {
          start = (await _rpc(
                  FileRequest(
                      op: FileWire.put,
                      id: _request,
                      budget: _budget,
                      store: store,
                      name: name,
                      size: size,
                      hash: hash,
                      chunk: chunk),
                  FileWire.startResponse,
                  timeout: const Duration(minutes: 2)))
              .start();
        } on FileTransferException catch (error) {
          if (error.code != 6) rethrow;
          final existing = await _stat(store, name);
          if (existing.size != size || existing.hashHex != digest.toString()) {
            rethrow;
          }
          _transferRequested = false;
          onProgress?.call(FileTransferProgress(size, size));
          return existing;
        }
        _session = start.session;
        if (start.size != size ||
            start.chunk != chunk ||
            _hex(start.hash) != digest.toString()) {
          throw const FormatException('Upload identity mismatch');
        }
        var acknowledged = start.offset, sent = start.offset, retries = 0;
        Object? failure;
        Completer<void> wake = Completer<void>();
        final listener = _messages.stream.listen((response) {
          if (response.request != _request) return;
          try {
            response.check();
            if (response.kind != FileWire.ackResponse) return;
            final ack = response.acknowledgment();
            if (ack.session != _session ||
                ack.offset < acknowledged ||
                ack.offset > sent ||
                ack.offset > size) {
              return;
            }
            if (ack.offset != size && ack.offset % chunk != 0) {
              throw const FormatException('Unaligned upload ACK');
            }
            acknowledged = ack.offset;
            if (ack.rewind) sent = acknowledged;
            onProgress?.call(FileTransferProgress(acknowledged, size));
          } catch (e) {
            failure = e;
          }
          if (!wake.isCompleted) wake.complete();
        }, onError: (Object e, StackTrace _) {
          failure = e;
          if (!wake.isCompleted) wake.complete();
        });
        final input = await source.open();
        try {
          while (acknowledged < size) {
            _check();
            if (failure != null) throw failure!;
            wake = Completer<void>();
            final previous = acknowledged;
            while (sent < size && sent - acknowledged < start.window * chunk) {
              final position = sent;
              await input.setPosition(position);
              final bytes = await input.read(min(chunk, size - position));
              _check();
              if (position != sent) continue;
              if (bytes.isEmpty) throw const FileTransferException(6);
              sent += bytes.length;
              await transport
                  .writeData(FileData(_session, position, bytes).encode());
              _check();
            }
            if (acknowledged == size) break;
            if (acknowledged != previous) {
              retries = 0;
              continue;
            }
            try {
              await _wait(wake.future, const Duration(seconds: 2));
            } on TimeoutException {
              if (++retries > 12) rethrow;
              final ack =
                  (await _rpc(_command(FileWire.status), FileWire.ackResponse))
                      .acknowledgment();
              if (ack.session != _session ||
                  ack.offset < acknowledged ||
                  ack.offset > sent) {
                throw const FormatException('Invalid resumed upload offset');
              }
              acknowledged = ack.offset;
              sent = acknowledged;
            }
          }
          _check();
          if (failure != null) throw failure!;
          onProgress?.call(FileTransferProgress(size, size, verifying: true));
          await _rpc(_command(FileWire.complete), FileWire.completeResponse,
              timeout: Duration(seconds: max(30, size ~/ (1024 * 1024))));
          _session = 0;
          _transferRequested = false;
          onProgress?.call(FileTransferProgress(size, size));
          return RemoteFile(name: name, size: size, hash: hash);
        } finally {
          await listener.cancel();
          await input.close();
        }
      });

  void cancel() {
    _cancelled = true;
    final interrupted = _interrupted;
    if (interrupted != null && !interrupted.isCompleted) interrupted.complete();
  }

  Future<void> close() async {
    cancel();
    _closed = true;
    if (_busy && transport.isCurrent) {
      try {
        await transport
            .writeControl(FileRequest(
                    op: FileWire.cancel,
                    id: _request,
                    budget: _budget,
                    session: 0)
                .encode())
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    await _statusSubscription?.cancel();
    await _dataSubscription?.cancel();
    await transport.close();
    await _messages.close();
  }

  static String _hex(List<int> hash) =>
      hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Future<Digest> _digest(File file) => sha256
      .bind(file.openRead().map((bytes) {
        _check();
        return bytes;
      }))
      .first;
  Future<String> _hash(File file) async => (await _digest(file)).toString();
}
