import 'scooter_command.dart';

/// Command to control the scooter blinkers
class BlinkCommand extends ScooterCommand {
  /// Creates a blink command
  /// 
  /// [scooterId] ID of the target scooter
  /// [left] Whether to activate the left blinker
  /// [right] Whether to activate the right blinker
  /// Setting both [left] and [right] to true will activate hazard lights
  /// Setting both [left] and [right] to false will deactivate all blinkers
  BlinkCommand({
    required String scooterId,
    required bool left,
    required bool right,
  }) : super(
          scooterId: scooterId,
          type: CommandType.blink,
          parameters: {'left': left, 'right': right},
        );

  /// Whether to activate the left blinker
  bool get left => parameters['left'] as bool;
  
  /// Whether to activate the right blinker
  bool get right => parameters['right'] as bool;

  @override
  bool get canExecuteViaBle => true;
  
  @override
  bool get canExecuteViaCloud => false; // Example of BLE-only command
  
  @override
  bool validate() => true;
}