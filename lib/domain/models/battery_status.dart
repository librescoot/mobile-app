import 'package:flutter/foundation.dart';

/// Represents the type of battery in the scooter
enum BatteryType {
  /// Primary battery (main power source)
  primary,
  
  /// Secondary battery (additional power source)
  secondary,
  
  /// Central Battery Box
  cbb,
  
  /// Auxiliary battery (powers auxiliary systems)
  auxiliary
}

/// Represents the complete status of a battery
@immutable
class BatteryStatus {
  /// State of charge in percentage (0-100)
  final int? soc;
  
  /// Number of charge cycles
  final int? cycles;
  
  /// Health percentage (0-100)
  final double? health;
  
  /// Whether the battery is currently charging
  final bool isCharging;
  
  /// Type of battery
  final BatteryType type;

  const BatteryStatus({
    this.soc,
    this.cycles,
    this.health,
    this.isCharging = false,
    required this.type,
  });

  /// Creates an empty battery status with default values
  factory BatteryStatus.empty({BatteryType type = BatteryType.primary}) {
    return BatteryStatus(type: type);
  }

  /// Creates a copy with updated fields
  BatteryStatus copyWith({
    int? soc,
    int? cycles,
    double? health,
    bool? isCharging,
  }) {
    return BatteryStatus(
      soc: soc ?? this.soc,
      cycles: cycles ?? this.cycles,
      health: health ?? this.health,
      isCharging: isCharging ?? this.isCharging,
      type: this.type,
    );
  }

  /// Converts to JSON
  Map<String, dynamic> toJson() {
    return {
      'soc': soc,
      'cycles': cycles,
      'health': health,
      'isCharging': isCharging,
      'type': type.index,
    };
  }

  /// Creates from JSON
  factory BatteryStatus.fromJson(Map<String, dynamic> json) {
    return BatteryStatus(
      soc: json['soc'],
      cycles: json['cycles'],
      health: json['health'],
      isCharging: json['isCharging'] ?? false,
      type: BatteryType.values[json['type']],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is BatteryStatus &&
      other.soc == soc &&
      other.cycles == cycles &&
      other.health == health &&
      other.isCharging == isCharging &&
      other.type == type;
  }

  @override
  int get hashCode {
    return soc.hashCode ^
      cycles.hashCode ^
      health.hashCode ^
      isCharging.hashCode ^
      type.hashCode;
  }

  @override
  String toString() {
    return 'BatteryStatus(soc: $soc, cycles: $cycles, health: $health, isCharging: $isCharging, type: $type)';
  }
}