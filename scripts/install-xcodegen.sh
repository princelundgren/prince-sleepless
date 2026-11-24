#!/usr/bin/env bash
# Installs the pinned XcodeGen release into build/tools/xcodegen and prints its bin directory.
set -euo pipefail

XCODEGEN_VERSION="2.46.0"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/build/tools/xcodegen"
stamp="$dest/.version"

if [[ -x "$dest/bin/xcodegen" && "$(cat "$stamp" 2>/dev/null)" == "$XCODEGEN_VERSION" ]]; then
  echo "$dest/bin"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl --fail --retry 3 --silent --show-error --location \
  --output "$work/xcodegen.zip" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"

actual="$(shasum -a 256 "$work/xcodegen.zip" | cut -d' ' -f1)"
if [[ "$actual" != "$XCODEGEN_SHA256" ]]; then
  echo "XcodeGen $XCODEGEN_VERSION checksum mismatch: expected $XCODEGEN_SHA256, got $actual" >&2
  exit 1
fi

rm -rf "$dest"
mkdir -p "$dest"
unzip -q "$work/xcodegen.zip" -d "$work/unpacked"
mv "$work"/unpacked/xcodegen/* "$dest"/
echo "$XCODEGEN_VERSION" > "$stamp"
echo "$dest/bin"
