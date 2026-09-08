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


## Shared session-targeted actions and keyless lifecycle (milestone 2)

`ScooterActions` now executes the live facade and settings/keycard/USB UI calls
in `scooter_flutter`, using the **existing** `ScooterSession` and
`ScooterTelemetry`. Each action captures its `SessionConnection`, repository,
immutable settings, SOC and supplied location once. Binding/invalidation are
wired through the existing session phase effects; there is no new connection
owner, generation, retry loop, or basic-action serialization. Delayed steps and
queued extended writes check the captured token, including same-ID replacement.
All extended single/list operations still use the one existing transport FIFO.

Ownership actually moved (not just protocol helpers):
- Unlock, lock, wake, wake-and-unlock, seat, blink/hazard, hibernate/timed
  hibernate/cancel, reboot/hard-reboot execution and 1/2/5-second sequencing.
- Keycard count/list/add/delete, USB mode, generic/APN/standby/hibernate settings,
  clock transport and scooter-side bond forget/ACK/disconnect/phone removal.
- Scheduled-hibernation first-enable sequencing (optional cron then duration,
  enabled last) is one captured-session operation. Disabling writes only the
  enabled flag. Partial acknowledgements are not rolled back after a later
  failure or replacement; no transaction guarantee was added.
- Three-second RSSI polling, ten-second characteristic refresh, threshold/auth/
  standby decisions, aggregate-transition cooldown and 60-second expiry now
  have explicit shared start/stop/dispose. App background composition controls
  the compatibility `rssiTimer.start/pause/cancel` handle. Pause retains its
  remaining interval; start is idempotent; disposal is terminal. These are the
  only APIs used in this tree and `/home/teal/src/reunu/unustasis`.
- Pure core owns action/source enums (unchanged names/order), immutable settings,
  event/location/warning values, command constants/builders and APN/duration
  validation. The app still maps successful acknowledgements to unawaited heavy
  haptics (lock/unlock only) then activity logging, retaining supplied source/SOC.
  Wake/hibernate remain app-source events without SOC; automatic seat is auto.

Legacy `ble_commands.dart` functions remain exports or app-effect wrappers;
Provider facade methods remain delegates. Navigation, OTA, static native-widget
power connection, native identifiers, preference schemas, dependencies, location
polling, heartbeat/resume and background scheduling were not moved. Settings UI
still has read-only alarm/OTA characteristic-availability checks; these are not
new command escape hatches and remain later UI/telemetry/OTA migration work.

### Explicit correctness changes and before/after evidence

These are intentional corrections, **not** claims of mechanical relocation:

1. A cancelled/replaced action no longer dereferences the replacement device in
   a delayed seat/hazard/handlebar step. `/tmp/actions-before.log` reproduces the
   inherited hazard writing `scooter:blinker off` to B. The retained app
   `actions_stale_reproduction_test.dart` now exercises real facade connection
   setup and confirms only A's initial blink is written.
2. One 45-second budget includes wake write, standby wait, unlock and awaited
   delays. Subscribe-before-wake remains; failure/timeout cleans up the waiter.
   Expiry also marks the captured action invalid so a still-running underlying
   delay cannot later actuate. `/tmp/actions-additional-before.log` reproduces
   inherited hazards after the deadline. Shared tests release an artificially
   held seat delay and ordinary hazard delays after expiry and observe no write.
3. The same additional-before log reproduces A's pending RSSI result unlocking
   B. Shared tests reject B/same-ID/disconnect/disposal and paused polling
   results, and bound even late underlying RSSI results by the existing
   transport's 15-second timeout. Failed reads no longer reuse old strong RSSI.
   That read budget does not impose a new deadline on the subsequent basic
   unlock. Reentrant RSSI/acknowledgement/cooldown/warning effects are covered.
4. Handlebar warnings remain five-second awaited observations, but no longer
   throw a command-failure exception after an acknowledged write. Unlock warns
   for locked handlebars; lock warns only when the setting enables it. A typed
   captured-action warning stream drives the **existing Home warning dialog**;
   old failure catches were removed, not left as dead warning delivery. The
   compatibility exception type remains. Wake alone never hazards; wake/unlock
   hazards require acknowledged unlock and `hazardLocking`, regardless of a
   later handlebar warning. Shared traces and the app facade warning/haptic
   regression pin these semantics.
5. The inherited `autoUnlockCooldown()` unconditionally invoked the UI
   `FlutterBackgroundService` facade even inside the service isolate. The
   separate before log records that actual invoke, not a generated-plugin
   warning. Local cooldown always starts; relay is now UI-only. App tests pin
   both isolate modes, 59/60-second expiry and disposal. Overlapping cooldown
   expiry retains its inherited first-expiry behavior rather than silently
   extending the policy.
6. Bond observation subscribes before the forget ACK so an immediate firmware
   disconnect is not lost, and cancels its observation in `finally`. Stop retry
   still precedes the firmware request; phone removal still follows the ACK/
   disconnect wait or best-effort failure. Captured-session checks prevent late
   bond completion from removing/disconnecting a replacement. Scheduled enable
   similarly cannot retarget later settings to B or a new same-ID attempt.
7. Review caught a migration regression: after a real disconnect the retained
   device ID selected the shared forget action, whose live-only capture threw
   before phone/local removal. `/tmp/actions-forget-before.log` reproduces this
   through connect A → disconnect → `forgetSavedScooter('A')`, and an unbound
   retained device fails the same way. Forget now captures the existing session
   identity without requiring live characteristics, stops retry, and performs
   best-effort offline phone cleanup. The connected firmware/ACK/disconnect/
   phone-removal order is unchanged. Captured intent/attempt checks guard each
   transport and facade await, including same-ID replacement and disposal;
   guarded cache refetch cannot later overwrite replacement presentation.
   Twelve app regressions cover disconnected/unbound/never-connected removal,
   replacement or disposal during transport cleanup, and same-ID replacement
   or disposal during phone removal, saved-record removal and cache refetch.
   Already-issued native or persistence operations cannot be rolled back;
   stale completion cannot initiate subsequent removal/publication steps.
8. A second review exposed an entry-time no-op after a failed reconnect: the
   last published connection was from A, but the actual attempt generation had
   advanced for a failed A/B attempt. Requiring that old publication to be the
   current attempt rejected every subsequent saved-ID forget. The session now
   supplies `captureOperationFreshness()`, a read-only predicate over its
   **existing** intent/attempt counters and disposal state. It does not require
   a live/publication token or add another counter/owner. Both the facade and
   shared forget action use it; ordinary BLE actions still require their
   captured live `SessionConnection`. A disconnect alone preserves this
   operation predicate, retaining firmware-forget ACK/disconnect ordering.
   `/tmp/actions-forget-generation-before.log` records eight failed local-removal
   cases (manual/automatic failure × same/different ID × current/other saved ID)
   and two obsolete automatic-attempt continuations. All now pass, including
   automatic attempts which fail before any transport publication changes.
   The targeted app suite has 28 passing tests. Quiet supersession/disposal
   remains the established `Future<void>` contract, but the saved-card success
   toast now requires the captured ID to be absent after awaiting removal and
   the widget to remain mounted. A focused source-boundary test pins this gate;
   no broader UI/result API or transaction semantics were introduced.
9. Pending-before-entry reconnects are now conservatively deferred. A review
   reproduction held a same-ID replacement connect, started forgetting, then
   completed that replacement before releasing the old device's disconnect;
   the former facade initiated `store.remove('A')` against the replacement.
   `/tmp/actions-pending-forget-before.log` records that actual failure. Both
   facade and direct shared forgetting now return before any cleanup when the
   session's read-only `hasPendingConnectionAttempt` getter reports its existing
   private pending-attempt slot. It is not derived from connected state or the
   last publication, and remains true during ready publication until the attempt
   exits `finally`. No pending connect is cancelled/superseded and no new owner,
   generation or retry policy is introduced. Completed-failure generation
   snapshots and later-supersession/disposal guards remain unchanged.
   Twenty-seven added app regressions cover the exact overlap, a 24-case matrix
   (saved A/saved B/direct shared × manual/automatic × pending A/B × subsequent
   success/failure), and two reentrant connected-ready publications. Entry
   assertions prove no disconnect, phone bond removal, store removal, notifier
   publication or connected-state mutation. Every matrix case then verifies
   normal local forgetting after the pending attempt settles. Targeted suite:
   55 passing tests in `/tmp/actions-pending-forget-after.log`.

Forgetting decision matrix reviewed together:

| Entry / continuation | Policy and evidence |
| --- | --- |
| Never connected, no pending attempt | Phone-only and saved-record removal; app regression. |
| Current connected, no pending attempt | Existing firmware forget/ACK/disconnect/phone ordering; adapter handshake traces. |
| Disconnected retained/unbound device | Best-effort cleanup without live characteristics; app regressions. |
| Completed failed A/B attempt | New operation uses actual owner generation, not stale publication; eight app cases. |
| Actual pending attempt before entry | Quietly defer all saved-ID/shared forgetting before cleanup; 27 new app cases, including ready publication. |
| New attempt during an await | Existing owner-generation predicate prevents subsequent work/publication; app transport/phone/store/cache and adapter firmware/bond regressions. |
| Disposal before entry or during await | Reject/stop subsequent effects; existing disposal regressions. |

Already-issued native/persistence effects cannot be rolled back. Quiet deferral
still returns `Future<void>`; the existing mounted/captured-ID-absence toast guard
prevents false success when no local removal occurred.

Before-only extra harness: `/tmp/actions_legacy_additional_reproduction_test.dart`
was run against `git show HEAD:lib/scooter_service.dart`, then the implementation
was restored. It overrides only unlock recording for the RSSI reproduction;
its deadline reproduction executes the actual inherited wake/unlock/hazard
workflow with fake characteristics. No hardware was actuated.

Validation: **510 tests (194 app, 107 core, 209 adapter)**, up from the complete
389 baseline (136/102/151). All original 24 service connection and 21 identity
tests are unchanged. Added: 58 adapter action/polling/setting traces, five core
value/protocol tests and 58 app facade/boundary tests (52 added during review). Full pinned analyses and
suites use `/tmp/flutter-sdk-3.41.9/bin`; Java 17 debug APK is built with
`ASDF_JAVA_VERSION=temurin-17.0.13+11`. Logs are `/tmp/actions-{core-validation,
adapter-validation,app-analyze,app-tests,build}.log`; complete tracked and new
file diff is `/tmp/ls-actions-runtime.diff` (nothing staged).

The final recovery build explicitly completed (`✓ Built`), unlike the earlier
truncated build log. APK: `build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
`37098cc6ec0f232e4643b192bebc5c361cda6a6400c142726737a25929453ba0`.
The final pending-attempt-fix build completed in 14.7 seconds. No dependency changes,
skipped tests or unrelated assertion changes were used to bypass validation.

Already-issued native writes/notification enables cannot be physically undone.
The inherited extended FIFO response timeout policy is unchanged: write/notify
waits are not bounded by its ten-second response timeout. Legacy raw command
wrappers cannot infer a session token; app action UI now uses the captured shared
APIs. Device BLE/bonding/background/widgets and visible warning-dialog smoke
remain hardware/manual gates; APK compilation is not that validation. No device,
seatbox, commit, push or deployment operations were performed.

## Shared navigation runtime (milestone 3, navigation only)

`NavigationRuntime` now owns pending/active destination state, preference
restoration/invalid-entry removal through supplied effects, firmware-ready
pending dispatch, direct/favorite navigation, cancel, favorite list/save/delete,
and captured-session delete-then-add rename. `ScooterService` only composes its
`pendingNavigation` preference and name-decoding effects, delegates compatibility
views, and forwards the existing session binding/invalidation and telemetry
firmware/navigation events. NavigationScreen uses shared workflow APIs rather
than raw characteristics/command functions; its cancel/active transition and
rename sequence no longer execute in UI. This is the **navigation half only** of
milestone 3: no OTA transfer/controller/UI changes were made.

Core owns `NavigationDestination`, the unchanged `SpecialDestinationType` enum,
JSON coordinate/name/id/type codec, destination/favorite command builders and
favorite-list entry decoding. The mutable app `NavDestination` extends that DTO,
preserving its constructor/fromJson/toJson APIs, inferred-name lists and
`ensureNamed()` geocoding behavior. Shared runtime snapshots mutable input values
at entry and returns copies; geocoding, name inference, labels, consent,
confirmation dialogs and saved-scooter favorite caching stay app adapters/UI.
Core uses the existing pure `latlong2` **0.9.1**, with newly needed core lockfile
transitives matching the app's existing `intl` 0.20.2 and `clock` 1.1.2. There are
no unrelated dependency upgrades or Flutter/app imports into core.

The six navigation BLE operations live in the shared adapter and enter the
**existing** extended-channel FIFO alongside actions/keycards/capability queries.
Listen-before-write buffering, notify reuse, command strings, permissive favorite
ACK-ID extraction/list parsing, ten-second list/response timing, long-write flags,
and truncation by Dart string length (including split surrogate pairs) are
unchanged. Non-ASCII outgoing names still fail the inherited ASCII transport;
this is explicitly tested, not silently corrected to UTF-8. No independent
connection engine, connection generation or extended queue was introduced.

### Explicit correctness changes and evidence

Four tests against HEAD `a0ccef7` reproduced stale pending-navigation ACKs wrongly
activating a destination after a newer pending request, B replacement, same-ID
replacement or disconnect. Before evidence: `/tmp/navigation-before.log` (four
failures); retained real-facade regressions now pass in
`test/service/navigation_stale_reproduction_test.dart`. They hold the actual
extended write across actual facade connection/telemetry setup, not a simulated
state setter. Two additional app cases pin the real preference key/schema,
invalid-entry removal and successful firmware-ready dispatch/removal.

Every dispatch now captures a destination snapshot, an independent **request
identity** (not destination ID or object equality), and the existing
`SessionConnection`/repository. Old completions cannot activate or clear newer
pending/active state, including synchronous publication reentrancy and same-ID
replacement. Queued commands and notification-enable continuations check that
same captured token before writing. Repeated firmware-ready dispatch of the same
request/session is coalesced; an explicit later retry after failure remains
possible. A retained request can dispatch on a new ready session while the old
write finishes without the old completion clearing it.

Pending preference effects are serialized in invocation order so a delayed
removal cannot erase a newer persisted request; failure does not poison later
persistence. This is a bounded race correction, not a schema change. Cancel
preserves the previous UI behavior of dismissing an active card even on command
failure/offline entry, but a stale cancel cannot clear replacement state. Pending
cancellation remains the separate `setPending(null)` path. Favorite rename
retains delete-then-add, without rollback; both steps now use one captured session.
Already-issued BLE or persistence effects cannot be physically undone.

Review found a mixed-request regression: a persisted A dispatch awaiting its ACK
was invalidated correctly by direct/favorite B, but B's successful completion did
not retire A. `/tmp/navigation-mixed-before.log` reproduces both forms with actual
shared FIFO writes: pending and persisted A remained after B succeeded, and the
next firmware-ready session actually wrote A again. The two success cases failed;
the four direct/favorite failure and cancel compatibility cases passed.

A successful direct/favorite request now retires its entry-time pending destination
through the existing serialized persistence path, only while its captured request
identity and `SessionConnection` remain current. It rechecks after active publication
because a synchronous listener can replace either owner. Requests with no pending
at entry do not introduce preference writes. Failed/offline selection does not
retire pending; storage failure still propagates without rollback, as for pending
dispatch. No new identity counter, queue, connection owner or schema was added.

The reviewed transition matrix is now pinned by 42 additional adapter tests:

| Transition | Pending/active policy |
| --- | --- |
| Pending A dispatch → current successful direct/favorite B | Only B publishes active and retires A; A's old ACK cannot publish/remove. Next restored firmware session does not replay A. |
| Pending A dispatch → failed direct/favorite B | B does not publish/retire; A remains persisted for a later firmware-ready retry. |
| Direct/favorite ACK → newer pending C or pending cancellation | New request wins, including while the write is held, synchronous active publication or delayed preference removal. Old completion cannot erase C or restore cancelled pending. |
| Active publication → newer direct/favorite | New request owns its ACK and pending retirement; the older publication cannot append removal afterward. |
| Active publication → cancel or compatibility active setter | Replacement owns active presentation; old navigation cannot retire pending after that reentrant request. |
| Pending dispatch → active cancel (success/failure), or offline cancel | Active-card dismissal remains separate from pending cancellation; pending remains until explicit `setPending(null)` or successful navigation. |
| Replacement session, same-ID replacement, disconnect or disposal before ACK | Obsolete navigation cannot publish or retire pending. |
| Reentrant session replacement during active publication | Already-published active is not rolled back; the obsolete continuation cannot retire pending. |
| New pending/session during issued persistence removal | Existing FIFO persists removal before the newer pending save; old completion cannot erase or notify for the newer request. |
| No pending at direct/favorite entry; offline selection; persistence failure | No unnecessary preference write; offline selection leaves state intact; failed persistence propagates, and a newer pending save still works. |

The complete targeted navigation suite passes **79 tests** in
`/tmp/navigation-mixed-after.log`, including the earlier 37. Already-issued native
or preference effects still cannot be physically undone; if persistent removal
fails, its old disk value is not claimed to have disappeared.

Validation: **605 tests (205 app, 112 core, 288 adapter)**, up from the 510 baseline
(194/107/209) and the pre-review 563. Added: 79 adapter navigation/persistence/session/FIFO tests, five
pure DTO/codec fixtures and 11 app facade/DTO/boundary tests. The original **24
connection and 21 identity tests are unchanged**. All three analyses/suites pass
with `/tmp/flutter-sdk-3.41.9/bin`; debug APK builds with
`ASDF_JAVA_VERSION=temurin-17.0.13+11`. APK:
`build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
`6fd20660b12241aca1cba2f90689a779575a4a89b314b0e363b8b551c1122f56`.
Logs: `/tmp/navigation-{core-validation,adapter-validation,app-analyze,app-tests,
build}.log`. Full tracked+untracked diff: `/tmp/ls-navigation-runtime.diff`;
nothing staged, committed, pushed, deployed or actuated on hardware.

Remaining scope: OTA transfer and update orchestration; activity persistence;
saved-record/cache side effects; lifecycle/resume/location/heartbeat composition;
background scheduling/native bindings and remaining OTA/read-only UI escape
hatches. Favorite cache/geocoding presentation remains app-owned. Legacy raw
navigation wrappers delegate shared protocol but cannot infer a session token;
all live navigation UI wire callers use the captured controller instead. The
inherited FIFO policy still does not bound pending native writes/notify enables
by the response timeout, or physically cancel an already-issued operation.
Hardware BLE/navigation/background/widgets and visible UI behavior remain manual
smoke gates; APK compilation is not hardware validation.


## Shared OTA transfer and update controller (milestone 3, OTA closure)

`OtaTransferService` now lives wholly in `scooter_flutter`: actual streamed file
SHA-256, Android priority boost, START negotiation, negotiated-MTU DATA cap,
resume offsets, cumulative ACK/window/go-back-N loop, throughput/ETA, COMPLETE,
installation adoption/following, local abort and notification/file cleanup. The
root service path is an export. Core adds the **unchanged ordered transfer enum**
and structured update-check/HTTP error values; existing protocol bytes and
`UpdatePlanner` are unchanged single implementations (no CRC/hash redesign).

`UpdateController` owns version queries → supplied release index → existing plan
→ serialized cache maintenance/download/checksum → captured transfer, including
full-image fallback selection. `ScooterService` composes one controller on its
**existing** `ScooterSession` and forwards bind/invalidate/ready/dispose. There is
no new connection owner/generation, retry loop, extended FIFO or static transfer.
Version queries use the existing FIFO and now accept its existing freshness
predicate. Cache-pruning completes inside the planning operation before a ready
plan can admit a download; cache lookup/checksum is also busy work, preventing
parallel Resume/Install operations even when no HTTP bytes are needed.

App composition supplies stable as initial channel, the existing
`https://downloads.librescoot.org/releases/{channel}.json` policy and 15-second
index deadline, index-provided asset URLs verbatim, HTTP client and
`applicationSupport/ota` cache directory. Bundle clients close on success/error;
shared code owns the streamed sink/checksum and resume cache. Existing index
checksum optionality, case-insensitive expected hash, same-size cache reuse,
corrupt-file deletion, full fallback (same release then newest supported channel
full), warnings, channel inference/switch, and bundle ID validation remain. The
existing bundle-ID guard now runs before deriving a cache path as well as START.
No dependency upgrades: adapter adds the app's existing `crypto: ^3.0.3`, resolving
the same **3.0.7**; tracked lockfiles are unchanged after normal pub get. Adapter
lockfile remains ignored under the existing package policy.

The OTA screen only attaches/detaches a controller listener, supplies confirmed
channel/step choices and renders/localizes the shared values. It no longer owns
HTTP, file/cache/hash, version queries, planner/fallback algorithms, raw device/
characteristics or static plan/download state. Normal styling, confirmation
strings and app/native identities are unchanged. A download/transfer survives
screen disposal and the actual widget reattaches to its existing state.

### Demonstrated corrections (not merely relocation)

Before moving internals, **25** real-file/fake-characteristic characterization
tests passed against HEAD's app service: `/tmp/ota-characterization-before.log`.
Three additional failures in `/tmp/ota-defects-before.log` demonstrated:

1. Immediate INSTALL_PROGRESS after COMPLETE_ACK was lost, hanging the install.
   Installation observations now buffer before COMPLETE, including immediate
   terminal success/failure and verification/progress bursts.
2. Missing/unreadable preparation files failed outside the failure/cleanup scope,
   leaving idle/hash state. Preparation now shares that scope.
3. Disconnect after accepted COMPLETE falsely published failure even though the
   scooter had accepted installation. It now releases observers/files and keeps
   an explicit **unconfirmed installing** outcome, not success or failure.

An exact-HEAD additional harness (`/tmp/ota-additional-before.log`) demonstrated
ignored disconnect while parked on a DATA window and an unhandled `Stream.first`
error after a failed control write. The existing 20ms loop now observes the
stream failure; request-owned response waiters subscribe before write, observe
errors immediately and cancel their timer/subscription in finally. START's three
5-second attempts, >5-second ACK rewind, 30-rewind budget, 30-second COMPLETE and
4-second STATUS budgets are pinned with controlled time. Native writes/notify
waits remain unbounded by those response timers, as before. A clock seam defaults
to DateTime.now; production loop delays/timing are unchanged.

A real legacy-screen cached-Resume reproduction against HEAD also initiated
START and COMPLETE on obsolete A after switching to B while awaiting the cache
path: `/tmp/ota-cached-ui-before.log`. Retained widget and controller regressions
now reject the cached/downloaded completion before any START. A controller
operation captures the existing connection/repository and checks after every
pre-transfer await/publication, including same-ID replacement, disconnect and
disposal. Already-issued file/native operations cannot be physically undone.

**Accepted-install ownership policy:** A's accepted but unconfirmed outcome is
not invalidated into a transfer failure or automatically resent. B cannot query
or confirm it or begin another update. Only a fresh current **same-ID A** session
can query STATUS to recover/confirm it; stale old-token responses cannot adopt.
Until confirmation, reset cannot erase uncertainty. This deliberately blocks B
updates if A is unavailable; no archive/rollback subsystem was added. A single
exceptional-state app string asks to reconnect to A's captured app display name
(or captured ID). Missing translations use the existing English fallback; a
German-locale widget test verifies actual rendered text, not a raw missing key.
Normal OTA strings are untouched. Translation review remains a manual follow-up.
Confirmed pendingReboot remains settled/busy-but-not-active and resettable;
ready after reboot re-plans without requiring a mounted screen. Local abort
still stops DATA without emitting wire ABORT or deleting the resume cache.
Inherited inline-ACK rewind/send-position behavior is explicitly characterized,
not silently repaired during relocation.

Validation after OTA recovery review: **725 tests (219 app, 114 core, 392
adapter)** versus 605 (205/112/288), and 688 before the recovery fixes. Added:
42 transfer, eight virtual-time transfer/cleanup, 54 controller/provider/cache/
session/recovery tests, two core value fixtures and 14 app boundary/widget/name
capture tests. The original **24 connection and 21 identity tests are
unchanged**. All three pinned Flutter/Dart **3.41.9** analyses and full suites
pass; no skipped tests. Java **Temurin 17.0.13+11** debug APK completed:
`build/app/outputs/flutter-apk/app-debug.apk`, SHA-256
`1e71672d2cd9142214f16399670d0c7e6d66a6b338ebed8343f326db2dedec25`.
Latest logs: `/tmp/ota-recovery-{core-validation,adapter-validation,app-analyze,
app-tests,build}.log`; final Gradle debug build completed in 13.7 seconds.
Full tracked + untracked diff: `/tmp/ls-ota-runtime.diff`; nothing staged,
committed, pushed, deployed or used for OTA network/hardware actuation.

### OTA recovery review: P1/P2 closure

The independent review found two missing transitions despite the initial 688
passing tests. Ten new regressions **failed before edits** in
`/tmp/ota-recovery-before.log`: cold STATUS adoption failed to own A; a previous
completed B could wrongly own/confirm newly adopted A; and interrupted version
query/index planning never recovered on same/different-ID readiness, both before
and after the obsolete operation's finally.

**P1:** A fresh, current STATUS result now acquires its captured target before
any adopted-state publication. The transfer's narrow pre-adoption callback runs
only after a valid adoptable response; stale responses cannot acquire ownership.
`UpdateController.onTargetCaptured(id)` supplies the app-only display-name
capture effect for each fresh adoption/execute. ScooterService captures the saved
name or ID there, replacing its old ID-change listener. A fresh same-ID operation
recaptures a renamed scooter; reconnection recovery never recaptures or substitutes
B's identity. Freshness is rechecked after the effect and after publication,
including reentrant replacement/disconnect/disposal; obsolete callbacks cannot
publish adoption, set an active transfer step or initiate download/START. Callback
failure also releases the STATUS observation. No identity counter, model/schema
or second update owner was added.

**P2:** An interrupted query/index planning operation retains only its channel/
channel-switch intent, separately from accepted-install uncertainty. Current
session readiness consumes that intent once through the controller's existing
serialization. Ready-before-finally drains after the stale operation exits;
ready-after-finally consumes it directly. Invalidation clears obsolete readiness
so a newer binding cannot borrow an older session's ready event. An accepted
explicit check/channel choice or transfer supersedes deferred planning. Published
plans and check errors settle the request; a failed recovery remains an error
with the existing explicit Retry action, not an automatic retry loop. No firmware
transfer or accepted-data resend is started by idle planning recovery, and the
same-ID unconfirmed-install blocking policy remains separate and unchanged.

The recovery increment is **37 tests**: 28 adapter regressions for ownership,
reentrant target effects/state publication, stale recovery responses, query/index
× same/different-ID × readiness ordering, channel choice/newer plan/error
supersession and retry ownership; six actual facade display-name composition
fixtures (all adopted phases, ID fallback, fresh same-ID recapture and recovery
retention); and three mounted-widget regressions proving a current A/B Install
plan appears without reopening and a failed recovered index exposes working
explicit Retry. Facade name tests explicitly bind fake tokens without starting
its background/runtime or HTTP; adapter tests exercise the actual session owner.
Original 24 connection and 21 identity tests remain byte-for-byte unchanged.

**Remaining activity/lifecycle closure is not claimed.** Activity persistence,
saved-record/cache side effects, lifecycle/resume/location/heartbeat composition,
background scheduling/native bindings, remaining non-OTA UI read-only escape
hatches and the native iOS widget BLE exception remain separate milestones.
The OTA-specific screen lifetime, session replacement and controller disposal
boundary is closed by controlled tests; broader runtime-enabled startup,
background ownership, firmware BLE/native notification delivery and visible
on-device OTA behavior still require manual/hardware validation. APK compilation
is not firmware-install/hardware validation. No scooter or seatbox was operated.



## Remaining runtime boundary (milestone 4)

`ScooterRuntime<T extends SavedScooterRecord>` now orchestrates the existing
session, telemetry, actions, navigation, settings and generic scooter store. It
owns explicit initialization/disposal, cache load/selection/seed/refetch,
saved-record add/forget continuation ordering, foreground manual-target expiry
and heartbeat, passive candidate connection, bounded manual reconnect, explicit
action target selection, real-background resume detection, delayed scan resync,
stale-link RSSI probing and 20-second captured-session location acquisition.
RSSI/characteristic polling remains in the existing `ScooterActions`; retry and
all intent/attempt freshness remain in the existing `ScooterSession`. The runtime
only starts/stops/forwards those owners: no second session, generation, retry
loop, extended FIFO or native scheduler was created. The generic constraint is
the existing storage contract, with app-supplied ID/cache projections, not a new
saved-record DTO or schema.

`ScooterService` composes these owners and forwards lifecycle events. Runtime-
disabled tests retain their original seam; runtime-enabled callers can observe
`runtimeReady`. UI and app/background widget publications consume
`currentScooterId`, capability views and shared disconnect/actions rather than
raw devices/repositories. The unused facade repository slot is removed; the
legacy device getter/setter is explicitly test/demo-only so the original service
fixtures remain unchanged. UI settings constants import core, not BLE wrappers.
Architecture assertions forbid raw BLE consumers throughout UI and app/widget
publication, and forbid polling, parsing, persistence and probe loops returning
to the facade.

Core `LogEntry` owns the exact event JSON codec; adapter `ActivityStore` owns the
enabled setting, enqueue chain, persistence and permission/location acquisition
through supplied hooks. App `StatisticsHelper` supplies Geolocator and logging,
retains its singleton compatibility and alone creates demo entries. No dependency
or preference-schema changes were needed. Before moving, seven tests pinned
`eventLogs`/`eventLoggingEnabled`, enum `.toString()`, ISO timestamps, LatLng JSON,
immediate `logEvent` completion versus queued writes, cached permission, caught
location errors, poisoned queue failure and unqueued clear resurrection. All
remain passing: these inherited failure/race semantics were **not** repaired.

### Bounded reviewed corrections and reproduction

The immutable U snapshot `/tmp/unustasis-backend-17d2e9f` supplied only bounded
manual reconnect and explicit action/application integration corrections, not
whole app files or U identities. Two original-LS manual reconnect reproductions
failed: Home start and silent-link resume did not retry retained manual A. The
same existing session now retries that pin, or makes one targeted attempt for
`restart: false`; repeated calls neither start another retry owner nor release
intent. New manual B supersedes A through that same owner.

The legacy widget consumer also failed a real under-gate unlock reproduction
(no write), and the notification entry failed to persist before invoking. The
before-only widget harness exposed the original private consumer via a delegate,
without replacing its algorithm. Shared explicit action preparation captures
external pin > local manual pin > connected target > most recent saved target,
bypassing passive suppression only for that one captured request. The app
retains native action-name mapping and claims the existing two-key pending slot
just before dispatch. Pin/attempt changes and pre-issue connection failures
retain the request; uncertain issued writes consume it and are not automatically
replayed. All 25 reviewed U integration cases pass through the LS composition,
including notification persist-before-invoke, delayed duplicates, same-ID
supersession, claim-time pin changes, pending-attempt deferral and awaited seat
issuance. The two keys are still a non-atomic single slot, not an exactly-once or
cross-isolate transaction mechanism.

A runtime-enabled before test additionally reproduced delayed cache load
notifying a disposed facade. Approved lifetime guards now use runtime disposal
and the existing session freshness predicate. Obsolete startup/refetch target
presentation is suppressed, but target replacement does not suppress global
navigation/settings restoration. In-flight persistence cannot be rolled back.
Runtime tests cover disposal during store load, selection, navigation read/invalid
entry removal and each settings-read phase; normal/idempotent foreground startup;
scan, heartbeat, RSSI and location stop; same/different-target startup; delayed
refetch; pending location; and obsolete same-ID/B resume RSSI failures. Shared
standalone fixtures use the existing generic store without any application model.

Validation: **789 tests (273 app, 116 core, 400 adapter)**, versus the actual
**725 (219/114/392)** clean `c50da38` baseline. The original **24 connection and
21 identity tests remain byte-for-byte unchanged** and their targeted suite
passes all 45. All three analyses and suites pass on Flutter **3.41.9** / Dart
**3.11.5**. Normal repeated pub get retains identical app/core/adapter lock hashes;
there are no dependency changes. Temurin **17.0.13+11** debug APK validation and
its final checksum are recorded in the durable runtime-closure implementation
report. `/tmp/runtime-closure-logs/` contains actual before/after suite,
characterization, reproduction, lock-repeat, analysis and build logs.

### Legitimate app boundaries and residual algorithms

App-owned: SavedScooter setters/branding/default display name, rename/recolor
presentation and selected-record metadata publication, geocoding, ping and typed
cache-patch-to-model effects, demo state, haptics, permission UX/location provider,
widget payloads/identities, lifecycle observer registration, splash, plugin
registrant, background service/rescan/demotion scheduling and notification/pending
native-slot integration. The static iOS widget power entrypoint remains the
explicit native BLE exception; it is not another shared general runtime.

Background cross-isolate scheduling/publication and the two-key native pending
slot have not been redesigned. Activity write poisoning/clear races, inherited
unbounded native writes/notification-enables and issued-effect non-rollback remain
known limitations. Hardware BLE, native background/widgets, permissions and
visible UX require device smoke testing; unit tests and an APK are not that gate.
No device/seatbox, commit, staging, push, deployment, assets, native identity or
unrelated UI/style changes were performed.



### Runtime closure review: pre-issue request retention (P1)

The independent review blocked the initial 789-test closure: a connected session
with a missing command characteristic consumed a widget request without any
write. After `setBool(false)`, a failed preference reload/name removal likewise
left a definitely unissued request unarmed. The parent's actual missing-command
failure was reproduced, and the retained pre-issue fault matrix produced **10
failures / 2 passes before this correction**.

A captured `ExplicitActionDispatch` now supplies readiness from the **same**
current session/pin and shared action binding. Required basic-command availability
is checked during preparation, immediately before the app claims its native slot,
and again at dispatch. It does not reconnect or capture a different target just
to check readiness. The shared basic transport records possible issuance directly
before invoking native `write`, after validation/ASCII encoding. Explicit action
execution returns `false` only for definite non-writes; synchronous native errors,
ACK failures and later action-effect errors stay ambiguous and propagate without
restoring a consumed request. Ordinary command errors and successful action/source/
settings/ACK behavior remain unchanged.

The native consumer checks both preference boolean results, re-reads after partial
claim/removal, and performs **one best-effort recovery pass** only before dispatch
or after a definite non-write. It reloads durable preferences rather than trusting
the legacy adapter's optimistic cache, and checks the slot again before rearming.
An observed newer distinct request is neither removed nor overwritten/rearmed as
the old request. Recovery read/write failure is explicitly logged; it can leave
the request unarmed, and is not retried indefinitely. No new keys, transaction,
RPC, queue or exactly-once guarantee were added. Cross-isolate races inside an
already-issued preference call remain a limitation of the two-key single slot.

Added coverage: **43 app integration and 14 shared tests** for all three actions'
partial discovery, pre-claim and dispatch-time characteristic loss, known
transport preconditions, claim/reload/remove throw and false-return failures
(including persistence applied before failure), newer armed/unarmed distinct
requests, failures at each recovery stage, pin/session/same-ID/disposal changes,
possible native write failures and post-ACK effect failures. All prior 25 reviewed
U integration cases remain passing (targeted integration file: **87 tests**).
The test activity-preferences fake now implements its missing `getBool` method;
production activity queue behavior is unchanged.

Final P1 validation: **846 tests (316 app, 116 core, 414 adapter)** versus the
actual follow-up baseline **789 (273/116/400)** and original clean-base **725**.
All three pinned Flutter 3.41.9 / Dart 3.11.5 analyses pass. Original 24 connection
and 21 identity files remain unchanged. Normal repeated pub get retains delivered
locks. Temurin 17.0.13+11 debug APK built successfully; SHA-256:
`9e264b1ee1795973304e77ec12e5ce86ce5b992d367f558658f4af895fe91a84`.
Actual before/after logs and complete tracked+untracked patch accompany the durable
`preissue-retention.md` report. No staged files, commits, push, deployment or
hardware operations.

**Separate remaining debt, not hidden by this P1 correction:** the facade still
has rename/recolor asynchronous selection-and-publication orchestration. That
bounded follow-up was not bundled here. Branding/color/geocoding/model effects,
native/background scheduling and static iOS widget entrypoint stay app-owned;
activity poisoning/clear races and existing issued-effect/native-wait limitations
are unchanged. Independent re-review and device smoke remain separate gates.


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
