import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release-mode file tunnel availability is separate from the debug browser gate', () {
    final source = File('packages/scooter_flutter/lib/file_transfer_controller.dart').readAsStringSync();
    final available =
        source.substring(source.indexOf('bool get available =>'), source.indexOf('Object? get connectionScope'));
    final dataBrowser =
        source.substring(source.indexOf('bool get dataBrowserAvailable =>'), source.indexOf('bool get busy =>'));
    expect(available, contains('_connection?.isCurrent == true'));
    expect(available, contains('supportsFirmware()'));
    expect(available, isNot(contains('kDebugMode')));
    expect(dataBrowser, contains('kDebugMode || kProfileMode'));
  });
}
