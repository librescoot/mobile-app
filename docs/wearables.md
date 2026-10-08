# Wearable companions

The companion MVP provides native Wear OS and watchOS controls. Both watch apps
have explicit lock, unlock, seatbox and refresh actions, cached state, battery
levels, nominal range, scooter selection, and last-known location links when the
phone supplies coordinates. A Tile or complication opens the app; it never
actuates the scooter.

## Validation status

- **Wear OS:** Android debug builds, Kotlin protocol/HCE tests and Android lint
  are supported. Hardware pairing, background interruption, reconnect latency,
  battery cost and NFC routing require device validation.
- **watchOS:** SwiftUI app, Core Bluetooth client, WatchConnectivity relay,
  WidgetKit complications and Xcode targets are provided. Foundation-only Swift
  tests and source parsing do not establish Apple SDK compatibility. A macOS
  Xcode build, signing, simulator installation and physical-watch tests are
  release gates.
- Neither watch is certified as a sole vehicle key. Keep a physical backup key.
- Passive proximity unlocking, Apple Wallet/NFC keys, remote cloud controls,
  firmware updates and unattended background scanning are outside this MVP.

## Connection modes

### Via phone

The phone publishes its current scooter snapshot through `wearable_bridge`.
Each watch retains up to 20 observed targets. Phone and direct-BLE targets are
separate entries, even when they refer to the same physical vehicle.

A command is dispatched to one live Flutter engine already connected to the
exact requested scooter. It does not start a connection, launch a headless
engine, change the selected scooter, or persist an action for later execution.
If no live owner exists, open the phone app and connect it to the scooter, or
select an enrolled direct key. An Android background-service engine can handle
requests while it owns the live connection; availability after process death or
OS suspension is not guaranteed. The phone's optional-authentication setting
blocks watch-relayed actuation and directs the user to the phone.

Wear Data Layer requires matching application IDs and signing certificates on
phone and watch. Debug builds use `org.librescoot.mobile.unu.debug` on both.
Wear commands require the source node to be reported as nearby on both ends.
Status synchronization can use Google's Data Layer network transport.
WatchConnectivity reachability is not a cryptographic proximity check. Neither
transport is used as evidence that a person is beside the scooter.

### Direct Bluetooth key

1. Park the scooter using an existing key, following its normal pairing flow.
2. Disconnect the phone if it occupies the scooter's BLE connection.
3. Select **Pair direct BLE key**, scan, and choose the scooter.
4. Complete the OS pairing/PIN prompt on the watch. Successful encrypted reads
   establish the local shortcut; setup never sends unlock or seatbox commands.
5. Select the direct entry for phone-free use. No internet is required.

The watch establishes its own OS-managed bond. Phone bond secrets are not
copied. A phone's Core Bluetooth identifier is only a relay target; direct watch
connections use watch-local identifiers. Normal operations have a 15-second
budget; enrollment has a 60-second budget. Sessions
close after the operation. There is no reconnect loop or automatic fallback to
the phone.

Controls read live vehicle/seatbox state before acting:

| Action | Accepted state | Completion evidence |
|---|---|---|
| Unlock | `stand-by` or already `parked` | `parked` |
| Lock | `parked` or already `stand-by` | `stand-by` |
| Open seatbox | `parked` | Seatbox sensor reports open |
| Refresh | Read-only | Live state read |

`ready-to-drive`, transitions, unknown states and `off` do not permit actuation.
Wake a sleeping scooter through its normal physical wake mechanism before using
these controls. Automatic hibernation wake-and-unlock is not implemented. A
seatbox-open lock transition that does not reach `stand-by` reports an unknown
outcome; the client does not send another lock to confirm that transition.

Refresh reads available battery presence and charge characteristics. Range is a
nominal estimate of 45 km per full battery, not a measured remaining distance.
Missing data is shown as unavailable. Direct control snapshots can omit battery
values; use Refresh to obtain them. Coordinates are supplied by the phone, not
inferred from a BLE connection.

Direct watch commands cannot suspend another device's independent keyless
policy. Disable phone proximity unlocking during watch-key validation. Phone
relay lock requests use the phone's keyless cooldown.

### Experimental Wear OS NFC key

NFC payments alone do not imply third-party host card emulation (HCE) support.
The setup action requires the HCE system feature, NFC enabled and a secure watch
screen lock. The service is disabled until explicitly enabled. It also rejects
APDUs while the device is locked or its screen is off, including on OS versions
that ignore the manifest screen-on flag.

The watch creates its own P-256 key in Android Keystore. It implements the same
ISO-DEP signed-challenge credential format as the Android phone key, with an
independent fingerprint. Private keys are not transferred from the phone.

On compatible scooter firmware, tap a master card to enter learn mode, present
the unlocked watch with the screen on, then tap the master again to save. Verify
the displayed fingerprint in the scooter's credential-management UI. Support is
model-dependent and must be tested on a real reader. Challenge signing does not
provide distance bounding or protection against a live NFC relay.

**Removal is not revocation.** Removing a watch shortcut does not delete its BLE
bond. Disabling NFC stops local service use but does not revoke an enrolled
credential on the scooter. Revoke an NFC key by its fingerprint through the
scooter's credential-management interface. Verify the supported BLE lost-peer
revocation/recovery procedure for the installed firmware before relying on a
watch. An app reinstall or watch replacement requires enrollment again.

## Command contract

The phone relay uses version 1 requests:

```json
{
  "version": 1,
  "id": "a17311fa-f067-4c08-a538-ef7b38b93470",
  "scooterId": "platform-local-phone-peripheral-id",
  "action": "unlock",
  "issuedAt": 1800000000000,
  "expiresAt": 1800000015000
}
```

Actions are `refresh`, `lock`, `unlock`, and `openSeat`; never a state toggle.
Timestamps are Unix milliseconds. The maximum lifetime is 15 seconds, with at
most two seconds of future clock skew. Phone/watch clocks must be synchronized.
Native phone routing records consumed request IDs before dispatch, serializes
requests across its engines, and does not retain an actuation queue. The Dart
executor captures the current connection and also applies a monotonic budget.

Results carry `version`, `id`, `scooterId`, and `status`. Status values include
`confirmed`, `unknown`, `unavailable`, `expired`, `duplicate`, `busy`,
`unsafeState`, `phoneAuthRequired`, `phoneNotNearby`, and `invalid`.
A BLE write acknowledgement is not confirmation of vehicle state. Once a write
may have been issued, a timeout/disconnection produces **outcome unknown**, not
a retry. Refresh or inspect the vehicle before another deliberate request.
Automatic unlock side effects such as seat opening and hazard flashes are not
part of a watch command.

Android paths are `/companion/v1/state` (DataItem snapshot),
`/companion/v1/command` (message), and `/companion/v1/result` (message).
Apple uses application context for snapshots and immediate `sendMessage` with a
reply handler for commands, not deferred user-info transfers.

Implementations live in:

- `packages/scooter_core/lib/companion.dart`: bounded command/state contract.
- `packages/wearable_bridge/`: per-engine native phone transport.
- `android/wear/`: native Wear OS app, BLE/HCE, Tile and complication.
- `ios/ScooterWatch/`, `ios/ScooterWatchWidget/`: watchOS app and complications.
- `ios/WatchSupport/`: Foundation-only Swift contract and tests.
- `test/fixtures/companion_contract.json`: shared Dart/Kotlin/Swift state fixtures.

## Build and test

The **Native builds** GitHub Actions workflow compiles Android phone/Wear OS
apps, checks the phone's release App Bundle with a disposable signing identity,
archives iOS with its embedded watch targets without signing, and
builds the watchOS simulator app and complications. It also runs Wear OS
protocol tests/lint and Swift protocol tests. Trusted repository pushes also
verify a signed IPA export using the same signing setup as Nightly and Release.
Pull requests and forks use unsigned Apple builds. The workflow does not upload
to stores or establish physical-device compatibility. The separate **CI**
workflow analyzes and tests Dart/Flutter.

### Wear OS

Use the repository's Android SDK and a Java version supported by its Gradle/AGP
configuration (Java 21 for the current configuration):

```sh
flutter pub get
flutter build apk --debug
cd android
./gradlew :wear:assembleDebug :wear:testDebugUnitTest :wear:lintDebug
```

Outputs relative to the repository root:

- Phone: `build/app/outputs/flutter-apk/app-debug.apk`
- Watch: `build/wear/outputs/apk/debug/wear-debug.apk`

Install each APK on its respective emulator/device. The watch supports Wear OS
3+ (Android API 30+). Release distribution requires explicit signing and version
code configuration; the watch and phone must use the same signing identity.

### watchOS

The app targets watchOS 10+. On a Mac with Xcode and the watchOS SDK:

```sh
flutter pub get
(cd ios && pod install)
xcodebuild -project ios/Runner.xcodeproj -scheme ScooterWatch \
  -configuration Debug -sdk watchsimulator \
  -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Use the `ScooterWatch` scheme for watch development. The `Runner` target embeds
the watch app, which embeds its WidgetKit extension. Before a physical install,
configure signing for both watch targets and register/enable the shared app
group `group.org.librescoot.mobile.unu.watch`. Watch versions come from Flutter's
generated build configuration. Run `pod install` to resolve the local phone
bridge and update CocoaPods integration on macOS.

Distribution builds require App Store profiles containing the CI distribution
certificate and the watch App Group entitlement:

- `org.librescoot.mobile.unu.watch`: `Librescoot Watch App Store CI`
- `org.librescoot.mobile.unu.watch.widget`: `Librescoot Watch Widget App Store CI`

The shared `.github/actions/ios-signing` action downloads and checks these and
the phone/widget profiles. It does not register bundle IDs, create App Groups,
or issue provisioning profiles. Configure those in the Apple developer account
before merging changes that embed the watch targets into a publishing branch.

### Hardware-free checks

```sh
flutter test test/
(cd packages/scooter_core && dart test)
(cd packages/scooter_flutter && flutter test)
(cd android && ./gradlew :wear:testDebugUnitTest :wear:lintDebug)
swift test --package-path ios/WatchSupport
```

The Swift protocol package runs on Linux as well as macOS. It does not import
Core Bluetooth, SwiftUI, WidgetKit, WatchConnectivity or Flutter; passing it is
not a substitute for an Apple SDK build.

## Physical release checklist

Use a stationary scooter and obtain explicit permission before actuating it.
Check each supported watch model and firmware combination:

- Pair/re-pair, PIN dismissal, permission denial, BLE disabled and bond loss.
- Direct controls with phone powered off and without network access.
- Phone connected concurrently, busy radio and deliberate transport selection.
- Standby/suspend/hibernation, state transitions and seatbox-open locking.
- Duplicate taps, expiry, disconnect immediately after a write, app termination,
  watch reboot, and late replies: no replay or transport fallback.
- Phone authentication and keyless cooldown; locked/backgrounded/killed phone.
- Watch removal/lock, screen-off behavior, battery saver, battery cost and latency.
- NFC enrollment, challenge exchange, locked-screen denial and actual revocation.
- Small/round displays, large text, screen readers, Tile/complication cache age,
  and notification/permission prompts.
- Signed iOS/watchOS installation, App Group access, WidgetKit refresh and phone
  relay under actual watchOS background scheduling.
