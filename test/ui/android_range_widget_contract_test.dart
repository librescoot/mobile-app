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
  test('range widget only opens the app and exposes an accessible cached estimate', () {
    final file = Directory('android/app/src/main/kotlin').listSync(recursive: true)
        .whereType<File>().singleWhere((file) => file.path.endsWith('/RangeWidgetReceiver.kt'));
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
