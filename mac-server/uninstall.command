#!/usr/bin/env bash
set -euo pipefail

install_dir="$HOME/Library/Application Support/WhisperBridge"
launcher="$install_dir/mac-server/launch.py"
python_bin="$(command -v python3 2>/dev/null || true)"

if [ -f "$launcher" ] && [ -n "$python_bin" ]; then
  "$python_bin" "$launcher" --uninstall-login
else
  launchctl unload "$HOME/Library/LaunchAgents/com.whisperbridge.launcher.plist" >/dev/null 2>&1 || true
fi

echo "Login startup removed. Your token remains at ~/.config/whisperbridge/token."
read -r -p "Press Return to close."
