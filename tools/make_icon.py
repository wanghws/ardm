# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Build ARDM/Media/Icon.tga from the game's own Garrote and Rupture icons.

Usage: uv run tools/make_icon.py

The source BLPs are fetched by FileDataID from wago.tools' CASC mirror, so the
art is exactly what the client ships rather than a re-compressed web preview.
"""

import io
import math
import urllib.request
from pathlib import Path

from PIL import Image

GARROTE_FDID = 132297  # Interface/Icons/Ability_Rogue_Garrote
RUPTURE_FDID = 132302  # Interface/Icons/Ability_Rogue_Rupture

# Spell icons are 64x64 with a 4px bevelled frame baked into the texture.
SIZE = 64
FRAME = 4

SEPARATOR = (10, 10, 10, 255)
SEPARATOR_WIDTH = 1.5

OUT = Path(__file__).resolve().parent.parent / "ARDM" / "Media" / "Icon.tga"


def fetch_icon(fdid: int) -> Image.Image:
    url = f"https://wago.tools/api/casc/{fdid}?download"
    req = urllib.request.Request(url, headers={"User-Agent": "ARDM-icon-builder"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        icon = Image.open(io.BytesIO(resp.read())).convert("RGBA")
    if icon.size != (SIZE, SIZE):
        raise SystemExit(f"FileDataID {fdid}: expected {SIZE}x{SIZE}, got {icon.size}")
    return icon


def mix(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(4))


def compose(garrote: Image.Image, rupture: Image.Image) -> Image.Image:
    """Split the artwork along the top-left to bottom-right diagonal.

    Both paintings run along the other diagonal: Garrote's wire climbs from the
    bottom-left corner and Rupture's blade points to the top-right. Cutting on
    this axis keeps the lower half of the wire and the blade whole; the other
    axis would slice each of them lengthwise. The frame is left untouched so
    the result still reads as a standard spell icon.
    """
    g, r = garrote.load(), rupture.load()
    out = rupture.copy()
    o = out.load()
    for y in range(FRAME, SIZE - FRAME):
        for x in range(FRAME, SIZE - FRAME):
            # Signed distance from the pixel centre to the diagonal, positive
            # below it; used for a one-pixel anti-aliased edge.
            d = ((y + 0.5) - (x + 0.5)) / math.sqrt(2)
            px = mix(r[x, y], g[x, y], min(1.0, max(0.0, 0.5 + d)))
            edge = min(1.0, max(0.0, SEPARATOR_WIDTH / 2 + 0.5 - abs(d)))
            o[x, y] = mix(px, SEPARATOR, edge)
    return out


def main() -> None:
    icon = compose(fetch_icon(GARROTE_FDID), fetch_icon(RUPTURE_FDID))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    # Addons can only ship BLP or TGA textures; Pillow writes uncompressed
    # 32-bit TGA by default, which every client version loads.
    icon.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
