import 'scooter_command.dart';

/// Command to put the scooter into hibernation mode
class HibernateCommand extends ScooterCommand {
  /// Creates a hibernate command
  /// 
  /// [scooterId] ID of the target scooter
  HibernateCommand({
    required String scooterId,
  }) : super(
          scooterId: scooterId,
          type: CommandType.hibernate,
        );

  @override
  bool get canExecuteViaBle => true;
  
  @override
  bool get canExecuteViaCloud => false; // Typically hibernation is BLE-only
  
  @override
  bool validate() => true;
}