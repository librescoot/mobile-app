import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:unustasis/domain/log_helper.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captures framework and uncaught asynchronous errors while preserving handlers', () async {
    final directory = await Directory.systemTemp.createTemp('diagnostic-errors');
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    var flutterCalled = false;
    var platformCalled = false;
    FlutterError.onError = (_) => flutterCalled = true;
    PlatformDispatcher.instance.onError = (_, __) {
      platformCalled = true;
      return false;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (_) async => true,
    );
    final helper = LogHelper.test();
    await helper.initialize();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('framework failure'), stack: StackTrace.current));
    expect(PlatformDispatcher.instance.onError!(StateError('async failure'), StackTrace.current), isFalse);
    final snapshot = File('${directory.path}/diagnostic-journal.jsonl.crash').readAsStringSync();
    expect(snapshot, contains('async failure'));
    await helper.flushForTesting();
    final content = await (await helper.saveLogsToFile()).readAsString();
    expect(content, contains('framework failure'));
    expect(content, contains('async failure'));
    expect(flutterCalled, isTrue);
    expect(platformCalled, isTrue);
    helper.dispose();
    await helper.flushForTesting();
    FlutterError.onError = oldFlutter;
    PlatformDispatcher.instance.onError = oldPlatform;
    PathProviderPlatform.instance = paths;
    await directory.delete(recursive: true);
  });

  test('retains recent diagnostics across restarts and omits shared location content', () async {
    final directory = await Directory.systemTemp.createTemp('diagnostic-test');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    });
    final journal = File('${directory.path}/diagnostic-journal.jsonl');
    await journal.writeAsString('${jsonEncode({
          'time': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
          'message': 'expired'
        })}\ninvalid json');
    final first = LogHelper.test();
    await first.initialize();
    first.addLog(LogRecord(Level.FINE, 'before restart', 'test'));
    first.addLog(LogRecord(Level.FINE, 'sensitive location', 'SharingHandler'));
    await first.flushForTesting();
    first.dispose();
    await first.flushForTesting();

    final second = LogHelper.test();
    await second.initialize();
    final report = await second.saveLogsToFile();
    final content = await report.readAsString();
    expect(content, contains('before restart'));
    expect(content, contains('[location or shared content omitted]'));
    expect(content, isNot(contains('sensitive location')));
    expect(content, isNot(contains('expired')));
    second.dispose();
    await second.flushForTesting();
  });
}
