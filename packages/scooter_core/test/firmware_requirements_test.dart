import 'package:scooter_core/firmware_requirements.dart';
import 'package:test/test.dart';

void main() {
  for (final version in [
    'v1.2.0',
    '1.2.0',
    '1.2.0+20260803123456',
    'v1.2.1',
    '1.10.0',
    '2.0.0',
    '1.2.1-rc.1',
    '1.3.0-beta.1',
    ' v1.2.0 ',
    'nightly-20260803',
    'testing-20260803',
    'nightly-20260803T000000',
    'testing-20260803T235959',
    'testing-20261002T012345',
    'nightly-20280229T120000',
  ]) {
    test('$version supports Bluetooth firmware updates', () {
      expect(supportsBluetoothFirmwareUpdates(version), isTrue);
    });
  }

  for (final version in <String?>[
    null,
    '',
    ' ',
    'unknown',
    'demo',
    'v1.1.9',
    '0.20.0',
    'v1.2.0-beta.1',
    '1.2.0-rc.1+build',
    'nightly-20260802T235959',
    'testing-20260802',
    'nightly-20260802+20261005',
    'custom-nightly-20260803T120000-main',
    '1.2',
    'v1.2.x',
    'v01.2.0',
    '1.2.00',
    '1.3.0-beta.01',
    'v1.2.0+',
    'v1.2.0 garbage',
    'nightly-20260230T120000',
    'testing-20261301',
    'testing-20260800',
    'nightly-20260803t000000',
    'nightly-20260803T240000',
    'nightly-20260803T126000',
    'nightly-20260803T120060',
    'testing-20260803T12',
    'nightly-20260803junk',
    'testing-03.08.26',
  ]) {
    test('$version cannot establish Bluetooth update support', () {
      expect(supportsBluetoothFirmwareUpdates(version), isFalse);
    });
  }
}
