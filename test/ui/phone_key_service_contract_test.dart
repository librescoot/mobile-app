import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone key service defaults on and is controlled from app settings', () {
    final build = File('android/app/build.gradle').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final native = File('android/app/src/main/kotlin/org/librescoot/mobile/unu/MainActivity.kt').readAsStringSync();
    final screen = File('lib/ui/screens/ls_keycard_screen.dart').readAsStringSync();
    final settings = File('lib/ui/screens/settings_screen.dart').readAsStringSync();

    expect(build, contains('manifestPlaceholders.phoneKeyEnabled = "true"'));
    expect(build, matches(RegExp(r'release\s*\{[^}]*buildConfigField "boolean", "PHONE_KEY_ENABLED", "true"')));
    expect(build, isNot(contains('manifestPlaceholders.phoneKeyEnabled = "false"')));
    expect(manifest, contains('android:enabled="\${phoneKeyEnabled}"'));
    expect(native, contains('"serviceEnabled" ->'));
    expect(native, contains('"setServiceEnabled" ->'));
    expect(native, contains('packageManager.setComponentEnabledSetting('));
    expect(native, contains('PackageManager.COMPONENT_ENABLED_STATE_DEFAULT'));
    expect(native, contains('packageManager.getServiceInfo(component, 0).enabled'));
    expect(settings, contains("invokeMethod<bool>('serviceEnabled')"));
    expect(settings, contains("invokeMethod<void>('setServiceEnabled', {'enabled': enabled})"));
    expect(screen, isNot(contains("invokeMethod<void>('setServiceEnabled'")));
    expect(screen, contains('_phoneKeyServiceEnabled != false) {'));
  });

  test('phone key branding uses Librescoot capitalization', () {
    // Assembled from two literals so this file never spells it out contiguously.
    const forbidden = 'Libre' 'Scoot';
    final service = File('android/app/src/main/kotlin/org/librescoot/mobile/unu/PhoneKeyService.kt').readAsStringSync();
    final strings = File('android/app/src/main/res/values/strings.xml').readAsStringSync();
    expect(service, isNot(contains(forbidden)));
    expect(strings, contains('Librescoot scooter key'));
    expect(strings, isNot(contains(forbidden)));
  });
}
