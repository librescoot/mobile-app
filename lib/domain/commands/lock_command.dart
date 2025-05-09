import 'scooter_command.dart';

/// Command to lock the scooter
class LockCommand extends ScooterCommand {
  /// Creates a lock command
  /// 
  /// [scooterId] ID of the target scooter
  /// [hazardLights] Whether to flash hazard lights after locking
  LockCommand({
    required String scooterId,
    bool hazardLights = false,
  }) : super(
          scooterId: scooterId,
          type: CommandType.lock,
          parameters: {'hazardLights': hazardLights},
        );

  /// Whether hazard lights should be flashed after locking
  bool get hazardLights => parameters['hazardLights'] as bool;

  @override
  bool get canExecuteViaBle => true;
  
  @override
  bool get canExecuteViaCloud => true;
  
  @override
  bool validate() => true; // No specific validation needed for lock
}