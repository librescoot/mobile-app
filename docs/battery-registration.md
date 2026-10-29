# Shared battery tracker

The battery feature invites riders to join the shared tracker and register the
batteries they use, so serial numbers can help identify stolen batteries when
they are seen again. Account signup is the primary action in Your batteries,
the first-run introduction and the once-only existing-user announcement.

The app has no phone-side battery inventory or history. Serial readings are
transient input to registration and disappear when the page closes. A scan does
not upload anything. The app also removes the `batteryTracker.v1` preference
at startup so no phone-side inventory is retained.

## Account and registration availability

Signup opens `https://sunshine.rescoot.org/users/sign_up` without a serial or
other battery data. The website controls account and invitation requirements.
Opening signup does not mean an account or battery registration was completed.

Shared registration is separately release-gated. The default build leaves
`SUNSHINE_BATTERY_REGISTRATION_ENABLED` off because the registration service
must be deployed and its routes verified before users are sent there. Signup
and serial reading remain available without exposing broken registration links.
Only enable the build flag after the backend release is authorized and verified.

With registration enabled, account management opens
`https://sunshine.rescoot.org/battery_registrations`. Registering a scanned pack
first shows its serial and read method, requires checking the physical label,
and explains the exact upload and destination. Only explicit continuation opens
`https://sunshine.rescoot.org/battery_registrations/new` with `serial_number`
and `source=ble|nfc`. No location, scooter identifier or history is included.
No registration is queued or automatically retried.

The website requires account login and separate consent before recording the
claim. Browser launch is never presented as registration success. Users manage
or delete shared registrations through their account.

A registration is an unverified account assertion, not proof of ownership or a
theft report. It does not grant ownership, create a scooter assignment, change
a theft flag, or reveal another account's ownership or theft information.
Conflicting ownership claims require separate review.

## Identity sources and firmware markers

The read-method sheet puts a usable method first. Only the scooter Bluetooth
option carries the Librescoot marker; NFC and account signup have no Librescoot
firmware requirement. The first stable firmware release with battery identity
support is not established, so the UI uses the confirmed `battery=1` capability
instead of inventing a minimum version.

- Bluetooth discovers the battery capability, then reads `battery:snapshot:0`
  and `battery:snapshot:1`. Each response uses one Redis hash snapshot, for
  example `battery:snapshot:0:{"present":true,"serial_number":"T-UNU22205090007"}`.
  An absent pack returns `{"present":false}` without a retained serial. Unknown
  presence or invalid identity returns a `battery:error:...` response. Disconnect
  or session replacement discards the entire phone-side read. Reported values
  may be cached by the scooter; verify the label before registering them.
- NFC uses read-only Type 2 READ commands at pages `0xc4` and `0xc8`, matching
  byte addresses `0x0310` and `0x0320` in the scooter-side reader. The serial is
  bytes 4-15 of the first block plus bytes 0-3 of the second. Blocks must be
  complete and printable, with matching serials on a second read. The tag UID
  is not pack identity. Unsupported or cancelled scans produce no registration.

Serials preserve leading zeroes. Sixteen-character hexadecimal serials are
uppercased; battery serials never use board hex-to-decimal conversion.
Placeholder and malformed identities are rejected.

Before release, verify both tags on real packs against their labels and BLE
readings, and exercise NFC cancellation and unsupported tags on Android and iOS.
