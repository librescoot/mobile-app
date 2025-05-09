import '../commands/scooter_command.dart';
import '../models/scooter.dart';

/// Discovery information for a scooter found during scanning
class ScooterDiscovery {
  /// Unique identifier for the scooter
  final String id;
  
  /// Advertised name of the scooter
  final String name;
  
  /// Signal strength indicator
  final int rssi;
  
  /// Whether this scooter is already saved in the repository
  final bool isSaved;
  
  ScooterDiscovery({
    required this.id,
    required this.name, 
    required this.rssi,
    this.isSaved = false,
  });
}

/// Exception thrown when a command could not be executed
class CommandException implements Exception {
  final String message;
  CommandException(this.message);
  
  @override
  String toString() => 'CommandException: $message';
}

/// Exception thrown when connection to a scooter fails
class ConnectionException implements Exception {
  final String message;
  ConnectionException(this.message);
  
  @override
  String toString() => 'ConnectionException: $message';
}

/// Repository interface for scooter operations
abstract class ScooterRepository {
  /// Retrieves all stored scooters
  Future<List<Scooter>> getAllScooters();
  
  /// Retrieves a specific scooter by ID
  Future<Scooter?> getScooter(String scooterId);
  
  /// Saves scooter data to storage
  Future<void> saveScooter(Scooter scooter);
  
  /// Removes a scooter from storage
  Future<void> deleteScooter(String scooterId);
  
  /// Connects to a scooter
  /// 
  /// This will attempt to establish a connection to the specified scooter
  /// using available channels (BLE or cloud).
  Future<void> connect(String scooterId);
  
  /// Disconnects from a scooter
  /// 
  /// This will terminate the active connection with the specified scooter.
  Future<void> disconnect(String scooterId);
  
  /// Stream of connection status updates for a specific scooter
  Stream<bool> getConnectionStatus(String scooterId);
  
  /// Executes a command on a scooter
  /// 
  /// This will select the appropriate channel (BLE or cloud) to execute the
  /// command based on current connectivity and command capabilities.
  Future<void> executeCommand(ScooterCommand command);
  
  /// Scans for available scooters
  /// 
  /// Returns a list of discovered scooters from available channels.
  Future<List<ScooterDiscovery>> scanForScooters();
  
  /// Stream of scooter discoveries as they happen
  Stream<ScooterDiscovery> getScooterDiscoveryStream();
  
  /// Stops an ongoing scan
  Future<void> stopScan();
  
  /// Stream of scooter updates
  /// 
  /// This will emit updates whenever a scooter's state changes.
  Stream<Scooter> getScooterUpdates();
  
  /// Stream of updates for a specific scooter
  Stream<Scooter> getScooterUpdatesById(String scooterId);
  
  /// Stream of all errors that occur within the repository
  Stream<Exception> getErrorStream();
}