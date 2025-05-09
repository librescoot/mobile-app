import '../models/scooter.dart';

/// Represents an API request to the cloud service
class ApiRequest {
  /// The endpoint to target
  final String endpoint;
  
  /// The data to send
  final Map<String, dynamic> data;
  
  ApiRequest({required this.endpoint, required this.data});
}

/// Service interface for cloud operations
abstract class CloudService {
  /// Checks if cloud connectivity is available
  bool isAvailable();
  
  /// Checks if currently authenticated to the cloud
  bool isConnected();
  
  /// Connects to the cloud service for a specific scooter
  Future<void> connect(String scooterId);
  
  /// Gets the current state of a scooter from the cloud
  Future<Scooter?> getScooter(String scooterId);
  
  /// Gets all scooters accessible to the current user
  Future<List<Scooter>> getAllScooters();
  
  /// Sends a request to the cloud API
  Future<dynamic> sendRequest(ApiRequest request);
  
  /// Stream of state updates for a specific scooter
  Stream<Scooter> getScooterUpdateStream(String scooterId);
  
  /// Authenticates with the cloud service
  Future<bool> authenticate({
    required String username, 
    required String password,
  });
  
  /// Logs out from the cloud service
  Future<void> logout();
  
  /// Checks if the current session is valid
  Future<bool> validateSession();
}