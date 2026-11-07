#!/usr/bin/env python3
"""render_brand_icons.py — the v4.41 brand-icon pipeline.

ONE source of truth: design/brand/app-icon.png — the owner's delivered app
icon (256×256, uniform 24% rounded square, green tile + white A-mark;
round 17: «آیکون اصلی برنامه رو هم ضمیمه کردم جایگزینش کن. دقیقا همین
آیکون باشه فقط اگه گوشه هاش استاندارد نبود تغیرات ایجاد کن داخلش»).
The corners measured UNIFORM (r = 61.5px = 24.0% on all four, the same
radius family as the owner's own auto-location tile) — a clean standard
rounded square, so the artwork ships EXACTLY as delivered, one face
everywhere (this supersedes the v4.39 transparent-mark / mark-on-white
two-face rule):

  windows/runner/resources/app_icon.ico    (16..256, the tile as-is)
  windows/runner/resources/tray_icon.ico   (16/24/32/48, the tile as-is)
  linux/packaging/aethone-icon.png         (256)
  linux/packaging/aethone-tray.png         (96)
  android/app/src/main/res/mipmap-{mdpi..xxxhdpi}/ic_launcher.png
    (48/72/96/144/192)

The committed outputs are the authoritative CI inputs — CI never re-renders
(the .ico frames are embedded into aethone.exe by Runner.rc, the bundle
legs fail closed if the linux PNGs are missing, and the APK legs rebuild
against the committed mipmaps). This script is the derivation record: run
it on a host with Pillow after any change to the source PNG, then commit
both the source and the regenerated outputs together.

Small sizes are downsampled with LANCZOS from the 256 source; the ICO
frames are fed via append_images (Pillow keeps an exactly-sized frame
verbatim instead of resampling).
"""

from __future__ import annotations

import sys
from io import BytesIO
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "design" / "brand" / "app-icon.png"


def render(size: int) -> Image.Image:
    """The tile at `size` px — exact artwork, LANCZOS resample."""
    return Image.open(SRC).convert("RGBA").resize((size, size), Image.LANCZOS)


def write_ico(path: Path, sizes: list[int]) -> None:
    # v4.41: the v4.39 `sizes=[…] + append_images` form silently collapsed
    # to a single 16 px directory entry (Pillow keeps `sizes` authoritative
    # and drops the appended frames). Base = the LARGEST frame with the
    # smaller ones appended, no `sizes` kwarg — a true multi-frame ICO.
    frames = sorted((render(s) for s in sizes), key=lambda f: f.size[0])
    frames[-1].save(path, format="ICO", append_images=frames[:-1])


def main() -> int:
    if not SRC.is_file():
        print(f"FATAL: the app icon is missing: {SRC}", file=sys.stderr)
        return 1
    outputs: list[Path] = []

    p = REPO / "windows" / "runner" / "resources" / "tray_icon.ico"
    write_ico(p, [16, 24, 32, 48])
    outputs.append(p)

    p = REPO / "windows" / "runner" / "resources" / "app_icon.ico"
    write_ico(p, [16, 24, 32, 48, 64, 128, 256])
    outputs.append(p)

    p = REPO / "linux" / "packaging" / "aethone-tray.png"
    render(96).save(p, format="PNG")
    outputs.append(p)

    p = REPO / "linux" / "packaging" / "aethone-icon.png"
    render(256).save(p, format="PNG")
    outputs.append(p)

    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)):
        p = (REPO / "android" / "app" / "src" / "main" / "res"
             / f"mipmap-{dpi}" / "ic_launcher.png")
        render(px).save(p, format="PNG")
        outputs.append(p)

    for o in outputs:
        img = Image.open(o)
        corner = img.convert("RGBA").getpixel((0, 0))
        print(f"  {o.relative_to(REPO)}  {img.size} {img.mode} corner={corner}")
    print(f"render_brand_icons: {len(outputs)} outputs regenerated from {SRC.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
