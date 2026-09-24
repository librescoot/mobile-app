import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('vehicle action receivers fail closed while app-owned widget callbacks remain usable', () {
    final manifest = source('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest,
      contains(
        '<receiver\n            android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver"\n            android:exported="false">',
      ),
    );
    expect(
      manifest,
      contains(
        '<receiver\n            android:name=".tasker.TaskerActionReceiver"\n            android:exported="true">',
      ),
    );

    final receiver = source(
      'android/app/src/main/kotlin/org/librescoot/mobile/unu/tasker/TaskerActionReceiver.kt',
    );
    expect(receiver, contains('TaskerAuthorization.accepts(context, settings)'));
    expect(
      receiver.indexOf('TaskerAuthorization.accepts(context, settings)'),
      lessThan(receiver.indexOf('TaskerActionService.start(appContext')),
    );

    final editor = source(
      'android/app/src/main/kotlin/org/librescoot/mobile/unu/tasker/TaskerActionEditActivity.kt',
    );
    expect(editor, contains('TaskerAuthorization.isTrustedEditor(callingPackage)'));
    expect(editor, contains('TaskerAuthorization.authorize(this@TaskerActionEditActivity, this)'));
    expect(editor, isNot(contains('FlutterSharedPreferences')));
    expect(editor, contains('TaskerSettings.backgroundScanEnabled(this)'));
  });

  test('Tasker result codes match the upstream plugin protocol', () {
    final protocol = source(
      'android/app/src/main/kotlin/org/librescoot/mobile/unu/tasker/TaskerAction.kt',
    );
    expect(protocol, contains('RESULT_CODE_FAILED = Activity.RESULT_FIRST_USER + 1'));
    expect(protocol, contains('RESULT_CODE_PENDING = Activity.RESULT_FIRST_USER + 2'));
  });

  test('Tasker requests use independent atomic preference entries', () {
    final bridge = source('lib/background/tasker_bridge.dart');
    expect(bridge, contains('const String pendingTaskerActionPrefix = "pendingTaskerAction."'));
    expect(bridge, contains('prefs.setString(pendingTaskerActionKey(requestId), action)'));
    expect(bridge, isNot(contains('pendingWidgetActionRequestId')));
  });
}
