# 🎙 Whisper Flow Bridge

Talk into **Whisper Flow** on your Android phone → text appears on your Mac, typed into whatever app has focus. Like a walkie-talkie for dictation.

## Quick Start

1. **Download the APK** from [Releases](https://github.com/BrandonKNguyen192/whisperflow-bridge/releases) and install on your Android phone
2. **Start the Mac server:**
   ```bash
   cd mac-server && python3 launch.py
   ```
   On first run a token is generated and saved to `~/.config/whisperbridge/token` (mode 0600). The token is printed once so you can pair your phone.
3. **On the phone:** Open Whisper Bridge → tap the gear ⚙️ → enter your Mac's IP + port + token → tap **Test**
4. **Use it:** Type in the app, or share from Whisper Flow → Whisper Bridge

For Tailscale remote access:
```bash
python3 launch.py --install-login
```
Then use your Mac's Tailscale IP (e.g. `100.x.x.x`) in the phone app. The `--install-login` flag makes it launch at boot and stay alive.

```
┌──────────────┐   WiFi / LAN / Tailscale   ┌──────────────┐
│   Android     │  ──── HTTP POST ────►     │     Mac       │
│  Whisper Flow │      text/plain           │  server.py    │
│  → Share →    │                           │  → ⌘V paste   │
│  Bridge App   │                           │  → clipboard  │
└──────────────┘                            └──────────────┘
```

## Features ✨

- **Multi-profile switching** — toggle between multiple Macs (MacBook, Studio, etc.) with one-tap profile chips
- **Theme system** — Light, Pure OLED Black (#000), and System modes. Choose any accent color from a Material picker
- **Enter/Return button** — separate button to send Return key after typing
- **Enter-after-type** — optional checkbox to auto-press Enter after pasting
- **Pair by QR** — scan a QR code from the Mac console to auto-fill connection details
- **Four modes** — Type (⌘V paste), Clipboard (copy only), Append (add to existing clipboard), and Enter (Return key)
- **Remote via Tailscale** — works anywhere, not just on your home WiFi. Token-based auth
- **Login item** — `--install-login` makes it launch at boot and stay alive
- **Share sheet integration** — share transcribed text directly from Whisper Flow to your Mac
- **Floating overlay** — status pill on your Mac desktop showing live dictation feedback

## How It Works

1. **Speak** into Whisper Flow on your Android phone → transcribed text appears
2. **Share** → **Whisper Bridge** (or open the app and type/paste)
3. The bridge app sends the text over WiFi/LAN or Tailscale to the Mac server
4. The Mac server pastes it (⌘V) into the focused text field, or copies to clipboard

## Setup

### 1. Mac Server

No dependencies — just Python 3 (built into macOS).

```bash
cd mac-server
python3 launch.py
```

Then open **http://localhost:9877** in your browser — you'll see the console with a QR code to pair your phone.

**First run:** macOS will ask for permission to control your computer via Accessibility. Go to **System Settings → Privacy & Security → Accessibility** and allow Terminal (or whichever app runs the script).

**Options:**
```bash
python3 launch.py --install-login   # run at boot, stay alive (recommended)
python3 launch.py --port 8080                       # custom port
python3 launch.py --no-sound                        # disable the chime
python3 launch.py --uninstall-login                 # remove login item
```

**Test it:**
```bash
curl -X POST http://localhost:9877/send \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $(cat ~/.config/whisperbridge/token)" \
  -d '{"text": "Hello from the terminal!", "mode": "type"}'
```

### 2. Find Your Mac's IP Address

```bash
ipconfig getifaddr en0
# e.g., 192.168.1.42
```

### 3. Android App

**Download the APK** from [GitHub Releases](https://github.com/BrandonKNguyen192/whisperflow-bridge/releases) and install it on your phone. You'll need to allow "Install from unknown sources" in Android Settings. Verify the download with:
```bash
shasum -a 256 app-release.apk
```

**To build from source:** Open the `android-app/` folder in Android Studio, sync Gradle, and Run. Requires JDK 17 and SDK 34.

**First launch:** Open Whisper Bridge → tap the gear ⚙️ → enter your Mac's details:
- **Host:** your Mac's LAN IP (e.g. `192.168.1.42`) or Tailscale IP (e.g. `100.105.11.31`)
- **Port:** `9877` (default)
- **Token:** the same secret you passed with `--token`
- Tap **Test** to verify the connection

Or scan the QR code from the Mac console (`http://localhost:9877`) by tapping **Scan** in settings.

### 4. Use It!

**From the app:**
1. Type or paste text → tap **Type on Mac**, **Enter**, or **Clipboard**

**From Whisper Flow:**
1. Transcribe your speech in Whisper Flow
2. Tap the **Share** button (⋮ or share icon)
3. Choose **Whisper Bridge** from the share sheet
4. Text is auto-sent to your Mac ✓

**Manual entry:**
1. Open the Whisper Bridge app
2. Type or paste text
3. Tap **Type on Mac**, **Enter**, or **Clipboard**

## Modes

| Mode | What it does |
|------|-------------|
| **Type** (default) | Copies text to Mac clipboard, then simulates ⌘V to paste into the focused app |
| **Enter** | Sends a Return/Enter keypress (no text) |
| **Clipboard** | Copies text to Mac clipboard only — you paste manually |
| **Append** | Appends to existing clipboard content with a newline |

## Android App Features

### Settings (gear icon ⚙️)
- **Connection** — Host IP, Port, Token, Scan QR, and Test button
- **Appearance** — Theme (Light / Dark OLED / System), Accent color picker (8 colors: Sage, Sky, Rose, Amber, Violet, Teal, Ruby, Mint)

### Profile switcher
Tap the profile chips at the top to switch between multiple Macs. Long-press to delete. Each profile stores its own host, port, and token.

### Theme
- **Light** — warm off-white canvas with sage accents
- **Dark OLED** — pure black (#000000) background for power savings on OLED screens
- **System** — follows your phone's dark mode setting

## Remote Use (Tailscale)

The same server works away from home — no port forwarding, no certificates.

1. Install **Tailscale** on the Mac and on the Android phone; sign in with the same account.
2. On the Mac, note its tailnet address: `tailscale ip -4` (e.g. `100.64.1.23`) or its MagicDNS name (e.g. `mac-studio`).
3. Start the server: `python3 launch.py`. A token is generated and persisted automatically — it gates `/send` and the web console without appearing in your shell history.
4. In the app, put the tailnet address in **Host** and the same secret in **Token**, then tap **Test** — it verifies the token too.

Why this is safe: Tailscale's WireGuard tunnel is encrypted end‑to‑end, so plain HTTP inside it is fine.

**⚠️ Important:** On a plain LAN (without Tailscale), the token and every dictated character travel in the clear and are readable by anything else on that Wi‑Fi. Use Tailscale whenever you're not on a trusted home network. The server already listens on `0.0.0.0`, so one running instance serves your LAN *and* your tailnet at once — at home use the LAN IP, away use the tailnet address. Keep Tailscale **Funnel** *off*; Funnel would publish the port to the public internet.

```bash
# from anywhere on your tailnet
curl -H "Authorization: Bearer $(cat ~/.config/whisperbridge/token)" -H 'Content-Type: application/json' \
  -d '{"text": "dictated from a coffee shop", "mode": "type"}' \
  http://<tailnet-ip>:9877/send
```

## Menu Bar App (always-on, launches at login)

`menubar.py` runs the bridge in the background and puts a 🎙 status item in your menu bar showing the live **LAN** and **Tailscale** addresses, the token state, and the last dictation — with one-click *Open console*, *Copy pairing link*, and *Quit*. The `launch.py` script is recommended for most users since it includes the floating overlay.

```bash
pip3 install rumps            # one-time; pulls PyObjC for the menu bar
python3 mac-server/menubar.py
```

## Troubleshooting

- **"Connection failed"** — Make sure both devices are on the same WiFi network. Check the IP address. Make sure the Mac server is running.
- **Text doesn't appear** — macOS Accessibility permission is required. Go to System Settings → Privacy & Security → Accessibility and enable your terminal app.
- **Firewall blocking** — macOS may block incoming connections. Allow Python in System Settings → Network → Firewall, or temporarily disable the firewall to test.
- **Share sheet doesn't show Whisper Bridge** — Reinstall the app, or look under "More" in the share sheet.

## Project Structure

```
Whisperflow Bridge/               ← this repo
├── mac-server/
│   ├── server.py              # Bridge engine (zero dependencies, Python stdlib)
│   ├── launch.py              # Convenience launcher: server + overlay + login item
│   ├── overlay.py             # Floating status pill (tkinter)
│   ├── menubar.py             # Menu-bar app + login item (needs `rumps`)
│   └── qrcode.js              # Vendored QR encoder for the console (MIT)
├── android-app/               # Android Studio project
│   ├── app/src/main/java/com/whisperbridge/
│   │   ├── MainActivity.kt           # Multi-profile UI + settings + theme picker
│   │   ├── ShareReceiverActivity.kt  # Share sheet receiver
│   │   ├── ScanActivity.kt           # In-app QR scanner (ZXing)
│   │   ├── ProfileManager.kt         # Multi-profile storage
│   │   ├── ThemeManager.kt           # Light / Dark OLED / System + accent colors
│   │   ├── Pairing.kt                # Parses QR / deep link URLs
│   │   └── BridgeClient.kt           # HTTP client (type, clipboard, append, enter)
│   └── res/                          # Layouts, colors, icons, drawables, themes
├── DESIGN.md                    # Komodos design language reference
├── LICENSE                      # MIT
└── README.md
```

## License

MIT — use it, fork it, ship it. See [LICENSE](LICENSE).
