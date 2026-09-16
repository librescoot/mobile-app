# Releasing

Three workflows. `ci.yaml` analyzes and tests every push and PR. `nightly.yaml`
builds signed Android and iOS artifacts from every push to `main`, publishes the
AAB to Play internal testing and the IPA to TestFlight, and publishes the APK as
a `nightly-<timestamp>` prerelease, keeping the last 10. `release.yaml` builds
signed release artifacts from a version tag or manual dispatch, uploads the AAB
to its resolved Play track, and can upload iOS to TestFlight when configured.

## Cutting a release

The app version tracks the matching Librescoot stable release's `major.minor`.
Mobile releases use their own patch and prerelease suffix. CI overrides the
Android build number with seconds since 2020, which is monotonic and distinct
from historic manually assigned codes. For example, releases aligned with
Librescoot 1.3 may be `1.3.1+48` or `1.3.2-beta.1+49`; keep the format
conventional Dart/Flutter semantic versioning rather than introducing a second
embedded version tuple.

```bash
# bump pubspec.yaml, for example: version: 1.3.1+48
# rewrite changelog.md and localized distribution/play changelog files
distribution/play/metadata/android/<locale>/changelogs/<tag>.txt
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
overridden for a manual dispatch. It verifies the uploaded AAB's version code
and SHA-256 before committing the Play edit, then checks the committed track and
bundle again. Every configured iOS build goes to TestFlight, since TestFlight
has no track split.

`changelog.md` becomes the GitHub release body. Play release notes come from
the per-locale files
`distribution/play/metadata/android/<locale>/changelogs/<version>.txt`, keyed by
the release version name (the git tag, e.g. `1.3.1.txt` or
`1.3.2-beta.1.txt`). `en-US` is required and a missing locale file fails the
release rather than shipping stale text; every file must stay within Play's
500-character limit.

Nightly internal-track builds synthesize their English Play notes from the
commit subjects since the previous `nightly-*` tag instead (see
`.github/scripts/nightly_notes.py`). The nightly workflow uses the same
seconds-since-2020 value for Android's version code and iOS's TestFlight build
number, ensuring that every pushed build is newer than its predecessor.

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

The iOS jobs are skipped when `APPSTORE_KEY_ID`, `IOS_DIST_CERT_P12` or
`APPLE_TEAM_ID` is missing, so Android can publish before Apple's side is set
up. On pushes to `main`, the nightly iOS job uploads automatically; App Store
Connect then processes the build and distributes it according to the TestFlight
group's automatic-distribution setting.

Provisioning profiles are fetched from App Store Connect at build time rather
than stored, so they cannot drift out of step with the certificate. The app and
embedded widget bundle IDs use the manually managed `Librescoot App Store CI`
and `Librescoot Widget App Store CI` profiles for
`org.librescoot.mobile.unu` and
`org.librescoot.mobile.unu.ScooterWidget`. Both need the
`group.org.librescoot.mobile.unu` app group. Regenerate both profiles when the
distribution certificate changes. The disabled share extension is not embedded
and therefore needs neither an App ID nor a provisioning profile.

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

GitHub Actions authenticates through Google Workload Identity Federation, not a
stored token or service-account key. The `github-actions` pool's `mobile-app`
provider accepts only OIDC tokens for `librescoot/mobile-app`; it may impersonate
`librescoot-play-publisher@android-apps-508215.iam.gserviceaccount.com` through
`roles/iam.workloadIdentityUser`.

Keep organization policy preventing service-account key creation enabled. A
maintainer who needs manual Publisher access must use a short-lived impersonated
token; never download or store a service-account key. Never promote an internal
release to another track without explicit owner approval.

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
