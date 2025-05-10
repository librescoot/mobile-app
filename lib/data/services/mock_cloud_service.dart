import 'dart:async';

import 'package:logging/logging.dart';

import '../../domain/models/scooter.dart';
import '../../domain/services/cloud_service.dart';

/// Mock implementation of [CloudService] for development
class MockCloudService implements CloudService {
  final Logger _logger = Logger('MockCloudService');
  bool _isConnected = false;
  
  // Mock scooter cache
  final Map<String, Scooter> _scooters = {};
  
  // Stream controllers for scooter updates
  final Map<String, StreamController<Scooter>> _updateControllers = {};
  
  @override
  bool isAvailable() {
    return true; // Always available in mock
  }
  
  @override
  bool isConnected() {
    return _isConnected;
  }
  
  @override
  Future<void> connect(String scooterId) async {
    _logger.info('Mock connecting to cloud for scooter: $scooterId');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    _isConnected = true;
    
    // Create a mock scooter if it doesn't exist
    if (!_scooters.containsKey(scooterId)) {
      _scooters[scooterId] = Scooter.empty(scooterId);
    }
  }
  
  @override
  Future<Scooter?> getScooter(String scooterId) async {
    if (!_isConnected) {
      throw Exception('Not connected to cloud service');
    }
    
    _logger.info('Mock getting scooter from cloud: $scooterId');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 300));
    
    return _scooters[scooterId];
  }
  
  @override
  Future<List<Scooter>> getAllScooters() async {
    if (!_isConnected) {
      throw Exception('Not connected to cloud service');
    }
    
    _logger.info('Mock getting all scooters from cloud');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 300));
    
    return _scooters.values.toList();
  }
  
  @override
  Future<dynamic> sendRequest(ApiRequest request) async {
    if (!_isConnected) {
      throw Exception('Not connected to cloud service');
    }
    
    _logger.info('Mock sending request to cloud: ${request.endpoint}');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 400));
    
    // Mock responses based on endpoint
    switch (request.endpoint) {
      case 'scooter/status':
        final scooterId = request.data['scooterId'] as String?;
        if (scooterId != null && _scooters.containsKey(scooterId)) {
          return {'success': true, 'data': _scooters[scooterId]!.toJson()};
        }
        return {'success': false, 'error': 'Scooter not found'};
        
      case 'scooter/command':
        final scooterId = request.data['scooterId'] as String?;
        final command = request.data['command'] as String?;
        
        if (scooterId != null && command != null) {
          if (_scooters.containsKey(scooterId)) {
            // Update mock scooter state based on command
            final scooter = _scooters[scooterId]!;
            Scooter updatedScooter;
            
            switch (command) {
              case 'lock':
                updatedScooter = scooter.copyWith(
                  handlebarsLocked: true,
                );
                break;
                
              case 'unlock':
                updatedScooter = scooter.copyWith(
                  handlebarsLocked: false,
                );
                break;
                
              case 'openSeat':
                updatedScooter = scooter.copyWith(
                  seatClosed: false,
                );
                break;
                
              default:
                return {'success': false, 'error': 'Unknown command'};
            }
            
            // Update the mock scooter
            _scooters[scooterId] = updatedScooter;
            
            // Notify any listeners
            if (_updateControllers.containsKey(scooterId)) {
              _updateControllers[scooterId]!.add(updatedScooter);
            }
            
            return {'success': true};
          }
          return {'success': false, 'error': 'Scooter not found'};
        }
        return {'success': false, 'error': 'Invalid request'};
        
      default:
        return {'success': false, 'error': 'Unknown endpoint'};
    }
  }
  
  @override
  Stream<Scooter> getScooterUpdateStream(String scooterId) {
    if (!_updateControllers.containsKey(scooterId)) {
      _updateControllers[scooterId] = StreamController<Scooter>.broadcast();
    }
    
    return _updateControllers[scooterId]!.stream;
  }
  
  @override
  Future<bool> authenticate({
    required String username, 
    required String password,
  }) async {
    _logger.info('Mock authenticating with cloud');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 700));
    
    // Mock authentication - always succeeds
    _isConnected = true;
    return true;
  }
  
  @override
  Future<void> logout() async {
    _logger.info('Mock logging out from cloud');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 300));
    
    _isConnected = false;
  }
  
  @override
  Future<bool> validateSession() async {
    _logger.info('Mock validating cloud session');
    
    // Simulate some delay
    await Future.delayed(const Duration(milliseconds: 200));
    
    return _isConnected;
  }
  
  /// Updates a mock scooter (for testing)
  void updateMockScooter(Scooter scooter) {
    _scooters[scooter.id] = scooter;
    
    // Notify any listeners
    if (_updateControllers.containsKey(scooter.id)) {
      _updateControllers[scooter.id]!.add(scooter);
    }
  }
}