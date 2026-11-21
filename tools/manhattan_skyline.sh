#!/bin/sh
# Build the parking garage's Manhattan skyline from zack's Google Earth tiles (see the header of
# tools/manhattan_skyline.py). Output: shopping-cart/assets/manhattan_skyline/ (kept out of git).
#
#   sh tools/manhattan_skyline.sh [tile dir]
#
# Needs Blender (BLENDER, default the Mac app), node/npx (for gltfpack), python3 with Pillow, and
# macOS's sips. Takes ~15 minutes, most of it the panorama render.
set -e
cd "$(dirname "$0")/.."
SRC="${1:-$HOME/Pictures/blender/MANHATTAN}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
OUT=shopping-cart/assets/manhattan_skyline
SMALL="$SRC/../MANHATTAN_2k"   # 2K copies of every tile's texture, for the panorama render
NEAR_TILES="30 31 32 39 40 41" # the tiles with buildings within NEAR_M of the garage
mkdir -p "$OUT" "$SMALL"

# 2K textures for the panorama, full 4K for the near tiles (they're seen from ~60 m).
for f in "$SRC"/*.png; do
	n=$(basename "$f" .png); n=${n##*_}
	[ -f "$SMALL/tile_$n.jpg" ] || sips -s format jpeg -s formatOptions 85 -Z 2048 "$f" --out "$SMALL/tile_$n.jpg" >/dev/null
done
for t in $NEAR_TILES; do
	sips -s format jpeg -s formatOptions 88 -Z 4096 "$SRC/8fd1b8414f3a_gltf_tile_$t.png" --out "$OUT/near_$t.jpg" >/dev/null
done

# Near buildings: cut and welded in Blender, then thinned by gltfpack keeping the photo's UVs.
for t in $NEAR_TILES; do
	"$BLENDER" -b -P tools/manhattan_skyline.py -- near "$SRC" "$OUT" "$t" 2>&1 | grep -E "NEAR|Error" || true
	if [ -f "$OUT/near_${t}_full.glb" ]; then
		npx --yes gltfpack@1.3 -i "$OUT/near_${t}_full.glb" -o "$OUT/near_$t.glb" -si 0.1 -sp -se 0.005 -vpf -vtf -kv
		rm "$OUT/near_${t}_full.glb"
	fi
done

# Far skyline: one panorama, then a lossy WebP with alpha (~a tenth of the PNG).
"$BLENDER" -b -P tools/manhattan_skyline.py -- far "$SRC" "$SMALL" "$OUT/far_panorama.png" 8192 2>&1 | grep -E "FAR|Error|Saved" || true
python3 -c "from PIL import Image; Image.open('$OUT/far_panorama.png').save('$OUT/far_panorama.webp', quality=90, method=6)"
rm "$OUT/far_panorama.png"

python3 tools/manhattan_skyline_scene.py
echo "Now import: godot --headless --path shopping-cart --import"
