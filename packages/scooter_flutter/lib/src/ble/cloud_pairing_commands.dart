import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';
import 'firmware_queries.dart';

class CloudPairingStatus {
  const CloudPairingStatus(
      {required this.state, required this.running, this.code, this.expiresAt});

  final String state;
  final bool running;
  final String? code;
  final DateTime? expiresAt;

  factory CloudPairingStatus.parse(String response) {
    const prefix = 'cloud-pairing:status:';
    if (!response.startsWith(prefix)) {
      throw const FormatException('Invalid Connect pairing response');
    }
    final value = jsonDecode(response.substring(prefix.length));
    if (value is! Map<String, dynamic> ||
        value['state'] is! String ||
        value['running'] is! bool ||
        !const {
          'not_registered',
          'registered',
          'starting',
          'waiting_for_web_setup',
          'applying',
          'connected',
          'error',
          'stopping',
          'paused'
        }.contains(value['state'])) {
      throw const FormatException('Invalid Connect pairing status');
    }
    final code = value['code'];
    final expiry = value['expires_at'];
    if (code != null &&
        (value['state'] != 'waiting_for_web_setup' ||
            code is! String ||
            code.length != 11 ||
            !RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{5}-[0-9ABCDEFGHJKMNPQRSTVWXYZ]{5}$')
                .hasMatch(code) ||
            expiry is! int)) {
      throw const FormatException('Invalid Connect pairing code');
    }
    return CloudPairingStatus(
      state: value['state'] as String,
      running: value['running'] as bool,
      code: code as String?,
      expiresAt: code == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((expiry as int) * 1000),
    );
  }
}

Future<bool> supportsCloudPairingCommand(
    BluetoothDevice? device, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final groups = await discoverLsCapabilityGroupsCommand(device, repo,
      isCurrent: isCurrent);
  if (!groups.answered) throw StateError('Could not read scooter capabilities');
  return groups.versions['cloud-pairing'] == 1;
}

Future<CloudPairingStatus> cloudPairingCommand(
    BluetoothDevice? device, CharacteristicRepository repo, String action,
    {bool Function()? isCurrent}) async {
  if (!const {'start', 'status', 'stop'}.contains(action)) {
    throw ArgumentError.value(action, 'action');
  }
  final response = await sendLsExtendedCommand(
      device, repo, 'cloud-pairing:$action',
      isCurrent: isCurrent, responseTimeout: const Duration(seconds: 12));
  if (response == null) {
    throw TimeoutException('Connect pairing response timed out');
  }
  if (response.startsWith('cloud-pairing:error:')) {
    throw StateError('Connect pairing unavailable');
  }
  return CloudPairingStatus.parse(response);
}
