import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:unustasis/service/ble_commands.dart';

class _Device extends Fake implements BluetoothDevice {
  bool connected = false;
  final resets = StreamController<void>.broadcast();
  @override
  bool get isDisconnected => !connected;
  @override
  Stream<void> get onServicesReset => resets.stream;
  @override
  Future<void> connect(
      {Duration timeout = const Duration(seconds: 35),
      int? mtu = 512,
      bool autoConnect = false}) async {
    connected = true;
  }
}

class _Command extends Fake implements BluetoothCharacteristic {
  final writes = <String>[];
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) async {
    writes.add(ascii.decode(value));
  }
}

class _Repository extends CharacteristicRepository {
  _Repository(super.scooter, this.validation, this.command) {
    commandCharacteristic = command;
  }
  final String? validation;
  final _Command command;
  @override
  Future<void> findAll({bool additionalLibrescootFeatures = false}) async {}
  @override
  Future<String?> validateGattTable({required bool isAndroid}) async =>
      validation;
}

void main() {
  test('static power command validates before its application write', () async {
    final device = _Device();
    final command = _Command();
    var refreshes = 0;
    await expectLater(
        sendStaticPowerCommand('A', 'power-off',
            deviceFromId: (_) => device,
            repositoryFactory: (device) =>
                _Repository(device, 'unsafe table', command),
            clearGattCache: (_) async {
              refreshes++;
            },
            isAndroid: true),
        throwsStateError);
    expect(refreshes, 1);
    expect(device.connected, isTrue,
        reason: 'the disconnected/static use case still connects');
    expect(command.writes, isEmpty);
    await device.resets.close();
  });

  test('static power command writes after successful validation', () async {
    final device = _Device();
    final command = _Command();
    await sendStaticPowerCommand('A', 'power-off',
        deviceFromId: (_) => device,
        repositoryFactory: (device) => _Repository(device, null, command),
        isAndroid: false);
    expect(command.writes, ['power-off']);
    await device.resets.close();
  });

  group('checkApn', () {
    test('accepts a plain operator APN', () {
      expect(checkApn('internet'), isNull);
      expect(checkApn('web.vodafone.de'), isNull);
      expect(checkApn('internet.t-mobile'), isNull);
      expect(checkApn('m2m_internet'), isNull);
    });

    test('rejects an empty APN', () {
      expect(checkApn(''), ApnProblem.empty);
    });

    test('rejects inner whitespace and tabs', () {
      expect(checkApn('two words'), ApnProblem.invalidCharacters);
      expect(checkApn('tab\there'), ApnProblem.invalidCharacters);
    });

    test('rejects non-ASCII, which the command characteristic cannot carry', () {
      expect(checkApn('süd.example'), ApnProblem.invalidCharacters);
      expect(checkApn('интернет'), ApnProblem.invalidCharacters);
    });

    test('accepts an APN of exactly the maximum length', () {
      expect(checkApn('a' * maxApnLength), isNull);
    });

    test('rejects an APN one character over the maximum', () {
      expect(checkApn('a' * (maxApnLength + 1)), ApnProblem.tooLong);
    });

    test('leaves room for the command prefix inside one extended write', () {
      // The whole "config:apn <value>" write has to fit the extended command
      // budget, so the cap can't be the 100 octets 3GPP allows for an APN.
      expect('config:apn ${'a' * maxApnLength}'.length, lessThanOrEqualTo(100));
    });

    test('the command prefix keeps its trailing space', () {
      // clearCellularApnCommand sends the bare prefix to set an empty value.
      // The firmware splits the payload on the first space and answers
      // config:error:missing value when there is no second field, so dropping
      // that space would turn "clear" into an error with nothing to show for
      // it. maxApnLength is derived from the prefix length, which pins it.
      expect(100 - maxApnLength, 'config:apn '.length);
    });
  });
}
