import 'dart:async';
import 'dart:convert';

import 'package:scooter_core/extended_response.dart';
import 'package:scooter_flutter/command_transport.dart';
import 'package:scooter_flutter/action_commands.dart' as action_commands;
import 'package:scooter_core/actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../domain/nav_destination.dart';
import '../domain/statistics_helper.dart';
import '../infrastructure/characteristic_repository.dart';

// Preserve the legacy command API while protocol consumers migrate to core.
export 'package:scooter_core/extended_response.dart';
export 'package:scooter_core/telemetry.dart'
    show lsKeyScheduledHibernateEnabled, lsKeyBatteryKeepActiveOnSeatboxOpen;
export 'package:scooter_flutter/command_transport.dart' show sendCommand, sendLsExtendedCommand;
export 'package:scooter_flutter/firmware_queries.dart';
export 'package:scooter_core/actions.dart';
export 'package:scooter_flutter/action_commands.dart' hide unlockScooter, lockScooter, openSeatCommand, wakeUpCommand, hibernateCommand, hibernateForCommand;

final log = Logger('BleCommands');

/// Returns [name] truncated so that [prefix] + "," + name fits within
/// [extendedCommandMaxBytes]. Returns null when there is no room at all.
String? _truncateNavName(String prefix, String? name) {
  if (name == null || name.isEmpty) return null;
  final available = extendedCommandMaxBytes - prefix.length - 1; // -1 for ","
  if (available <= 0) return null;
  return name.length > available ? name.substring(0, available) : name;
}

/// Sends a power command to a scooter by ID, connecting first if needed.
Future<void> sendStaticPowerCommand(String id, String command) async {
  BluetoothDevice scooter = BluetoothDevice.fromId(id);
  if (scooter.isDisconnected) {
    await scooter.connect();
  }
  await scooter.discoverServices();
  BluetoothCharacteristic? commandCharacteristic = CharacteristicRepository.findCharacteristic(
    scooter,
    "9a590000-6e67-5d0d-aab9-ad9126b66f91",
    "9a590001-6e67-5d0d-aab9-ad9126b66f91",
  );
  await commandCharacteristic!.write(ascii.encode(command));
}

Future<void> unlockScooter(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
}) async {
  await action_commands.unlockScooter(scooter, repo);
  HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(
    eventType: EventType.unlock,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> lockScooter(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
  dynamic lastLocation,
}) async {
  await action_commands.lockScooter(scooter, repo);
  HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(
    eventType: EventType.lock,
    scooterId: scooter!.remoteId.toString(),
    location: lastLocation,
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> openSeatCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
}) async {
  await action_commands.openSeatCommand(scooter, repo);
  StatisticsHelper().logEvent(
    eventType: EventType.openSeat,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> wakeUpCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await action_commands.wakeUpCommand(scooter, repo);
  StatisticsHelper().logEvent(
    eventType: EventType.wakeUp,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> hibernateCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await action_commands.hibernateCommand(scooter, repo);
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> hibernateForCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  Duration wakeAfter,
) async {
  await action_commands.hibernateForCommand(scooter, repo, wakeAfter);
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> navigateCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  NavDestination destination,
) async {
  final base = "nav:dest ${destination.location.latitude},${destination.location.longitude}";
  final name = _truncateNavName(base, destination.name);
  final command = name != null ? "$base,$name" : base;
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    command,
  );
  if (response != "nav:ok") {
    log.severe("Failed to navigate, response: $response");
    throw "Failed to navigate, response: $response";
  }
  return;
}

Future<void> cancelNavigationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:clear",
  );
  if (response != "nav:ok") {
    log.severe("Failed to cancel navigation, response: $response");
    throw "Failed to cancel navigation, response: $response";
  }
  return;
}

/// Saves a navigation destination on the scooter. Returns the ID of the saved destination if successful.
Future<String> saveNavDestinationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  NavDestination destination,
) async {
  if (destination.name == null || destination.name!.isEmpty) {
    log.warning("Destination name cannot be empty when storing as favorite");
    throw "Destination name cannot be empty when storing as favorite";
  }
  final base = "nav:fav:add ${destination.location.latitude},${destination.location.longitude}";
  final name = _truncateNavName(base, destination.name) ?? destination.name!;
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "$base,$name",
  );

  String? id = response?.split(":").last;
  if (id == null) {
    log.severe("Failed to save navigation destination, response: $response");
    throw "Failed to save navigation destination";
  }
  return id;
}

Future<List<NavDestination>> listFavDestinationsCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) =>
    withExtendedChannel(() async {
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await ensureExtendedNotify(resp);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, "nav:fav:list", characteristic: cmd);
    final stream = listener.responses.timeout(const Duration(seconds: 10));
    return await readExtendedList(stream, (msg) {
      // format: nav:fav:<id>:lat,lon[,name]
      final parts = msg.split(":");
      if (parts.length < 4) return null;
      final coords = parts[3].split(",");
      if (coords.length < 2) return null;
      final lat = double.tryParse(coords[0]);
      final lon = double.tryParse(coords[1]);
      if (lat == null || lon == null) return null;
      final name = coords.length >= 3 ? coords.sublist(2).join(",") : null;
      return NavDestination(
        location: LatLng(lat, lon),
        name: name?.isNotEmpty == true ? name : null,
        id: parts[2],
      );
    });
  } finally {
    await listener.cancel();
  }
});

Future<void> navigateFavCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String id,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:navigate $id",
  );
  if (response != "nav:ok") {
    log.severe("Failed to navigate to favorite destination, response: $response");
    throw "Failed to navigate to favorite destination, response: $response";
  }
  return;
}

Future<void> deleteFavDestinationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String id,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:delete $id",
  );
  if (response != "nav:ok") {
    log.severe("Failed to delete favorite destination, response: $response");
    throw "Failed to delete favorite destination, response: $response";
  }
  return;
}
