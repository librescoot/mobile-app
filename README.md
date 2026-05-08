<p align="center">
  <img src="images/librescoot_logo.png" width="200" alt="Librescoot logo">
</p>

<h1 align="center">Librescoot mobile app</h1>

<p align="center">
  This is the <a href="https://github.com/reunu/unustasis">unustasis</a> app with Librescoot adaptations.<br>
  Open-source, BLE-only companion app for the unu Scooter Pro.
</p>

<p align="center">
  <a href="https://librescoot.org">librescoot.org</a> ·
  <a href="https://discord.gg/BmY2P2T9j3">Discord</a> ·
  <a href="../../releases/latest">Latest release</a>
</p>

---

## Install

- **Android APK** — grab the latest build from [Releases](../../releases/latest) and side-load it.
- **Google Play** / **iOS TestFlight** — pre-release builds may be available; ask in Discord for current status.

The app needs Bluetooth, location (Android requires it for BLE scanning), and notification permissions.

## Build

Flutter app targeting Android and iOS. Follow the [Flutter install guide](https://docs.flutter.dev/get-started/install) for the SDK and platform toolchains.

Pinned: Flutter `3.38.6`, Dart SDK `>=3.5.0 <4.0.0` (see `pubspec.yaml`).

```bash
git clone https://github.com/librescoot/mobile-app.git
cd mobile-app
flutter pub get
flutter run
```

Release APK:

```bash
flutter build apk --release
```

iOS builds need Xcode and a paid Apple developer account for on-device runs.

## Project layout

```
lib/                         # Dart source
assets/i18n/                 # translation JSON files
assets/faq_*.json            # in-app FAQ content
images/                      # scooter sprites, battery icons, decoration
android/, ios/               # platform projects
```

## Contributing

- **Bugs and feature requests:** open a [GitHub issue](../../issues).
- **Chat:** [Librescoot Discord](https://discord.gg/BmY2P2T9j3).
- **Translations:** edit `assets/i18n/<lang>.json` and the matching `assets/faq_<lang>.json`. Run `dart run build_runner build` if you touch annotated classes.
- Run `flutter analyze` before opening a PR.

## Upstream

Fork of [reunu/unustasis](https://github.com/reunu/unustasis). The upstream history is preserved in `git log`.

## License

See [LICENSE](LICENSE).
