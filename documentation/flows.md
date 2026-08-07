# Security-Sensitive Flows

## Pair A Desktop

**Actor:** local desktop user with the Android phone in hand.  
**Precondition:** receiver is running and its local console was opened with the token.  
**Outcome:** Android stores a profile containing host, port, display name, and token.

1. The authenticated local console builds a QR payload in `common/bridge_server.py`.
2. Android scans it through `ScanActivity.kt` and parses it through `Pairing.kt`.
3. A deliberate camera scan saves the profile. A browser deep link instead requires the confirmation dialog in `MainActivity.kt`.
4. Deny case: malformed payloads are discarded; an unconfirmed browser link cannot activate a profile.

Trust crossing: desktop token enters Android private app storage. Side effect: profile creation and active-profile change.

## Send Text Or Return

**Actor:** Android user.  
**Precondition:** a paired profile is selected and the desktop receiver is reachable.  
**Outcome:** text is copied/pasted, or Return is pressed, on the selected computer.

1. The user taps Type, Clipboard, or Enter in `MainActivity.kt`, or confirms a shared-text preview in `ShareReceiverActivity.kt`.
2. `BridgeClient.kt` sends JSON with `Authorization: Bearer <token>`.
3. `BridgeHandler.do_POST` validates Host, content type, token, size, JSON types, and mode.
4. The platform backend performs the requested side effect in the focused OS session.
5. Deny cases: invalid Host `403`, invalid token `401`, wrong content type `415`, invalid body/mode `400`.

Trust crossings: Android to network receiver, then receiver to OS input control. Side effects: clipboard mutation, paste, Return, local notification/chime.

## Install Login Persistence

**Actor:** local desktop user.  
**Outcome:** receiver restarts at user login without placing its token in startup arguments.

- macOS writes a `0600` LaunchAgent that resolves the token from the protected file (`mac-server/launch.py`). Legacy token-bearing plists are migrated before replacement.
- Ubuntu writes a `0600` systemd user unit (`ubuntu-server/launch.py`).
- Windows writes a current-user Run entry and protects the token ACL during installation (`windows-server/launch.py`, `install.ps1`).

## Publish Android Release

**Actor:** repository maintainer.  
**Precondition:** release key and GitHub Actions secrets are available.  
**Outcome:** APK updates remain installable over earlier release-signed versions.

1. `build.sh --release` retrieves the local password from macOS Keychain and refuses missing signing inputs.
2. Gradle signs with the keystore outside the repository.
3. Tag workflow reconstructs the same key from GitHub Actions secrets and publishes checksummed assets.
4. Deny case: absent credentials fail the release before Gradle can emit an unsigned public artifact.
