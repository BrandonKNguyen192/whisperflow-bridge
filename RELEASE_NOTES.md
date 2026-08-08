# Whisper Bridge - v1.2.0

Whisper Bridge lets you dictate with Wispr Flow on Android and send the result to a computer on your local network or through Tailscale. This is an independent, unofficial companion project and is not affiliated with or endorsed by Wispr.

## New Features

- **Mouse control from your phone:** A Mac trackpad view moves and clicks the cursor remotely, plus an air-mouse mode that steers the cursor by tilting the phone.
- **Earth theme:** A warm earth palette joins Light, Pure OLED Black, and System modes, with any RGB accent color.
- **Material 3 motion:** Press, entrance, and breathing micro-interactions across the Android app.
- **iOS/iPadOS client (preview):** A SwiftUI client in `ios-app/` with typing, clipboard, Enter, pairing, and the same theme system. Source ships in the repo while it finishes beta.
- **Branded setup guide:** A printable PDF walkthrough plus expanded first-time setup docs.

## Improvements

- **Cleaner Android UI:** Centered labels, aligned icon rows, and consistent Material sizing across every screen.
- **Sharper pairing:** Tailscale CGNAT hosts are labeled correctly, deep-link pairing asks for confirmation before saving, and the share sheet sends nothing until you tap.
- **Stronger receivers:** Ubuntu and Windows backends gained more robust input paths and installers.

## Bug Fixes

- Fixed the Enter/Return button that could fail with HTTP 400 against the Mac receiver.
- Fixed narrow Android action buttons that wrapped labels one character per line.

## Upgrade Note

- Existing v1.1.0 installs upgrade normally; both versions use the project's permanent signing key. Users still on the v1.0.0 debug-signed APK must uninstall once before installing v1.2.0.

## Platform Status

- Android and macOS: release candidate, verified locally.
- Ubuntu: beta; automated backend tests pass, a real-desktop smoke test is still recommended.
- Windows: preview; automated tests pass, a real-PC smoke test is still recommended.
- iOS/iPadOS: preview; source builds and runs on device, not yet wired into the automated release pipeline.

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
