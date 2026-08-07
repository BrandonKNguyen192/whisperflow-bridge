#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
package_root="$(dirname "$script_dir")"
install_dir="$HOME/.local/share/whisperbridge"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer currently supports Ubuntu/Debian systems with apt."
  exit 1
fi

echo "Installing Ubuntu input helpers..."
sudo apt-get update
sudo apt-get install -y python3 wl-clipboard ydotool xdotool xclip libnotify-bin pulseaudio-utils

install -d -m 700 "$install_dir"
cp -R "$package_root/common" "$install_dir/"
cp -R "$package_root/ubuntu-server" "$install_dir/"
find "$install_dir" -type d -exec chmod 700 {} +
find "$install_dir" -type f -exec chmod 600 {} +
chmod 700 "$install_dir/ubuntu-server/launch.py" "$install_dir/ubuntu-server/install.sh"

systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XAUTHORITY DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
python3 "$install_dir/ubuntu-server/launch.py" --install-login

if command -v ydotoold >/dev/null 2>&1; then
  if systemctl list-unit-files --no-legend ydotool.service 2>/dev/null | grep -q '^ydotool\.service'; then
    sudo systemctl enable --now ydotool.service || true
  elif systemctl list-unit-files --no-legend ydotoold.service 2>/dev/null | grep -q '^ydotoold\.service'; then
    sudo systemctl enable --now ydotoold.service || true
  fi
fi

token_file="$HOME/.config/whisperbridge/token"
for _attempt in 1 2 3 4 5; do
  [ -s "$token_file" ] && break
  sleep 1
done

echo
echo "Whisper Bridge is installed and starts automatically at login."
echo "Open http://localhost:9877 to pair your Android phone."
echo "Logs: journalctl --user -u whisperbridge -f"

if command -v xdg-open >/dev/null 2>&1 && [ -s "$token_file" ]; then
  pairing_token="$(tr -d '\r\n' < "$token_file")"
  xdg-open "http://localhost:9877/?token=$pairing_token" >/dev/null 2>&1 || true
fi
