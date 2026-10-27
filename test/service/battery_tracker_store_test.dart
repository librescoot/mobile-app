import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:unustasis/service/battery_tracker_store.dart';

void main() {
  BatteryIdentity identity(String serial, {BatteryIdentitySource source = BatteryIdentitySource.ble, int? slot}) =>
      BatteryIdentity(serialNumber: serial, source: source, slot: slot, checkedAt: DateTime.utc(2026, 10, 27));

  test('disabled by default and checks do not persist without local opt-in', () async {
    var writes = 0;
    final store = BatteryTrackerStore(read: () async => null, write: (_) async => writes++);
    await store.load();
    await store.remember([identity('T-UNU22205090007')]);
    expect(store.enabled, isFalse);
    expect(store.batteries, isEmpty);
    expect(writes, 0);
  });

  test('serial identity merges NFC and slot moves but separates two packs', () async {
    String? saved;
    final store = BatteryTrackerStore(read: () async => saved, write: (value) async => saved = value);
    await store.setEnabled(true);
    await store.remember([identity('T-UNU22205090007', slot: 0), identity('T-UNU22009170066', slot: 1)]);
    await store.remember([identity('T-UNU22205090007', source: BatteryIdentitySource.nfc)]);
    expect(store.batteries.length, 2);
    final restored = BatteryTrackerStore(read: () async => saved, write: (_) async {});
    await restored.load();
    expect(restored.enabled, isTrue);
    expect(restored.batteries.length, 2);
    expect(restored.batteries.firstWhere((entry) => entry.serialNumber == 'T-UNU22205090007').source,
        BatteryIdentitySource.nfc);
    await store.forget('T-UNU22205090007');
    await restored.load();
    expect(restored.batteries.single.serialNumber, 'T-UNU22009170066');
  });

  test('serialized opt-out prevents later checks from persisting', () async {
    final gate = Completer<void>();
    var writes = 0;
    final store = BatteryTrackerStore(
        read: () async => null,
        write: (_) async {
          writes++;
          if (writes == 2) await gate.future;
        });
    await store.setEnabled(true);
    final first = store.remember([identity('T-UNU22205090007')]);
    final disable = store.setEnabled(false);
    final later = store.remember([identity('T-UNU22009170066')]);
    gate.complete();
    await Future.wait([first, disable, later]);
    expect(store.enabled, isFalse);
    expect(store.batteries.single.serialNumber, 'T-UNU22205090007');
    expect(writes, 3);
  });

  test('malformed data never enables tracking and failed writes preserve state', () async {
    final store = BatteryTrackerStore(
        read: () async => '{"enabled":true,"batteries":[{}]}', write: (_) async => throw StateError('disk'));
    await store.load();
    expect(store.enabled, isFalse);
    await expectLater(store.setEnabled(true), throwsStateError);
    expect(store.enabled, isFalse);
  });
}
