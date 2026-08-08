# Whisper Bridge — iOS / iPadOS app

Native SwiftUI companion for the Whisper Bridge desktop receiver, targeting
iOS 26+ so it can use Liquid Glass materials. Speaks the exact same HTTP
contract as the Android app, so existing receivers need no changes.

## Requirements

- Xcode 26+ (built with Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
cd ios-app
xcodegen generate
xcodebuild -scheme WhisperBridge -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

## Test

```bash
xcodebuild -scheme WhisperBridge -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

## Pair With A Receiver

1. Run the receiver on your computer (`mac-server/launch.py`) and open
   `http://localhost:9877`.
2. In the app: Settings → paste the pairing link from the console's "Copy
   link" button, or scan the QR with a physical device. Simulators have no
   camera, so paste is the simulator path.
3. Tap **Save**, then **Test** to verify host and token.

The receiver console's pairing link looks like:
`whisperbridge://pair?host=H&port=P&token=T&name=N`.

## Layout

| Path | Purpose |
|---|---|
| `WhisperBridgeCore/` | Shared framework: `BridgeClient` (HTTP), `Pairing` (QR/deep link parser), `ProfileStore` (Keychain tokens), `ThemeStore` |
| `WhisperBridge/` | SwiftUI app: split view, compose, trackpad, settings, QR scan |
| `WhisperBridgeTests/` | Unit tests for pairing parsing and HTTP behavior (URLProtocol stub) |

The `.xcodeproj` and `Info.plist` are generated from `project.yml` and are
gitignored — edit `project.yml`, then rerun `xcodegen generate`.

## Status

- [x] Core protocol parity (send / control / health / probe, bearer auth)
- [x] Pairing parser parity + QR scan + paste-link fallback
- [x] Profiles with Keychain-backed tokens, sidebar + chips
- [x] Compose: Type / Enter / Clipboard, enter-after
- [x] Trackpad: move, tap-click, hold-drag, scroll, right/double click
- [x] Themes: Light / Earth / Dark OLED / System + accent picker
- [ ] Share extension (voice input from any app / Wispr Flow)
- [ ] In-app dictation (`SFSpeechRecognizer`)
- [ ] Air mouse (`CoreMotion`)
- [ ] TestFlight / App Store signing
