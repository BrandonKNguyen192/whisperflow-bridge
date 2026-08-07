# 🎙 Whisper Flow Bridge

Talk into **Whisper Flow** on your Android phone → text appears on your Mac, typed into whatever app has focus. Like a walkie-talkie for dictation.

```
┌──────────────┐   WiFi / LAN / Tailscale   ┌──────────────┐
│   Android     │  ──── HTTP POST ────►     │     Mac       │
│  Whisper Flow │      text/plain           │  server.py    │
│  → Share →    │                           │  → ⌘V paste   │
│  Bridge App   │                           │  → clipboard  │
└──────────────┘                            └──────────────┘
```

## Features

- **Multi-profile switching** — toggle between multiple Macs (MacBook, Studio, etc.) with one-tap profile chips. Each profile stores its own host, port, and token.
- **Pure OLED dark mode** — the Android app and web console follow your system preference. True black (#000) background with a vibrant green accent.
- **Enter-after-type** — optional checkbox to auto-press Return/Enter after pasting text. Perfect for sending messages or submitting forms.
- **Pair by QR** — scan a QR code from the Mac console to auto-fill connection details.
- **Three modes** — Type (⌘V paste), Clipboard (copy only), and Append (add to existing clipboard).
- **Remote via Tailscale** — works anywhere, not just on your home WiFi. Token-based auth keeps it secure.
- **Menu bar app** — always-on with live status, one-click pairing, and login-at-launch support.
- **Share sheet integration** — share transcribed text directly from Whisper Flow to your Mac.

## How It Works

1. **Speak** into Whisper Flow on your Android phone
2. **Share** the transcribed text → **Whisper Bridge** (or type/paste manually)
3. The bridge app sends the text over your local WiFi to the Mac server
4. The Mac server **pastes it** (⌘V) into whatever text field has focus — or copies it to your Mac's clipboard

## Setup

### 1. Mac Server

No dependencies — just Python 3 (built into macOS).

```bash
cd mac-server
python3 server.py
```

You'll see:
```
  ╔══════════════════════════════════════════════╗
  ║       Whisper Flow Bridge — Mac Server       ║
  ╠══════════════════════════════════════════════╣
  ║  Listening on 0.0.0.0:9877                   ║
  ║  Mode: type (⌘V paste)                       ║
  ║  Auth: none (LAN ok) · --token for remote    ║
  ║  LAN : http://<lan-ip>:9877                  ║
  ║  Tail: http://<tailnet-ip>:9877              ║
  ╚══════════════════════════════════════════════╝
```

**First run:** macOS will ask for permission to control your computer via Accessibility. Go to **System Settings → Privacy & Security → Accessibility** and allow Terminal (or whichever app runs the script).

**Options:**
```bash
python3 server.py --port 8080          # custom port
python3 server.py --clipboard-only     # only copy to clipboard, don't auto-paste
python3 server.py --token SECRET       # require a shared secret (use for Tailscale/remote)
```

**Test it** — open http://localhost:9877 in your browser for a quick web UI, or:
```bash
curl -X POST http://localhost:9877/send \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello from the terminal!", "mode": "type"}'
```

### 2. Find Your Mac's IP Address

```bash
ipconfig getifaddr en0
# e.g., 192.168.1.42
```

### 3. Android App

Built with **AGP 8.2.2 · Kotlin 1.9.22 · Gradle 8.5 · compileSdk 34** (minSdk 26). The build needs **JDK 17** — Android Studio bundles it, so don't point Gradle at JDK 8.

**Prereqs:** Android Studio (Hedgehog 2023.1.1 or any newer release), SDK 34 + build-tools (the SDK Manager offers them on first sync), and either a phone with **Developer options → USB debugging** (or **Wireless debugging**) enabled, or an API 34 emulator.

**In Android Studio (recommended):**
1. **File → Open** and select the `android-app/` folder — the one containing `settings.gradle.kts`, *not* the repo root.
2. Trust the project and let **Gradle sync** finish (it downloads Gradle 8.5 and the deps, including the ZXing scanner). Accept any SDK 34 / build-tools prompts.
3. Connect your phone (tap **Allow** on the USB-debugging fingerprint) or start an emulator.
4. **Run → Run 'app'** (▶). Android Studio compiles `app-debug.apk` and installs it.
5. On the phone open **Whisper Bridge**. First-time pairing: tap **Scan** and aim at the QR on your Mac console — the app requests **Camera** permission the first time (allow it). Or type the Mac IP / port / token by hand. Tap **Test**.

**From the command line (optional):** this checkout ships the Gradle wrapper *properties* (Gradle 8.5) but not the `gradlew` launcher script. The easiest fix is to let Android Studio sync once (it honors the wrapper config); alternatively generate the launcher with a system Gradle (`gradle wrapper --gradle-version 8.5` inside `android-app/`). Then:

```bash
cd android-app
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

If `adb devices` shows the phone as *unauthorized*, accept the fingerprint prompt on the phone.

**Permissions:** the app declares `INTERNET` + `CAMERA`. Camera is requested at runtime the first time you tap **Scan**; the deep-link path (`whisperbridge://…`) needs none. Cleartext HTTP to your Mac is allowed by the included `res/xml/network_security_config.xml` — required because the bridge speaks plain HTTP inside your LAN / Tailscale tunnel (the tunnel itself is encrypted).

### 4. Use It!

**From Whisper Flow:**
1. Transcribe your speech in Whisper Flow
2. Tap the **Share** button (⋮ or share icon)
3. Choose **Whisper Bridge** from the share sheet
4. Text is auto-sent to your Mac ✓

**Manual entry:**
1. Open the Whisper Bridge app
2. Type or paste text
3. Tap **⌘V Type on Mac** or **📋 Clipboard**

## Modes

| Mode | What it does |
|------|-------------|
| **Type** (default) | Copies text to Mac clipboard, then simulates ⌘V to paste into the focused app |
| **Clipboard** | Copies text to Mac clipboard only — you paste manually |
| **Append** | Appends to existing clipboard content with a newline |

## Remote Use (Tailscale)

The same server works away from home — no port forwarding, no certificates.

1. Install **Tailscale** on the Mac and on the Android phone; sign in with the same account.
2. On the Mac, note its tailnet address: `tailscale ip -4` (e.g. `100.64.1.23`) or its MagicDNS name (e.g. `mac-studio`).
3. Start the server **with a token**: `python3 server.py --token YOUR_SECRET` (or `export WHISPERFLOW_TOKEN=...`). The token gates `/send` and the web console.
4. In the app, put the tailnet address in **Host** and the same secret in **Token**, then tap **Test** — it verifies the token too.

Why this is safe: Tailscale's WireGuard tunnel is encrypted end‑to‑end, so plain HTTP inside it is fine. The server already listens on `0.0.0.0`, so one running instance serves your LAN *and* your tailnet at once — at home use the LAN IP, away use the tailnet address. Keep Tailscale **Funnel** *off*; Funnel would publish the port to the public internet. For a network‑level lock, restrict the port to just your phones with Tailscale ACLs.

```bash
# from anywhere on your tailnet
curl -H "Authorization: Bearer YOUR_SECRET" -H 'Content-Type: application/json' \
  -d '{"text": "dictated from a coffee shop", "mode": "type"}' \
  http://<tailnet-ip>:9877/send
```

> First time the server listens, macOS may ask you to allow incoming connections for Python — click **Allow** (System Settings → Network → Firewall).

## Menu Bar App (always-on, launches at login)

`menubar.py` runs the bridge in the background and puts a 🎙 status item in your menu bar showing the live **LAN** and **Tailscale** addresses, the token state, and the last dictation — with one-click *Open console*, *Copy pairing link*, and *Quit*.

```bash
pip3 install rumps            # one-time; pulls PyObjC for the menu bar
python3 mac-server/menubar.py --token YOUR_SECRET
```

Launch at login (writes a LaunchAgent to `~/Library/LaunchAgents/`):

```bash
python3 mac-server/menubar.py --token YOUR_SECRET --install-login   # add
python3 mac-server/menubar.py --uninstall-login                     # remove
python3 mac-server/menubar.py --print-plist                         # inspect (no side effects)
```

If `rumps` isn't installed it falls back to running the server headless, so a login launch still works — just without the icon. Don't run `server.py` and `menubar.py` on the same port at once.

**Status dot in the title:** the menu-bar icon carries a colored dot — 🟢 when your Tailscale tailnet is connected (remote-ready), 🟡 when you're on LAN only, 🔴 if the port couldn't bind. (A few macOS setups render menu-bar emoji in monochrome; the drop-down menu always spells the state out in plain text.)

**Chime:** every successful dictation plays a soft macOS sound (default `Tink`) through `afplay`, in both standalone and menu-bar mode. Pick another with `--sound Pop` / `--sound Glass`, or silence it with `--no-sound` (or `WHISPERFLOW_NO_SOUND=1`). The flag is baked into the login item, so `--install-login --no-sound` stays quiet across reboots.

## Pair by QR (auto-fill host + token)

The console shows a **Pair phone** card with a QR code (toggle LAN / Tailscale). Scanning it fills the app's Host, Port, and Token in one step — no typing.

- **In-app:** tap **Scan** in the Connection card and point the camera at the QR.
- **Any scanner:** scan with your phone's camera / Google Lens — the `whisperbridge://pair?...` link opens the app and fills the fields via deep link.

The QR is generated in the browser by a vendored copy of Kazuhiko Arase's MIT-licensed QR encoder (`mac-server/qrcode.js`); nothing leaves your machine.

## Troubleshooting

- **"Connection failed"** — Make sure both devices are on the same WiFi network. Check the IP address. Make sure the Mac server is running.
- **Text doesn't appear** — macOS Accessibility permission is required. Go to System Settings → Privacy & Security → Accessibility and enable your terminal app.
- **Firewall blocking** — macOS may block incoming connections. Allow Python in System Settings → Network → Firewall, or temporarily disable the firewall to test.
- **Share sheet doesn't show Whisper Bridge** — Reinstall the app, or look under "More" in the share sheet.

## Project Structure

```
Whisperflow Bridge/
├── mac-server/
│   ├── server.py              # Bridge engine (zero dependencies)
│   ├── launch.py              # Convenience launcher: server + overlay
│   ├── overlay.py             # Floating status pill (tkinter)
│   ├── menubar.py             # Menu-bar app + login item (needs `rumps`)
│   └── qrcode.js              # Vendored QR encoder for the console (MIT)
├── android-app/               # Android Studio project
│   ├── app/src/main/
│   │   ├── java/com/whisperbridge/
│   │   │   ├── MainActivity.kt           # Multi-profile UI + chip toggles + manual entry
│   │   │   ├── ShareReceiverActivity.kt  # Receives shared text from Whisper Flow
│   │   │   ├── ScanActivity.kt           # In-app QR scanner (ZXing)
│   │   │   ├── ProfileManager.kt         # Multi-profile storage (JSON in SharedPreferences)
│   │   │   ├── Pairing.kt                # Parses pairing QR / deep link URLs
│   │   │   └── BridgeClient.kt           # HTTP client (type, clipboard, append, enter_after)
│   │   └── res/                          # Layouts, colors (light + dark), icons, themes
│   └── build.gradle.kts
├── DESIGN.md                    # Komodos design language reference
├── LICENSE                      # MIT
└── README.md
```
