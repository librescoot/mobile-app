import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';
import 'firmware_queries.dart';

class TripHistoryException implements Exception {
  const TripHistoryException(this.code);
  final String code;
  @override
  String toString() => 'Trip history: $code';
}

class TripHistoryEntry {
  const TripHistoryEntry({
    required this.id,
    required this.startedAtSeconds,
    required this.endedAtSeconds,
    required this.distanceMeters,
    required this.readyDurationSeconds,
    required this.pointCount,
    this.averageSpeedKmh,
    this.maxRecordedGpsSpeedKmh,
  });
  final String id;
  final int startedAtSeconds,
      endedAtSeconds,
      distanceMeters,
      readyDurationSeconds,
      pointCount;
  final double? averageSpeedKmh, maxRecordedGpsSpeedKmh;

  factory TripHistoryEntry.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final started = value['started_at_s'];
    final ended = value['ended_at_s'];
    final distance = value['distance_m'];
    final duration = value['ready_duration_s'];
    final count = value['point_count'];
    final average = value['average_speed_kmh'];
    final maxGps = value['max_recorded_gps_speed_kmh'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        started is! int ||
        ended is! int ||
        distance is! int ||
        distance < 0 ||
        duration is! int ||
        duration < 0 ||
        count is! int ||
        count < 0 ||
        (average != null && average is! num) ||
        (maxGps != null && maxGps is! num)) {
      throw const FormatException('Invalid trip history entry');
    }
    return TripHistoryEntry(
      id: id,
      startedAtSeconds: started,
      endedAtSeconds: ended,
      distanceMeters: distance,
      readyDurationSeconds: duration,
      pointCount: count,
      averageSpeedKmh: (average as num?)?.toDouble(),
      maxRecordedGpsSpeedKmh: (maxGps as num?)?.toDouble(),
    );
  }
}

class TripHistoryPage {
  const TripHistoryPage(this.trips, this.nextCursor);
  final List<TripHistoryEntry> trips;
  final String? nextCursor;
  factory TripHistoryPage.fromJson(Map<String, dynamic> value) {
    final rows = value['trips'];
    final cursor = value['next_cursor'];
    if (rows is! List ||
        rows.length > 50 ||
        (cursor != null && (cursor is! String || cursor.length > 512))) {
      throw const FormatException('Invalid trip history page');
    }
    return TripHistoryPage(
      List.unmodifiable(
        rows.map((row) {
          if (row is! Map<String, dynamic>) {
            throw const FormatException('Invalid trip');
          }
          return TripHistoryEntry.fromJson(row);
        }),
      ),
      cursor as String?,
    );
  }
}

class TripHistoryPoint {
  const TripHistoryPoint(
    this.id,
    this.timestampMs,
    this.latitude,
    this.longitude,
  );
  final int id, timestampMs;
  final double latitude, longitude;
  factory TripHistoryPoint.fromJson(Map<String, dynamic> value) {
    final id = value['id'],
        timestamp = value['timestamp_ms'],
        lat = value['latitude'],
        lon = value['longitude'];
    if (id is! int ||
        id <= 0 ||
        timestamp is! int ||
        lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw const FormatException('Invalid GPS point');
    }
    return TripHistoryPoint(id, timestamp, lat.toDouble(), lon.toDouble());
  }
}

class TripHistoryPointsPage {
  const TripHistoryPointsPage(this.points, this.nextAfterId);
  final List<TripHistoryPoint> points;
  final int? nextAfterId;
  factory TripHistoryPointsPage.fromJson(Map<String, dynamic> value) {
    final points = value['points'], next = value['next_after_id'];
    if (points is! List ||
        points.length > 256 ||
        (next != null && (next is! int || next <= 0))) {
      throw const FormatException('Invalid GPS page');
    }
    return TripHistoryPointsPage(
      List.unmodifiable(
        points.map((point) {
          if (point is! Map<String, dynamic>) {
            throw const FormatException('Invalid GPS point');
          }
          return TripHistoryPoint.fromJson(point);
        }),
      ),
      next as int?,
    );
  }
}

Future<void> _historyQueue = Future.value();
Future<T> _serialized<T>(Future<T> Function() operation) {
  final result = _historyQueue.then((_) => operation());
  _historyQueue = result.then((_) {}, onError: (_) {});
  return result;
}

Future<Map<String, dynamic>> _historyRequest(
  BluetoothDevice? device,
  CharacteristicRepository repo,
  String kind,
  Map<String, dynamic> payload,
  bool Function()? isCurrent,
) async {
  final caps = await discoverLsCapabilityGroupsCommand(
    device,
    repo,
    isCurrent: isCurrent,
  );
  if (!caps.answered || caps.versions['trip-history'] != 1) {
    throw UnsupportedError('Trip history requires compatible scooter firmware');
  }
  Future<String> request(String command) async {
    checkCommandCurrent(isCurrent);
    final response = await sendLsExtendedCommand(
      device,
      repo,
      command,
      isCurrent: isCurrent,
    );
    if (response == null) {
      throw TimeoutException('Trip history response timed out');
    }
    if (response.startsWith('h:x:')) {
      throw TripHistoryException(response.substring(4));
    }
    return response;
  }

  final input =
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  final start = await request('trip:history:start:$kind:$input');
  final match =
      RegExp(r'^h:s:([0-9a-f]{8}):([0-9a-z]{1,4})$').firstMatch(start);
  if (match == null) {
    throw const FormatException('Invalid trip history response');
  }
  final token = match.group(1)!;
  final length = int.parse(match.group(2)!, radix: 36);
  if (length > 65536) {
    throw const FormatException('Trip history response too large');
  }
  final budget = min(244, max(20, (device?.mtuNow ?? 23) - 3));
  final bytes = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < length) {
    final offsetText = offset.toRadixString(36);
    final response = await request(
      'trip:history:get:$token:$offsetText:$budget',
    );
    final chunk = decodeTripHistoryChunk(response, token, offsetText);
    if (chunk.isEmpty || offset + chunk.length > length) {
      throw const FormatException('Invalid trip history chunk length');
    }
    bytes.add(chunk);
    offset += chunk.length;
  }
  checkCommandCurrent(isCurrent);
  final result = jsonDecode(utf8.decode(bytes.takeBytes()));
  if (result is! Map<String, dynamic>) {
    throw const FormatException('Invalid trip history JSON');
  }
  return result;
}

List<int> decodeTripHistoryChunk(String response, String token, String offset) {
  final prefix = 'h:p:$token:$offset:';
  if (!response.startsWith(prefix)) {
    throw const FormatException('Invalid trip history chunk');
  }
  return base64Url
      .decode(base64Url.normalize(response.substring(prefix.length)));
}

Future<TripHistoryPage> readTripHistoryPage(
  BluetoothDevice? device,
  CharacteristicRepository repo, {
  String? cursor,
  int limit = 10,
  bool Function()? isCurrent,
}) =>
    _serialized(() async {
      if (limit < 1 || limit > 50 || (cursor?.length ?? 0) > 512) {
        throw const FormatException('Invalid history request');
      }
      final result = await _historyRequest(
          device,
          repo,
          'l',
          {
            'limit': limit,
            if (cursor != null) 'cursor': cursor,
          },
          isCurrent);
      final page = TripHistoryPage.fromJson(result);
      if (page.nextCursor != null &&
          (page.nextCursor!.isEmpty || page.nextCursor == cursor)) {
        throw const FormatException('Invalid history cursor');
      }
      return page;
    });

Future<TripHistoryEntry> readTripHistoryEntry(
  BluetoothDevice? device,
  CharacteristicRepository repo,
  String id, {
  bool Function()? isCurrent,
}) =>
    _serialized(() async {
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
        throw const FormatException('Invalid trip ID');
      }
      return TripHistoryEntry.fromJson(
        await _historyRequest(device, repo, 'd', {'id': id}, isCurrent),
      );
    });

Future<TripHistoryPointsPage> readTripHistoryPoints(
  BluetoothDevice? device,
  CharacteristicRepository repo,
  String id, {
  int afterId = 0,
  int limit = 64,
  bool Function()? isCurrent,
}) =>
    _serialized(() async {
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
          afterId < 0 ||
          limit < 1 ||
          limit > 256) {
        throw const FormatException('Invalid points request');
      }
      final page = TripHistoryPointsPage.fromJson(
        await _historyRequest(
            device,
            repo,
            'p',
            {
              'id': id,
              'after_id': afterId,
              'limit': limit,
            },
            isCurrent),
      );
      var previous = afterId;
      for (final point in page.points) {
        if (point.id <= previous) {
          throw const FormatException('Unordered GPS page');
        }
        previous = point.id;
      }
      if (page.nextAfterId != null && page.nextAfterId != previous) {
        throw const FormatException('Invalid GPS cursor');
      }
      return page;
    });
