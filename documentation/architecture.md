# Architecture

## Product

Whisper Bridge sends user-confirmed text from an Android device to a selected desktop receiver and pastes it into the currently focused field. The receiver supports macOS, Ubuntu, and Windows; Tailscale is the recommended remote transport.

## Components

| Component | Stack | Responsibility |
|---|---|---|
| Android app | Kotlin, Material 3, `HttpURLConnection` | Profiles, pairing, share preview, authenticated sends |
| Shared receiver | Python standard library | HTTP API, token auth, Host validation, local console, pairing QR |
| macOS backend | Python, `pbcopy`, AppleScript | Clipboard, paste, Return, LaunchAgent, overlay |
| Ubuntu backend | Python, `wl-clipboard`/`ydotool` or `xclip`/`xdotool` | Clipboard, paste, Return, systemd user service |
| Windows backend | Python, PowerShell, SendKeys | Clipboard, paste, Return, current-user login startup |

The protocol lives in `common/bridge_server.py`. Platform launchers configure a target name and replace only the input, notification, and sound functions through `common/receiver_runtime.py`.

## Trust Boundaries

- Android to receiver crosses a network boundary. `/send` and `/status` require a bearer token; `/health` reveals only availability.
- The local web console can bootstrap with a token query parameter because browser navigation cannot set an authorization header. The page removes that query from the visible URL immediately.
- The receiver to desktop input backend crosses the OS-control boundary. A successful request can paste and optionally press Return in the focused application.
- Release signing crosses from GitHub source into a private Android signing identity stored outside the repository.

## Known Risks And Assumptions

- HTTP is unencrypted. A trusted LAN is assumed; Tailscale is required for confidential remote transport (`README.md`, `SECURITY.md`).
- A valid token grants keyboard-like power to the focused desktop application (`common/bridge_server.py`).
- GNOME Wayland blocks ordinary synthetic input; Ubuntu relies on `ydotool` or a compatible `wtype` environment (`ubuntu-server/backend.py`).
- Windows and Ubuntu packaging is statically tested on macOS and must still receive real-machine installation tests before broad promotion (`documentation/tests.md`).
- The Mac ZIP is not Apple-notarized, so Gatekeeper may require an explicit Open action.

## Out-Of-Scope Capabilities

There is no cloud service, account database, email, scheduled work, public SEO route, embedded agent, webhook, analytics, or advertising integration.

## Related Documents

- [Flows](flows.md)
- [Permissions](permissions.md)
- [Variables And Secrets](variables.md)
- [Test Coverage](tests.md)
- [Release Operations](release.md)
- [Privacy Policy](../PRIVACY.md)
- [Security Policy](../SECURITY.md)
