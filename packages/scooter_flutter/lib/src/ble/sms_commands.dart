import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';
import 'firmware_queries.dart';

class SmsMessage {
  const SmsMessage(
      {required this.id,
      required this.from,
      required this.text,
      required this.timestamp,
      required this.read,
      required this.forwardStatus});
  final String id, from, text, timestamp, forwardStatus;
  final bool read;

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        json['from'] is! String ||
        json['text'] is! String ||
        json['timestamp'] is! String ||
        json['read'] is! bool) {
      throw const FormatException('Invalid SMS message');
    }
    return SmsMessage(
        id: id,
        from: json['from'] as String,
        text: json['text'] as String,
        timestamp: json['timestamp'] as String,
        read: json['read'] as bool,
        forwardStatus: json['forward-status'] is String
            ? json['forward-status'] as String
            : '');
  }
}

class SmsInbox {
  const SmsInbox(this.messages, this.unread);
  final List<SmsMessage> messages;
  final int unread;
}

Future<void> _smsQueue = Future.value();

Future<SmsInbox> readSmsInboxCommand(
    BluetoothDevice? device, CharacteristicRepository repo,
    {bool Function()? isCurrent}) {
  final result = _smsQueue.then((_) => _readInbox(device, repo, isCurrent));
  _smsQueue = result.then((_) {}, onError: (_) {});
  return result;
}

Future<SmsInbox> _readInbox(BluetoothDevice? device,
    CharacteristicRepository repo, bool Function()? isCurrent) async {
  final groups = await discoverLsCapabilityGroupsCommand(device, repo,
      isCurrent: isCurrent);
  if (!groups.answered || groups.versions['sms'] != 1) {
    throw UnsupportedError('SMS inbox requires compatible scooter firmware');
  }
  Future<String> request(String command) async {
    checkCommandCurrent(isCurrent);
    final response = await sendLsExtendedCommand(device, repo, command,
        isCurrent: isCurrent);
    if (response == null) throw TimeoutException('SMS response timed out');
    return response;
  }

  final start = await request('sms:start');
  final match =
      RegExp(r'^s:s:([0-9a-f]{4}):(\d{1,3}):(\d{1,3})$').firstMatch(start);
  if (match == null) throw const FormatException('Invalid SMS inbox response');
  final token = match.group(1)!;
  final count = int.parse(match.group(2)!);
  final unread = int.parse(match.group(3)!);
  if (count > 100 || unread > count) {
    throw const FormatException('Invalid SMS count');
  }
  final budget = min(244, max(20, (device?.mtuNow ?? 23) - 3));
  final messages = <SmsMessage>[];
  for (var index = 0; index < count; index++) {
    final bytes = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final offsetText = offset.toRadixString(36);
      final response =
          await request('sms:get:$token:$index:$offsetText:$budget');
      if (response == 's:e:$token:$offsetText') break;
      final data = decodeSmsChunk(response, token, offsetText);
      if (data.isEmpty || offset + data.length > 32768) {
        throw const FormatException('Invalid SMS chunk length');
      }
      bytes.add(data);
      offset += data.length;
    }
    final json = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid SMS JSON');
    }
    messages.add(SmsMessage.fromJson(json));
  }
  checkCommandCurrent(isCurrent);
  return SmsInbox(List.unmodifiable(messages), unread);
}

List<int> decodeSmsChunk(String response, String token, String offset) {
  final prefix = 's:p:$token:$offset:';
  if (!response.startsWith(prefix)) {
    throw const FormatException('Invalid SMS chunk');
  }
  return base64Url
      .decode(base64Url.normalize(response.substring(prefix.length)));
}

Future<void> changeSmsCommand(BluetoothDevice? device,
    CharacteristicRepository repo, String action, String id,
    {bool Function()? isCurrent}) async {
  if ((action != 'read' && action != 'delete') ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
    throw const FormatException('Invalid SMS action');
  }
  final response = await sendLsExtendedCommand(device, repo, 'sms:$action:$id',
      isCurrent: isCurrent);
  if (response != 's:queued') throw StateError('SMS action not queued');
}
