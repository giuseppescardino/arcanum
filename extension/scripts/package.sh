#!/usr/bin/env bash
# Packages the browser extension into OUT_DIR (default: extension/dist).
#
#   scripts/package.sh chromium [OUT_DIR]  zip of src/ for Chrome, Opera and
#                                          Edge: unzip and "Load unpacked",
#                                          or upload to a store as is
#   scripts/package.sh safari [OUT_DIR]    Safari wrapper app, ad-hoc signed
#                                          (macOS + Xcode); needs Safari's
#                                          "Allow Unsigned Extensions"
#
# File names carry the version from src/manifest.json.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
out="${2:-$here/dist}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$here/src/manifest.json" | head -1)"
[ -n "$version" ] || { echo "no version in src/manifest.json" >&2; exit 1; }

case "$target" in
  chromium)
    zip_path="$out/Arcanum-extension-chromium-$version.zip"
    rm -f "$zip_path"
    # manifest.json at the root of the archive, as the stores expect.
    (cd "$here/src" && zip -qr -X "$zip_path" . -x '.*' -x '*/.*')
    echo "$zip_path"
    ;;
  safari)
    build="$(mktemp -d)"
    app="$build/Build/Products/Release/Arcanum Safari.app"
    # Xcode registers what it builds with Launch Services. A record left
    # pointing at a deleted bundle stops Safari loading the extension's
    # background, so unregister before deleting.
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    trap '"$lsregister" -u "$app" >/dev/null 2>&1 || true; rm -rf "$build"' EXIT
    xcodebuild -project "$here/safari/Arcanum Safari/Arcanum Safari.xcodeproj" \
      -scheme "Arcanum Safari" -configuration Release -derivedDataPath "$build" \
      CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
      MARKETING_VERSION="$version" -quiet build
    zip_path="$out/Arcanum-Safari-$version.zip"
    rm -f "$zip_path"
    ditto -c -k --keepParent "$app" "$zip_path"
    echo "$zip_path"
    ;;
  *)
    echo "usage: $0 chromium|safari [OUT_DIR]" >&2
    exit 2
    ;;
esac
