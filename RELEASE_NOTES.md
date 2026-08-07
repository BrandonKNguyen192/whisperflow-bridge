# Whisper Bridge - v1.1.0

Whisper Bridge lets you dictate with Wispr Flow on Android and send the result to a computer on your local network or through Tailscale. This is an independent, unofficial companion project and is not affiliated with or endorsed by Wispr.

## New Features

- **Choose your computer:** Save multiple receiver profiles and switch between them from the top of the Android compose screen.
- **Ubuntu receiver beta:** Install a login-persistent receiver for Ubuntu with Wayland and X11 support.
- **Windows receiver preview:** A first Windows client uses built-in PowerShell input APIs and can start automatically when you sign in.
- **One-step computer installers:** Downloadable packages now include guided installers for macOS, Ubuntu, and Windows.
- **Return from your phone:** Send Enter or Return separately, or enable it after typing.
- **Personalized appearance:** Choose light mode, pure-black OLED mode, and any RGB accent color in the Android app.

## Improvements

- **Safer pairing:** Receivers use a generated access token stored outside launch arguments, apply request-size limits, and avoid exposing sensitive text in logs.
- **Clearer compose screen:** Connection details live in Settings so the main screen stays focused on typing, Return, and clipboard actions.
- **Durable macOS service:** The Mac receiver starts at login and recovers automatically if it exits.
- **Reproducible releases:** Android builds now have permanent signing, sequential build numbers, checksums, CI checks, and versioned APK archives.

## Bug Fixes

- Fixed the Return button request that could fail with HTTP 400 against the Mac receiver.
- Fixed narrow Android action buttons that wrapped labels one character per line.
- Improved host naming and pairing behavior across multiple computers.

## Upgrade Note

- **Action required for v1.0.0 users:** The old public APK used Android's temporary debug certificate. Uninstall that APK once, then install v1.1.0. Future releases will upgrade normally because v1.1.0 uses the project's permanent signing certificate.

## Platform Status

- Android and macOS: release candidate, verified locally.
- Ubuntu: beta; automated backend tests pass, but a real Ubuntu desktop smoke test is still required.
- Windows: preview; automated command-construction tests pass, but a real Windows PC smoke test is still required.
