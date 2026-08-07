#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
package_root="$(dirname "$script_dir")"
install_dir="$HOME/Library/Application Support/WhisperBridge"

python_bin=""
for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    python_bin="$candidate"
    break
  fi
done
if [ -z "$python_bin" ]; then
  echo "Python 3 is required. Install it from https://www.python.org/downloads/macos/ and run this installer again."
  read -r -p "Press Return to close."
  exit 1
fi

mkdir -p "$install_dir"
ditto "$package_root/common" "$install_dir/common"
ditto "$package_root/mac-server" "$install_dir/mac-server"
chmod 700 "$install_dir/mac-server/launch.py" "$install_dir/mac-server/install.command"

"$python_bin" "$install_dir/mac-server/launch.py" --install-login

token_file="$HOME/.config/whisperbridge/token"
if [ -s "$token_file" ]; then
  pairing_token="$(tr -d '\r\n' < "$token_file")"
  open "http://localhost:9877/?token=$pairing_token"
else
  open "http://localhost:9877"
fi
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo
echo "Whisper Bridge is installed and will stay running after login."
echo "Allow the selected Python app under Accessibility so it can paste and press Return."
read -r -p "Press Return to close."
