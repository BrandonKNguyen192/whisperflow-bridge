# Variables And Secrets

| Name / location | Used by | Source and scope | Rotation | Risk |
|---|---|---|---|---|
| Desktop token file | Receiver, overlay, Android profile | Generated locally; `~/.config/whisperbridge/token` on macOS/Ubuntu, `%APPDATA%\WhisperBridge\token` on Windows | Replace file, update profiles, restart | Grants send/status access |
| `WHISPERFLOW_TOKEN` | Shared receiver | Optional process environment override | Replace environment value and profiles | Avoid command-line exposure |
| `WHISPERFLOW_NO_SOUND`, `WHISPERFLOW_SOUND` | Desktop receiver | Local environment | No secret | Configuration only |
| Android release keystore | Gradle signing | `~/.config/whisperbridge/signing/whisperbridge-release.jks`, mode `0600` | Do not rotate unless migration is planned | Loss prevents seamless Android updates |
| Keychain service `com.whisperbridge.android-signing` | `build.sh` | Local macOS Keychain | Update together with keystore | Signing password |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | GitHub release workflow | GitHub Actions secret | Replace only with coordinated signing migration | Private signing key |
| Android release password/alias secrets | GitHub release workflow | GitHub Actions secrets | Update with keystore | Signing credentials |

No project secret is committed to Git or bundled into the APK. Android contains only user-entered profile tokens in app-private storage.

## Pre-Release Checklist

- Confirm release APK certificate fingerprint matches `documentation/release.md`.
- Confirm no token appears in process arguments, startup files, logs, APK resources, ZIPs, or Git history.
- Confirm all SHA-256 files verify.
- Back up the release keystore outside the working Mac; GitHub Actions secrets provide signing continuity but are not an exportable backup.
