import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:unustasis/service/onboarding_permissions.dart';

class _Gateway implements OnboardingPermissionGateway {
  _Gateway.android(this.sdk)
      : isAndroid = true,
        isIOS = false;
  _Gateway.ios()
      : sdk = 0,
        isAndroid = false,
        isIOS = true;

  final int sdk;
  @override
  final bool isAndroid;
  @override
  final bool isIOS;
  final statuses = <Permission, PermissionStatus>{};
  final requested = <Permission>[];
  int settingsOpens = 0;

  @override
  Future<int> get androidSdk async => sdk;

  @override
  Future<PermissionStatus> request(Permission permission) async {
    requested.add(permission);
    return statuses[permission] ?? PermissionStatus.granted;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpens++;
    return true;
  }
}

void main() {
  test('Android below API 31 requires location and no runtime Bluetooth access', () async {
    final gateway = _Gateway.android(30)..statuses[Permission.locationWhenInUse] = PermissionStatus.permanentlyDenied;
    final controller = PlatformOnboardingPermissionController(gateway: gateway);

    final result = await controller.requestPermissions();

    expect(gateway.requested, [Permission.locationWhenInUse]);
    expect(result.nearbyDevicesGranted, true);
    expect(result.locationRequiredForScanning, true);
    expect(result.requiredPermissionsGranted, false);
    expect(result.notificationsGranted, true);
    expect(result.canOpenSettings, true);
  });

  test('Android API 31 requests nearby access while location stays optional', () async {
    final gateway = _Gateway.android(31)..statuses[Permission.locationWhenInUse] = PermissionStatus.denied;
    final controller = PlatformOnboardingPermissionController(gateway: gateway);

    final result = await controller.requestPermissions();

    expect(gateway.requested, [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ]);
    expect(result.nearbyDevicesGranted, true);
    expect(result.locationRequiredForScanning, false);
    expect(result.locationGranted, false);
    expect(result.requiredPermissionsGranted, true);
    expect(result.notificationsGranted, true);
  });

  test('Android API 33 includes optional notification access', () async {
    final gateway = _Gateway.android(33)
      ..statuses[Permission.notification] = PermissionStatus.denied
      ..statuses[Permission.bluetoothScan] = PermissionStatus.denied;
    final controller = PlatformOnboardingPermissionController(gateway: gateway);

    final result = await controller.requestPermissions();

    expect(gateway.requested, [
      Permission.notification,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ]);
    expect(result.notificationsGranted, false);
    expect(result.nearbyDevicesGranted, false);
    expect(result.requiredPermissionsGranted, false);
  });

  test('iOS requests notification, Bluetooth, and when-in-use location access', () async {
    final gateway = _Gateway.ios()
      ..statuses[Permission.bluetooth] = PermissionStatus.permanentlyDenied
      ..statuses[Permission.locationWhenInUse] = PermissionStatus.limited;
    final controller = PlatformOnboardingPermissionController(gateway: gateway);

    final result = await controller.requestPermissions();

    expect(gateway.requested, [
      Permission.notification,
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ]);
    expect(result.nearbyDevicesGranted, false);
    expect(result.locationGranted, true);
    expect(result.locationRequiredForScanning, false);
    expect(result.canOpenSettings, true);
    expect(await controller.openSettings(), true);
    expect(gateway.settingsOpens, 1);
  });
}
