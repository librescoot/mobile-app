import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:scooter_core/navigation.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

import '../support/command_transport_fakes.dart';

class _PlanRepository extends CharacteristicRepository {
  _PlanRepository(super.scooter);

  void use(TransportTestCharacteristic command,
      TransportTestCharacteristic response) {
    extendedCommandCharacteristic = command;
    extendedResponseCharacteristic = response;
  }
}

void main() {
  test('list plan reads the header and every stop from one reply', () async {
    final device = TransportTestDevice();
    final command = TransportTestCharacteristic();
    final response = TransportTestCharacteristic();
    command.onWrite = (write) async {
      expect(write.command, 'nav:route:list');
      response.reply('nav:route:count:2:1');
      response.reply('nav:route:0:52.51,13.41,Home');
      response.reply('nav:route:1:52.52,13.42,Work');
    };
    final repository = _PlanRepository(device)..use(command, response);

    final plan = await listRoutePlanCommand(device, repository);

    expect(plan.currentStep, 1);
    expect(plan.stops.map((stop) => stop.name), ['Home', 'Work']);
    expect(plan.stops.first.location.latitude, 52.51);
  });

  test('list plan reads an empty plan without waiting for entries', () async {
    final device = TransportTestDevice();
    final command = TransportTestCharacteristic();
    final response = TransportTestCharacteristic();
    command.onWrite = (_) async => response.reply('nav:route:count:0:0');
    final repository = _PlanRepository(device)..use(command, response);

    final plan = await listRoutePlanCommand(device, repository);

    expect(plan.isEmpty, isTrue);
  });

  test('list plan refuses a disconnected scooter', () async {
    final device = TransportTestDevice()..isDisconnected = true;
    final command = TransportTestCharacteristic();
    final response = TransportTestCharacteristic();
    final repository = _PlanRepository(device)..use(command, response);

    expect(listRoutePlanCommand(device, repository), throwsA(anything));
  });

  test('plan mutations send one stop per command', () async {
    final device = TransportTestDevice();
    final command = TransportTestCharacteristic();
    final response = TransportTestCharacteristic();
    command.onWrite = (_) async => response.reply('nav:route:count:1:0');
    final repository = _PlanRepository(device)..use(command, response);

    await addRouteStopCommand(
        device,
        repository,
        NavigationDestination(
            location: const LatLng(52.51, 13.41), name: 'Home'));
    await removeRouteStopCommand(device, repository, 1);
    await skipRouteStopCommand(device, repository);

    expect(
        command.writes.map((write) => write.command),
        [
          'nav:route:add 52.51,13.41,Home',
          'nav:route:remove 1',
          'nav:route:skip',
        ]);
  });
}