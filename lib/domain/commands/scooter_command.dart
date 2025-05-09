import 'package:flutter/foundation.dart';

/// Types of commands that can be executed on a scooter
enum CommandType {
  /// Lock the scooter
  lock,
  
  /// Unlock the scooter
  unlock,
  
  /// Open the seat compartment
  openSeat,
  
  /// Control the blinkers
  blink,
  
  /// Wake up the scooter from hibernation
  wakeUp,
  
  /// Put the scooter into hibernation mode
  hibernate,
}

/// Abstract base class for all commands that can be executed on a scooter
@immutable
abstract class ScooterCommand {
  /// ID of the scooter this command targets
  final String scooterId;
  
  /// Type of command
  final CommandType type;
  
  /// When the command was created
  final DateTime timestamp;
  
  /// Additional parameters for the command
  final Map<String, dynamic> parameters;
  
  const ScooterCommand({
    required this.scooterId,
    required this.type,
    Map<String, dynamic>? parameters,
    DateTime? timestamp,
  }) : 
    this.parameters = parameters ?? const {},
    this.timestamp = timestamp ?? DateTime.now();
    
  /// Whether this command can be executed via BLE
  bool get canExecuteViaBle;
  
  /// Whether this command can be executed via Cloud
  bool get canExecuteViaCloud;
  
  /// Validates if the command can be executed
  bool validate();
  
  /// Converts to JSON representation
  Map<String, dynamic> toJson() {
    return {
      'scooterId': scooterId,
      'type': type.index,
      'timestamp': timestamp.toIso8601String(),
      'parameters': parameters,
    };
  }
}