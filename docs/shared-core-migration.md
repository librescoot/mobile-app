# Shared core migration

## Repository model

Unustasis and Librescoot remain separate, single-app repositories. Each keeps
local copies of `packages/scooter_core` and `packages/scooter_flutter`, consumed
through path dependencies. Shared-package changes should be separate commits
from presentation changes and synchronized between repositories. Do not add a
second app directory or introduce app-brand conditionals in shared behavior.

The extraction branch starts at design-refresh `0f2bafc`. This is an incremental
migration, not a completed replacement of the backend.

## First testable slice

- `lib/main.dart`: entry point delegating to `bootstrap()`.
- `lib/bootstrap.dart`: existing initialization and Provider composition.
- `lib/app.dart`: app identity, routes, localization, theme and lifecycle binding.
- `lib/ui/{screens,sheets,dialogs,widgets,theme}`: existing presentation, moved
  without redesign. Native projects and assets stay at the repository root.
- `packages/scooter_core`: OTA protocol/planner, duration/schedule handling and
  alarm wake-source decoding. Runtime implementations retain their behavior.
- `packages/scooter_flutter`: existing FlutterBluePlus wrapper and
  ChangeNotifier-based StateWaiter, unchanged.
- Legacy domain/service import paths forward to the shared packages so callers
  can migrate independently without duplicate implementations or type identity.

The UI still consumes the existing ScooterService. Most backend logic still
lives in root `lib/service`, `lib/state`, `lib/infrastructure` and `lib/background`.
These are **migration debt**, not the target shared-package boundary. Some domain
models still mix presentation or storage concerns, and UI still has direct BLE
accesses. The OTA planner still returns legacy localization keys; replace these
with typed warnings in a later API migration, not during the mechanical move.

## Target dependency rules

1. `scooter_core` imports neither Flutter, plugins nor application code.
2. `scooter_flutter` may depend on core and plugins, never app UI or assets.
3. Application composition supplies identity, resources and presentation policy.
4. Firmware capabilities are not app-brand flags.
5. Keep Provider while extracting behavior; do not also replace state management.
6. Exactly one implementation owns connection coordination in each executing
   isolate. Compatibility facades must delegate, not start a second engine.

## State model extraction (next slice)

Scooter aggregate/vehicle/power state and alarm status belong in core, including
wire parsing, aggregation and action predicates. Localized labels, descriptions
and colors belong in `lib/ui/presentation`. Legacy domain files re-export both
for screen compatibility; backend callers import core directly, avoiding a
transitive dependency on UI extensions. Preserve enum names/order and parsing
semantics because callers persist and transmit these values.

The former `infrastructure/utils.dart` split follows the same boundary:
`subscribeCharacteristic` lives in `scooter_flutter`; localized relative-time
formatting lives in `ui/presentation/relative_time.dart`. Reader code imports the
adapter directly rather than pulling UI formatting into the backend.

Architecture tests prevent extracted packages from importing application code
or escaping their own library directories, and prevent Flutter/plugin imports
from entering the pure core.

## Remaining slices

1. Characterize connection intent/attempt generations, manual-target pinning,
   same-device supersession, stale reads/probes/disconnects, lifecycle behavior,
   background suppression and retry ownership using injected transport/time.
2. Extract immutable domain state without UI/localization methods. Expose
   session-targeted typed commands/results and explicitly ordered snapshots.
3. Extract connection ownership behind the ScooterService compatibility facade;
   remove each old implementation as its delegate becomes active.
4. Extract command protocols and workflows, preserving subscribe-before-write
   buffering, extended-channel serialization, wake deadlines and cleanup.
5. Extract storage/background/navigation/activity/update adapters with fixtures
   for existing preference keys, enum strings, timestamps and widget payloads.
6. Migrate screens away from characteristics and mutable service internals;
   remove the compatibility facade only when no caller needs its escape hatches.

Retain Android/iOS application IDs, signing identities, widget groups, background
entry points and existing storage schemas throughout. The iOS widget's native
BLE implementation remains an explicit exception requiring its own contract and
hardware tests; Dart extraction does not replace it.

## Next connection seam

Do not move the constructor's side effects into a new core constructor. The live
ScooterService currently restores storage asynchronously, observes lifecycle,
subscribes to scan state and starts heartbeat/location/RSSI/refresh timers during
construction. Before extracting that owner, introduce explicit initialization
and disposal tests with injected adapters. Preserve foreground/background
runtime ownership rather than starting a parallel service to satisfy new APIs.

A transport fake must control connect, bond, disconnect, characteristic discovery
and late callback completion independently for two IDs (including two attempts
for the same ID). Fake time must control heartbeat, retry and wake deadlines.
The first gates are ordered traces of existing behavior, not a rewritten
connection algorithm. A stale attempt completing after another intent must not
publish linking/connected state, replace subscriptions or disconnect the newer
owner. This remains a separate migration slice from extracting enum models.

## Validation

Run all suites (root `flutter test` does not run package tests):

```sh
(cd packages/scooter_core && dart pub get && dart analyze && dart test)
(cd packages/scooter_flutter && flutter pub get && flutter analyze && flutter test)
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

CI runs the package suites before the app suite. Compare combined test counts,
not just the root count, because extracted tests move with their implementation.

Before calling the larger migration complete, smoke-test the redesign on-device:
startup and locale/theme persistence, scooter switching, odometer visibility,
settings, activity-log controls, wake-and-unlock, background reconnect and widgets.
For Hubert, never operate the seatbox. Hardware availability and a passing APK
build are different gates; neither implies the other.
