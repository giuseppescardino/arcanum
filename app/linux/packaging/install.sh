#!/usr/bin/env bash
# Installs the Arcanum bundle for the current user (no root needed):
#   ~/.local/share/arcanum/            the bundle (binary, lib/, data/)
#   ~/.local/bin/arcanum               symlink to the binary
#   ~/.local/share/applications/       desktop entry
#   ~/.local/share/icons/hicolor/...   icon
# Run it from the extracted bundle. `install.sh --uninstall` removes it all.
set -euo pipefail

id=io.github.giuseppescardino.arcanum
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
share="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$share/arcanum"
bin="$HOME/.local/bin"
icon="$share/icons/hicolor/256x256/apps/$id.png"
entry="$share/applications/$id.desktop"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$dest" "$bin/arcanum" "$icon" "$entry"
  echo "Arcanum removed (the vault is kept)."
  exit 0
fi

[[ -x "$here/arcanum" ]] || { echo "Run this from the extracted Arcanum bundle." >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest" "$bin" "$(dirname "$icon")" "$(dirname "$entry")"
cp -R "$here/arcanum" "$here/lib" "$here/data" "$dest/"
ln -sf "$dest/arcanum" "$bin/arcanum"
cp "$here/data/arcanum.png" "$icon"
sed "s|^Exec=.*|Exec=$dest/arcanum|" "$here/data/$id.desktop" > "$entry"

command -v update-desktop-database >/dev/null && update-desktop-database "$share/applications" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$share/icons/hicolor" || true
echo "Arcanum installed in $dest."
