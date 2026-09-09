import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/statistics_helper.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import '../support/persistence_fakes.dart';

// ignore: must_be_immutable
class _Preferences extends Fake implements SharedPreferencesAsync {
  final values = <String, Object>{};
  Completer<void>? readGate;
  bool fail = false;
  int writes = 0;
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final snapshot = (values[key] as List<String>?)?.toList();
    await readGate?.future;
    return snapshot;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    writes++;
    if (fail) throw StateError('disk');
    values[key] = value.toList();
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _Location extends GeolocatorPlatform {
  int checks = 0, reads = 0;
  LocationPermission permission = LocationPermission.whileInUse;
  @override
  Future<LocationPermission> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    reads++;
    throw StateError('GPS unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Preferences prefs;
  late _Location location;
  SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
  final helper = StatisticsHelper();
  setUp(() {
    prefs = _Preferences();
    location = _Location();
    GeolocatorPlatform.instance = location;
    helper.prefs = prefs;
    helper.locationPermission = null;
  });
  Future<void> drain() => Future<void>.delayed(Duration.zero);

  test('LogEntry preserves enum strings ISO timestamp LatLng JSON and unknown fallback', () {
    final entry = LogEntry(
        timestamp: DateTime.utc(2024, 2, 3),
        eventType: EventType.lock,
        source: EventSource.background,
        scooterId: 'A',
        soc1: 50,
        location: const LatLng(1, 2));
    final json = jsonDecode(entry.toJsonString()) as Map<String, dynamic>;
    expect(json, {
      'timestamp': '2024-02-03T00:00:00.000Z',
      'eventType': 'EventType.lock',
      'source': 'EventSource.background',
      'scooterId': 'A',
      'soc1': 50,
      'soc2': null,
      'location': const LatLng(1, 2).toJson()
    });
    expect(LogEntry.fromJsonString(entry.toJsonString()).toJsonString(), entry.toJsonString());
    json['eventType'] = 'future';
    json['source'] = 'future';
    final unknown = LogEntry.fromJsonString(jsonEncode(json));
    expect(unknown.eventType, EventType.unknown);
    expect(unknown.source, EventSource.unknown);
  });
  test('enabled key defaults true and disabled events do not acquire location', () async {
    expect(await helper.isEventLoggingEnabled(), isTrue);
    await helper.setEventLoggingEnabled(false);
    expect(prefs.values['eventLoggingEnabled'], false);
    await helper.logEvent(eventType: EventType.lock);
    await drain();
    expect(prefs.writes, 0);
    expect(location.checks, 0);
  });
  test('logEvent completes immediately while FIFO writes await storage', () async {
    helper.locationPermission = false;
    prefs.readGate = Completer<void>();
    await helper.logEvent(eventType: EventType.lock);
    await helper.logEvent(eventType: EventType.unlock);
    expect(prefs.writes, 0);
    prefs.readGate!.complete();
    await drain();
    expect((await helper.getEventLogs()).map((e) => e.eventType), [EventType.lock, EventType.unlock]);
    expect(prefs.values.containsKey('eventLogs'), isTrue);
  });
  test('permission is cached and caught location errors still append', () async {
    await helper.logEvent(eventType: EventType.lock);
    await drain();
    location.permission = LocationPermission.denied;
    await helper.logEvent(eventType: EventType.unlock);
    await drain();
    expect(location.checks, 1);
    expect(location.reads, 2);
    expect((await helper.getEventLogs()).every((e) => e.location == null), isTrue);
  });
  test('supplied location still checks permission but skips acquisition', () async {
    await helper.logEvent(eventType: EventType.lock, location: const LatLng(1, 2));
    await drain();
    expect(location.checks, 1);
    expect(location.reads, 0);
    expect((await helper.getEventLogs()).single.location, const LatLng(1, 2));
  });
  test('clear is not queued and an in-flight append resurrects its snapshot', () async {
    helper.locationPermission = false;
    await helper.logEvent(eventType: EventType.lock);
    await drain();
    prefs.readGate = Completer<void>();
    await helper.logEvent(eventType: EventType.unlock);
    await drain();
    await helper.clearEventLogs();
    expect(prefs.values['eventLogs'], isNull);
    prefs.readGate!.complete();
    await drain();
    expect((await helper.getEventLogs()).length, 2);
  });
  // Last: the singleton's inherited failed queue is intentionally terminal.
  test('failed write poisons later enqueues without failing logEvent completion', () async {
    final errors = <Object>[];
    helper.locationPermission = false;
    prefs.fail = true;
    runZonedGuarded(() {
      helper.logEvent(eventType: EventType.lock);
    }, (error, stack) => errors.add(error));
    await drain();
    expect(errors, hasLength(1));
    prefs.fail = false;
    await helper.logEvent(eventType: EventType.unlock);
    await drain();
    expect(prefs.writes, 1);
    expect(errors, hasLength(2));
  });
}
