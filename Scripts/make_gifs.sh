#!/usr/bin/env bash
# Renders README media into docs/media: app scene GIFs (via the app's --snapshot --frames mode) and a web burn-down
# GIF (via headless Chrome and web/index.html?still=…). Needs ImageMagick (magick) and Google Chrome.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/media
TMP=$(mktemp -d)
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
mkdir -p "$OUT"

swift build --product TokensVSRainForest >/dev/null
.build/debug/TokensVSRainForest --snapshot "$TMP/app" --frames
for name in tree block progress; do
  magick -delay 8 -loop 0 "$TMP/app/frames-$name"/frame_*.png -layers Optimize "$OUT/app-$name.gif"
done

# Web: 40 frames across the whole burn, map area only.
(printf '<!doctype html>\n'; cat web/index.html) > "$TMP/web.html"
mkdir -p "$TMP/web"
for i in $(seq 0 39); do
  f=$(python3 -c "print(round($i / 39, 4))")
  t=$(python3 -c "print(round($i / 12, 3))")
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1200,900 --virtual-time-budget=3000 \
    --screenshot="$TMP/web/full_$(printf %03d "$i").png" "file://$TMP/web.html?still=$f&t=$t" 2>/dev/null
  magick "$TMP/web/full_$(printf %03d "$i").png" -crop 1080x610+60+252 +repage -resize 720x \
    "$TMP/web/frame_$(printf %03d "$i").png"
done
magick -delay 10 -loop 0 "$TMP/web"/frame_*.png -delay 120 "$TMP/web/frame_039.png" -layers Optimize "$OUT/web-burndown.gif"
rm -rf "$TMP"
ls -la "$OUT"
