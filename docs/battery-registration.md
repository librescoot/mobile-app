# Shared battery tracker

The battery feature starts with the rider's own batteries: record their serial
numbers so they can be recognised after a theft. "Add a battery" is the single
primary entry in Your batteries and the once-only introduction after connecting
a scooter. Setup finishes pairing before offering this introduction. The shared matching benefit is explained in an
expandable section, rather than competing with that first action.

The app has no phone-side battery inventory or history. Serial readings are
transient input to registration and disappear when the page closes. A scan does
not upload anything. The app also removes the `batteryTracker.v1` preference
at startup so no phone-side inventory is retained.

## Email verification and registration availability

The app guides the rider through three steps:

1. Read a battery using Bluetooth or NFC. A usable method is listed first.
2. Compare the serial with the physical label and explicitly confirm it matches.
   Multiple readings require choosing a battery; a mismatch returns to scanning.
3. Review the selected serial and sharing disclosure, then explicitly continue
   to the browser. The website verifies the email with a six-digit code if needed
   and separately asks for registration consent.

The automatic introduction waits until a scooter is connected, startup notices
and authentication have finished, and the home screen is in the foreground.
Deferral does not mark it seen. Its action enters the native flow directly,
without an email-signup detour. Manual entry, including NFC during setup, remains
available without a scooter connection. Email verification creates tracker-only access, not a
Sunshine account or full-account login. Existing account data remains separate,
even if its email matches. The phone shows a browser-completion reminder, never
registration success based only on launching the browser.

The default build leaves `SUNSHINE_BATTERY_REGISTRATION_ENABLED` off until the
email-verification and registration service is deployed and verified.
Registration and management links stay disabled while unavailable; local reads
and label checks remain available. First-run
and existing-user invitations are deferred without marking them as seen.
Only enable the build flag after an authorized backend release is verified.

For scoped Android acceptance, manually dispatch `.github/workflows/internal-android.yaml`
on `main` with `battery_tracker=true`. The input defaults to false. The workflow
checks the selected define, builds a signed AAB, records its commit/version/hash
and publishes only to Play's internal track. It creates no GitHub release or tag
and does not build or distribute iOS. General build defaults remain unchanged.
Pushing `main` normally triggers the separate public Nightly workflow; use an
explicit `[skip ci]` commit when only this manual internal delivery is authorized.
The internal workflow runs the full analysis and test suites before building.

With the service enabled, tracker management opens
`https://sunshine.rescoot.org/battery_tracker/registrations`. Registering a scanned pack
first shows its serial and read method, requires checking the physical label,
and explains the exact upload and destination. Only explicit continuation requests
a challenge and submits the selected serial and `source=ble|nfc` to Sunshine.
The browser opens `https://sunshine.rescoot.org/battery_tracker/handoff#code=...`.
The opaque code is in the URL fragment, never the HTTP path, query or Referer;
serial and source are not in the browser URL. No location, scooter identifier or
history is included. No registration is queued or automatically retried.

## Challenge and browser handoff

Both API calls use fixed HTTPS endpoints, JSON bodies, no account authentication
or cookies, and no redirects. The app has a 30-second total deadline and accepts
at most 4 KiB of JSON response data.

1. `POST /api/v1/battery_tracker/challenges` with `{}` returns HTTP 201,
   `challenge` (32 random bytes encoded as 43 base64url characters) and
   `expires_at` (UTC ISO8601). The challenge expires after ten minutes.
2. `POST /api/v1/battery_tracker/claims` sends `challenge`, `serial_number` and
   `source`. HTTP 201 returns `code` (43 base64url characters) and `expires_at`.
   An identical retry returns HTTP 200 with the same code and expiration. A
   changed payload cannot reuse the nonce. The code lasts ten minutes.
3. The browser prepares its own session using a CSRF-protected POST, removes the
   fragment, and continues through email verification and explicit consent.
   Preparation does not consume the claim; final registration atomically binds
   it once, using the server-stored payload rather than hidden form fields.

The app retains an ambiguous claim request only in memory so an explicit retry
can reuse the exact nonce and payload. Cancellation discards it and closes the
client; a late challenge cannot start an upload or open the browser. Browser
launch failure reuses the prepared code until it expires. HTTP 429 offers a wait
and retry hint. Other failures stay on the sharing step without falling back to
serial-bearing URLs. Nothing retries automatically.

These endpoints authenticate the handoff and prevent mutation/reuse of a claim;
they do not attest the reading hardware. No shared app signing secret, Play
Integrity or App Attest is used. Older app links remain supported by the server
as unverified serial/source handoffs, not as challenge-backed claims.

The website verifies the email with an expiring, browser-bound, single-use
code, then requires separate consent before recording a claim. Codes have
attempt and resend limits. Browser launch and email verification are never
presented as successful battery registration. Users manage or delete their
email-linked registrations in the tracker.

A registration is an unverified email-linked assertion, not proof of ownership or a
theft report. It does not grant ownership, create a scooter assignment, change
a theft flag, or reveal another account's ownership or theft information.
Conflicting ownership claims require separate review.

## Identity sources and firmware markers

The read-method sheet puts a usable method first. Only the scooter Bluetooth
option carries the Librescoot marker; NFC and email verification have no Librescoot
firmware requirement. The first stable firmware release with battery identity
support is not established, so the UI uses the confirmed `hash=1` capability
instead of inventing a minimum version.

- Bluetooth discovers `hash=1`, then uses the [generic hash reader](ble-hash-reads.md)
  for `battery:0` and `battery:1`, selecting `present,serial-number` in that order.
  Each atomic snapshot is an array of unchanged strings or missing-field nulls,
  for example `["true","T-UNU22205090007"]`. Battery interpretation is entirely
  client-side: presence must be exactly `"true"` or `"false"`. An absent pack's
  retained serial is ignored. Missing or invalid presence and invalid present-pack
  serials fail the read. Disconnect or session replacement discards the entire
  phone-side read. Reported values may be cached by the scooter; verify the label
  before registering them.
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
