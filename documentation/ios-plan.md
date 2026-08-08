# iOS / iPadOS App Plan — Whisper Bridge

Status: v1 foundation built and verified. Target: iOS 26+ with Liquid Glass UI,
iPhone + iPad, mirroring the Android app's feature set, plus native voice input.

## Goal

Ship a native SwiftUI app that turns the iPhone/iPad into the same
"talk into the phone, type on the Mac" controller the Android app provides
today, with an Apple-native skin: Liquid Glass materials, vibrancy, depth,
haptics, and adaptive light/dark behavior. The desktop receivers (macOS,
Ubuntu, Windows) already exist and need zero protocol changes.

## Protocol We Reuse (No Server Changes)

| Endpoint | Method | Body | Purpose |
|---|---|---|---|
| `/send` | POST | `{"text", "mode", "source", "enter_after"}` | Type / Clipboard / Append / Enter |
| `/control` | POST | `{"action", "dx", "dy", "button", "x", "y"}` | Mouse: `move, scroll, click, double_click, drag, down, up` |
| `/health` | GET | — | Reachability |
| `/status` | GET | — | Live activity (optional UI) |
| Pairing QR | — | `whisperbridge://pair?host=H&port=P&token=T&name=N` | Camera scan bootstraps a profile |

Auth is `Authorization: Bearer <token>`, matching `BridgeClient.kt`. Host
validation and all error codes (`401/403/415/400/413`) are enforced server-side.

## iOS-Specific Design Decisions

### 1. Liquid Glass (iOS 26 / 27)

Use Apple's Liquid Glass design language across every surface:

- `.glassEffect()` and `GlassEffectContainer` for the primary canvas, compose
  bar, trackpad, and settings panels so UI sits in layered, translucent depth
  over the content behind it.
- Keep the app's existing Komodos tokens as the tint layer: sage green accent
  `#2E7D46`, pure-black OLED dark mode `#000`, warm-neutral `#F5F5F7` light
  canvas, hairline borders instead of heavy shadows.
- Materials adapt automatically in light/dark; accent color picked by the user
  drives `tint()` everywhere (same custom RGB picker as Android).
- Motion follows the M3-style system already shipped in Android: press-scale on
  tap, fade/slide entrances, gentle "breath" on live status, `prefers-reduced-
  motion` respected.
- Verify final iOS 27 material behaviors (specular highlights, dynamic glass
  shape, vibrancy) against the 2026 SDK during implementation; the API surface
  above is stable from iOS 26.

### 2. Voice Input

Three input paths, in priority order:

1. **In-app dictation button** — `SFSpeechRecognizer` mic button next to the
   compose field. Transcribes on-device/offline when available, drops the text
   into the field, then Type/Enter/Clipboard works as usual. Requires
   `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.
2. **Share extension** — the iOS equivalent of Android's share sheet: any app
   (including Wispr Flow if/when it ships iOS, plus dictation keyboards and
   note apps) shares plain text into Whisper Bridge. The extension shows the
   existing confirm-preview UI and sends through the shared core client.
3. **Clipboard paste** — manual paste into the compose field, same as Android.

Android's Wispr Flow share flow maps 1:1 to path 2, so users get the identical
"dictate elsewhere, share into the bridge" muscle memory.

### 3. Profiles, Pairing, Security

- Profile model matches Android: `name` (MacBook Pro, Mac Studio, ...), `host`,
  `port`, `token`. One-tap pill chips switch targets.
- QR pairing via `AVCaptureMetadataOutput` parsing the existing
  `whisperbridge://pair` payload; manual host entry with a Test button is the
  fallback (same UX as Android).
- Store tokens in **Keychain** (shared access group so the share extension can
  read them); store non-secret profile metadata in App Group `UserDefaults`.
- Network permission: add `NSLocalNetworkUsageDescription`, and allow plain
  HTTP to LAN/Tailscale hosts in ATS (the server is intentionally HTTP;
  Tailscale carries the encryption, as in the Android design). The bridge
  client separately rejects public internet hosts, so the ATS exception is
  scoped to receiver addresses in practice.

### 4. Trackpad and Air Mouse

- **Trackpad**: a dedicated glass surface using `DragGesture`; translation
  deltas are throttled (~30-60 Hz) and POSTed as `/control move`. Tap = click,
  double-tap = double click, press-and-hold = drag, two-finger drag = scroll.
  The surface captures input on tap-in (`scrollDisabled`/`contentShape` +
  simultaneous gestures) so the page stops scrolling while steering, and a tap
  outside releases it — exactly the behavior we shipped in Android.
- **Air mouse**: `CoreMotion` `deviceMotion` stream while holding the air-mouse
  button; attitude deltas map to relative moves with deadzone, sensitivity
  sliders, and a brief auto-calibration on start. Mirrors `MotionKit.kt`.
- Haptics on clicks and profile switches via `UIImpactFeedbackGenerator`.

### 5. iPhone vs iPad Layouts

- **iPhone**: single-column. Compose field and Type/Enter/Clipboard row on top,
  profile chips beneath, gear opens the settings sheet. Dictation mic in the
  compose bar.
- **iPad**: `NavigationSplitView` — sidebar holds profiles and settings, detail
  pane is the compose/trackpad canvas. Multi-window support so a user can keep
  one window pointed at the MacBook Pro and another at the Mac Studio.
  Landscape uses a wide control rail; portrait keeps the phone layout.

## Project Layout

```
ios-app/
  project.yml                    # XcodeGen spec (reproducible project file)
  WhisperBridge.xcodeproj        # generated
  WhisperBridgeCore/             # shared framework: client, pairing, profiles, throttle
    BridgeClient.swift           # URLSession port of BridgeClient.kt
    Pairing.swift                # whisperbridge:// parser (port of Pairing.kt)
    ProfileStore.swift           # Keychain tokens + App Group metadata
    ControlStream.swift          # trackpad/air-mouse delta throttler
  WhisperBridge/                 # main app target (SwiftUI)
  ShareExtension/                # share sheet target
  WhisperBridgeTests/            # XCTest: Pairing, BridgeClient (URLProtocol mock), throttling
  Assets.xcassets                # icon, dark/light colors, accent palette
```

Build with XcodeGen so the project is reproducible from the command line, and
add a `ios-app/README.md` with build/signing steps.

## Phases

1. **Core app** — scaffold, compose view (Type/Enter/Clipboard/Append,
   enter-after-type), manual profile entry + Test, QR pairing, themes + accent
   picker, Local Network/ATS config, Keychain + App Group storage.
2. **Voice** — share extension with confirm preview; in-app `SFSpeechRecognizer`
   dictation button; status feedback for all three paths.
3. **Mouse** — glass trackpad with capture/release, scroll, clicks, drag; air
   mouse via CoreMotion; sensitivity settings.
4. **iPad** — split view, multi-window, landscape rail, Stage Manager pass.
5. **Polish + release** — Liquid Glass pass across surfaces, empty/error states,
   haptics, accessibility (VoiceOver labels, dynamic type), then TestFlight →
   App Store. Update `PRIVACY.md`/`README.md` and the public release notes.

Each phase is verifiable against the real receiver with `test_server.py`'s
endpoints and a local `curl` smoke test before any UI work.

## Signing and Distribution

- **Personal use**: free Apple ID via Xcode (7-day provisioning, reinstall
  weekly) or a $99 personal team for a year-long device install. TestFlight is
  the clean path for a private build.
- **Public release**: Apple Developer account, TestFlight beta, then App Store
  listing as a free utility app. No backend or account system needed, so the
  existing privacy posture stays intact.

## Risks and Open Questions

- Wispr Flow does not currently ship an iOS client we can verify against; the
  share-extension path is designed to absorb it the moment it exists, and the
  built-in dictation covers the same job today.
- Plain HTTP to LAN IPs requires the ATS local-networking exception and the
  iOS Local Network permission prompt; the flow must explain why the prompt
  appears.
- Liquid Glass requires iOS 26+. If a broad older-device audience matters
  later, we can lower the floor with custom translucent materials, but the plan
  keeps the floor at iOS 26 to honor the design goal.
- App Store review: keyboard/input remoting apps are accepted, but the listing
  should be explicit that this is an unofficial Wispr Flow companion (same
  disclaimer already in the README).

## First Build Checklist

1. Create `ios-app/` with XcodeGen spec + core framework + unit tests.
2. Port `Pairing.kt` and `BridgeClient.kt` to Swift with test parity.
3. Stand up the local receiver, pair from the simulator, and send text.
4. Then start Phase 2 voice, then mouse, then iPad layout.

## Current Build (Phase 1 Complete)

- `ios-app/` builds with XcodeGen on Xcode 27 and runs on the iOS 27 iPad
  simulator. `xcodebuild` and `xcodebuild test` both pass (10 unit tests).
- Core framework `WhisperBridgeCore` ports `BridgeClient.kt`, `Pairing.kt`,
  profile storage (tokens in Keychain), and theme persistence with test parity.
- UI: sidebar profiles + chips, compose (Type / Enter / Clipboard,
  enter-after), glass trackpad (move, tap-click, hold-drag, scroll, right and
  double click), settings with explicit connection Save / Test / Scan and
  paste-link pairing, Light / Earth / Dark OLED / System themes, and the eight
  accent presets plus custom RGB picker.
- Build and run instructions live in `ios-app/README.md`.

Remaining phases: share extension, in-app `SFSpeechRecognizer` dictation,
CoreMotion air mouse, and TestFlight / App Store signing.
