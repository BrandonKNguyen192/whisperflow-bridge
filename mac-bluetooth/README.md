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
2. Open **WhisperBridge Bluetooth** on the Mac and allow Bluetooth. If the menu
   says "Bluetooth permission needed", click **Open Bluetooth Privacy Settings…**
   and turn it on.
3. Menu bar → **Pair iPhone…** shows a QR (the receiver's token from
   `~/.config/whisperbridge/token` plus `transport=bluetooth`). On the iPhone:
   Settings → **Scan**. It creates "<Mac> · Bluetooth" and selects it.
   **Copy link** works too: paste it with "Paste pairing link".
4. Tap **Test** on the iPhone. There is no Bluetooth pairing prompt: the QR's
   token is the pairing (see "How it works").

The menu shows the Bluetooth state, whether an iPhone is connected, whether the
receiver on port 9877 answers, and the last message. The iPhone shows a blue
"Bluetooth · Connected to <Mac>" pill whenever a Bluetooth profile is active
("Wi‑Fi" or "Tailscale" otherwise).

## On the plane

Keep Bluetooth on (it is allowed in airplane mode). Open the helper on the Mac,
open the app on the iPhone, dictate and send. The menu bar item shows
"iPhone connected" and the last result.

## How it works

- Custom GATT service `6E1B0001-7A3C-4F5D-9B21-57A1B7E0B4C1`: a write
  characteristic for message frames and a notify characteristic for acks.
- **Security is at the app layer, not OS pairing.** An iPhone and a Mac on the
  same Apple ID already share Continuity keys and an LE link, and
  encryption-required characteristics there stall or never prompt. Instead each
  message is sealed with AES-GCM using `HKDF-SHA256(receiver token)`. Only a
  phone that scanned the QR can send; nobody nearby can read the text; the
  token itself never crosses the air. Messages older than 5 minutes or replayed
  are refused, and acks are sealed too. The helper forwards with the token in
  `~/.config/whisperbridge/token` (read per message).
- Frames have a 7‑byte header (version 2, message id, chunk index, chunk
  count). Reassembly caps at 64 KB with a 10 s timeout. `BLEFraming.swift` and
  `BLESecurity.swift` are shared with the iOS app (symlinks).
- Receiver on another port: `defaults write com.whisperbridge.bluetooth receiverPort -int 9878`.

## Troubleshooting

- Mac: menu → **Show Log** opens `~/Library/Logs/WhisperBridgeBluetooth.log`
  (state changes, connections, write sizes, receiver HTTP status; never text or
  tokens).
- iPhone: Settings → Bluetooth profile → **Bluetooth diagnostics** → Copy log.
  Errors include the CoreBluetooth domain and code.

## Limits

- Range: a few metres, same as any Bluetooth LE link.
- Speed: fine for dictation (a few KB per second); max 64 KB per message.
- The iPhone connects to the first Mac it finds running the helper. If two
  Macs run it nearby, quit it on the one you don't want.
- iOS can only keep the link while the app is open.
