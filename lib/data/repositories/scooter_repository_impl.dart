import 'dart:async';

import 'package:logging/logging.dart';

import '../../domain/commands/scooter_command.dart';
import '../../domain/models/scooter.dart';
import '../../domain/repositories/scooter_repository.dart';
import '../../domain/services/ble_service.dart';
import '../../domain/services/cloud_service.dart';
import '../../domain/services/local_storage_service.dart';

/// Implementation of [ScooterRepository]
class ScooterRepositoryImpl implements ScooterRepository {
  final Logger _logger = Logger('ScooterRepositoryImpl');
  final BleService _bleService;
  final CloudService _cloudService;
  final LocalStorageService _storageService;
  
  // Stream controllers
  final StreamController<Scooter> _scooterUpdateController = 
      StreamController<Scooter>.broadcast();
  final StreamController<ScooterDiscovery> _discoveryController = 
      StreamController<ScooterDiscovery>.broadcast();
  final StreamController<Exception> _errorController = 
      StreamController<Exception>.broadcast();
  
  // Streams for connection status
  final Map<String, StreamController<bool>> _connectionStatusControllers = {};
  
  ScooterRepositoryImpl({
    required BleService bleService,
    required CloudService cloudService,
    required LocalStorageService storageService,
  }) : 
    _bleService = bleService,
    _cloudService = cloudService,
    _storageService = storageService {
    // Forward BLE discovery events
    _bleService.getScanResults().listen((discovery) {
      _discoveryController.add(discovery);
    });
  }
  
  @override
  Future<List<Scooter>> getAllScooters() async {
    try {
      // Get scooters from local storage
      final scooters = await _storageService.getScooters();
      
      // Update connection status for each scooter
      return scooters.map((scooter) {
        final isConnected = _bleService.isConnected(scooter.id);
        return scooter.copyWith(isConnected: isConnected);
      }).toList();
    } catch (e) {
      _logger.severe('Failed to get all scooters', e);
      _errorController.add(Exception('Failed to get all scooters: ${e.toString()}'));
      return [];
    }
  }
  
  @override
  Future<Scooter?> getScooter(String scooterId) async {
    try {
      // Get scooter from local storage
      final scooter = await _storageService.getScooter(scooterId);
      if (scooter == null) return null;
      
      // Update connection status
      final isConnected = _bleService.isConnected(scooterId);
      return scooter.copyWith(isConnected: isConnected);
    } catch (e) {
      _logger.severe('Failed to get scooter: $scooterId', e);
      _errorController.add(Exception('Failed to get scooter: ${e.toString()}'));
      return null;
    }
  }
  
  @override
  Future<void> saveScooter(Scooter scooter) async {
    try {
      await _storageService.saveScooter(scooter);
      _scooterUpdateController.add(scooter);
    } catch (e) {
      _logger.severe('Failed to save scooter: ${scooter.id}', e);
      _errorController.add(Exception('Failed to save scooter: ${e.toString()}'));
      rethrow;
    }
  }
  
  @override
  Future<void> deleteScooter(String scooterId) async {
    try {
      // Disconnect first if connected
      if (_bleService.isConnected(scooterId)) {
        await _bleService.disconnect(scooterId);
      }
      
      await _storageService.deleteScooter(scooterId);
    } catch (e) {
      _logger.severe('Failed to delete scooter: $scooterId', e);
      _errorController.add(Exception('Failed to delete scooter: ${e.toString()}'));
      rethrow;
    }
  }
  
  @override
  Future<void> connect(String scooterId) async {
    try {
      // Try BLE connection first
      if (_bleService.isAvailable()) {
        try {
          await _bleService.connect(scooterId);
          
          // If connection successful, update connection status
          _updateConnectionStatus(scooterId, true);
          
          // Read current state and update local storage
          await _updateScooterStateFromBle(scooterId);
          
          return;
        } catch (e) {
          _logger.warning('BLE connection failed, trying cloud', e);
        }
      }
      
      // If BLE fails or is not available, try cloud connection
      if (_cloudService.isAvailable() && _cloudService.isConnected()) {
        await _cloudService.connect(scooterId);
        
        // Get scooter data from cloud
        final cloudScooter = await _cloudService.getScooter(scooterId);
        if (cloudScooter != null) {
          // Update local storage with cloud data
          await saveScooter(cloudScooter);
        }
        
        return;
      }
      
      // If both fail, throw
      throw ConnectionException('No connectivity available');
    } catch (e) {
      _logger.severe('Failed to connect to scooter: $scooterId', e);
      _errorController.add(e is Exception 
          ? e 
          : Exception('Failed to connect to scooter: ${e.toString()}'));
      rethrow;
    }
  }
  
  @override
  Future<void> disconnect(String scooterId) async {
    try {
      if (_bleService.isConnected(scooterId)) {
        await _bleService.disconnect(scooterId);
      }
      
      _updateConnectionStatus(scooterId, false);
    } catch (e) {
      _logger.severe('Failed to disconnect from scooter: $scooterId', e);
      _errorController.add(Exception('Failed to disconnect: ${e.toString()}'));
      rethrow;
    }
  }
  
  @override
  Stream<bool> getConnectionStatus(String scooterId) {
    if (!_connectionStatusControllers.containsKey(scooterId)) {
      _connectionStatusControllers[scooterId] = 
          StreamController<bool>.broadcast();
      
      // Initialize with current status
      _connectionStatusControllers[scooterId]!
          .add(_bleService.isConnected(scooterId));
    }
    
    return _connectionStatusControllers[scooterId]!.stream;
  }
  
  @override
  Future<void> executeCommand(ScooterCommand command) async {
    try {
      // Try BLE first if connected and command supports BLE
      if (command.canExecuteViaBle && 
          _bleService.isAvailable() && 
          _bleService.isConnected(command.scooterId)) {
        try {
          // Map command to BLE command
          final bleCommand = _mapCommandToBle(command);
          
          // Execute via BLE
          await _bleService.sendCommand(bleCommand);
          
          // Update scooter state after command execution
          await _updateScooterStateFromBle(command.scooterId);
          
          return;
        } catch (e) {
          _logger.warning('BLE command failed, trying cloud', e);
        }
      }
      
      // Try cloud if BLE fails or is not available and command supports cloud
      if (command.canExecuteViaCloud && 
          _cloudService.isAvailable() && 
          _cloudService.isConnected()) {
        try {
          // Map command to API request
          final apiRequest = _mapCommandToApiRequest(command);
          
          // Execute via cloud
          await _cloudService.sendRequest(apiRequest);
          
          // Update scooter state from cloud
          final cloudScooter = await _cloudService.getScooter(command.scooterId);
          if (cloudScooter != null) {
            await saveScooter(cloudScooter);
          }
          
          return;
        } catch (e) {
          _logger.severe('Cloud command failed', e);
          throw CommandException('Cloud command failed: ${e.toString()}');
        }
      }
      
      // If both fail, throw
      throw CommandException(
        'No available executor for command: ${command.type}'
      );
    } catch (e) {
      _logger.severe('Failed to execute command', e);
      _errorController.add(e is Exception 
          ? e 
          : CommandException('Command execution failed: ${e.toString()}'));
      rethrow;
    }
  }
  
  @override
  Future<List<ScooterDiscovery>> scanForScooters() async {
    try {
      if (_bleService.isAvailable()) {
        return await _bleService.scan();
      }
      
      return [];
    } catch (e) {
      _logger.severe('Failed to scan for scooters', e);
      _errorController.add(Exception('Scan failed: ${e.toString()}'));
      rethrow;
    }
  }
  
  @override
  Stream<ScooterDiscovery> getScooterDiscoveryStream() {
    return _discoveryController.stream;
  }
  
  @override
  Future<void> stopScan() async {
    try {
      if (_bleService.isAvailable()) {
        await _bleService.stopScan();
      }
    } catch (e) {
      _logger.warning('Failed to stop scan', e);
      // Don't throw - stopping should be best effort
    }
  }
  
  @override
  Stream<Scooter> getScooterUpdates() {
    return _scooterUpdateController.stream;
  }
  
  @override
  Stream<Scooter> getScooterUpdatesById(String scooterId) {
    return _scooterUpdateController.stream
        .where((scooter) => scooter.id == scooterId);
  }
  
  @override
  Stream<Exception> getErrorStream() {
    return _errorController.stream;
  }
  
  /// Updates connection status and notifies listeners
  void _updateConnectionStatus(String scooterId, bool isConnected) {
    if (_connectionStatusControllers.containsKey(scooterId)) {
      _connectionStatusControllers[scooterId]!.add(isConnected);
    }
  }
  
  /// Updates scooter state from BLE and saves to storage
  Future<void> _updateScooterStateFromBle(String scooterId) async {
    try {
      // Read current state from BLE
      final bleState = await _bleService.readScooterState(scooterId);
      
      // Get current scooter data from storage
      final currentScooter = await _storageService.getScooter(scooterId) ?? 
                             Scooter.empty(scooterId);
      
      // Update with new state
      final updatedScooter = currentScooter.copyWith(
        // Map BLE state to domain model
        // This is a placeholder - actual mapping would depend on the scooter's data format
        state: bleState.state,
        seatClosed: bleState.seatClosed,
        handlebarsLocked: bleState.handlebarsLocked,
        primaryBattery: currentScooter.primaryBattery.copyWith(
          soc: bleState.primaryBattery,
        ),
        secondaryBattery: currentScooter.secondaryBattery.copyWith(
          soc: bleState.secondaryBattery,
        ),
        cbbBattery: currentScooter.cbbBattery.copyWith(
          soc: bleState.cbbBattery,
        ),
        auxBattery: currentScooter.auxBattery.copyWith(
          soc: bleState.auxBattery,
        ),
        lastConnected: DateTime.now(),
        isConnected: true,
      );
      
      // Save updated scooter
      await saveScooter(updatedScooter);
    } catch (e) {
      _logger.warning('Failed to update scooter state from BLE', e);
      // Don't throw - this is a background operation
    }
  }
  
  /// Maps a domain command to a BLE command
  BleCommand _mapCommandToBle(ScooterCommand command) {
    switch (command.type) {
      case CommandType.lock:
        return BleCommand(
          characteristic: CharacteristicType.state,
          value: "scooter:state lock",
          scooterId: command.scooterId,
        );

      case CommandType.unlock:
        return BleCommand(
          characteristic: CharacteristicType.state,
          value: "scooter:state unlock",
          scooterId: command.scooterId,
        );

      case CommandType.openSeat:
        return BleCommand(
          characteristic: CharacteristicType.seat,
          value: "scooter:seatbox open",
          scooterId: command.scooterId,
        );

      case CommandType.blink:
        final left = command.parameters['left'] as bool? ?? false;
        final right = command.parameters['right'] as bool? ?? false;

        String value;
        if (left && right) {
          value = "scooter:blinker both";
        } else if (left) {
          value = "scooter:blinker left";
        } else if (right) {
          value = "scooter:blinker right";
        } else {
          value = "scooter:blinker off";
        }

        return BleCommand(
          characteristic: CharacteristicType.blinker,
          value: value,
          scooterId: command.scooterId,
        );

      case CommandType.wakeUp:
        return BleCommand(
          characteristic: CharacteristicType.hibernation,
          value: "wakeup",
          scooterId: command.scooterId,
        );

      case CommandType.hibernate:
        return BleCommand(
          characteristic: CharacteristicType.hibernation,
          value: "hibernate",
          scooterId: command.scooterId,
        );
    }

    throw CommandException('Unreachable code - unsupported command type: ${command.type}');
  }
  
  /// Maps a domain command to a cloud API request
  ApiRequest _mapCommandToApiRequest(ScooterCommand command) {
    switch (command.type) {
      case CommandType.lock:
        return ApiRequest(
          endpoint: 'scooter/command',
          data: {
            'scooterId': command.scooterId,
            'command': 'lock',
          },
        );
        
      case CommandType.unlock:
        return ApiRequest(
          endpoint: 'scooter/command',
          data: {
            'scooterId': command.scooterId,
            'command': 'unlock',
          },
        );
        
      case CommandType.openSeat:
        return ApiRequest(
          endpoint: 'scooter/command',
          data: {
            'scooterId': command.scooterId,
            'command': 'openSeat',
          },
        );
        
      default:
        throw CommandException('Unsupported command type for cloud: ${command.type}');
    }
  }
}