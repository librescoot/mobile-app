import 'scooter_command.dart';

/// Command to open the seat compartment
class OpenSeatCommand extends ScooterCommand {
  /// Creates an open seat command
  /// 
  /// [scooterId] ID of the target scooter
  OpenSeatCommand({
    required String scooterId,
  }) : super(
          scooterId: scooterId,
          type: CommandType.openSeat,
        );

  @override
  bool get canExecuteViaBle => true;
  
  @override
  bool get canExecuteViaCloud => true;
  
  @override
  bool validate() => true;
}