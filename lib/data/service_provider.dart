import '../domain/repositories/scooter_repository.dart';
import '../domain/services/ble_service.dart';
import '../domain/services/cloud_service.dart';
import '../domain/services/local_storage_service.dart';
import '../flutter/blue_plus_mockable.dart';
import 'repositories/scooter_repository_impl.dart';
import 'services/flutter_blue_service.dart';
import 'services/mock_cloud_service.dart';
import 'services/shared_prefs_storage_service.dart';

/// Service provider for dependency injection
class ServiceProvider {
  static final ServiceProvider _instance = ServiceProvider._internal();
  
  factory ServiceProvider() {
    return _instance;
  }
  
  ServiceProvider._internal();
  
  // Services
  BleService? _bleService;
  CloudService? _cloudService;
  LocalStorageService? _storageService;
  
  // Repositories
  ScooterRepository? _scooterRepository;
  
  /// Get the BLE service
  BleService getBleService(FlutterBluePlusMockable flutterBlue) {
    _bleService ??= FlutterBlueService(flutterBlue);
    return _bleService!;
  }
  
  /// Get the cloud service
  CloudService getCloudService() {
    _cloudService ??= MockCloudService();
    return _cloudService!;
  }
  
  /// Get the local storage service
  LocalStorageService getStorageService() {
    _storageService ??= SharedPrefsStorageService();
    return _storageService!;
  }
  
  /// Get the scooter repository
  ScooterRepository getScooterRepository(FlutterBluePlusMockable flutterBlue) {
    _scooterRepository ??= ScooterRepositoryImpl(
      bleService: getBleService(flutterBlue),
      cloudService: getCloudService(),
      storageService: getStorageService(),
    );
    return _scooterRepository!;
  }
}