#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="$(tr -d '[:space:]' < "$root_dir/VERSION")"
dist_dir="$root_dir/dist"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/whisperbridge-package.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT

mkdir -p "$dist_dir"

package_platform() {
  platform="$1"
  source_dir="$2"
  archive="$dist_dir/WhisperBridge-$platform-v$version.zip"
  package_dir="$stage_dir/WhisperBridge-v$version"

  rm -rf "$package_dir"
  mkdir -p "$package_dir"
  cp -R "$root_dir/common" "$package_dir/common"
  cp -R "$root_dir/$source_dir" "$package_dir/$source_dir"
  cp "$root_dir/LICENSE" "$root_dir/PRIVACY.md" "$root_dir/SECURITY.md" "$package_dir/"
  find "$package_dir" -type d -name __pycache__ -prune -exec rm -rf {} +
  rm -f "$archive" "$archive.sha256"
  (cd "$stage_dir" && zip -qr "$archive" "WhisperBridge-v$version")
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$archive" > "$archive.sha256"
  else
    sha256sum "$archive" > "$archive.sha256"
  fi
  echo "Built $(basename "$archive")"
}

package_platform "Mac" "mac-server"
package_platform "Ubuntu" "ubuntu-server"
package_platform "Windows" "windows-server"
