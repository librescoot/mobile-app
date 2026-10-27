import 'dart:convert';

import 'package:scooter_core/battery_identity.dart';
import 'package:test/test.dart';

void main() {
  final time = DateTime.utc(2026, 10, 27);

  test('canonical serial preserves zeroes and does not apply board conversion',
      () {
    expect(
        canonicalBatterySerial(' 00000000000000ab\x00 '), '00000000000000AB');
    expect(canonicalBatterySerial('0012345'), '0012345');
    expect(canonicalBatterySerial('T-UNU22205090007'), 'T-UNU22205090007');
    for (final invalid in [
      '',
      'unknown',
      'null',
      'n/a',
      '0000',
      '---',
      'has space',
      '\u0080',
      '\u00a0ABC',
      'x' * 65
    ]) {
      expect(() => canonicalBatterySerial(invalid), throwsFormatException);
    }
  });

  test('snapshot binds presence and serial to the requested slot', () {
    final identity = parseBatteryIdentitySnapshot(
        'battery:snapshot:0:{"present":true,"serial_number":"T-UNU22205090007"}',
        0,
        time)!;
    expect(identity.serialNumber, 'T-UNU22205090007');
    expect(identity.slot, 0);
    expect(identity.source, BatteryIdentitySource.ble);
    expect(
        parseBatteryIdentitySnapshot(
            'battery:snapshot:1:{"present":false}', 1, time),
        isNull);
    for (final invalid in [
      'battery:snapshot:1:{"present":true,"serial_number":"OTHER"}',
      'battery:snapshot:0:{"present":true}',
      'battery:snapshot:0:{"present":"true","serial_number":"OTHER"}',
      'battery:snapshot:0:{"present":true,"serial_number":"unknown"}',
      'battery:error:unavailable',
    ]) {
      expect(() => parseBatteryIdentitySnapshot(invalid, 0, time),
          throwsFormatException);
    }
  });

  test('NFC serial comes from both complete status blocks, never tag UID', () {
    final serial = ascii.encode('T-UNU22205090007');
    final first = [0, 0, 0, 0, ...serial.take(12)];
    final second = [...serial.skip(12), ...List.filled(12, 0)];
    expect(decodeNfcBatterySerial(first, second), 'T-UNU22205090007');
    expect(() => decodeNfcBatterySerial(first.take(15).toList(), second),
        throwsFormatException);
    expect(() => decodeNfcBatterySerial(first, second.take(4).toList()),
        throwsFormatException);
    first[4] = 0xff;
    expect(() => decodeNfcBatterySerial(first, second), throwsFormatException);
  });

  test('BLE and NFC identify the same pack independently of slot', () {
    final serial = ascii.encode('T-UNU22205090007');
    final nfc = decodeNfcBatterySerial([0, 0, 0, 0, ...serial.take(12)],
        [...serial.skip(12), ...List.filled(12, 0)]);
    final ble = parseBatteryIdentitySnapshot(
        'battery:snapshot:1:{"present":true,"serial_number":"$nfc"}', 1, time)!;
    expect(ble.serialNumber, nfc);
  });

  test(
      'browser handoff contains only serial and source on the fixed HTTPS origin',
      () {
    final identity = BatteryIdentity(
        serialNumber: 'T-UNU22205090007',
        source: BatteryIdentitySource.nfc,
        checkedAt: time);
    final uri = batteryRegistrationUri(identity);
    expect(uri.scheme, 'https');
    expect(uri.host, 'rescoot.org');
    expect(uri.path, '/battery_registrations/new');
    expect(uri.queryParameters,
        {'serial_number': identity.serialNumber, 'source': 'nfc'});
    expect(BatteryIdentity.fromJson(identity.toJson()).serialNumber,
        identity.serialNumber);
  });
}
