# Releasing

Two workflows. `nightly.yaml` builds an APK from every push to `main` and
replaces the rolling `nightly` prerelease. `release.yaml` fires on a version tag
and is the one that reaches the stores.

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
`com.librescoot.app` has to exist there with at least one manual upload
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

Provisioning profiles are fetched from App Store Connect at build time rather
than stored, so they cannot drift out of step with the certificate. Both
`com.librescoot.app` and `com.librescoot.app.ScooterWidget` need App Store
provisioning profiles that include the `group.com.librescoot.app` app group.

## Known gaps

The iOS job is allowed to fail without blocking the Android release. Two
reasons it currently might:

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
