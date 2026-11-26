#!/bin/bash
# Builds "WhisperBridge Bluetooth.app" (arm64) into mac-bluetooth/build/.
# Signs with an Apple Development identity so macOS keeps the Bluetooth
# permission across rebuilds. Override with SIGN_IDENTITY="-" for ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/WhisperBridge Bluetooth.app"
IDENTITY="${SIGN_IDENTITY:-Apple Development: Brandon Nguyen (HAKXH57QS2)}"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/WhisperBridgeBluetooth"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WhisperBridgeBluetooth"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.whisperbridge.bluetooth</string>
  <key>CFBundleName</key><string>WhisperBridge Bluetooth</string>
  <key>CFBundleDisplayName</key><string>WhisperBridge Bluetooth</string>
  <key>CFBundleExecutable</key><string>WhisperBridgeBluetooth</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>WhisperBridge Bluetooth receives text from your iPhone over Bluetooth when there is no Wi-Fi, for example on a plane.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
