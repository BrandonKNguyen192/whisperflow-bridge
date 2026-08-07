# Release Operations

## Android Signing Identity

- Alias: `whisperbridge`
- Owner: `CN=Whisper Bridge, O=Whisper Bridge, C=US`
- SHA-256 certificate fingerprint: `0C:89:60:D7:F3:96:6C:2D:65:3A:52:1E:6F:4D:C8:FE:B6:64:65:4E:6B:FC:6C:A0:3A:DA:16:1F:9F:74:84:3D`
- Local keystore: `~/.config/whisperbridge/signing/whisperbridge-release.jks`
- Local password: macOS Keychain service `com.whisperbridge.android-signing`, account `password`
- CI continuity: `ANDROID_RELEASE_*` GitHub Actions secrets

The keystore is the permanent update identity. Never commit it, email it, regenerate it casually, or publish its password. Keep an encrypted offline backup under the repository owner's control.

## Versioning

`VERSION` contains semantic product version. `builds/BUILD` is the monotonically increasing Android `versionCode`. Every APK filename includes both.

## Release Procedure

1. Update `VERSION` and the default version fields in `android-app/app/build.gradle.kts`.
2. Run all Python tests, Android Lint, and `mac-server/verify_security.sh` against a live receiver.
3. Run `./build.sh --release` and verify metadata plus certificate with Android `aapt` and `apksigner`.
4. Run `./packaging/build-desktop-packages.sh` and verify every checksum.
5. Commit, push, pass CI, merge to `master`, and create the matching `vX.Y.Z` tag.
6. The tag workflow signs Android with GitHub secrets and publishes Android, Mac, Ubuntu, and Windows assets.
7. Install the published APK over the prior release on a real phone before announcing broadly.

## Recovery

If the local keystore is lost, GitHub Actions can continue signing while its secrets remain configured, but those secrets cannot be downloaded as a backup. Restore the encrypted offline keystore copy as soon as possible. If both are lost, existing installations cannot accept a normal update signed by a new key.
