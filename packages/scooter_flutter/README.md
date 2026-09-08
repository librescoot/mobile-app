# scooter_flutter

Shared Flutter/device integration, consumed through local path dependencies by
separate single-app repositories. This package contains no screens or branding.

The package now owns `FlutterBluePlusMockable`, `BleScanner`, the plugin-bound
`ScooterCandidate`, characteristic subscription setup and the
ChangeNotifier-based `StateWaiter`. Discovery filtering and scan lifecycle are
covered by hardware-free adapter tests; legacy app imports remain forwarding
exports. The waiter remains here, not in
`scooter_core`, because its current API depends on Flutter. Connection ownership,
background services and persistence still reside in the application until their
behavior is characterized and their dependencies can be injected.

This is not yet a platform-neutral transport API. Plugin types in the existing
BLE wrapper remain adapter details and must not enter `scooter_core` contracts.
`ScooterCandidate` still carries `BluetoothDevice` and legacy display helpers;
it is an adapter DTO, not the future platform-neutral core discovery snapshot.

```sh
flutter pub get
flutter analyze
flutter test
```
