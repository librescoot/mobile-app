import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('facade delegates action timing and keyless policy to shared runtime', () {
    final source = File('lib/scooter_service.dart').readAsStringSync();
    expect(source, contains('actions.wakeUpAndUnlock('));
    expect(source, contains('runtime.initialize()'));
    expect(File('packages/scooter_flutter/lib/src/runtime/scooter_runtime.dart').readAsStringSync(),
        contains('actions.startPolling()'));
    expect(source, contains('service.actions.aggregateTransition(previous, next)'));
    for (final legacy in [
      'StateWaiter<',
      'PausableTimer.periodic',
      'myScooter!.readRssi();\n        } catch',
      'Duration(seconds: handlebarCheckSeconds)',
      'Duration(seconds: keylessCooldownSeconds)',
      'settings.autoUnlockThreshold &&'
    ]) {
      expect(source, isNot(contains(legacy)), reason: legacy);
    }
  });
  test('forget success presentation requires removal of the captured ID and mounted UI', () {
    final source = File('lib/ui/screens/scooter_screen.dart').readAsStringSync();
    expect(
        source,
        matches(RegExp(
          r'final service = context\.read<ScooterService>\(\);\s*'
          r'final id = savedScooter\.id;\s*'
          r'await service\.forgetSavedScooter\(id\);\s*'
          r'//[^\n]*\n\s*'
          r'if \(!context\.mounted \|\| service\.savedScooters\.containsKey\(id\)\) return;\s*'
          r'rebuild\(\);\s*Fluttertoast\.showToast\(msg: message\);',
        )));
  });
  test('action settings and keycard UI no longer access characteristics', () {
    for (final screen in ['ls_keycard_screen', 'ls_scheduled_hibernation_screen', 'settings_screen']) {
      final source = File('lib/ui/screens/$screen.dart')
          .readAsStringSync();
      expect(source, isNot(contains('characteristicRepository')), reason: screen);
    }
    final home = File('lib/ui/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('service.actionWarnings.listen'));
    expect(home, contains('showHandlebarWarning(didNotUnlock: warning.didNotUnlock)'));
    expect(home, isNot(contains('on HandlebarLockException')));
  });
}
