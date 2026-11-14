// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_keyless_distance.dart';
import '../scooter_service.dart';

class LogHelper {
  // Private constructor
  LogHelper._internal();

  @visibleForTesting
  LogHelper.test();

  // Singleton instance
  static final LogHelper _instance = LogHelper._internal();

  // Factory constructor to return the same instance
  factory LogHelper() {
    return _instance;
  }

  final int maxBufferSize = 2000;
  final List<Map<String, String>> _logBuffer = [];
  Timer? _cleanupTimer;
  Timer? _saveTimer;
  File? _journal;
  Future<void> _writes = Future.value();
  StreamSubscription<LogRecord>? _subscription;
  FlutterExceptionHandler? _previousFlutterHandler;
  FlutterExceptionHandler? _flutterHandler;
  ErrorCallback? _previousPlatformHandler;
  ErrorCallback? _platformHandler;
  static const _diagnostics = MethodChannel('app.diagnostics/process_exits');

  Future<void> initialize() async {
    try {
      final directory = await getTemporaryDirectory();
      _journal = File('${directory.path}/diagnostic-journal.jsonl');
      if (await _journal!.exists()) {
        final lines = await _journal!.readAsLines();
        for (final line in lines) {
          try {
            final item = jsonDecode(line);
            if (item is Map<String, dynamic>) {
              _logBuffer.add(item.map((key, value) => MapEntry(key, value.toString())));
            }
          } on FormatException {
            continue;
          }
        }
        _trimBuffer();
      }
    } catch (_) {
      // Reporting must not prevent the app from starting.
    }
    _subscription = Logger.root.onRecord.listen(addLog);
    _previousFlutterHandler = FlutterError.onError;
    _flutterHandler = (details) {
      _saveCrash('Flutter', details.exception, details.stack);
      Logger('Flutter').severe(details.exceptionAsString(), details.exception, details.stack);
      _previousFlutterHandler?.call(details);
    };
    FlutterError.onError = _flutterHandler;
    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    _platformHandler = (error, stack) {
      _saveCrash('Platform', error, stack);
      Logger('Platform').severe('Unhandled asynchronous error', error, stack);
      return _previousPlatformHandler?.call(error, stack) ?? false;
    };
    PlatformDispatcher.instance.onError = _platformHandler;
    _startLogCleanup();
    await _clearStaleCrash();
  }

  void addLog(LogRecord record) {
    if (kDebugMode && record.level >= Level.INFO) {
      Fluttertoast.showToast(
        msg: record.message,
        fontSize: 12.0,
        backgroundColor:
            Colors.black.withValues(alpha: 0.7), // fluttertoast android logspams if no background color is set
        textColor: Colors.white,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
    }
    // ignore: avoid_print
    print(record);
    String bounded(String value) => value.length <= 16384 ? value : '${value.substring(0, 16384)} [truncated]';
    final sensitive = {'GeoHelper', 'LocationUrlParser', 'SharingHandler'}.contains(record.loggerName);
    _logBuffer.add({
      'time': record.time.toIso8601String(),
      'level': record.level.name,
      'logger': record.loggerName,
      'message': sensitive ? '[location or shared content omitted]' : bounded(record.message),
      'error': sensitive ? '' : bounded(record.error?.toString() ?? ''),
      'stackTrace': bounded(record.stackTrace?.toString() ?? '')
    });
    _trimBuffer();
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      _persist();
    });
    if (record.level >= Level.SEVERE) _persist();
  }

  void _saveCrash(String source, Object error, StackTrace? stack) {
    final journal = _journal;
    if (journal == null) return;
    String bounded(String value) => value.length <= 16384 ? value : value.substring(0, 16384);
    try {
      File('${journal.path}.crash').writeAsStringSync(
          jsonEncode({
            'time': DateTime.now().toIso8601String(),
            'type': 'uncaught_error',
            'source': source,
            'error': bounded(error.toString()),
            'stackTrace': bounded(stack?.toString() ?? ''),
          }),
          flush: true);
    } catch (_) {
      // Keep the original error handling path even if storage is unavailable.
    }
  }

  void _trimBuffer() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _logBuffer.removeWhere((log) {
      final time = DateTime.tryParse(log['time'] ?? '');
      return time == null || time.isBefore(cutoff);
    });
    if (_logBuffer.length > maxBufferSize) {
      _logBuffer.removeRange(0, _logBuffer.length - maxBufferSize);
    }
  }

  void _persist() {
    final file = _journal;
    if (file == null) return;
    final snapshot = _logBuffer.map(jsonEncode).join('\n');
    _writes = _writes.then((_) async {
      try {
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(snapshot, flush: true);
        await temporary.rename(file.path);
      } on FileSystemException {
        // A full or inaccessible filesystem must not crash logging.
      }
    });
  }

  @visibleForTesting
  Future<void> flushForTesting() async {
    _persist();
    await _writes;
  }

  Future<void> _clearStaleCrash() async {
    final journal = _journal;
    if (journal == null) return;
    try {
      final crash = File('${journal.path}.crash');
      if (await crash.exists() &&
          (await crash.lastModified()).isBefore(DateTime.now().subtract(const Duration(hours: 24)))) {
        await crash.delete();
      }
    } on FileSystemException {
      // Cleanup is best effort.
    }
  }

  void _startLogCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _trimBuffer();
      _persist();
      _clearStaleCrash();
    });
  }

  Future<File> saveLogsToFile() async {
    _trimBuffer();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/logs.txt');
    final lines = _logBuffer.map(jsonEncode).toList();
    final journal = _journal;
    if (journal != null) {
      try {
        final crash = jsonDecode(await File('${journal.path}.crash').readAsString());
        final time = DateTime.tryParse(crash['time'] as String? ?? '');
        if (time != null && time.isAfter(DateTime.now().subtract(const Duration(hours: 24)))) {
          lines.add(jsonEncode(crash));
        }
      } catch (_) {
        // The crash snapshot may be absent or incomplete.
      }
    }
    if (Platform.isAndroid) {
      try {
        final exits = await _diagnostics.invokeMethod<List<dynamic>>('recentExits');
        for (final exit in exits ?? []) {
          lines.add(jsonEncode({'type': 'android_process_exit', 'details': exit}));
        }
      } on PlatformException catch (error) {
        lines.add(jsonEncode({'type': 'android_process_exit_error', 'error': error.toString()}));
      } on MissingPluginException {
        lines.add(jsonEncode({'type': 'android_process_exit_error', 'error': 'unavailable'}));
      }
    }
    return file.writeAsString(lines.join('\n'));
  }

  static void startBugReport(BuildContext context) async {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(FlutterI18n.translate(context, "settings_report")),
              content: Text(FlutterI18n.translate(context, "settings_report_description")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(FlutterI18n.translate(context, "settings_report_cancel"))),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(FlutterI18n.translate(context, "settings_report_proceed"))),
              ],
            )).then((confirmed) async {
      if (confirmed == true) {
        // write log file
        File logFile = await LogHelper().saveLogsToFile();

        // get some more device info to add to the body
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        String device, os;
        if (Platform.isIOS) {
          IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
          device = iosInfo.utsname.machine;
          os = iosInfo.systemVersion;
        } else if (Platform.isAndroid) {
          AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
          device = "${androidInfo.brand} ${androidInfo.model}";
          os = androidInfo.version.release;
        } else {
          device = "unknown";
          os = "unsupported";
        }

        final package = await PackageInfo.fromPlatform();
        SharedPreferencesAsync prefs = SharedPreferencesAsync();
        if (context.mounted) {
          ScooterService service = context.read<ScooterService>();
          final Email email = Email(
            body: '''${FlutterI18n.translate(context, "report_placeholder")}

-------------------------------
App: ${package.packageName} ${package.version} (${package.buildNumber})
Device: $device
OS: $os
Settings: 
      backgroundScan = ${await prefs.getBool("backgroundScan") ?? false}
      biometrics = ${await prefs.getBool("biometrics") ?? false}
      autoUnlock = ${service.autoUnlock}
      autoUnlockDistance = ${ScooterKeylessDistance.fromThreshold(service.autoUnlockThreshold)}
      openSeatOnUnlock = ${service.openSeatOnUnlock}
      hazardLocking = ${service.hazardLocking}
      osmConsent = ${await prefs.getBool("osmConsent") ?? false}
      seasonal = ${await prefs.getBool("seasonal") ?? true}
Saved scooter count: ${service.savedScooters.length}
''',
            subject: FlutterI18n.translate(context, "report_subject"),
            recipients: ['app-support@librescoot.org'],
            attachmentPaths: [logFile.path],
            isHTML: false,
          );

          await FlutterEmailSender.send(email);
        }
      }
    });
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _saveTimer?.cancel();
    _subscription?.cancel();
    if (FlutterError.onError == _flutterHandler) FlutterError.onError = _previousFlutterHandler;
    if (PlatformDispatcher.instance.onError == _platformHandler) {
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
    _persist();
  }
}
