# scooter_core

Pure Dart scooter domain logic with no runtime dependencies or Flutter imports.
Import `package:scooter_core/scooter_core.dart` or the individual public libraries:
`ota_protocol.dart`, `update_planner.dart`, `go_duration.dart`,
`hibernation_schedule.dart`, and `alarm_wake_sources.dart`.

This first extraction contains OTA wire encoding/decoding and release planning,
Go duration conversion, hibernation cron schedules, and alarm wake-source parsing.
Implementations and APIs are preserved; the app's legacy domain libraries forward
to these same declarations rather than wrapping or duplicating types.

Transport, BLE plugins, persistence, application state, widgets, and localization
rendering remain outside this package. Planner warning localization keys and
parameters are temporarily retained for compatibility; presentation resolves them.
Do not add Flutter, plugin, or application-layer dependencies here.

Run independently from this directory:

```sh
dart pub get
dart analyze
dart test
```
