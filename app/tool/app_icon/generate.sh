#!/bin/sh
# Regenerates every platform's app icon from draw.swift (macOS only).
#   app/tool/app_icon/generate.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O "$here/draw.swift" -o "$tmp/draw"
draw="$tmp/draw"

# iOS: full-bleed, opaque; sizes from the asset catalog.
ios="$app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
python3 - "$ios" "$draw" <<'PY'
import json, subprocess, sys
d, draw = sys.argv[1], sys.argv[2]
for i in json.load(open(d + '/Contents.json'))['images']:
    px = round(float(i['size'].split('x')[0]) * int(i['scale'][0]))
    subprocess.run([draw, 'full', str(px), d + '/' + i['filename']], check=True)
PY

# macOS: rounded tile on the standard grid.
for n in 16 32 64 128 256 512 1024; do
  "$draw" mac $n "$app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$n.png"
done

# Android: legacy icon plus adaptive layers (108dp) and themed monochrome.
res="$app/android/app/src/main/res"
for pair in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read -r d legacy adaptive <<EOP
$pair
EOP
  "$draw" full $legacy "$res/mipmap-$d/ic_launcher.png"
  "$draw" fg $adaptive "$res/mipmap-$d/ic_launcher_foreground.png"
  "$draw" bg $adaptive "$res/mipmap-$d/ic_launcher_background.png"
  "$draw" mono $adaptive "$res/mipmap-$d/ic_launcher_monochrome.png"
done

# Windows: .ico with PNG entries.
sizes="16 24 32 48 64 128 256"
for n in $sizes; do "$draw" mac $n "$tmp/$n.png"; done
python3 - "$tmp" "$app/windows/runner/resources/app_icon.ico" $sizes <<'PY'
import struct, sys
tmp, out, sizes = sys.argv[1], sys.argv[2], [int(s) for s in sys.argv[3:]]
data = [open(f'{tmp}/{n}.png', 'rb').read() for n in sizes]
offset = 6 + 16 * len(sizes)
entries = b''
for n, png in zip(sizes, data):
    entries += struct.pack('<BBBBHHII', n % 256, n % 256, 0, 0, 1, 32, len(png), offset)
    offset += len(png)
with open(out, 'wb') as f:
    f.write(struct.pack('<HHH', 0, 1, len(sizes)) + entries + b''.join(data))
PY
echo "Icons regenerated."
