#!/usr/bin/env bash
# Build Whisper Bridge APK with auto-incrementing build number.
# Usage: ./build.sh [--release]
#   --release      Build a release APK (unsigned unless keystore is configured)
#   (default)      Build a debug APK
set -euo pipefail
cd "$(dirname "$0")"

BUILD_FILE="builds/BUILD"
BUILDS_DIR="builds"
GRADLE_FILE="android-app/app/build.gradle.kts"

# Resolve Java
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
if [ ! -x "$JAVA_HOME/bin/java" ]; then
  echo "ERROR: JAVA_HOME=$JAVA_HOME not found."
  exit 1
fi

# Determine build type
BUILD_TYPE="debug"
APK_SUFFIX="-debug"
GRADLE_TASK="assembleDebug"
if [ "${1:-}" = "--release" ]; then
  BUILD_TYPE="release"
  APK_SUFFIX="-release-unsigned"
  GRADLE_TASK="assembleRelease"
fi

# Read + bump build number
if [ -f "$BUILD_FILE" ]; then
  BUILD=$(cat "$BUILD_FILE")
else
  BUILD=0
fi
BUILD=$((BUILD + 1))

echo "  -> Build #$BUILD ($BUILD_TYPE)"

# Update versionCode / versionName in build.gradle.kts
sed -i '' \
  -e "s/versionCode = .*/versionCode = $BUILD/" \
  -e "s/versionName = .*/versionName = \"1.0.$BUILD\"/" \
  "$GRADLE_FILE"

# Build
echo "  -> Building..."
(cd android-app && ./gradlew "$GRADLE_TASK" 2>&1) || {
  echo "  X Build failed"
  exit 1
}

# Copy APK to builds/
SRC="android-app/app/build/outputs/apk/$BUILD_TYPE/app${APK_SUFFIX}.apk"
DST="builds/WhisperBridge-v1.0.$BUILD.apk"

if [ ! -f "$SRC" ]; then
  echo "  X APK not found at $SRC"
  exit 1
fi

mkdir -p "$BUILDS_DIR"
cp "$SRC" "$DST"
shasum -a 256 "$DST" > "builds/WhisperBridge-v1.0.$BUILD.apk.sha256"

# Persist build number
echo "$BUILD" > "$BUILD_FILE"

# Report
SIZE=$(ls -lh "$DST" | awk '{print $5}')
SHA=$(cat "builds/WhisperBridge-v1.0.$BUILD.apk.sha256" | awk '{print $1}')

echo ""
echo "  ================================================"
echo "  Build #$BUILD complete"
echo "  $DST"
echo "  Size: $SIZE"
echo "  SHA:  $SHA"
echo "  ================================================"
echo ""
echo "  git add \"$GRADLE_FILE\" \"$BUILD_FILE\" \"$DST\" \"$DST.sha256\""
echo "  git commit -m 'build: v1.0.$BUILD'"
