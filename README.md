# Librescoot App for unu

Part of the [Librescoot](https://librescoot.org/) open-source platform.

A Flutter app for the unu Scooter Pro. It connects to the scooter over Bluetooth Low Energy (BLE) to show vehicle status and provide controls. The app builds on the [Unustasis project](https://github.com/reunu/unustasis).

## Capabilities

The app works over BLE with the unu Scooter Pro; it does not require a cloud account for vehicle controls.

- **Vehicle and access:** Pair and manage multiple scooters; view vehicle and lock state, main and auxiliary battery details, estimated range and odometer; lock, unlock and open the seatbox. Control turn signals, wake and hibernate the scooter, and access supported reboot controls.
- **Keyless use:** Automatically unlock when in range, choose a proximity threshold, optionally open the seatbox on unlock and flash the hazard lights when locking. Android can scan in the background and show scooter notifications; Android and iOS have home-screen widgets.
- **Riding and navigation:** View a driving display and scooter location, search or save destinations and send navigation to the scooter. On compatible Librescoot firmware, edit a multi-stop route (add, reorder, skip and remove stops) and view the ride counter with distance, riding time and average speed.
- **Librescoot administration:** Add, name and remove keycards; set up an Android NFC phone key, list and remove enrolled phones, and name unlock cards, master cards and phones on compatible scooters. Manage alarm and honk settings, auto-standby and auto-hibernation timers, scheduled hibernation, battery keep-active and cellular APN. Check installed system versions, synchronize the clock, select USB update mode or service mode, and check for and install supported firmware updates over BLE.
- **App settings and integrations:** Choose light, dark or system theme and app language; use biometric protection where available. Android supports Tasker actions. A temporary demo mode lets you explore the interface without connecting to a scooter.

Features that change vehicle settings, route plans or firmware require a connected scooter with the corresponding Librescoot software and advertised capabilities. Platform-specific integrations require a supported Android or iOS device.

### NFC phone keys and credential names

On an Android device with NFC host card emulation, open the app's Keycards screen and set up a device-bound phone key. Tap an existing master card on the scooter to enter learning mode, present the unlocked phone with NFC and its screen on, then tap the master again to save the key. Keep the phone unlocked with its screen and NFC on for future taps. NFC unlock works independently of BLE.

When connected over BLE to a scooter advertising `keycard=2`, the app can list and remove enrolled phones and name cards (including masters) and phones. Names are stored on the scooter as display labels. Scooter names take precedence over older app-local card names; valid local names for enrolled cards without a scooter name are imported. If an Android app installation or its device-bound key is lost, revoke the old phone fingerprint from the scooter and enroll a new one. Physical card exports contain card UIDs.

### What this app adds

- **Over [Unustasis](https://github.com/reunu/unustasis):** Capability-gated multi-stop route planning, a ride counter with reset and retention settings, Android Tasker actions and a redesigned multi-scooter interface.
- **Over [unu-app](https://github.com/reunu/unu-app):** All of the above, plus Librescoot-specific controls for keycards, alarms, power timers, APN and firmware updates, and navigation. Both apps provide basic BLE controls and keyless unlocking.

## Installation

Android APKs are available from this repository's [releases](https://github.com/librescoot/mobile-app/releases). Android testing builds are also distributed through Google Play, and iOS testing builds through TestFlight.

The Android package and main iOS bundle use `org.librescoot.mobile.unu`, allowing installation alongside Unustasis.

## Build and test

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and the platform tools for Android or iOS. From the repository root:

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

For release automation and distribution details, see [RELEASING.md](RELEASING.md).

## Contributing

Issues and contributions are welcome in the [mobile-app repository](https://github.com/librescoot/mobile-app). Join the [Librescoot community on Discord](https://discord.gg/BmY2P2T9j3), or [learn more about Librescoot](https://librescoot.org/).

## License

This project is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](LICENSE).

Made with ❤️ by the Librescoot community
