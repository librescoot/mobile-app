import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:scooter_core/companion.dart';
import 'package:test/test.dart';

void main() {
  test('matches the cross-platform state contract', () {
    final contract = jsonDecode(
        File('../../test/fixtures/companion_contract.json').readAsStringSync());
    for (final item in contract['stateCases']) {
      final observation =
          CompanionObservation(item['state'], item['seatClosed']);
      expect(observation.allows(item['action']), item['allowed']);
      expect(observation.confirms(item['action']), item['confirmed']);
    }
  });
  var now = 100000;
  CompanionRequest request(
          {String action = 'unlock',
          String id = '00000000-0000-0000-0000-000000000001'}) =>
      CompanionRequest.fromJson({
        'version': 1,
        'id': id,
        'scooterId': 'scooter-a',
        'action': action,
        'issuedAt': 100000,
        'expiresAt': 115000
      });
  late CompanionObservation observed;
  late CompanionExecutor executor;
  late List<String> writes;
  var current = true;
  setUp(() {
    now = 100000;
    current = true;
    observed = const CompanionObservation('stand-by', true);
    writes = [];
    executor = CompanionExecutor(
      current: (id) => current && id == 'scooter-a',
      read: () async => observed,
      write: (action) async {
        writes.add(action);
        observed = const CompanionObservation('parked', true);
      },
      now: () => now,
      delay: (duration) async {
        now += duration.inMilliseconds;
      },
    );
  });
  test('confirms vehicle state rather than write acknowledgement', () async {
    expect(await executor.execute(request()), 'confirmed');
    expect(writes, ['unlock']);
  });
  test('deduplicates even after success', () async {
    await executor.execute(request());
    expect(await executor.execute(request()), 'duplicate');
    expect(writes, hasLength(1));
  });
  test('never sends expired requests', () async {
    now = 115000;
    expect(await executor.execute(request()), 'expired');
    expect(writes, isEmpty);
  });
  test('does not actuate another or disconnected scooter', () async {
    current = false;
    expect(await executor.execute(request()), 'unavailable');
    expect(writes, isEmpty);
  });
  test('does not lock a vehicle ready to drive', () async {
    observed = const CompanionObservation('ready-to-drive', true);
    expect(await executor.execute(request(action: 'lock')), 'unsafeState');
    expect(writes, isEmpty);
  });
  test('seat requires parked state', () async {
    expect(await executor.execute(request(action: 'openSeat')), 'unsafeState');
    expect(writes, isEmpty);
  });
  test('refresh never unlocks', () async {
    expect(await executor.execute(request(action: 'refresh')), 'confirmed');
    expect(writes, isEmpty);
  });
  test('an already reached target does not write again', () async {
    observed = const CompanionObservation('parked', true);
    expect(await executor.execute(request()), 'confirmed');
    expect(writes, isEmpty);
  });
  test('expiry during preparation prevents a write', () async {
    executor = CompanionExecutor(
        current: (_) => true,
        now: () => now,
        read: () async {
          now = 115000;
          return observed;
        },
        write: (action) async => writes.add(action));
    expect(await executor.execute(request()), 'expired');
    expect(writes, isEmpty);
  });
  test('uncertain write is not retried', () async {
    executor = CompanionExecutor(
        current: (_) => true,
        now: () => now,
        read: () async => observed,
        write: (action) async {
          writes.add(action);
          throw StateError('lost link');
        });
    expect(await executor.execute(request()), 'unknown');
    expect(await executor.execute(request()), 'duplicate');
    expect(writes, ['unlock']);
  });
  test('acknowledged write without state change is unknown', () async {
    executor = CompanionExecutor(
        current: (_) => true,
        now: () => now,
        read: () async => observed,
        write: (action) async => writes.add(action),
        delay: (duration) async {
          now += duration.inMilliseconds;
        });
    expect(await executor.execute(request()), 'unknown');
    expect(writes, ['unlock']);
  });
  test('simultaneous actions are not queued', () async {
    final gate = Completer<CompanionObservation>();
    executor = CompanionExecutor(
        current: (_) => true,
        now: () => now,
        read: () => gate.future,
        write: (action) async => writes.add(action));
    final first = executor.execute(request());
    expect(
        await executor
            .execute(request(id: '00000000-0000-0000-0000-000000000002')),
        'busy');
    gate.complete(const CompanionObservation('parked', true));
    expect(await first, 'confirmed');
    expect(writes, isEmpty);
  });
  test('schema excludes toggles, unknown versions and unlimited lifetime', () {
    for (final override in [
      {'action': 'toggle'},
      {'version': 2},
      {'expiresAt': 130000},
      {'id': 'x'},
    ]) {
      expect(
          () => CompanionRequest.fromJson({
                'version': 1,
                'id': '00000000-0000-0000-0000-000000000001',
                'scooterId': 'a',
                'action': 'unlock',
                'issuedAt': 100000,
                'expiresAt': 115000,
                ...override
              }),
          throwsFormatException);
    }
  });
}
