import '../repositories/scooter_repository.dart';

/// Enum representing different characteristic types
enum CharacteristicType {
  /// State characteristic (lock/unlock)
  state,
  
  /// Seat control characteristic
  seat,
  
  /// Blinker control characteristic
  blinker,
  
  /// Hibernation command characteristic
  hibernation,
  
  /// Primary battery characteristic
  primaryBattery,
  
  /// Secondary battery characteristic
  secondaryBattery,
  
  /// CBB battery characteristic
  cbbBattery,
  
  /// Auxiliary battery characteristic
  auxBattery,
}

/// Represents a command to be sent over BLE
class BleCommand {
  /// The characteristic to write to
  final CharacteristicType characteristic;
  
  /// The value to write
  final String value;
  
  /// The ID of the target scooter
  final String scooterId;
  
  BleCommand({
    required this.characteristic, 
    required this.value,
    required this.scooterId,
  });
}

/// Represents a raw state read from a scooter via BLE
class ScooterState {
  /// The current operational state
  final dynamic state;
  
  /// Whether the seat is closed
  final bool seatClosed;
  
  /// Whether the handlebars are locked
  final bool handlebarsLocked;
  
  /// Primary battery status
  final dynamic primaryBattery;
  
  /// Secondary battery status
  final dynamic secondaryBattery;
  
  /// CBB battery status
  final dynamic cbbBattery;
  
  /// Auxiliary battery status
  final dynamic auxBattery;
  
  ScooterState({
    required this.state,
    required this.seatClosed,
    required this.handlebarsLocked,
    required this.primaryBattery,
    required this.secondaryBattery,
    required this.cbbBattery,
    required this.auxBattery,
  });
}

/// Service interface for BLE operations
abstract class BleService {
  /// Checks if BLE is available on the device
  bool isAvailable();
  
  /// Checks if a scooter is currently connected via BLE
  bool isConnected(String scooterId);
  
  /// Connects to a scooter via BLE
  Future<void> connect(String scooterId);
  
  /// Disconnects from a scooter
  Future<void> disconnect(String scooterId);
  
  /// Reads the current state of a scooter
  Future<ScooterState> readScooterState(String scooterId);
  
  /// Stream of state updates for a specific scooter
  Stream<ScooterState> getScooterStateStream(String scooterId);
  
  /// Sends a command to a scooter
  Future<void> sendCommand(BleCommand command);
  
  /// Scans for nearby scooters
  Future<List<ScooterDiscovery>> scan({
    Duration timeout = const Duration(seconds: 30)
  });
  
  /// Stream of scan results as they come in
  Stream<ScooterDiscovery> getScanResults();
  
  /// Stops an ongoing scan
  Future<void> stopScan();
}