# F-Droid setup

The app ID is `com.stackek.tracky`.

## Included files

- `.fdroid.yml` — build metadata for running `fdroid build` from this repository.
- `fdroid/metadata/com.stackek.tracky.yml` — metadata for submission to the
  official F-Droid data repository.
- `fastlane/metadata/android/en-US/` — app title, descriptions, icon, feature
  graphic and version changelog (versionCode 2).

## Local F-Droid build

Install `fdroidserver`, then from this repository run:

```sh
fdroid build com.stackek.tracky:2
```

## Submit to the official F-Droid repository

1. Fork https://gitlab.com/fdroid/fdroiddata.
2. Copy `fdroid/metadata/com.stackek.tracky.yml` to
   `metadata/com.stackek.tracky.yml` in the fork.
3. Commit, push and open a merge request against `master`.
4. F-Droid will build from the `v1.0.1` tag using Flutter `3.47.4`.

The Fastlane files are already in this repository and are picked up from the
tagged commit, so they should be updated before creating each release tag.

## Signing

F-Droid signs its own builds with the F-Droid signing key. The APK published on
GitHub is signed separately. Users cannot upgrade between the two builds
without uninstalling first.
