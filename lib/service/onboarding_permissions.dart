import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingPermissionSummary {
  const OnboardingPermissionSummary({
    required this.nearbyDevicesGranted,
    required this.notificationsGranted,
    required this.locationGranted,
    required this.locationRequiredForScanning,
    required this.canOpenSettings,
  });

  final bool nearbyDevicesGranted;
  final bool notificationsGranted;
  final bool locationGranted;
  final bool locationRequiredForScanning;
  final bool canOpenSettings;

  bool get requiredPermissionsGranted => nearbyDevicesGranted && (!locationRequiredForScanning || locationGranted);
}

abstract interface class OnboardingPermissionController {
  Future<OnboardingPermissionSummary> requestPermissions();
  Future<bool> openSettings();
}

/// Injectable boundary around the platform and permission-handler plugin.
abstract interface class OnboardingPermissionGateway {
  bool get isAndroid;
  bool get isIOS;
  Future<int> get androidSdk;
  Future<PermissionStatus> request(Permission permission);
  Future<bool> openSettings();
}

class PlatformOnboardingPermissionGateway implements OnboardingPermissionGateway {
  PlatformOnboardingPermissionGateway({DeviceInfoPlugin? deviceInfo}) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  bool get isIOS => Platform.isIOS;

  @override
  Future<int> get androidSdk async => (await _deviceInfo.androidInfo).version.sdkInt;

  @override
  Future<PermissionStatus> request(Permission permission) => permission.request();

  @override
  Future<bool> openSettings() => openAppSettings();
}

class PlatformOnboardingPermissionController implements OnboardingPermissionController {
  PlatformOnboardingPermissionController({OnboardingPermissionGateway? gateway})
      : _gateway = gateway ?? PlatformOnboardingPermissionGateway();

  final OnboardingPermissionGateway _gateway;

  static bool _isGranted(PermissionStatus status) => status.isGranted || status.isLimited;

  @override
  Future<OnboardingPermissionSummary> requestPermissions() async {
    var notificationStatus = PermissionStatus.granted;
    var locationStatus = PermissionStatus.granted;
    var nearbyGranted = true;
    var nearbyBlocked = false;
    var locationRequiredForScanning = false;

    if (_gateway.isAndroid) {
      final sdk = await _gateway.androidSdk;
      locationRequiredForScanning = sdk < 31;
      if (sdk >= 33) {
        notificationStatus = await _gateway.request(Permission.notification);
      }
      if (sdk >= 31) {
        final scanStatus = await _gateway.request(Permission.bluetoothScan);
        final connectStatus = await _gateway.request(Permission.bluetoothConnect);
        nearbyGranted = _isGranted(scanStatus) && _isGranted(connectStatus);
        nearbyBlocked = scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied;
      }
      locationStatus = await _gateway.request(Permission.locationWhenInUse);
    } else if (_gateway.isIOS) {
      notificationStatus = await _gateway.request(Permission.notification);
      final bluetoothStatus = await _gateway.request(Permission.bluetooth);
      nearbyGranted = _isGranted(bluetoothStatus);
      nearbyBlocked = bluetoothStatus.isPermanentlyDenied;
      locationStatus = await _gateway.request(Permission.locationWhenInUse);
    }

    return OnboardingPermissionSummary(
      nearbyDevicesGranted: nearbyGranted,
      notificationsGranted: _isGranted(notificationStatus),
      locationGranted: _isGranted(locationStatus),
      locationRequiredForScanning: locationRequiredForScanning,
      canOpenSettings: nearbyBlocked || notificationStatus.isPermanentlyDenied || locationStatus.isPermanentlyDenied,
    );
  }

  @override
  Future<bool> openSettings() => _gateway.openSettings();
}
