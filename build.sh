#!/usr/bin/env bash
# Build Whisper Bridge APK with a semantic version and auto-incrementing code.
# Usage: ./build.sh [--release] [--version X.Y.Z]
#   --release      Build a signed release APK (fails without release credentials)
#   --version      Override the version in VERSION
#   (default)      Build a debug APK
set -euo pipefail
cd "$(dirname "$0")"

BUILD_FILE="builds/BUILD"
BUILDS_DIR="builds"
GRADLE_FILE="android-app/app/build.gradle.kts"
VERSION_FILE="VERSION"

# Resolve Java
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
if [ ! -x "$JAVA_HOME/bin/java" ]; then
  echo "ERROR: JAVA_HOME=$JAVA_HOME not found."
  exit 1
fi

BUILD_TYPE="debug"
APK_SUFFIX="-debug"
GRADLE_TASK="assembleDebug"
APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --release)
      BUILD_TYPE="release"
      APK_SUFFIX="-release"
      GRADLE_TASK="assembleRelease"
      shift
      ;;
    --version)
      APP_VERSION="${2:?--version requires X.Y.Z}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown option: $1"
      exit 1
      ;;
  esac
done

if ! [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: invalid version '$APP_VERSION' (expected X.Y.Z)"
  exit 1
fi

# Read + bump build number
if [ -f "$BUILD_FILE" ]; then
  BUILD=$(cat "$BUILD_FILE")
else
  BUILD=0
fi
BUILD=$((BUILD + 1))

echo "  -> Whisper Bridge v$APP_VERSION, build #$BUILD ($BUILD_TYPE)"

if [ "$BUILD_TYPE" = "release" ]; then
  if [ -z "${RELEASE_STORE_FILE:-}" ] && command -v security >/dev/null 2>&1; then
    signing_dir="$HOME/.config/whisperbridge/signing"
    signing_password="$(security find-generic-password -w -s com.whisperbridge.android-signing -a password 2>/dev/null || true)"
    if [ -n "$signing_password" ]; then
      export RELEASE_STORE_FILE="$signing_dir/whisperbridge-release.jks"
      export RELEASE_STORE_PASSWORD="$signing_password"
      export RELEASE_KEY_ALIAS="whisperbridge"
      export RELEASE_KEY_PASSWORD="$signing_password"
    fi
  fi
  for required in RELEASE_STORE_FILE RELEASE_STORE_PASSWORD RELEASE_KEY_ALIAS RELEASE_KEY_PASSWORD; do
    required_value="$(printenv "$required" 2>/dev/null || true)"
    if [ -z "$required_value" ]; then
      echo "ERROR: $required is required for a signed release build."
      exit 1
    fi
  done
  if [ ! -f "$RELEASE_STORE_FILE" ]; then
    echo "ERROR: release keystore not found: $RELEASE_STORE_FILE"
    exit 1
  fi
fi

# Build from a clean output tree. Synced folders can otherwise retain duplicate
# generated resources that make Gradle's incremental merge stall.
echo "  -> Building..."
(cd android-app && ./gradlew clean "$GRADLE_TASK" \
  -PVERSION_CODE="$BUILD" -PVERSION_NAME="$APP_VERSION" 2>&1) || {
  echo "  X Build failed"
  exit 1
}

# Copy APK to builds/
SRC="android-app/app/build/outputs/apk/$BUILD_TYPE/app${APK_SUFFIX}.apk"
if [ "$BUILD_TYPE" = "release" ]; then
  DST="builds/WhisperBridge-v$APP_VERSION-build$BUILD.apk"
else
  DST="builds/WhisperBridge-v$APP_VERSION-debug-build$BUILD.apk"
fi

if [ ! -f "$SRC" ]; then
  echo "  X APK not found at $SRC"
  exit 1
fi

mkdir -p "$BUILDS_DIR"
cp "$SRC" "$DST"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$DST" > "$DST.sha256"
else
  sha256sum "$DST" > "$DST.sha256"
fi

# Persist release metadata only after a successful build.
echo "$BUILD" > "$BUILD_FILE"
echo "$APP_VERSION" > "$VERSION_FILE"
BUILD="$BUILD" APP_VERSION="$APP_VERSION" perl -0pi -e '
  s/(versionCode = .*?\?: )\d+/$1$ENV{BUILD}/;
  s/(versionName = .*?\?: )"[^"]+"/$1"$ENV{APP_VERSION}"/;
' "$GRADLE_FILE"

# Report
SIZE=$(ls -lh "$DST" | awk '{print $5}')
SHA=$(awk '{print $1}' "$DST.sha256")

echo ""
echo "  ================================================"
echo "  Whisper Bridge v$APP_VERSION, build #$BUILD complete"
echo "  $DST"
echo "  Size: $SIZE"
echo "  SHA:  $SHA"
echo "  ================================================"
echo ""
echo "  git add \"$GRADLE_FILE\" \"$BUILD_FILE\" \"$DST\" \"$DST.sha256\""
echo "  git commit -m 'build: v$APP_VERSION ($BUILD)'"
