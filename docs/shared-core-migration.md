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

## Discovery, response protocol and settings slices

- BLE discovery and its plugin-bound candidate DTO now live in
  `scooter_flutter`. Legacy scanner/candidate imports forward to the same types.
  Tests cover filters, startup failure, cancellation and missing stop events.
- Extended-response buffering, counted-list decoding and capability-entry
  parsing now live in core (`extended_response.dart`). Command serialization
  and characteristic access remain in the application for the next slices.
- `UserSettings` storage now lives in `scooter_flutter`, accepting preferences
  and an update callback. The root compatibility subclass alone chooses whether
  to invoke foreground-to-background messages. Mutable fields, storage keys,
  defaults, inverted biometrics and write-before-notification order remain.
- Keyless distance thresholds and lookup belong in core; localized labels and
  dBm display formatting belong in app presentation extensions. Invalid threshold
  lookup still throws rather than silently changing existing behavior.

## Telemetry reader boundary

Byte decoding is pure core (`characteristic_values.dart`): string normalization,
strict uint32 values and padded odometer decoding. The current odometer's unsigned
32-bit interpretation is retained rather than changing the wire contract during
extraction. Battery type/charging enums are also core; labels, SOC text and image
paths remain app presentation extensions.

Characteristic readers/subscriptions and `CharacteristicRepository` discovery
live in `scooter_flutter`. Repository tests pin service/characteristic matching,
optional OTA/alarm groups, missing fields and propagated discovery failures;
the app's legacy repository import forwards the same type. The live state objects and their subscription lifetimes now also live in the
adapter's telemetry runtime (see below), guarded by the sole session's captured
connection token. Compatibility mutable views remain for current app callers;
new consumers can use copied pure telemetry snapshots instead.

## Persistence characterization gate

The saved-scooter and storage suites exercise the actual implementations with
in-memory preference/background adapters. They pin JSON fields, microsecond
precision, nullable flags, auto-connect behavior and stale-instance resurrection
protection. Shared fakes live under `test/support`.

Storage operations now live in generic `scooter_flutter.ScooterStorage<T>`,
bounded by pure `SavedScooterRecord`. App factories supply the existing model and
default display name through a zero-argument compatibility subclass. The model's
JSON implementation, setter side effects, background notifications, navigation
and geocoding dependencies remain app-owned. The original 33 tests remain intact;
nine adapter tests exercise custom factories and the shared storage independently.

Some tests intentionally characterize existing flaws rather than endorse them:
a malformed entry aborts later entries, a missing preference can preserve stale
local entries, adding before loading can replace persisted data, and recoloring
an unknown scooter can remain memory-only. Fix those in explicit behavior-change
commits with updated regression expectations, not incidentally during relocation.

## Command transport boundary

ASCII command writes and single-response extended commands live in
`scooter_flutter/command_transport.dart`, re-exported through the legacy app API.
The adapter owns one shared extended-channel FIFO. App-side capabilities,
keycards and destination-list consumers enter that same queue; they must not
create independent queues while sharing the response characteristic.

Sixteen app tests cover validation, write flags/errors, notification reuse,
listen-before-write, mixed single/list FIFO ownership, response/notify failures
and timeout cleanup. Silent and closed streams are exercised with a fake clock;
stream closure currently waits for the ten-second timeout. A pending write or
notification enable is not bounded by that response timeout, and the transport
does not observe device-disconnect events directly. Those remain separate risks,
not behaviors silently changed by extraction.

Three adapter tests pin generic queue results and failure recovery. Version,
capability and generic setting queries now live in `firmware_queries.dart`, with
ten adapter tests for response prefixes, unsupported/empty values and exact
setting acknowledgements. Legacy command imports continue forwarding these APIs.
Navigation models, activity logging and higher-level command policy remain
app-owned.

## Next connection seam

The first executable connection seam is now in place: ScooterService accepts
optional storage, device and characteristic-repository factories, with unchanged
production defaults. `initializeRuntime: false` supports manually driven tests
without cache restoration, observers or timers; it does not bypass the actual
connection method. The runtime scan subscription is retained and cancelled on
disposal. Runtime-disabled instances do not initialize the public RSSI timer.

Twenty-four tests cover disabled-runtime lifecycle, manual row/intent publication,
obsolete automatic intent, immediate A/B requests and overlapping attempts with
late older success/failure, including distinct wrappers for one device and three
calls reusing one wrapper. They reproduce ownership failures fixed by an explicit
per-call attempt record and a validity check before publishing linking state.
Cleanup protects newer physical links by remote ID and explicit attempt ownership,
not wrapper identity or a changed generation alone. Disposal releases both pending
and published transports; regressions cover replacement-before-device-creation
and a connection completing after disposal.

The harness now also completes real characteristic setup and connection-state
subscription with fake transports, including stale success/failure after the newer
connection exits `finally`. Current disconnect events clear the connected state;
obsolete streams are cancelled. Injected location polling retains its production
default, with tests for current, superseded and disconnected location results.
Android bonding/priority, iOS widget calls and service-level late capability probes
still need coverage. Twenty-one separate identity tests pin caller-supplied nRF
and odometer freshness predicates, but do not prove the service supplies a correct
predicate for every session/disconnect transition.

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

## Shared connection/session owner

`ScooterService` now delegates connection, startup and retry orchestration to one
`scooter_flutter.ScooterSession` per service/isolate. The adapter owns manual
intent, per-call attempt identity, pending/published transports, linking-row ID,
connected flag, cancellation of connection-state listeners, scan-stop/connect,
Android bond/priority ordering, repository discovery, same-physical-ID stale
cleanup, and the single three-second retry loop. There are no duplicate intent,
attempt or retry counters/loops in the facade. Construction of this owner is
inert; the existing facade alone initializes runtime observers and timers.

Nine concrete phase effects retain app ownership of manual-target background
messages, telemetry cancellation/wiring, cached linking/model publication,
persistence, the iOS widget group/payload, ready metadata/location/background
publication, and disconnected state/ping publication. The ordered ready metadata
and ready effects intentionally straddle the connected notification. Widget
identity, saved model/storage schema, navigation, external background suppression,
lifecycle policy, location and heartbeat/RSSI/refresh timers remain app-owned.
The repository factory and device/platform/deadline seams have production defaults;
no plugin work or Flutter dependency was added to core.

Captured `SessionConnection` tokens supply freshness to shared nRF/odometer,
capability probes and app location results. They expire on replacement, disconnect or
disposal, not when connect's `finally` releases its pending slot. Checks after
phase publications also prevent synchronous listeners from continuing an obsolete
connection. A bounded correction to the inherited algorithm preserves a same-ID
manual no-op triggered during ready publication: only the exact still-current
pending/published owner may adopt that intent, rather than disconnecting the link
it has just published. Two regressions failed before that correction and pass
with it; a newer different-ID intent cannot adopt/revive the old owner.

The original 24 real-service connection tests are unchanged and execute the shared
owner via the facade, including actual app telemetry wiring and location effects.
32 additional adapter tests cover ordered Android bond reuse/creation and priority
failure, supersession at each Android await, iOS hook ordering/disposal, distinct
and reused same-ID wrappers, three overlapping calls, late errors/success and
cleanup, discovery failure, synchronous publication reentrancy, session freshness
(including same-ID linking before its transport exists), obsolete startup/manual
intent, and virtual-clock retry/listener/disposal ownership.
The combined suite is now 349 tests (135 app, 98 core, 116 adapter).

This is not the remaining storage/background/lifecycle extraction. Runtime-enabled
cache restoration and native widget/BLE behavior still need device smoke tests;
late startup adapter/scan waits retain their existing underlying transport timeout
behavior. A passing APK build does not validate hardware bonding or widgets.

## Shared live telemetry runtime (milestone 1)

`ScooterTelemetry` in `scooter_flutter/scooter_telemetry.dart` now owns actual
battery/vehicle subscriptions, firmware identity reads, odometer refresh, the
six sequential capability probes and aggregate-state publication. It has no
connect/start/retry API and no connection-generation counter: every binding uses
the existing `SessionConnection`, including same-ID replacement, disconnect and
disposal freshness. `invalidate()` cancels subscriptions; local subscription
lifetime guards also reject callbacks already handed to a dispatch queue before
cancellation. Every battery/vehicle callback checks freshness **before mutation**.
Reads and probes check before mutation and after reentrant effect publications.

Pure core `telemetry.dart` provides copied battery/vehicle/firmware snapshots,
nullable cached telemetry seeds/partial patches, USB mode and alarm-trigger
parsing. Snapshots carry captured scooter ID, session generation and monotonic
publication revision; no stream or second mutable app copy was introduced.
Null cache-patch fields mean unchanged, so known false and zero are persisted.
Only hibernate-for and APN capabilities are cached, as before. The two probe
setting-key constants have one shared definition and legacy command exports.

The app facade supplies typed effects for captured-ID SavedScooter patches,
ping/notification, firmware-ready pending-navigation dispatch, navigation clearing,
aggregate-transition cooldown and probe logging. Name/color/location/last-ping/RSSI
remain app presentation/polling metadata in a small `ScooterIdentity` subclass;
its firmware fields/read methods are inherited from shared `FirmwareIdentity`.
Legacy battery/vehicle paths are exports, not duplicate implementations.
`_subscribeToAllCharacteristics`, `_probeLsCapabilities`, aggregate computation
and odometer-read wiring have been removed from the facade. Shared packages import
no app code and have no new dependencies. Actions, navigation execution, OTA,
lifecycle/polling, native widget identities and background scheduling are unchanged.

Preserved contracts include cache-before-ping/notify, aggregate notification then
ping then cooldown effect, nRF cache then firmware-ready dispatch then probes,
false-on-failure/stock firmware, empty-but-supported setting values, optional
power/UMS/navigation/alarm groups, unknown USB retaining its prior value, alarm
parsing, and CBB integer microvolt/microamp-hour to millivolt/milliamp-hour
conversion. Cache refetch updates persisted levels (and handlebars when a record
exists) without turning it into a new-link reset. Linking clears the original
live-only fields and resets capabilities to the two cached flags; odometer resets
at transport-ready, preserving the original phase. Alarm values retain their
inherited cache-seed behavior (not cleared); correcting that is not bundled into
this extraction.

**Explicit bounded correctness fix, not just relocation:** a test run against
HEAD's app implementations reproduced a cancelled battery callback overwriting
SOC with 42 after cancellation (expected null). The same test now runs against
the shared implementations and passes. The fix rejects cancelled and obsolete
callbacks before they mutate state or patch any saved scooter, rather than only
suppressing the facade's notification. Original failure evidence is retained in
`/tmp/telemetry-before.log`; the final regression is
`packages/scooter_flutter/test/telemetry_stale_reproduction_test.dart`.

The original **24 real-service connection tests and 21 identity tests are
unchanged**, still executing the actual shared implementations through app
compatibility paths. Added coverage: 35 adapter telemetry tests for queued A/B
and same-ID callbacks, disconnect/disposal/invalidation, all battery conversions,
vehicle aggregates/optional groups, cache/refetch reset phases, copied snapshots,
real shared extended-channel successful probes and missing-channel failure,
all six delayed probe positions, stale errors, and reentrant cache/firmware/
notification effects. Four core tests pin values/parsing; one app architecture
test prevents telemetry algorithms returning to the facade.

Final suites: **389 tests (136 app, 102 core, 151 adapter)**, up from 349
(135/98/116). All three analyses passed with Flutter/Dart from
`/tmp/flutter-sdk-3.41.9/bin`; Android debug APK passed with
`ASDF_JAVA_VERSION=temurin-17.0.13+11`. No device operations were performed. Hardware
BLE/notifications, bonding, widgets, runtime-enabled cache restoration and native
background behavior remain smoke-test gates; APK compilation is not that gate.
Outstanding action/navigation/OTA/lifecycle milestones and the existing extended
query timeout/cancellation policy are intentionally unchanged.

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
