import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/src/ble/characteristic_repository.dart';
import 'package:scooter_flutter/src/ble/trip_history_commands.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  bool get isDisconnected => false;
  @override
  int get mtuNow => 23;
}

class _Channel extends Fake implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  late List<int> body;
  final List<String> commands = [];
  void Function(String)? onCommand;
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
    String response;
    if (command == 'cap:ext') {
      response = 'cap:ext:trip-history=1';
    } else if (command.startsWith('trip:history:start:')) {
      final parts = command.split(':');
      final request = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[4]))));
      expect(parts[3], 'l');
      expect(request['limit'], 10);
      response = 'h:s:12345678:${body.length.toRadixString(36)}';
    } else {
      final parts = command.split(':');
      final offsetText = parts[4];
      final offset = int.parse(offsetText, radix: 36);
      final prefix = 'h:p:12345678:$offsetText:';
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
    values.add(utf8.encode(response));
    onCommand?.call(command);
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
  const id = '0123456789abcdef0123456789abcdef';
  final valid = <String, dynamic>{
    'id': id,
    'started_at_s': 1793343600,
    'ended_at_s': 1793344600,
    'distance_m': 8400,
    'ready_duration_s': 1000,
    'point_count': 2,
    'average_speed_kmh': 30.24,
    'max_recorded_gps_speed_kmh': 45.0,
  };
  test('reads a page across minimum-MTU Bluetooth chunks', () async {
    final channel = _Channel()
      ..body = utf8.encode(jsonEncode({
        'trips': [valid]
      }));
    final page = await readTripHistoryPage(_Device(), _Repository(channel));
    expect(page.trips.single.id, id);
    expect(
        channel.commands.where((c) => c.startsWith('trip:history:get:')).length,
        greaterThan(1));
    expect(channel.values.hasListener, isFalse);
    await channel.values.close();
  });
  test('stops fetching when the session expires', () async {
    var current = true;
    final channel = _Channel()
      ..body = utf8.encode(jsonEncode({
        'trips': [valid]
      }))
      ..onCommand = (command) {
        if (command.startsWith('trip:history:get:')) current = false;
      };
    await expectLater(
        readTripHistoryPage(_Device(), _Repository(channel),
            isCurrent: () => current),
        throwsStateError);
    expect(
        channel.commands.where((c) => c.startsWith('trip:history:get:')).length,
        1);
    expect(channel.values.hasListener, isFalse);
    await channel.values.close();
  });
  test('validates a page and its entries', () {
    final page = TripHistoryPage.fromJson({
      'trips': [valid],
      'next_cursor': 'cursor'
    });
    expect(page.trips.single.id, id);
    expect(page.trips.single.distanceMeters, 8400);
    expect(page.nextCursor, 'cursor');
    expect(() => TripHistoryEntry.fromJson({...valid, 'id': 'bad'}),
        throwsFormatException);
    expect(() => TripHistoryEntry.fromJson({...valid, 'distance_m': -1}),
        throwsFormatException);
    expect(() => TripHistoryPage.fromJson({'trips': 'bad'}),
        throwsFormatException);
  });
  test('handles missing optional speeds and validates GPS', () {
    final trip = TripHistoryEntry.fromJson({
      ...valid,
      'average_speed_kmh': null,
      'max_recorded_gps_speed_kmh': null
    });
    expect(trip.averageSpeedKmh, isNull);
    final page = TripHistoryPointsPage.fromJson({
      'points': [
        {'id': 5, 'timestamp_ms': 1000, 'latitude': 52.5, 'longitude': 13.4}
      ],
      'next_after_id': 5
    });
    expect(page.points.single.latitude, 52.5);
    expect(page.nextAfterId, 5);
    expect(
        () => TripHistoryPoint.fromJson(
            {'id': 1, 'timestamp_ms': 0, 'latitude': 100, 'longitude': 0}),
        throwsFormatException);
  });
  test('rejects stale chunk identity and offset', () {
    final data = utf8.encode('Hello');
    final encoded = base64Url.encode(data).replaceAll('=', '');
    expect(decodeTripHistoryChunk('h:p:12345678:0:$encoded', '12345678', '0'),
        data);
    expect(
        () =>
            decodeTripHistoryChunk('h:p:87654321:0:$encoded', '12345678', '0'),
        throwsFormatException);
    expect(
        () =>
            decodeTripHistoryChunk('h:p:12345678:1:$encoded', '12345678', '0'),
        throwsFormatException);
  });
}
