import 'scooter_command.dart';

/// Command to wake up the scooter from hibernation
class WakeUpCommand extends ScooterCommand {
  /// Creates a wake up command
  /// 
  /// [scooterId] ID of the target scooter
  WakeUpCommand({
    required String scooterId,
  }) : super(
          scooterId: scooterId,
          type: CommandType.wakeUp,
        );

  @override
  bool get canExecuteViaBle => true;
  
  @override
  bool get canExecuteViaCloud => false; // Typically wake-up is BLE-only
  
  @override
  bool validate() => true;
}