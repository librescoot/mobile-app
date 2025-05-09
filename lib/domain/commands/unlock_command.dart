import 'scooter_command.dart';

/// Command to unlock the scooter
class UnlockCommand extends ScooterCommand {
  /// Creates an unlock command
  /// 
  /// [scooterId] ID of the target scooter
  /// [hazardLights] Whether to flash hazard lights after unlocking
  /// [openSeat] Whether to automatically open the seat after unlocking
  UnlockCommand({
    required String scooterId,
    bool hazardLights = false,
    bool openSeat = false,
  }) : super(
          scooterId: scooterId,
          type: CommandType.unlock,
          parameters: {
            'hazardLights': hazardLights,
            'openSeat': openSeat,
          },
        );

  /// Whether hazard lights should be flashed after unlocking
  bool get hazardLights => parameters['hazardLights'] as bool;
  
  /// Whether to automatically open the seat after unlocking
  bool get openSeat => parameters['openSeat'] as bool;

  @override
  bool get canExecuteViaBle => true;
  
  @override
  bool get canExecuteViaCloud => true;
  
  @override
  bool validate() => true;
}