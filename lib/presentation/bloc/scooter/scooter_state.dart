import 'package:flutter/foundation.dart';

import '../../../domain/commands/scooter_command.dart';
import '../../../domain/models/scooter.dart';
import '../../../domain/repositories/scooter_repository.dart';

/// Base class for all scooter-related states
@immutable
abstract class ScooterState {
  /// List of all scooters
  final List<Scooter> scooters;
  
  const ScooterState(this.scooters);
  
  /// Returns the first connected scooter, if any
  Scooter? get activeScooter => 
      scooters.firstWhere((s) => s.isConnected, orElse: () => null);
}

/// Initial state when the app starts
class ScootersInitial extends ScooterState {
  ScootersInitial() : super([]);
}

/// State when scooters are loaded
class ScootersLoaded extends ScooterState {
  const ScootersLoaded(List<Scooter> scooters) : super(scooters);
}

/// State during scanning for scooters
class ScootersScanning extends ScooterState {
  /// List of discovered scooters
  final List<ScooterDiscovery> discoveries;
  
  const ScootersScanning(
    List<Scooter> scooters,
    this.discoveries,
  ) : super(scooters);
}

/// State during connection to a scooter
class ScooterConnecting extends ScooterState {
  /// ID of the scooter being connected to
  final String scooterId;
  
  const ScooterConnecting(this.scooterId, List<Scooter> scooters) 
    : super(scooters);
}

/// State during command execution
class ScooterCommandExecuting extends ScooterState {
  /// Command being executed
  final ScooterCommand command;
  
  const ScooterCommandExecuting(this.command, List<Scooter> scooters) 
    : super(scooters);
}

/// State when an error occurs
class ScooterError extends ScooterState {
  /// Error message
  final String message;
  
  const ScooterError(this.message, List<Scooter> scooters) 
    : super(scooters);
}