import 'dart:async';
import 'dart:convert';

import 'package:scooter_core/extended_response.dart';
import 'package:scooter_flutter/command_transport.dart';
import 'package:scooter_flutter/firmware_queries.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../domain/nav_destination.dart';
import '../domain/statistics_helper.dart';
import '../infrastructure/characteristic_repository.dart';

// Preserve the legacy command API while protocol consumers migrate to core.
export 'package:scooter_core/extended_response.dart';
export 'package:scooter_flutter/command_transport.dart' show sendCommand, sendLsExtendedCommand;
export 'package:scooter_flutter/firmware_queries.dart';

final log = Logger('BleCommands');

/// Librescoot settings keys for scheduled hibernation.
const String lsKeyScheduledHibernateEnabled = "pm.scheduled-hibernate-enabled";
const String lsKeyScheduledHibernateCron = "pm.scheduled-hibernate-cron";
const String lsKeyScheduledHibernateDuration = "pm.scheduled-hibernate-duration";

/// Librescoot settings keys used by the scooter settings screen.
const String lsKeyAutoStandbySeconds = "scooter.auto-standby-seconds";
const String lsKeyHibernateTimer = "pm.hibernation-timer";
const String lsKeyCellularApn = "cellular.apn";

/// Librescoot settings key that keeps the running battery active while the
/// seatbox is open, instead of letting it drop out. battery-service also wakes
/// a sleeping pack when this is on, which is what makes it useful for digging
/// a scooter out of a flat AUX battery.
const String lsKeyBatteryKeepActiveOnSeatboxOpen = "scooter.battery-keep-active-on-seatbox-open";

/// Librescoot settings key for the alarm as a whole. Off means the scooter
/// never arms, whatever the vehicle is doing.
const String lsKeyAlarmEnabled = "alarm.enabled";

/// Librescoot settings key that adds the horn to the alarm's siren.
const String lsKeyAlarmHonk = "alarm.honk";

// Maximum payload for the extended command characteristic. The basic command
// characteristic is limited to 20 bytes (default BLE MTU minus ATT overhead),
// but the extended characteristic uses allowLongWrite so it can carry more.
// Keep this well under typical negotiated MTUs (185–512 bytes) and the
// scooter's own command-buffer size.
const int _extendedCommandMaxBytes = 100;

/// Returns [name] truncated so that [prefix] + "," + name fits within
/// [_extendedCommandMaxBytes]. Returns null when there is no room at all.
String? _truncateNavName(String prefix, String? name) {
  if (name == null || name.isEmpty) return null;
  final available = _extendedCommandMaxBytes - prefix.length - 1; // -1 for ","
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
  await sendCommand(scooter, repo, "scooter:state unlock");
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
  await sendCommand(scooter, repo, "scooter:state lock");
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
  await sendCommand(scooter, repo, "scooter:seatbox open");
  StatisticsHelper().logEvent(
    eventType: EventType.openSeat,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> blinkCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required bool left,
  required bool right,
}) async {
  if (left && !right) {
    await sendCommand(scooter, repo, "scooter:blinker left");
  } else if (!left && right) {
    await sendCommand(scooter, repo, "scooter:blinker right");
  } else if (left && right) {
    await sendCommand(scooter, repo, "scooter:blinker both");
  } else {
    await sendCommand(scooter, repo, "scooter:blinker off");
  }
}

Future<void> wakeUpCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "wakeup",
    characteristic: repo.hibernationCommandCharacteristic,
  );
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
  await sendCommand(
    scooter,
    repo,
    "hibernate",
    characteristic: repo.hibernationCommandCharacteristic,
  );
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> rebootCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "reboot",
    characteristic: repo.hibernationCommandCharacteristic,
  );
}

Future<void> hardRebootCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "hard-reboot",
    characteristic: repo.hibernationCommandCharacteristic,
  );
}

Future<void> enterUMSModeCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "usb:ums",
  );
  if (response != "usb:ok") {
    log.severe("Failed to enter UMS mode, response: $response");
    throw "Failed to enter UMS mode, response: $response";
  }
  return;
}

Future<void> enterNormalUsbModeCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "usb:normal",
  );
  if (response != "usb:ok") {
    log.severe("Failed to enter normal USB mode, response: $response");
    throw "Failed to enter normal USB mode, response: $response";
  }
  return;
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

/// Counts the number of keycards registered on the scooter by sending a command and listening for the count response.
/// Returns the count as an integer, or null if the command fails or times out.
Future<int?> countKeycardsCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "keycard:count",
  );
  if (response != null && response.startsWith("keycard:count:")) {
    return int.tryParse(response.split(":").last);
  }
  return null;
}

/// Lists keycards registered on the scooter.
/// Expects: `keycard:count:<n>`, then one `keycard:card:<uid>` message per entry.
Future<List<String>> listKeycardsCommand(
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
    await sendCommand(scooter, repo, "keycard:list", characteristic: cmd);
    final stream = listener.responses.timeout(const Duration(seconds: 10));
    return await readExtendedList(stream, (msg) {
      // format: keycard:card:<uid>
      final parts = msg.split(":");
      if (parts.length >= 3 && parts[0] == "keycard" && parts[1] == "card") {
        final uid = parts.sublist(2).join(":");
        return uid.isNotEmpty ? uid : null;
      }
      log.warning("listKeycardsCommand: unexpected message format: '$msg'");
      return null;
    });
  } finally {
    await listener.cancel();
  }
});

Future<void> deleteKeycardCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String uid,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "keycard:remove:$uid",
  );
  if (response != "keycard:ok") {
    log.severe("Failed to delete keycard, response: $response");
    throw "Failed to delete keycard, response: $response";
  }
  return;
}

Future<void> addKeycardCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String uid,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "keycard:add:$uid",
  );
  if (response != "keycard:ok") {
    log.severe("Failed to add keycard, response: $response");
    throw "Failed to add keycard, response: $response";
  }
  return;
}

/// Sets the auto-standby timer on the scooter. [time] is the duration until the scooter automatically enters standby mode when idle.
/// 0 = disabled
Future<void> setAutoStandbyTimeCommand(BluetoothDevice? scooter, CharacteristicRepository repo, Duration time) async {
  final seconds = time.inSeconds;
  if (seconds < 0) {
    log.warning("Auto-standby time cannot be negative");
    throw "Auto-standby time cannot be negative";
  }
  if (seconds > 3600) {
    log.warning("Auto-standby time cannot be greater than 1 hour");
    throw "Auto-standby time cannot be greater than 1 hour";
  }
  await setLsSettingCommand(scooter, repo, lsKeyAutoStandbySeconds, seconds.toString());
}

Future<void> setAutoHibernateTimeCommand(BluetoothDevice? scooter, CharacteristicRepository repo, Duration time) async {
  final seconds = time.inSeconds;
  await setLsSettingCommand(scooter, repo, lsKeyHibernateTimer, seconds.toString());
}

/// Why a user-entered APN can't be sent to the scooter.
enum ApnProblem { empty, invalidCharacters, tooLong }

const String _apnCommandPrefix = "config:apn ";

/// Longest APN that still fits into a single extended command.
const int maxApnLength = _extendedCommandMaxBytes - _apnCommandPrefix.length;

// APNs are DNS-style labels, so anything outside printable ASCII (a space
// included) would be rejected by the modem anyway, and the command
// characteristic only carries ASCII.
final RegExp _apnAllowedChars = RegExp(r'^[\x21-\x7E]+$');

/// Checks an already-trimmed APN against what the command channel and the
/// modem accept. Returns null when [apn] is usable.
ApnProblem? checkApn(String apn) {
  if (apn.isEmpty) return ApnProblem.empty;
  if (!_apnAllowedChars.hasMatch(apn)) return ApnProblem.invalidCharacters;
  if (apn.length > maxApnLength) return ApnProblem.tooLong;
  return null;
}

/// Sets the APN the scooter's modem attaches with.
///
/// Surrounding whitespace is trimmed. An empty APN is rejected here rather than
/// sent on, so that emptying the text field cannot silently drop the scooter
/// onto operator defaults. Use [clearCellularApnCommand] to do that on purpose.
Future<void> setCellularApnCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String apn,
) async {
  final trimmed = apn.trim();
  final problem = checkApn(trimmed);
  if (problem != null) {
    log.warning("Refusing to send APN '$apn': ${problem.name}");
    throw "Invalid APN (${problem.name})";
  }
  await setLsSettingCommand(scooter, repo, lsKeyCellularApn, trimmed);
}

/// Clears the configured APN so the modem falls back to whatever the SIM
/// operator hands out.
///
/// Sends the prefix and nothing after it. The trailing space in
/// [_apnCommandPrefix] is load-bearing: the firmware splits the payload on the
/// first space and answers `config:error:missing value` when there is no second
/// field, so `config:apn ` sets an empty value where `config:apn` would fail.
/// Only the value gets trimmed on the way in, never the command.
Future<void> clearCellularApnCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, _apnCommandPrefix);
  if (response != "config:ok") {
    log.severe("Failed to clear APN, response: $response");
    throw "Failed to clear APN, response: $response";
  }
  return;
}

/// Hibernates the scooter and arms a wake timer (librescoot pm capability).
/// [wakeAfter] must be positive; firmware silently clamps to its configured
/// maximum (7 days by default).
Future<void> hibernateForCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  Duration wakeAfter,
) async {
  if (wakeAfter <= Duration.zero) {
    throw "Hibernate wake timer must be positive";
  }
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "pm:hibernate-for ${wakeAfter.inSeconds}s",
  );
  if (response != "pm:ok") {
    log.severe("Failed to hibernate with wake timer, response: $response");
    throw "Failed to hibernate, response: $response";
  }
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

/// Cancels a pending hibernate-for wake timer.
Future<void> hibernateCancelCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, "pm:hibernate-cancel");
  if (response != "pm:ok") {
    log.severe("Failed to cancel hibernation, response: $response");
    throw "Failed to cancel hibernation, response: $response";
  }
}

/// Asks the scooter to forget this phone, clearing the scooter's half of the
/// bond. Only the caller's own bond can be dropped this way: the scooter
/// resolves the peer from the live connection, so there is nothing to pass and
/// no way to reach anyone else's bond.
///
/// Send this while still connected and before dropping the phone's own bond.
/// The command only travels over the authenticated link, and the scooter
/// disconnects to carry the delete out, so there is no second chance.
///
/// The reply means the command was accepted, not that the bond is gone: nothing
/// on the vehicle exposes a peer list. The scooter dropping the link afterwards
/// is the observable part, so callers should wait for it.
///
/// Throws if the scooter refuses or never answers. Needs librescoot 1.3 with
/// nRF firmware v2.8.0-ls or later; probe `cap:ble` for "forget" first.
Future<void> forgetBondCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, "ble:forget");
  if (response != "ble:forget:ok") {
    log.warning("Scooter would not forget this phone, response: $response");
    throw "Failed to forget the scooter side of the bond, response: $response";
  }
}
