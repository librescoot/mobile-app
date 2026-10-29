import 'dart:convert';

const batteryRegistrationConsentVersion = 'battery-registration-v1';

enum BatteryIdentitySource { ble, nfc }

String canonicalBatterySerial(String value) {
  final serial = value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .replaceAll(RegExp(r'^ +| +$'), '');
  if (serial.isEmpty ||
      serial.length > 64 ||
      !RegExp(r'^[\x21-\x7e]+$').hasMatch(serial) ||
      !RegExp(r'[1-9a-zA-Z]').hasMatch(serial) ||
      const {
        'unknown',
        'unbekannt',
        'n/a',
        'na',
        'none',
        'null',
        'nil',
        'undefined'
      }.contains(serial.toLowerCase())) {
    throw const FormatException('Invalid battery serial');
  }
  return RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(serial)
      ? serial.toUpperCase()
      : serial;
}

class BatteryIdentity {
  BatteryIdentity({
    required String serialNumber,
    required this.source,
    required this.checkedAt,
    this.slot,
  }) : serialNumber = canonicalBatterySerial(serialNumber);

  final String serialNumber;
  final BatteryIdentitySource source;
  // Time the phone checked the reported identity, not a pack telemetry timestamp.
  final DateTime checkedAt;
  final int? slot;

  Map<String, Object?> toJson() => {
        'serial_number': serialNumber,
        'source': source.name,
        'checked_at': checkedAt.toUtc().toIso8601String(),
        'slot': slot,
      };

  factory BatteryIdentity.fromJson(Map<String, dynamic> json) =>
      BatteryIdentity(
        serialNumber: json['serial_number'] as String,
        source: BatteryIdentitySource.values.byName(json['source'] as String),
        checkedAt: DateTime.parse(json['checked_at'] as String),
        slot: json['slot'] as int?,
      );
}

BatteryIdentity? parseBatteryIdentitySnapshot(
    String response, int slot, DateTime checkedAt) {
  if (slot != 0 && slot != 1) throw ArgumentError.value(slot, 'slot');
  final prefix = 'battery:snapshot:$slot:';
  if (!response.startsWith(prefix)) {
    throw const FormatException('Battery identity unavailable');
  }
  final data = jsonDecode(response.substring(prefix.length));
  if (data is! Map<String, dynamic> || data['present'] is! bool) {
    throw const FormatException('Invalid battery snapshot');
  }
  if (data['present'] == false) return null;
  if (data['serial_number'] is! String) {
    throw const FormatException('Missing battery serial');
  }
  return BatteryIdentity(
    serialNumber: data['serial_number'] as String,
    source: BatteryIdentitySource.ble,
    checkedAt: checkedAt,
    slot: slot,
  );
}

/// Type 2 READ at pages 0xc4 and 0xc8 returns status memory at byte
/// addresses 0x0310 and 0x0320, matching the scooter-side battery reader.
String decodeNfcBatterySerial(List<int> status1, List<int> status2) {
  if (status1.length != 16 || status2.length != 16) {
    throw const FormatException('Incomplete battery identity');
  }
  final bytes = [...status1.sublist(4, 16), ...status2.sublist(0, 4)];
  if (bytes.any((value) => value < 0x20 || value > 0x7e)) {
    throw const FormatException('Invalid battery identity bytes');
  }
  return canonicalBatterySerial(ascii.decode(bytes));
}

const sunshineAccountHost = 'sunshine.rescoot.org';

Uri sunshineSignupUri() => Uri.https(sunshineAccountHost, '/users/sign_up');
Uri sunshineBatteriesUri() =>
    Uri.https(sunshineAccountHost, '/battery_registrations');

Uri batteryRegistrationUri(BatteryIdentity identity) => Uri.https(
      sunshineAccountHost,
      '/battery_registrations/new',
      {'serial_number': identity.serialNumber, 'source': identity.source.name},
    );
