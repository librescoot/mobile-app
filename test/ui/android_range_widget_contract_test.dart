import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('range widget is a separate one-cell provider with picker preview', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('.HomeWidgetReceiver'));
    expect(manifest, contains('.RangeWidgetReceiver'));
    final info = File('android/app/src/main/res/xml/range_widget_info.xml').readAsStringSync();
    expect(info, contains('targetCellWidth="1"'));
    expect(info, contains('targetCellHeight="1"'));
    expect(info, contains('previewLayout="@layout/range_widget"'));
    expect(info, contains('previewImage="@drawable/range_widget_preview"'));
  });
  test('every Android refresh also notifies the read-only range provider', () {
    final source = File('lib/background/widget_handler.dart').readAsStringSync();
    expect(RegExp(r'await _refreshWidgets\(').allMatches(source).length, 5);
    expect(source, contains("if (Platform.isAndroid) {\n    await HomeWidget.updateWidget(qualifiedAndroidName:"));
    expect(source, contains('RangeWidgetReceiver'));
  });
  test('interactive widget describes reconnect-only actions accurately', () {
    final source = File(
      'android/app/src/main/kotlin/org/librescoot/mobile/unu/HomeWidgetGlanceAppWidget.kt',
    ).readAsStringSync();
    expect(RegExp(r'"Reconnect to scooter"').allMatches(source).length, 2);
    expect(RegExp(r'!enabled \|\| locked == null').allMatches(source).length, 2);
    expect(
      RegExp(
        r'if\s*\(locked == false && enabled\)\s*\{\s*actionRunCallback<LockAction>\(\)\s*\}\s*else if\s*\(locked == true && enabled\)\s*\{\s*actionRunCallback<UnlockAction>\(\)\s*\}\s*else\s*\{\s*actionRunCallback<ConnectAction>\(\)',
      ).allMatches(source).length,
      2,
    );
    expect(source, isNot(contains(r'" ${if (locked == false) "Unlock" else "Lock"} scooter"')));
  });

  test('reconnect readiness wait is scoped to reconnect and revalidates its request', () {
    final source = File('lib/background/bg_service.dart').readAsStringSync();
    expect(RegExp(r'await scooterService\.runtimeReady;').allMatches(source), hasLength(1));
    final connect = source.substring(
      source.indexOf('if (actionName == "connect")'),
      source.indexOf('final dispatch = await scooterService.prepareWidgetAction(actionName)'),
    );
    expect(connect.indexOf('await scooterService.runtimeReady;'), greaterThanOrEqualTo(0));
    expect(
      connect.indexOf('await prefs.reload();'),
      greaterThan(connect.indexOf('await scooterService.runtimeReady;')),
    );
    expect(
      connect.indexOf('if (!matchesRequest()) return;'),
      greaterThan(connect.indexOf('await prefs.reload();')),
    );
    expect(
      connect.indexOf('scooterService.mostRecentSavedScooterId'),
      greaterThan(connect.indexOf('if (!matchesRequest()) return;')),
    );
  });

  test('range widget only opens the app and exposes an accessible cached estimate', () {
    final file = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('/RangeWidgetReceiver.kt'));
    final source = file.readAsStringSync();
    expect(source, contains('PendingIntent.getActivity('));
    expect(source, contains('Intent(context, MainActivity::class.java)'));
    expect(source, isNot(contains('getBroadcast(')));
    expect(source, isNot(contains('startService(')));
    expect(source, contains('setContentDescription('));
    expect(source, contains('range_widget_cached'));
    expect(source, contains('range_widget_unavailable'));
  });
}
