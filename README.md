# Librescoot App for unu

The Librescoot-branded build of the community app for the unu Scooter Pro.

This is a rebrand of [reunu/unustasis](https://github.com/reunu/unustasis) ("stasis for unu"),
tracking it closely. All app development happens upstream; this repository carries
only the Librescoot branding on top, plus the release pipeline that publishes to
Google Play and TestFlight.

The Android app and the main iOS bundle ship as `org.librescoot.mobile.unu`, so
they install alongside the upstream build rather than replacing it.

## Keeping in sync

The branding lives in a single commit on top of upstream `main`. To take new
upstream work:

```bash
git fetch upstream                      # git@github.com:reunu/unustasis.git
git rebase --onto upstream/main <previous-upstream-main> main
```

Resolve conflicts in favour of upstream for anything that is not a brand string
or an identifier. Never merge upstream into this branch: the history is meant to
stay a thin, rebasable layer.

## Getting Started

### Using this app

If you just want to use this app, go into the "Releases" section on this page and download the latest APK file. The app is also available as proe-release through Google Play and Apple TestFlight, but that will change shortly.

### Building this app yourself

This app is made in Flutter for cross-platform functionality, UI performance, and rapid development. To build it on your system, [follow this getting-started guide](https://docs.flutter.dev/get-started/install) to install the Flutter SDK and required Android or iOS SDKs.

Run the following command in the root of this project to install and start the development version on your device:

```
flutter run
```

### Contributing

Interested in contributing? Join the [Librescoot Discord](https://discord.gg/BmY2P2T9j3) or create an issue right here on GitHub!
Pull requests are also very welcome, as my test devices are pretty limited and therefore I depend on any help I can get.



