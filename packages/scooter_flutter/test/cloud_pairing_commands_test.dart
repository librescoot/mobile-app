import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/src/ble/characteristic_repository.dart';
import 'package:scooter_flutter/src/ble/cloud_pairing_commands.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  bool get isDisconnected => false;
}

class _Channel extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  final commands = <String>[];
  String capabilities = 'cap:ext:cloud-pairing=1';
  String response =
      'cloud-pairing:status:{"state":"waiting_for_web_setup","running":true,"code":"ABCDE-12345","url":"https://connect.librescoot.org/pair","expires_at":4102444800}';
  @override
  bool get isNotifying => true;
  @override
  Stream<List<int>> get onValueReceived => values.stream;
  @override
  Future<bool> setNotifyValue(bool notify,
          {int timeout = 15, bool forceIndications = false}) async =>
      true;
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) async {
    final command = ascii.decode(value);
    commands.add(command);
    values.add(utf8.encode(command == 'cap:ext' ? capabilities : response));
  }
}

class _Repository extends Fake implements CharacteristicRepository {
  _Repository(this.channel);
  final _Channel channel;
  @override
  BluetoothCharacteristic get extendedCommandCharacteristic => channel;
  @override
  BluetoothCharacteristic get extendedResponseCharacteristic => channel;
  @override
  bool extendedNotifyVerified = false;
  @override
  bool get gattTableMismatch => false;
  @override
  bool get extendedChannelUnresponsive => false;
  @override
  bool get extendedChannelMissing => false;
  @override
  void noteExtendedResponse() {}
  @override
  void noteSilentExtendedCommand() {}
  @override
  void noteGattRejection(Object error, String operation) {}
}

void main() {
  test('discovers capability and parses a pairing status', () async {
    final channel = _Channel();
    addTearDown(channel.values.close);
    final repo = _Repository(channel);
    expect(await supportsCloudPairingCommand(_Device(), repo), isTrue);
    final status = await cloudPairingCommand(_Device(), repo, 'start');
    expect(status.state, 'waiting_for_web_setup');
    expect(status.running, isTrue);
    expect(status.code, 'ABCDE-12345');
    expect(status.expiresAt!.millisecondsSinceEpoch, 4102444800000);
    expect(channel.commands, ['cap:ext', 'cloud-pairing:start']);
    expect(channel.values.hasListener, isFalse);
  });
  test('does not infer support from an unversioned or missing capability',
      () async {
    final channel = _Channel()..capabilities = 'cap:ext:config:cloud-pairing';
    addTearDown(channel.values.close);
    expect(await supportsCloudPairingCommand(_Device(), _Repository(channel)),
        isFalse);
  });
  test('does not issue commands for expired sessions or unsupported actions',
      () async {
    final channel = _Channel();
    addTearDown(channel.values.close);
    final repo = _Repository(channel);
    await expectLater(
        cloudPairingCommand(_Device(), repo, 'start', isCurrent: () => false),
        throwsStateError);
    await expectLater(
        cloudPairingCommand(_Device(), repo, 'delete'), throwsArgumentError);
    expect(channel.commands, isEmpty);
  });
  test('reports firmware errors without treating them as status', () async {
    final channel = _Channel()..response = 'cloud-pairing:error:unavailable';
    addTearDown(channel.values.close);
    await expectLater(
        cloudPairingCommand(_Device(), _Repository(channel), 'status'),
        throwsStateError);
  });
  test('rejects invalid states, codes and errors', () {
    expect(
        () => CloudPairingStatus.parse(
            'cloud-pairing:status:{"state":"bad","running":true}'),
        throwsFormatException);
    expect(
        () => CloudPairingStatus.parse(
            'cloud-pairing:status:{"state":"connected","running":false,"code":"ABCDE-12345","expires_at":1}'),
        throwsFormatException);
    expect(
        () => CloudPairingStatus.parse(
            'cloud-pairing:status:{"state":"waiting_for_web_setup","running":true,"code":"abcde-12345","expires_at":1}'),
        throwsFormatException);
    expect(() => CloudPairingStatus.parse('cloud-pairing:error:unavailable'),
        throwsFormatException);
  });
}
