# Releasing

Three workflows. `ci.yaml` analyzes and tests every push and PR. `nightly.yaml`
builds an APK from every push to `main` and publishes it as its own
`nightly-<timestamp>` prerelease, keeping the last 10. `release.yaml` fires on a
version tag and is the one that reaches the stores.

## Cutting a release

```bash
# bump pubspec.yaml: version: 2.0.1+42
# rewrite changelog.md with the user-facing changes
git commit pubspec.yaml changelog.md -m "Version bump to 2.0.1"
git tag -a 2.0.1 -m "Librescoot App for unu 2.0.1"
git push origin main 2.0.1
```

The tag must match `version:` in `pubspec.yaml` or the workflow stops before
building. That check exists because a mislabelled build in TestFlight cannot be
withdrawn, only superseded.

A hyphen in the tag makes it a prerelease: `2.0.1-rc1` goes to Play's
`internal` track and is marked prerelease on GitHub, a bare `2.0.1` goes to
`beta`. Override with the `workflow_dispatch` input. Every iOS build goes to
TestFlight regardless, since TestFlight has no track split.

`changelog.md` becomes both the GitHub release body and the Play "what's new"
text. Play truncates at 500 characters, so keep it short.

## Required secrets

Set these under Settings -> Secrets and variables -> Actions.

### Android

| Secret | What it is |
| --- | --- |
| `KEYSTORE` | Upload keystore, base64. `base64 -w0 upload-keystore.jks` |
| `KEYSTORE_PASSWORD` | Store and key password (the workflow uses one value for both) |
| `KEY_ALIAS` | Optional, defaults to `upload` |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account JSON, whole file |

The Play step is skipped when `PLAY_SERVICE_ACCOUNT_JSON` is absent, so Android
builds and GitHub releases work before Play is wired up.

The service account needs the Release Manager role in Play Console, and
`org.librescoot.mobile.unu` has to exist there with at least one manual upload
already: Play rejects the first upload of a package from the API.

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

### Play service account

1. Play Console -> Setup -> API access, link a Google Cloud project.
2. In that project: IAM & Admin -> Service Accounts -> Create, then
   Keys -> Add key -> JSON. The whole downloaded file is
   `PLAY_SERVICE_ACCOUNT_JSON`.
3. Back in Play Console -> Users and permissions, invite the service account's
   email and give it Release manager, or app-level release permissions on
   `org.librescoot.mobile.unu`.
4. Upload one bundle by hand first. Play rejects the API's first upload of a
   package it has never seen.

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
