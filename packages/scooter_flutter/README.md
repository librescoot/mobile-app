# scooter_flutter

Shared Flutter/device integration, consumed through local path dependencies by
separate single-app repositories. This package contains no screens or branding.

The first extraction preserves `FlutterBluePlusMockable` and the
ChangeNotifier-based `StateWaiter` unchanged. The waiter remains here, not in
`scooter_core`, because its current API depends on Flutter. Connection ownership,
background services and persistence still reside in the application until their
behavior is characterized and their dependencies can be injected.

This is not yet a platform-neutral transport API. Plugin types in the existing
BLE wrapper remain adapter details and must not enter `scooter_core` contracts.
There is no core dependency yet; add it when an adapter implements a core port.

```sh
flutter pub get
flutter analyze
flutter test
```
