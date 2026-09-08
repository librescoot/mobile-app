import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart' as core;
import 'package:unustasis/domain/alarm_status.dart';
import 'package:unustasis/domain/scooter_power_state.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/domain/scooter_vehicle_state.dart';

void main() {
  test('legacy exports are identical core types and retain pure getters', () {
    expect(identical(ScooterState.values, core.ScooterState.values), isTrue);
    expect(identical(ScooterPowerState.values, core.ScooterPowerState.values), isTrue);
    expect(identical(ScooterVehicleState.values, core.ScooterVehicleState.values), isTrue);
    expect(identical(AlarmStatus.values, core.AlarmStatus.values), isTrue);
    for (final state in ScooterState.values) {
      expect(state.isOn, core.ScooterStatePermissions(state).isOn);
      expect(state.isReadyForLockChange, core.ScooterStatePermissions(state).isReadyForLockChange);
      expect(state.isReadyForSeatOpen, core.ScooterStatePermissions(state).isReadyForSeatOpen);
      expect(state.permitsHardReboot, core.ScooterStatePermissions(state).permitsHardReboot);
    }
  });

  testWidgets('legacy UI extensions retain implicit name(context) and explicit overrides', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(translationLoader: FileTranslationLoader(basePath: 'assets/i18n', fallbackFile: 'en')),
      ],
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    await tester.pumpAndSettle();
    for (final state in ScooterState.values) {
      expect(state.name(context), StateExtension(state).name(context));
      expect(state.description(context), StateExtension(state).description(context));
      expect(state.color(context), StateExtension(state).color(context));
    }
    for (final state in ScooterPowerState.values) {
      expect(state.name(context), PowerStateExtension(state).name(context));
    }
    for (final state in ScooterVehicleState.values) {
      expect(state.name(context), VehicleStateExtension(state).name(context));
    }
    for (final state in AlarmStatus.values) {
      expect(state.name(context), AlarmStatusExtension(state).name(context));
    }
    expect(ScooterState.ready.name(context), FlutterI18n.translate(context, 'state_name_ready'));
    expect(ScooterState.ready.description(context), FlutterI18n.translate(context, 'state_desc_ready'));
    expect(ScooterState.ready.color(context), Theme.of(context).colorScheme.primary);
    expect(ScooterState.off.color(context), Colors.grey.shade200);
    expect(ScooterState.disconnected.color(context), Theme.of(context).colorScheme.surfaceContainer);
  });
}
