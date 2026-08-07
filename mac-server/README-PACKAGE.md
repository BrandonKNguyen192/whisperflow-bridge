# Whisper Bridge for Mac

Double-click `mac-server/install.command`. It copies the receiver into `~/Library/Application Support/WhisperBridge`, installs a durable LaunchAgent, opens the pairing console, and opens macOS Accessibility settings.

Whisper Bridge needs Python 3 and Accessibility permission to paste into the focused application. The receiver listens on TCP port `9877` and requires the generated token for every send.

For encrypted remote use, install Tailscale on the Mac and Android phone and scan the Tailscale QR. Never expose port `9877` through public port forwarding or Tailscale Funnel.

To remove login startup, double-click `mac-server/uninstall.command`.
