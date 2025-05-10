import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../../domain/repositories/scooter_repository.dart';
import '../../domain/services/ble_service.dart';
import '../../flutter/blue_plus_mockable.dart';

/// Implementation of [BleService] using FlutterBluePlus
class FlutterBlueService implements BleService {
  final Logger _logger = Logger('FlutterBlueService');
  final FlutterBluePlusMockable _flutterBlue;
  
  // Cached devices and characteristics
  final Map<String, BluetoothDevice> _connectedDevices = {};
  final Map<String, Map<CharacteristicType, BluetoothCharacteristic>> _characteristics = {};
  
  // Service and characteristic UUIDs
  static const String _scooterServiceUuid = "9a590000-6e67-5d0d-aab9-ad9126b66f91";
  static const Map<CharacteristicType, String> _characteristicUuids = {
    CharacteristicType.state: "9a590001-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.seat: "9a590002-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.blinker: "9a590003-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.hibernation: "9a5900e0-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.primaryBattery: "9a5900a0-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.secondaryBattery: "9a5900a1-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.cbbBattery: "9a5900a2-6e67-5d0d-aab9-ad9126b66f91",
    CharacteristicType.auxBattery: "9a5900a3-6e67-5d0d-aab9-ad9126b66f91",
  };
  
  // Stream controllers for state updates
  final Map<String, StreamController<ScooterState>> _stateControllers = {};
  final StreamController<ScooterDiscovery> _discoveryController = 
      StreamController<ScooterDiscovery>.broadcast();
  
  // Discovery cache to avoid duplicates
  final List<String> _discoveryCache = [];
  
  FlutterBlueService(this._flutterBlue);
  
  @override
  bool isAvailable() {
    // Use a simple connectivity check for availability
    return true;
  }
  
  @override
  bool isConnected(String scooterId) {
    return _connectedDevices.containsKey(scooterId) && 
           _connectedDevices[scooterId]!.isConnected;
  }
  
  @override
  Future<void> connect(String scooterId) async {
    _logger.info('Connecting to scooter: $scooterId');
    
    try {
      // Check if we're already connected
      if (isConnected(scooterId)) {
        _logger.info('Already connected to scooter: $scooterId');
        return;
      }
      
      // If we have the device in cache but not connected
      if (_connectedDevices.containsKey(scooterId)) {
        final device = _connectedDevices[scooterId]!;
        if (device.isDisconnected) {
          await device.connect(timeout: const Duration(seconds: 30));
          _logger.info('Reconnected to scooter: $scooterId');
          
          // Rediscover characteristics
          await _discoverCharacteristics(device);
          
          // Set up state notifications
          _setupStateNotifications(device);
          
          return;
        }
      }
      
      // Try to find the device in system devices first
      final systemDevices = await _flutterBlue.systemDevices([Guid(_scooterServiceUuid)]);
      BluetoothDevice? targetDevice;
      
      for (var device in systemDevices) {
        if (device.remoteId.toString() == scooterId) {
          targetDevice = device;
          break;
        }
      }
      
      // If not found in system devices, create from ID
      if (targetDevice == null) {
        targetDevice = BluetoothDevice.fromId(scooterId);
      }
      
      // Connect to the device
      await targetDevice.connect(timeout: const Duration(seconds: 30));
      _logger.info('Connected to scooter: $scooterId');
      
      // Cache the connected device
      _connectedDevices[scooterId] = targetDevice;
      
      // Discover characteristics
      await _discoverCharacteristics(targetDevice);
      
      // Set up state notifications
      _setupStateNotifications(targetDevice);
      
      // Set up disconnect listener
      targetDevice.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          _logger.info('Scooter disconnected: $scooterId');
          _characteristics.remove(scooterId);
        }
      });
      
    } catch (e) {
      _logger.severe('Failed to connect to scooter: $scooterId', e);
      throw ConnectionException('Failed to connect to scooter: ${e.toString()}');
    }
  }
  
  @override
  Future<void> disconnect(String scooterId) async {
    _logger.info('Disconnecting from scooter: $scooterId');
    
    try {
      if (_connectedDevices.containsKey(scooterId)) {
        final device = _connectedDevices[scooterId]!;
        await device.disconnect();
        _characteristics.remove(scooterId);
        _logger.info('Disconnected from scooter: $scooterId');
      }
    } catch (e) {
      _logger.warning('Error disconnecting from scooter: $scooterId', e);
      // Don't throw - disconnection should be best effort
    }
  }
  
  @override
  Future<ScooterState> readScooterState(String scooterId) async {
    _logger.info('Reading state for scooter: $scooterId');
    
    if (!isConnected(scooterId)) {
      throw ConnectionException('Not connected to scooter: $scooterId');
    }
    
    try {
      // Read all required characteristics
      final stateCharacteristic = 
          await _getCharacteristic(scooterId, CharacteristicType.state);
      final seatCharacteristic = 
          await _getCharacteristic(scooterId, CharacteristicType.seat);
      final primaryBatteryCharacteristic = 
          await _getCharacteristic(scooterId, CharacteristicType.primaryBattery);
      final secondaryBatteryCharacteristic = 
          await _getCharacteristic(scooterId, CharacteristicType.secondaryBattery);
      final cbbBatteryCharacteristic = 
          await _getCharacteristic(scooterId, CharacteristicType.cbbBattery);
      final auxBatteryCharacteristic = 
          await _getCharacteristic(scooterId, CharacteristicType.auxBattery);
      
      // Read values
      final stateData = await stateCharacteristic.read();
      final seatData = await seatCharacteristic.read();
      final primaryBatteryData = await primaryBatteryCharacteristic.read();
      final secondaryBatteryData = await secondaryBatteryCharacteristic.read();
      final cbbBatteryData = await cbbBatteryCharacteristic.read();
      final auxBatteryData = await auxBatteryCharacteristic.read();
      
      // TODO: Implement parsing of the raw data
      // This is a placeholder implementation. The actual parsing would depend
      // on the specific protocol used by the scooter.
      return ScooterState(
        state: _parseStateData(stateData),
        seatClosed: _parseSeatData(seatData),
        handlebarsLocked: _parseHandlebarsData(stateData),
        primaryBattery: _parsePrimaryBatteryData(primaryBatteryData),
        secondaryBattery: _parseSecondaryBatteryData(secondaryBatteryData),
        cbbBattery: _parseCbbBatteryData(cbbBatteryData),
        auxBattery: _parseAuxBatteryData(auxBatteryData),
      );
    } catch (e) {
      _logger.severe('Failed to read scooter state: $scooterId', e);
      throw Exception('Failed to read scooter state: ${e.toString()}');
    }
  }
  
  @override
  Stream<ScooterState> getScooterStateStream(String scooterId) {
    if (!_stateControllers.containsKey(scooterId)) {
      _stateControllers[scooterId] = StreamController<ScooterState>.broadcast();
      
      // If we're already connected, set up notifications
      if (isConnected(scooterId)) {
        _setupStateNotifications(_connectedDevices[scooterId]!);
      }
    }
    
    return _stateControllers[scooterId]!.stream;
  }
  
  @override
  Future<void> sendCommand(BleCommand command) async {
    _logger.info('Sending command to scooter: ${command.scooterId}, characteristic: ${command.characteristic}, value: ${command.value}');
    
    if (!isConnected(command.scooterId)) {
      throw ConnectionException('Not connected to scooter: ${command.scooterId}');
    }
    
    try {
      final characteristic = 
          await _getCharacteristic(command.scooterId, command.characteristic);
      
      // Convert command value to bytes and write
      List<int> bytes = [];
      for (var i = 0; i < command.value.length; i++) {
        bytes.add(command.value.codeUnitAt(i));
      }
      
      await characteristic.write(bytes);
      _logger.info('Command sent successfully');
    } catch (e) {
      _logger.severe('Failed to send command', e);
      throw CommandException('Failed to send command: ${e.toString()}');
    }
  }
  
  @override
  Future<List<ScooterDiscovery>> scan({
    Duration timeout = const Duration(seconds: 30)
  }) async {
    _logger.info('Starting scan for scooters with timeout: ${timeout.inSeconds}s');
    
    try {
      // Clear discovery cache
      _discoveryCache.clear();
      
      // Start scanning
      _flutterBlue.startScan(
        withNames: ["unu Scooter"],
        timeout: timeout,
      );
      
      // Collect discoveries
      final discoveries = <ScooterDiscovery>[];
      await for (var scanResult in _flutterBlue.onScanResults) {
        if (scanResult.isNotEmpty) {
          ScanResult r = scanResult.last;
          final id = r.device.remoteId.toString();
          
          // Skip if already discovered
          if (_discoveryCache.contains(id)) {
            continue;
          }
          
          _discoveryCache.add(id);
          
          final discovery = ScooterDiscovery(
            id: id,
            name: r.device.platformName.isEmpty ? "unu Scooter" : r.device.platformName,
            rssi: r.rssi,
            isSaved: _connectedDevices.containsKey(id),
          );
          
          discoveries.add(discovery);
          _discoveryController.add(discovery);
        }
      }
      
      return discoveries;
    } catch (e) {
      _logger.severe('Error during scan', e);
      throw Exception('Scan failed: ${e.toString()}');
    } finally {
      // Ensure scan is stopped
      await stopScan();
    }
  }
  
  @override
  Stream<ScooterDiscovery> getScanResults() {
    return _discoveryController.stream;
  }
  
  @override
  Future<void> stopScan() async {
    _logger.info('Stopping scan');
    
    try {
      await _flutterBlue.stopScan();
    } catch (e) {
      _logger.warning('Error stopping scan', e);
      // Don't throw - stopping should be best effort
    }
  }
  
  /// Discovers all characteristics for a device
  Future<void> _discoverCharacteristics(BluetoothDevice device) async {
    _logger.info('Discovering characteristics for scooter: ${device.remoteId}');
    
    try {
      final services = await device.discoverServices();
      final scooterId = device.remoteId.toString();
      
      // Initialize characteristics map for this device
      if (!_characteristics.containsKey(scooterId)) {
        _characteristics[scooterId] = {};
      }
      
      // Find the scooter service
      for (var service in services) {
        if (service.uuid.toString() == _scooterServiceUuid) {
          // Find all required characteristics
          for (var char in service.characteristics) {
            for (var entry in _characteristicUuids.entries) {
              if (char.uuid.toString() == entry.value) {
                _characteristics[scooterId]![entry.key] = char;
                _logger.fine('Found characteristic: ${entry.key} for scooter: $scooterId');
              }
            }
          }
          break;
        }
      }
      
      // Verify we found all required characteristics
      for (var charType in _characteristicUuids.keys) {
        if (!_characteristics[scooterId]!.containsKey(charType)) {
          _logger.warning('Missing characteristic: $charType for scooter: $scooterId');
        }
      }
    } catch (e) {
      _logger.severe('Error discovering characteristics', e);
      throw Exception('Failed to discover characteristics: ${e.toString()}');
    }
  }
  
  /// Gets a characteristic for a scooter, discovering if necessary
  Future<BluetoothCharacteristic> _getCharacteristic(
    String scooterId, 
    CharacteristicType type
  ) async {
    // Check if we already have the characteristic
    if (_characteristics.containsKey(scooterId) && 
        _characteristics[scooterId]!.containsKey(type)) {
      return _characteristics[scooterId]![type]!;
    }
    
    // If not, rediscover characteristics
    if (_connectedDevices.containsKey(scooterId)) {
      await _discoverCharacteristics(_connectedDevices[scooterId]!);
      
      // Check again
      if (_characteristics.containsKey(scooterId) && 
          _characteristics[scooterId]!.containsKey(type)) {
        return _characteristics[scooterId]![type]!;
      }
    }
    
    // If still not found, throw
    throw Exception('Characteristic not found: $type for scooter: $scooterId');
  }
  
  /// Sets up notifications for state changes
  void _setupStateNotifications(BluetoothDevice device) async {
    final scooterId = device.remoteId.toString();
    _logger.info('Setting up state notifications for scooter: $scooterId');
    
    try {
      // Set up notifications for state characteristic
      final stateChar = await _getCharacteristic(scooterId, CharacteristicType.state);
      await stateChar.setNotifyValue(true);
      stateChar.onValueReceived.listen((value) {
        _handleStateUpdate(scooterId, value);
      });
      
      // Set up notifications for seat characteristic
      final seatChar = await _getCharacteristic(scooterId, CharacteristicType.seat);
      await seatChar.setNotifyValue(true);
      seatChar.onValueReceived.listen((value) {
        _handleSeatUpdate(scooterId, value);
      });
      
      // Set up notifications for battery characteristics
      for (var batteryType in [
        CharacteristicType.primaryBattery,
        CharacteristicType.secondaryBattery,
        CharacteristicType.cbbBattery,
        CharacteristicType.auxBattery,
      ]) {
        final char = await _getCharacteristic(scooterId, batteryType);
        await char.setNotifyValue(true);
        char.onValueReceived.listen((value) {
          _handleBatteryUpdate(scooterId, batteryType, value);
        });
      }
    } catch (e) {
      _logger.warning('Failed to set up state notifications', e);
      // Don't throw - notifications are optional
    }
  }
  
  /// Handles a state characteristic update
  void _handleStateUpdate(String scooterId, List<int> value) {
    _logger.fine('State update for scooter: $scooterId');
    
    // Only update if we have a stream controller for this scooter
    if (_stateControllers.containsKey(scooterId)) {
      try {
        // Read the current full state
        readScooterState(scooterId).then((state) {
          _stateControllers[scooterId]!.add(state);
        }).catchError((e) {
          _logger.warning('Failed to read full state after update', e);
        });
      } catch (e) {
        _logger.warning('Failed to process state update', e);
      }
    }
  }
  
  /// Handles a seat characteristic update
  void _handleSeatUpdate(String scooterId, List<int> value) {
    _logger.fine('Seat update for scooter: $scooterId');
    
    // Handle the same way as state updates for now
    _handleStateUpdate(scooterId, value);
  }
  
  /// Handles a battery characteristic update
  void _handleBatteryUpdate(
    String scooterId, 
    CharacteristicType batteryType, 
    List<int> value
  ) {
    _logger.fine('Battery update for scooter: $scooterId, type: $batteryType');
    
    // Handle the same way as state updates for now
    _handleStateUpdate(scooterId, value);
  }
  
  // Parsing helpers - these would be implemented based on the scooter's protocol
  
  dynamic _parseStateData(List<int> data) {
    // TODO: Implement actual parsing
    return "unknown";
  }
  
  bool _parseSeatData(List<int> data) {
    // TODO: Implement actual parsing
    return true;
  }
  
  bool _parseHandlebarsData(List<int> data) {
    // TODO: Implement actual parsing
    return true;
  }
  
  dynamic _parsePrimaryBatteryData(List<int> data) {
    // TODO: Implement actual parsing
    return 50;
  }
  
  dynamic _parseSecondaryBatteryData(List<int> data) {
    // TODO: Implement actual parsing
    return 50;
  }
  
  dynamic _parseCbbBatteryData(List<int> data) {
    // TODO: Implement actual parsing
    return 50;
  }
  
  dynamic _parseAuxBatteryData(List<int> data) {
    // TODO: Implement actual parsing
    return 50;
  }
}