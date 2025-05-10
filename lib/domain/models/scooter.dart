import 'package:flutter/foundation.dart';

import '../scooter_state.dart';
import '../scooter_power_state.dart';
import 'battery_status.dart';
import 'location.dart';

/// A unified model representing a scooter with its complete state
@immutable
class Scooter {
  /// Unique identifier for the scooter
  final String id;

  /// User-defined name for the scooter
  final String name;

  /// Scooter color variant (1-9)
  final int color;

  /// Current operational state of the scooter
  final ScooterState state;

  /// Whether the seat is closed
  final bool seatClosed;

  /// Whether the handlebars are locked
  final bool handlebarsLocked;

  /// Primary battery status
  final BatteryStatus primaryBattery;

  /// Secondary battery status
  final BatteryStatus secondaryBattery;

  /// Central Battery Box status
  final BatteryStatus cbbBattery;

  /// Auxiliary battery status
  final BatteryStatus auxBattery;

  /// When the scooter was last connected to
  final DateTime? lastConnected;

  /// Last recorded location of the scooter
  final Location? lastLocation;

  /// Whether this is a favorite scooter
  final bool isFavorite;

  /// Signal strength when connected via BLE (-100 to 0, higher is better)
  final int? rssi;

  /// Whether the scooter is currently connected
  final bool isConnected;

  /// Whether to automatically connect to this scooter when in range
  final bool autoConnect;

  const Scooter({
    required this.id,
    required this.name,
    required this.color,
    required this.state,
    required this.seatClosed,
    required this.handlebarsLocked,
    required this.primaryBattery,
    required this.secondaryBattery,
    required this.cbbBattery,
    required this.auxBattery,
    this.lastConnected,
    this.lastLocation,
    this.isFavorite = false,
    this.rssi,
    this.isConnected = false,
    this.autoConnect = true,
  });

  /// Creates a copy with updated fields
  Scooter copyWith({
    String? name,
    int? color,
    ScooterState? state,
    bool? seatClosed,
    bool? handlebarsLocked,
    BatteryStatus? primaryBattery,
    BatteryStatus? secondaryBattery,
    BatteryStatus? cbbBattery,
    BatteryStatus? auxBattery,
    DateTime? lastConnected,
    Location? lastLocation,
    bool? isFavorite,
    int? rssi,
    bool? isConnected,
    bool? autoConnect,
  }) {
    return Scooter(
      id: this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      state: state ?? this.state,
      seatClosed: seatClosed ?? this.seatClosed,
      handlebarsLocked: handlebarsLocked ?? this.handlebarsLocked,
      primaryBattery: primaryBattery ?? this.primaryBattery,
      secondaryBattery: secondaryBattery ?? this.secondaryBattery,
      cbbBattery: cbbBattery ?? this.cbbBattery,
      auxBattery: auxBattery ?? this.auxBattery,
      lastConnected: lastConnected ?? this.lastConnected,
      lastLocation: lastLocation ?? this.lastLocation,
      isFavorite: isFavorite ?? this.isFavorite,
      rssi: rssi ?? this.rssi,
      isConnected: isConnected ?? this.isConnected,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }

  /// Creates a new empty scooter with default values
  factory Scooter.empty(String id) {
    return Scooter(
      id: id,
      name: "Scooter Pro",
      color: 1,
      state: ScooterState.disconnected,
      seatClosed: true,
      handlebarsLocked: true,
      primaryBattery: BatteryStatus.empty(type: BatteryType.primary),
      secondaryBattery: BatteryStatus.empty(type: BatteryType.secondary),
      cbbBattery: BatteryStatus.empty(type: BatteryType.cbb),
      auxBattery: BatteryStatus.empty(type: BatteryType.auxiliary),
      isConnected: false,
    );
  }

  /// Converts to JSON representation
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'state': state.index,
      'seatClosed': seatClosed,
      'handlebarsLocked': handlebarsLocked,
      'primaryBattery': primaryBattery.toJson(),
      'secondaryBattery': secondaryBattery.toJson(),
      'cbbBattery': cbbBattery.toJson(),
      'auxBattery': auxBattery.toJson(),
      'lastConnected': lastConnected?.toIso8601String(),
      'lastLocation': lastLocation?.toJson(),
      'isFavorite': isFavorite,
      'rssi': rssi,
      'isConnected': isConnected,
      'autoConnect': autoConnect,
    };
  }

  /// Creates a scooter from JSON
  factory Scooter.fromJson(Map<String, dynamic> json) {
    return Scooter(
      id: json['id'],
      name: json['name'],
      color: json['color'],
      state: ScooterState.values[json['state']],
      seatClosed: json['seatClosed'],
      handlebarsLocked: json['handlebarsLocked'],
      primaryBattery: BatteryStatus.fromJson(json['primaryBattery']),
      secondaryBattery: BatteryStatus.fromJson(json['secondaryBattery']),
      cbbBattery: BatteryStatus.fromJson(json['cbbBattery']),
      auxBattery: BatteryStatus.fromJson(json['auxBattery']),
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'])
          : null,
      lastLocation: json['lastLocation'] != null
          ? Location.fromJson(json['lastLocation'])
          : null,
      isFavorite: json['isFavorite'] ?? false,
      rssi: json['rssi'],
      isConnected: json['isConnected'] ?? false,
      autoConnect: json['autoConnect'] ?? true,
    );
  }

  /// Creates a scooter from a legacy SavedScooter
  factory Scooter.fromSavedScooter(Map<String, dynamic> savedScooter) {
    final id = savedScooter['id'];
    return Scooter(
      id: id,
      name: savedScooter['name'] ?? 'Scooter Pro',
      color: savedScooter['color'] ?? 1,
      state: ScooterState.disconnected,
      seatClosed: true,
      handlebarsLocked: true,
      primaryBattery: BatteryStatus(
        type: BatteryType.primary,
        soc: savedScooter['lastPrimarySOC'],
      ),
      secondaryBattery: BatteryStatus(
        type: BatteryType.secondary,
        soc: savedScooter['lastSecondarySOC'],
      ),
      cbbBattery: BatteryStatus(
        type: BatteryType.cbb,
        soc: savedScooter['lastCbbSOC'],
      ),
      auxBattery: BatteryStatus(
        type: BatteryType.auxiliary,
        soc: savedScooter['lastAuxSOC'],
      ),
      lastConnected: savedScooter['lastPing'] != null
          ? DateTime.fromMicrosecondsSinceEpoch(savedScooter['lastPing'])
          : DateTime.now(),
      lastLocation: savedScooter['lastLocation'] != null
          ? Location.fromJson(savedScooter['lastLocation'])
          : null,
      autoConnect: savedScooter['autoConnect'] ?? true,
    );
  }

  /// Gets the primary battery SOC or null if not available
  int? get primarySOC => primaryBattery.soc;

  /// Gets the secondary battery SOC or null if not available
  int? get secondarySOC => secondaryBattery.soc;

  /// Parses a state string from BLE to a ScooterState
  static ScooterState parseStateString(String? stateStr, ScooterPowerState? powerState) {
    // Use the existing fromString method from ScooterState
    ScooterState? baseState = ScooterState.fromString(stateStr);

    // Combine with power state if available
    if (powerState != null) {
      return ScooterState.fromStateAndPowerState(baseState, powerState) ??
             baseState ??
             ScooterState.unknown;
    }

    return baseState ?? ScooterState.unknown;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Scooter &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.state == state &&
      other.seatClosed == seatClosed &&
      other.handlebarsLocked == handlebarsLocked &&
      other.primaryBattery == primaryBattery &&
      other.secondaryBattery == secondaryBattery &&
      other.cbbBattery == cbbBattery &&
      other.auxBattery == auxBattery &&
      other.lastConnected == lastConnected &&
      other.lastLocation == lastLocation &&
      other.isFavorite == isFavorite &&
      other.rssi == rssi &&
      other.isConnected == isConnected &&
      other.autoConnect == autoConnect;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      color.hashCode ^
      state.hashCode ^
      seatClosed.hashCode ^
      handlebarsLocked.hashCode ^
      primaryBattery.hashCode ^
      secondaryBattery.hashCode ^
      cbbBattery.hashCode ^
      auxBattery.hashCode ^
      lastConnected.hashCode ^
      lastLocation.hashCode ^
      isFavorite.hashCode ^
      rssi.hashCode ^
      isConnected.hashCode ^
      autoConnect.hashCode;
  }

  @override
  String toString() {
    return 'Scooter(id: $id, name: $name, state: $state, connected: $isConnected)';
  }
}