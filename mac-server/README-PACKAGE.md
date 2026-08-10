# Whisper Bridge for Mac

Double-click `mac-server/install.command`. It copies the receiver into `~/Library/Application Support/WhisperBridge`, installs a durable LaunchAgent, opens the pairing console, and opens macOS Accessibility settings.

Whisper Bridge needs Python 3 and Accessibility permission to paste into the focused application. The receiver listens on TCP port `9877` and requires the generated token for every send.

For encrypted remote use, install Tailscale on the Mac and Android phone and scan the Tailscale QR. Never expose port `9877` through public port forwarding or Tailscale Funnel.

To remove login startup, double-click `mac-server/uninstall.command`.

Prefer a menu-bar control? Run `python3 mac-server/menubar.py --install-app`
from the repo to build **Whisper Bridge.app** in `~/Applications`. It adds a
menu-bar item with one-click **Stop bridge** / **Start bridge** and a
**Launch at login** toggle, so you can bring the receiver online and offline
without touching the terminal.
