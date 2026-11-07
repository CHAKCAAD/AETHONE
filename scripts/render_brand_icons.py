#!/usr/bin/env python3
"""render_brand_icons.py — the v4.39 brand-icon pipeline.

ONE source of truth: design/brand/aethone-logo.svg — the owner's mark
(delivered 2026-11-07). Two shipped faces, per the owner's decree
(«آیکون تری باید دقیقا همین باشه اما آیکون اصلی اپ ... باید همین آیکون
با پس زمینه سفید باشه»):

  * the TRAY icon is the mark EXACTLY AS-IS (transparent background):
      windows/runner/resources/tray_icon.ico       (16/24/32/48)
      linux/packaging/aethone-tray.png             (96, alpha)
  * the APP icon (Start menu, taskbar, window caption, Android launcher,
    the Linux app grid) is the SAME mark on a WHITE background:
      windows/runner/resources/app_icon.ico        (16..256, replaces template)
      linux/packaging/aethone-icon.png             (256)
      android/app/src/main/res/mipmap-{mdpi..xxxhdpi}/ic_launcher.png
        (48/72/96/144/192, replaces the template set)

The committed outputs are the authoritative CI inputs — CI never re-renders:
the .ico frames are embedded into aethone.exe by Runner.rc, the bundle legs
fail closed if the linux PNGs are missing, and the APK legs rebuild against
the committed mipmaps. This script is the derivation record: run it on a
host with cairosvg + Pillow after any change to the SVG, then commit both
the SVG and the regenerated outputs together.

Every size is rendered NATIVELY from the vector (no bitmap downsampling) so
the geometry stays crisp at 16 px; the ICO frames are fed via append_images
(Pillow keeps an exactly-sized frame verbatim instead of resampling).
"""

from __future__ import annotations

import sys
from io import BytesIO
from pathlib import Path

import cairosvg
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SVG = REPO / "design" / "brand" / "aethone-logo.svg"


def render(size: int, white_background: bool) -> Image.Image:
    """The mark at `size` px, optionally composited over opaque white."""
    png = cairosvg.svg2png(url=str(SVG), output_width=size, output_height=size)
    mark = Image.open(BytesIO(png)).convert("RGBA")
    if not white_background:
        return mark
    plate = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    plate.alpha_composite(mark)
    return plate


def write_ico(path: Path, sizes: list[int], white: bool) -> None:
    frames = [render(s, white) for s in sizes]
    # Pillow keeps exactly-sized append_images as ICO frames verbatim.
    frames[0].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=frames[1:],
    )


def write_png(path: Path, size: int, white: bool) -> None:
    render(size, white).save(path, format="PNG")


def main() -> int:
    if not SVG.is_file():
        print(f"FATAL: the brand SVG is missing: {SVG}", file=sys.stderr)
        return 1
    outputs: list[Path] = []

    # ---- the tray face (the mark as-is, transparent) ----
    p = REPO / "windows" / "runner" / "resources" / "tray_icon.ico"
    write_ico(p, [16, 24, 32, 48], white=False)
    outputs.append(p)

    p = REPO / "linux" / "packaging" / "aethone-tray.png"
    write_png(p, 96, white=False)
    outputs.append(p)

    # ---- the app face (the mark on white) ----
    p = REPO / "windows" / "runner" / "resources" / "app_icon.ico"
    write_ico(p, [16, 24, 32, 48, 64, 128, 256], white=True)
    outputs.append(p)

    p = REPO / "linux" / "packaging" / "aethone-icon.png"
    write_png(p, 256, white=True)
    outputs.append(p)

    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)):
        p = (REPO / "android" / "app" / "src" / "main" / "res"
             / f"mipmap-{dpi}" / "ic_launcher.png")
        write_png(p, px, white=True)
        outputs.append(p)

    for o in outputs:
        img = Image.open(o)
        corner = img.convert("RGBA").getpixel((0, 0))
        print(f"  {o.relative_to(REPO)}  {img.size} {img.mode} corner={corner}")
    print(f"render_brand_icons: {len(outputs)} outputs regenerated from {SVG.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
