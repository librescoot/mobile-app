import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/src/ble/characteristic_repository.dart';
import 'package:scooter_flutter/src/ble/sms_commands.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  bool get isDisconnected => false;
  @override
  int get mtuNow => 23;
}

class _Channel extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  final body = utf8.encode(jsonEncode({
    'id': 'a' * 32,
    'from': '+49123',
    'text': 'Hello 😀',
    'timestamp': '2026-01-01',
    'read': false
  }));
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
    String response;
    if (command == 'cap:ext') {
      response = 'cap:ext:sms=1';
    } else if (command == 'sms:start') {
      response = 's:s:abcd:1:1';
    } else {
      final parts = command.split(':');
      final offsetText = parts[4];
      final offset = int.parse(offsetText, radix: 36);
      if (offset == body.length) {
        response = 's:e:abcd:$offsetText';
      } else {
        final prefix = 's:p:abcd:$offsetText:';
        var n = min(3, body.length - offset);
        while (prefix.length +
                base64Url
                    .encode(body.sublist(offset, offset + n))
                    .replaceAll('=', '')
                    .length >
            20) {
          n--;
        }
        response = prefix +
            base64Url
                .encode(body.sublist(offset, offset + n))
                .replaceAll('=', '');
      }
    }
    values.add(utf8.encode(response));
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
  test('reads a complete Unicode message at the minimum ATT payload', () async {
    final channel = _Channel();
    final inbox = await readSmsInboxCommand(_Device(), _Repository(channel));
    expect(inbox.unread, 1);
    expect(inbox.messages.single.text, 'Hello 😀');
    expect(channel.values.hasListener, isFalse);
    await channel.values.close();
  });
  test('decodes bounded chunks and rejects stale tokens and offsets', () {
    final value = utf8.encode('Hällo 😀');
    final encoded = base64Url.encode(value).replaceAll('=', '');
    expect(decodeSmsChunk('s:p:abcd:0:$encoded', 'abcd', '0'), value);
    expect(() => decodeSmsChunk('s:p:abcd:1:$encoded', 'abcd', '0'),
        throwsFormatException);
    expect(() => decodeSmsChunk('s:p:1234:0:$encoded', 'abcd', '0'),
        throwsFormatException);
  });
  test('validates message identity and fields', () {
    final message = SmsMessage.fromJson({
      'id': 'a' * 32,
      'from': '+49123',
      'text': 'hello',
      'timestamp': '2026-01-01',
      'read': false
    });
    expect(message.text, 'hello');
    expect(message.read, false);
    expect(() => SmsMessage.fromJson({'id': 'bad'}), throwsFormatException);
  });
}
