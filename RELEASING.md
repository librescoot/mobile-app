# Releasing

Three workflows. `ci.yaml` analyzes and tests every push and PR. `nightly.yaml`
builds an APK from every push to `main` and publishes it as its own
`nightly-<timestamp>` prerelease, keeping the last 10. `release.yaml` builds
signed release artifacts from a version tag or manual dispatch. It can upload
iOS to TestFlight when configured. Android Play publication is a separate,
keyless Publisher API step after the signed artifact has been verified.

## Cutting a release

The app version tracks the matching Librescoot stable release's `major.minor`.
Mobile releases use their own patch and prerelease suffix, plus an independently
monotonic build number. For example, releases aligned with Librescoot 1.3 may be
`1.3.1+48` or `1.3.2-beta.1+49`. Keep the format conventional Dart/Flutter
semantic versioning rather than introducing a second embedded version tuple.

```bash
# bump pubspec.yaml, for example: version: 1.3.1+48
# rewrite changelog.md and localized distribution/play changelog files
git commit pubspec.yaml changelog.md distribution/play/metadata/android \
  -m "Prepare 1.3.1 release"
git tag -a 1.3.1 -m "Librescoot App for unu 1.3.1"
git push origin main 1.3.1
```

The tag must match the version name before `+` in `pubspec.yaml` or the workflow
stops before building. That check exists because a mislabelled build in
TestFlight cannot be withdrawn, only superseded.

A hyphen in the tag marks it as a GitHub prerelease. The workflow resolves an
intended Play track (`internal` for prereleases, `beta` otherwise), which can be
overridden for a manual dispatch. Android is not uploaded automatically: verify
the signed AAB, then publish it to the intended track using the keyless process
below. Every configured iOS build goes to TestFlight, since TestFlight has no
track split.

`changelog.md` becomes the GitHub release body and the staged English Play
fallback. Keep it within Play's 500-character limit. The localized files under
`distribution/play/metadata/android/*/changelogs/<build>.txt` are authoritative
for the keyless Play upload.

## Required secrets

Set these under Settings -> Secrets and variables -> Actions.

### Android

| Secret | What it is |
| --- | --- |
| `KEYSTORE` | Upload keystore, base64. `base64 -w0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` | Store and key password (the workflow uses one value for both) |
| `KEY_ALIAS` | Optional, defaults to `upload` |

Do not create or store Google Play service-account JSON keys. Publisher API
access is keyless and uses short-lived credentials obtained by impersonating a
service account after interactive user authentication.

### iOS

| Secret | What it is |
| --- | --- |
| `APPSTORE_ISSUER_ID` | App Store Connect API issuer UUID |
| `APPSTORE_KEY_ID` | API key ID |
| `APPSTORE_PRIVATE_KEY` | Contents of the `.p8`, including the BEGIN/END lines |
| `IOS_DIST_CERT_P12` | Apple Distribution certificate as base64 `.p12` |
| `IOS_DIST_CERT_PASSWORD` | Password used when exporting that `.p12` |
| `APPLE_TEAM_ID` | Ten-character team ID |

The iOS job is skipped when `APPSTORE_KEY_ID`, `IOS_DIST_CERT_P12` or
`APPLE_TEAM_ID` is missing, so Android can release before Apple's side is set
up.

Provisioning profiles are fetched from App Store Connect at build time rather
than stored, so they cannot drift out of step with the certificate. All three
embedded bundle IDs need an App Store provisioning profile:
`org.librescoot.mobile.unu`, `org.librescoot.mobile.unu.ScooterWidget`, and
`org.librescoot.mobile.unu.ShareExtension`. The first two need the
`group.org.librescoot.mobile.unu` app group.

## Where each secret comes from

### Upload keystore

Generate once, then guard it. Play will not accept a bundle signed with a
different key later without a support request.

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -i upload-keystore.jks | pbcopy   # -> KEYSTORE
```

### Keyless Play Publisher access

1. Play Console -> Setup -> API access: link the Google Cloud project.
2. Give a service account app-level release permissions for
   `org.librescoot.mobile.unu` in Play Console.
3. Grant authorized maintainers `roles/iam.serviceAccountTokenCreator` on that
   service account. Keep organization policy preventing service-account key
   creation enabled.
4. Authenticate interactively with `gcloud auth application-default login`,
   including `https://www.googleapis.com/auth/androidpublisher` in the requested
   scopes.
5. Obtain a short-lived Publisher token with `gcloud auth application-default
   print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher
   --impersonate-service-account=<publisher-service-account>`.
6. Use a single Publisher edit to upload the verified AAB, replace only the
   intended track, verify its staged release name/code/notes, and commit the
   edit. Open a fresh read-only edit afterward to confirm the bundle digest,
   committed track state, and that production remains unchanged.

Never publish a first or follow-up release using a downloaded service-account
key. Never promote an internal release to another track without explicit owner
approval.

### App Store Connect API key

App Store Connect -> Users and Access -> Integrations -> App Store Connect API
-> Team Keys, generate a key with the App Manager role.

- `APPSTORE_ISSUER_ID`: the issuer UUID shown above the key list
- `APPSTORE_KEY_ID`: the key's ID in its row
- `APPSTORE_PRIVATE_KEY`: contents of the `.p8`, BEGIN/END lines included.
  It downloads exactly once, so save it somewhere before closing the tab.

### Distribution certificate

Xcode -> Settings -> Accounts -> your team -> Manage Certificates -> + ->
Apple Distribution. Then in Keychain Access, under My Certificates, right-click
"Apple Distribution: ..." -> Export as `.p12` and set a password.

```bash
base64 -i dist.p12 | pbcopy   # -> IOS_DIST_CERT_P12
```

The export password is `IOS_DIST_CERT_PASSWORD`.

### Team ID

developer.apple.com -> Membership details -> Team ID, ten characters.

### Discord webhook

Discord server settings -> Integrations -> Webhooks -> New Webhook -> Copy
Webhook URL. Only used by `discord.yaml` for PR and tag notifications.

## Known gaps

The iOS job is allowed to fail without blocking the Android release. Two
reasons it might once the credentials are in place:

- The UIScene migration (reunu/unustasis#157) is not merged upstream. Apple
  requires UIKit apps built against the post-iOS 26 SDK to adopt the scene
  lifecycle or they will not launch.
- `flutter_background_service_ios` 5.0.3 registers a `BGTaskScheduler`
  identifier from its own `didFinishLaunchingWithOptions`, which under UIScene
  runs after launch has finished. That API cannot be deferred. Upstream issue
  is open with no newer release, so a forked plugin behind
  `dependency_overrides` may be needed.

Sort both out before promoting an iOS build past internal testing.

## Staying current with upstream

See the sync section in the README. Branding is one commit on top of
`reunu/unustasis` main and is meant to be rebased, never merged.
