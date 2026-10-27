# Battery identification and registration

Battery identification is available from the battery screen, app settings and
initial setup. It works without a rescoot.org account. Local remembering is off
by default; enabling it saves subsequent explicit checks on the phone. The
inventory is keyed by pack serial, so slot changes and NFC/Bluetooth reads of
the same serial update one entry. Disabling remembering stops recording without
deleting entries. Forget removes a local entry.

## Identity sources

- Bluetooth discovers `battery=1` through the existing capability exchange,
  then reads `battery:snapshot:0` and `battery:snapshot:1`. Each response uses one
  Redis hash snapshot and has the form
  `battery:snapshot:0:{"present":true,"serial_number":"T-UNU22205090007"}`.
  An absent pack returns `{"present":false}` without a retained serial. Unknown
  presence or invalid identity returns a `battery:error:...` response. Disconnect
  or session replacement discards the entire phone-side read.
- NFC uses read-only Type 2 READ commands at pages `0xc4` and `0xc8`, corresponding
  to byte addresses `0x0310` and `0x0320` in the scooter-side battery reader.
  The serial comprises bytes 4-15 of the first block and bytes 0-3 of the second.
  Both blocks must be complete, printable and return the same serial on a
  second read. The NFC tag UID is not the pack serial. Unsupported tags fail
  without issuing writes or battery commands.

Serials preserve leading zeroes. Sixteen-character hexadecimal serials are
uppercased; no board-serial hex-to-decimal conversion applies. Placeholder and
malformed identities are rejected. Check times describe the phone's read of a
reported identity, not a fresh battery measurement. Bluetooth values may be
cached by the scooter. Verify the serial against the physical battery label
before registering it.

## Explicit registration

Checking and remembering do not upload anything. Selecting Register presents
the serial, the destination and the exact data to be sent. Continuing requires
confirmation that the serial matches the battery label. The app then opens the
fixed HTTPS URL `https://rescoot.org/battery_registrations/new`, with only
`serial_number` and `source=ble|nfc`. No location, scooter identifier or history
is included. No registration is queued or retried by the app.

The website requires account login and a separate consent confirmation before
recording the claim. Opening the browser is not reported as successful
registration. Registrations can be viewed and deleted under Parts > Battery
registrations on the website; forgetting locally does not delete them.

A registration is an unverified account assertion, not proof of ownership or a
theft report. It does not grant ownership, create a scooter assignment, change
a theft flag, or reveal another account's ownership or theft information.
Conflicting ownership claims require separate review.

The shared backend contract also provides OAuth-only
`POST /api/v1/battery_registrations` with the narrow `battery_register` scope,
`serial_number`, `source` and `consent_version=battery-registration-v1`. Create
and same-account retries return HTTP 200 `{"status":"recorded"}`. The mobile
browser flow needs no app client secret, stored access token or legacy API key.

## Device verification

Before release, verify both physical tags on each supported pack, match the
NFC serial to the label and Bluetooth result, and exercise cancellation and
unsupported tags on Android and iOS. The read-only transport and identity
layout have automated tests; real-phone/pack interoperability needs hardware.
