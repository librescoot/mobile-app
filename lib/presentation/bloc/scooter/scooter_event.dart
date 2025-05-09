import 'package:flutter/foundation.dart';

import '../../../domain/commands/scooter_command.dart';
import '../../../domain/models/scooter.dart';

/// Base class for all scooter-related events
@immutable
abstract class ScooterEvent {}

/// Event to load all scooters
class LoadScooters extends ScooterEvent {}

/// Event to connect to a specific scooter
class ConnectToScooter extends ScooterEvent {
  /// The ID of the scooter to connect to
  final String scooterId;
  
  ConnectToScooter(this.scooterId);
}

/// Event to disconnect from a scooter
class DisconnectScooter extends ScooterEvent {
  /// The ID of the scooter to disconnect from
  final String scooterId;
  
  DisconnectScooter(this.scooterId);
}

/// Event to execute a command on a scooter
class ExecuteScooterCommand extends ScooterEvent {
  /// The command to execute
  final ScooterCommand command;
  
  ExecuteScooterCommand(this.command);
}

/// Event to start scanning for scooters
class ScanForScooters extends ScooterEvent {
  /// Optional timeout for the scan
  final Duration? timeout;
  
  ScanForScooters({this.timeout});
}

/// Event to stop scanning for scooters
class StopScanningForScooters extends ScooterEvent {}

/// Event to rename a scooter
class RenameScooter extends ScooterEvent {
  /// The ID of the scooter to rename
  final String scooterId;
  
  /// The new name for the scooter
  final String newName;
  
  RenameScooter({
    required this.scooterId,
    required this.newName,
  });
}

/// Event to set a scooter's auto-connect property
class SetScooterAutoConnect extends ScooterEvent {
  /// The ID of the scooter to update
  final String scooterId;
  
  /// Whether to auto-connect to this scooter
  final bool autoConnect;
  
  SetScooterAutoConnect({
    required this.scooterId,
    required this.autoConnect,
  });
}

/// Event to delete a scooter
class DeleteScooter extends ScooterEvent {
  /// The ID of the scooter to delete
  final String scooterId;
  
  DeleteScooter(this.scooterId);
}

/// Event when a scooter update is received
class ScooterUpdated extends ScooterEvent {
  /// The updated scooter
  final Scooter scooter;
  
  ScooterUpdated(this.scooter);
}