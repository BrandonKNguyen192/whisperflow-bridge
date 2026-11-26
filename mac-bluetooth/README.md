# WhisperBridge Bluetooth (Mac helper, text only)

A small menu bar app that lets the iPhone app send **text** to this Mac over
Bluetooth LE when there is no Wi‑Fi or Tailscale, for example on a plane.
It does not type anything itself: each message is passed to the normal
Whisper Bridge receiver on `http://127.0.0.1:9877/send` (same JSON, same
token), so that receiver must be running.

Trackpad, air mouse and control commands are **not** supported over Bluetooth.
The iPhone hides them for Bluetooth profiles and this helper refuses them.

## Build

```bash
./build.sh          # → build/WhisperBridge Bluetooth.app (arm64, signed)
swift test          # framing + forwarder tests
```

`SIGN_IDENTITY="-" ./build.sh` signs ad hoc if you don't have the Apple
Development identity. A stable identity keeps macOS's Bluetooth permission
across rebuilds.

The helper has no login item. Open it when you need it; quit from its menu.

## Before the flight (at home)

1. Make sure the Python receiver starts on its own (or start it before you take off).
2. On the iPhone, scan the pairing QR so the profile has the token.
3. Open **WhisperBridge Bluetooth** on the Mac and allow Bluetooth.
4. On the iPhone: Settings → profile → **Transport: Bluetooth (text only)** → **Test**.
   Accept the pairing prompt on both devices. After this, pairing is remembered.

## On the plane

Keep Bluetooth on (it is allowed in airplane mode). Open the helper on the Mac,
open the app on the iPhone, dictate and send. The menu bar item shows
"iPhone connected" and the last result.

## How it works

- Custom GATT service `6E1B0001-7A3C-4F5D-9B21-57A1B7E0B4C1`. The message
  characteristic requires encryption, so text and token only travel on a
  paired, encrypted link. The Mac sends an ack per message on a notify
  characteristic.
- Messages are JSON, split into frames with a 7‑byte header (version, message
  id, chunk index, chunk count). The helper reassembles them with a 64 KB cap
  and a 10 s timeout. `BLEFraming.swift` is shared with the iOS app (symlink).
- The helper keeps nothing on disk. The receiver checks the token as usual.
- Receiver on another port: `defaults write com.whisperbridge.bluetooth receiverPort -int 9878`.

## Limits

- Range: a few metres, same as any Bluetooth LE link.
- Speed: fine for dictation (a few KB per second); max 64 KB per message.
- The iPhone connects to the first Mac it finds running the helper. If two
  Macs run it nearby, quit it on the one you don't want.
- iOS can only keep the link while the app is open.
