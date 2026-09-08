import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/service/ble_commands.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  bool isDisconnected = false;
}

class _Write {
  _Write(List<int> bytes, this.allowLongWrite, this.withoutResponse) : bytes = List.of(bytes);
  final List<int> bytes;
  final bool allowLongWrite;
  final bool withoutResponse;
  String get command => ascii.decode(bytes);
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  final writes = <_Write>[];
  final notifyCalls = <bool>[];
  final values = StreamController<List<int>>.broadcast(sync: true);
  Future<void> Function(_Write)? onWrite;
  Completer<void>? notifyGate;
  int listeners = 0;
  int maxListeners = 0;
  int cancellations = 0;

  @override
  bool isNotifying = false;

  @override
  Stream<List<int>> get onValueReceived => Stream<List<int>>.multi((sink) {
        listeners++;
        if (listeners > maxListeners) maxListeners = listeners;
        final subscription = values.stream.listen(
          sink.addSync,
          onError: sink.addErrorSync,
          onDone: sink.closeSync,
        );
        sink.onCancel = () {
          listeners--;
          cancellations++;
          return subscription.cancel();
        };
      }, isBroadcast: true);

  @override
  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false}) async {
    notifyCalls.add(notify);
    if (notifyGate != null) await notifyGate!.future;
    isNotifying = notify;
    return true;
  }

  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    final write = _Write(value, allowLongWrite, withoutResponse);
    writes.add(write);
    await onWrite?.call(write);
  }

  void reply(String response) => values.add(utf8.encode(response));
}

// Yield to queued microtasks without waiting for any protocol timeout.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Device device;
  late _Characteristic basic;
  late _Characteristic extended;
  late _Characteristic response;
  late CharacteristicRepository repo;

  setUp(() {
    device = _Device();
    basic = _Characteristic();
    extended = _Characteristic();
    response = _Characteristic();
    repo = CharacteristicRepository(device)
      ..commandCharacteristic = basic
      ..extendedCommandCharacteristic = extended
      ..extendedResponseCharacteristic = response;
  });

  tearDown(() async {
    expect(response.listeners, 0, reason: 'Every response subscription is cancelled');
    await Future.wait([basic.values.close(), extended.values.close(), response.values.close()]);
  });

  test('root sendCommand writes ASCII with default flags', () async {
    await sendCommand(device, repo, 'scooter:state unlock');
    expect(basic.writes.single.bytes, ascii.encode('scooter:state unlock'));
    expect(basic.writes.single.allowLongWrite, isFalse);
    expect(basic.writes.single.withoutResponse, isFalse);
    expect(extended.writes, isEmpty);
  });

  test('custom characteristic and explicit long-write flag are preserved', () async {
    repo.commandCharacteristic = null;
    await sendCommand(device, repo, 'custom', characteristic: extended);
    await sendCommand(device, repo, 'x' * 100, characteristic: extended, allowLongWrite: true);
    expect(extended.writes.map((write) => write.command), ['custom', 'x' * 100]);
    expect(extended.writes.map((write) => write.allowLongWrite), [false, true]);
    expect(basic.writes, isEmpty);
  });

  test('non-ASCII commands fail before writing', () async {
    await expectLater(sendCommand(device, repo, 'café'), throwsA(isA<ArgumentError>()));
    expect(basic.writes, isEmpty);
  });

  test('basic command rejects missing scooter, disconnection and missing target', () async {
    await expectLater(sendCommand(null, repo, 'test'), throwsA('Scooter not found!'));
    device.isDisconnected = true;
    await expectLater(sendCommand(device, repo, 'test'), throwsA('Scooter disconnected!'));
    device.isDisconnected = false;
    repo.commandCharacteristic = null;
    await expectLater(sendCommand(device, repo, 'test'), throwsA('Could not send command, move closer or reconnect'));
    expect(basic.writes, isEmpty);
  });

  test('basic write failures propagate unchanged', () async {
    final error = StateError('write failed');
    basic.onWrite = (_) async => throw error;
    await expectLater(sendCommand(device, repo, 'test'), throwsA(same(error)));
  });

  test('extended validation rejects unavailable connections and characteristics', () async {
    await expectLater(sendLsExtendedCommand(null, repo, 'test'), throwsA('Scooter not connected!'));
    device.isDisconnected = true;
    await expectLater(sendLsExtendedCommand(device, repo, 'test'), throwsA('Scooter not connected!'));
    device.isDisconnected = false;
    repo.extendedCommandCharacteristic = null;
    await expectLater(
        sendLsExtendedCommand(device, repo, 'test'), throwsA('Extended command characteristics not available'));
    repo.extendedCommandCharacteristic = extended;
    repo.extendedResponseCharacteristic = null;
    await expectLater(
        sendLsExtendedCommand(device, repo, 'test'), throwsA('Extended command characteristics not available'));
    expect(response.notifyCalls, isEmpty);
    expect(extended.writes, isEmpty);
  });

  test('notification enable completes before listening and writing', () async {
    response.notifyGate = Completer<void>();
    extended.onWrite = (_) async {
      expect(response.isNotifying, isTrue);
      expect(response.listeners, 1);
      response.reply('ready');
    };
    final result = expectLater(sendLsExtendedCommand(device, repo, 'test'), completion('ready'));
    await _flush();
    expect(response.notifyCalls, [true]);
    expect(response.listeners, 0);
    expect(extended.writes, isEmpty);
    response.notifyGate!.complete();
    await result;
  });

  test('listens before write, buffers immediate replies and enables notify only once', () async {
    extended.onWrite = (write) async {
      expect(response.listeners, 1);
      response.reply('${write.command}:ok');
    };
    for (final command in ['first', 'second']) {
      await expectLater(sendLsExtendedCommand(device, repo, command), completion('$command:ok'));
      expect(response.listeners, 0);
    }
    expect(response.notifyCalls, [true]);
    expect(response.isNotifying, isTrue);
    expect(response.cancellations, 2);
    expect(extended.writes.every((write) => write.allowLongWrite), isTrue);
    expect(basic.writes, isEmpty);
  });

  test('already enabled notifications are not toggled', () async {
    response.isNotifying = true;
    extended.onWrite = (_) async => response.reply('ok');
    await expectLater(sendLsExtendedCommand(device, repo, 'test'), completion('ok'));
    expect(response.notifyCalls, isEmpty);
    expect(response.cancellations, 1);
  });

  test('single-response commands are FIFO through write and response completion', () async {
    final writeGate = Completer<void>();
    extended.onWrite = (write) async {
      if (write.command == 'first') await writeGate.future;
    };
    final first = expectLater(sendLsExtendedCommand(device, repo, 'first'), completion('one'));
    final second = expectLater(sendLsExtendedCommand(device, repo, 'second'), completion('two'));
    await _flush();
    expect(extended.writes.map((write) => write.command), ['first']);
    expect(response.listeners, 1);
    writeGate.complete();
    await _flush();
    expect(extended.writes, hasLength(1), reason: 'Write completion alone does not release the channel');
    response.reply('one');
    await first;
    await _flush();
    expect(extended.writes.map((write) => write.command), ['first', 'second']);
    expect(response.listeners, 1);
    response.reply('two');
    await second;
    expect(response.maxListeners, 1);
    expect(response.cancellations, 2);
  });

  for (final capabilities in [true, false]) {
    test('single/list/single share FIFO (${capabilities ? 'capabilities' : 'keycards'})', () async {
      final first = expectLater(sendLsExtendedCommand(device, repo, 'before'), completion('before:ok'));
      final list = capabilities
          ? expectLater(getLsCapabilitiesCommand(device, repo, 'pm'), completion({'hibernate-for', 'hibernate-cancel'}))
          : expectLater(listKeycardsCommand(device, repo), completion(['AA', 'BB']));
      final last = expectLater(sendLsExtendedCommand(device, repo, 'after'), completion('after:ok'));
      await _flush();
      expect(extended.writes.map((write) => write.command), ['before']);
      response.reply('before:ok');
      await first;
      await _flush();
      final listCommand = capabilities ? 'cap:pm' : 'keycard:list';
      expect(extended.writes.map((write) => write.command), ['before', listCommand]);
      response.reply(capabilities ? 'cap:pm:count:2' : 'keycard:count:2');
      response.reply(capabilities ? 'cap:pm:hibernate-for <duration>' : 'keycard:card:AA');
      await _flush();
      expect(extended.writes, hasLength(2), reason: 'The entire list owns the channel');
      expect(response.listeners, 1);
      response.reply(capabilities ? 'cap:pm:hibernate-cancel' : 'keycard:card:BB');
      await list;
      await _flush();
      expect(extended.writes.map((write) => write.command), ['before', listCommand, 'after']);
      response.reply('after:ok');
      await last;
      expect(response.maxListeners, 1);
      expect(response.cancellations, 3);
      expect(response.notifyCalls, [true]);
    });
  }

  test('write failure cancels listener and releases FIFO to a queued list', () async {
    final gate = Completer<void>();
    final error = StateError('extended write failed');
    extended.onWrite = (write) async {
      if (write.command == 'broken') {
        await gate.future;
        throw error;
      }
      response.reply('keycard:count:1');
      response.reply('keycard:card:recovered');
    };
    final failed = expectLater(sendLsExtendedCommand(device, repo, 'broken'), throwsA(same(error)));
    final recovered = expectLater(listKeycardsCommand(device, repo), completion(['recovered']));
    await _flush();
    expect(extended.writes, hasLength(1));
    expect(response.listeners, 1);
    gate.complete();
    await failed;
    await recovered;
    expect(extended.writes.map((write) => write.command), ['broken', 'keycard:list']);
    expect(response.maxListeners, 1);
    expect(response.cancellations, 2);
    expect(response.notifyCalls, [true]);
  });
}
