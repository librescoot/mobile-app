import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/statistics_helper.dart';
import 'package:unustasis/scooter_service.dart';

import '../../packages/scooter_flutter/test/scooter_actions_test.dart' as runtime;
import '../support/persistence_fakes.dart';

class _Connection extends Fake implements SessionConnection {
  _Connection(this.device);
  @override
  final BluetoothDevice device;
  @override
  String get id => 'A';
  @override
  int get generation => 1;
  @override
  bool isCurrent = true;
}

class _NoLogsPreferences extends SharedPreferencesAsync {
  @override
  Future<bool?> getBool(String key) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    StatisticsHelper().prefs = _NoLogsPreferences();
    StatisticsHelper().locationPermission = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final scenario in ['ordinary', 'confirmed', 'invalidated']) {
    test('ScooterService.lock forwards $scenario open-seat intent without fallback', () async {
      final trace = <String>[];
      final device = runtime.Device('A', trace)..live = true;
      final repository = runtime.Repository(device, trace);
      final connection = _Connection(device);
      // Exercise real facade and actions; only connection/transport and unrelated
      // storage/platform startup are replaced. Session capture UI has its own tests.
      final service = ScooterService(runtime.Bluetooth(), initializeRuntime: false, isInBackgroundService: true);
      addTearDown(service.dispose);
      service.actions.bind(connection, repository);
      service.vehicle.seatClosed = false;
      final firstWrite = Completer<void>();
      repository.wire.onWrite = (_) => firstWrite.future;
      var completed = false;
      final action = scenario == 'ordinary'
          ? service.lock(checkHandlebars: false)
          : service.lock(checkHandlebars: false, confirmOpenSeat: true);
      final result =
          scenario == 'invalidated' ? expectLater(action, throwsStateError) : action.then((_) => completed = true);
      await runtime.settleTransport();
      expect(trace, ['A:scooter:state lock']);
      expect(completed, false);
      if (scenario == 'invalidated') connection.isCurrent = false;
      firstWrite.complete();
      await result;
      expect(
          trace, scenario == 'confirmed' ? ['A:scooter:state lock', 'A:scooter:state lock'] : ['A:scooter:state lock']);
      expect(completed, scenario != 'invalidated');
      await StatisticsHelper().pendingWrites;
    });
  }
}
