import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone key service starts disabled and is controlled from the keycard screen', () {
    final build = File('android/app/build.gradle').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final native = File('android/app/src/main/kotlin/org/librescoot/mobile/unu/MainActivity.kt').readAsStringSync();
    final screen = File('lib/ui/screens/ls_keycard_screen.dart').readAsStringSync();

    expect(build, contains('manifestPlaceholders.phoneKeyEnabled = "false"'));
    expect(build, isNot(contains('manifestPlaceholders.phoneKeyEnabled = "true"')));
    expect(manifest, contains('android:enabled="\${phoneKeyEnabled}"'));
    expect(native, contains('"serviceEnabled" ->'));
    expect(native, contains('"setServiceEnabled" ->'));
    expect(native, contains('packageManager.setComponentEnabledSetting('));
    expect(screen, contains("invokeMethod<bool>('serviceEnabled')"));
    expect(screen, contains("invokeMethod<void>('setServiceEnabled', {'enabled': enabled})"));
    expect(screen, contains('if (enabled) _stopBackgroundNfcScan();'));
    expect(screen, contains('_phoneKeyServiceEnabled == true) {'));
  });

  test('phone key branding uses Librescoot capitalization', () {
    final service = File('android/app/src/main/kotlin/org/librescoot/mobile/unu/PhoneKeyService.kt').readAsStringSync();
    final strings = File('android/app/src/main/res/values/strings.xml').readAsStringSync();
    expect(service, isNot(contains('LibreScoot')));
    expect(strings, contains('Librescoot scooter key'));
    expect(strings, isNot(contains('LibreScoot')));
  });
}
