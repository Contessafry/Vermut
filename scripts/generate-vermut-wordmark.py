#!/usr/bin/env python3
"""Outline 'Vermut' in Bricolage Grotesque (OFL) into BrandAssets PDFs/PNGs.

Axes follow brandkit/DESIGN-TOKENS.md: wght 700, wdth 85, opsz 96.
"""
from __future__ import annotations

import io
import os
import sys
from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

try:
    import cairosvg
except ImportError as exc:  # pragma: no cover
    sys.exit(f"cairosvg is required: {exc}")

ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = Path(os.environ.get("BRICOLAGE_TTF", "/tmp/bricolage/BricolageGrotesque.ttf"))
OUT_DIR = ROOT / "Sources/CaskLauncherCore/BrandAssets"
SVG_DIR = ROOT / "Resources/brand"
TEXT = "Vermut"
TARGET_HEIGHT = 15.0  # pt, sidebar wordmark
VAR = {"wght": 700, "wdth": 85, "opsz": 96}
COLORS = {
    "vermut-wordmark": "#09090B",
    "vermut-wordmark-white": "#FFFFFF",
}


def instantiate(path: Path) -> TTFont:
    font = TTFont(path)
    return instancer.instantiateVariableFont(font, VAR, inplace=False)


def outline(font: TTFont) -> tuple[str, float, float]:
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    hmtx = font["hmtx"].metrics

    x = 0.0
    parts: list[str] = []
    min_x = min_y = float("inf")
    max_x = max_y = float("-inf")
    for char in TEXT:
        name = cmap[ord(char)]
        bounds = BoundsPen(glyph_set)
        glyph_set[name].draw(bounds)
        if bounds.bounds:
            bx0, by0, bx1, by1 = bounds.bounds
            min_x = min(min_x, x + bx0)
            min_y = min(min_y, by0)
            max_x = max(max_x, x + bx1)
            max_y = max(max_y, by1)
        svg_pen = SVGPathPen(glyph_set)
        transform = Transform(1, 0, 0, 1, x, 0)
        glyph_set[name].draw(TransformPen(svg_pen, transform))
        d = svg_pen.getCommands()
        if d:
            parts.append(d)
        x += hmtx[name][0]

    if not parts:
        raise SystemExit("no outlines produced")

    # Scale the tight glyph bbox to 15pt tall (not the em square).
    scale = TARGET_HEIGHT / (max_y - min_y)
    width = (max_x - min_x) * scale
    height = TARGET_HEIGHT
    a, b, c, d, e, f = (
        scale,
        0,
        0,
        -scale,
        -min_x * scale,
        max_y * scale,
    )
    combined = " ".join(parts)
    group = (
        f'<g transform="matrix({a:.6f} 0 0 {d:.6f} {e:.6f} {f:.6f})">'
        f'<path d="{combined}"/></g>'
    )
    return group, width, height


def svg_document(inner: str, width: float, height: float, fill: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{width:.3f}" height="{height:.3f}" '
        f'viewBox="0 0 {width:.3f} {height:.3f}">'
        f'<g fill="{fill}">{inner}</g></svg>\n'
    )


def write_raster(svg: str, dest: Path, scale: int, height: float) -> None:
    png = cairosvg.svg2png(
        bytestring=svg.encode("utf-8"),
        output_height=int(round(height * scale)),
    )
    dest.write_bytes(png)


def main() -> None:
    if not FONT_PATH.exists():
        sys.exit(f"missing font: {FONT_PATH}")
    font = instantiate(FONT_PATH)
    inner, width, height = outline(font)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    print(f"wordmark size {width:.3f}x{height:.3f} pt  aspect={width/height:.4f}")

    for stem, fill in COLORS.items():
        svg = svg_document(inner, width, height, fill)
        svg_path = SVG_DIR / f"{stem}.svg"
        svg_path.write_text(svg, encoding="utf-8")
        pdf = cairosvg.svg2pdf(bytestring=svg.encode("utf-8"))
        (OUT_DIR / f"{stem}.pdf").write_bytes(pdf)
        write_raster(svg, OUT_DIR / f"{stem}.png", 1, height)
        write_raster(svg, OUT_DIR / f"{stem}@2x.png", 2, height)
        write_raster(svg, OUT_DIR / f"{stem}@3x.png", 3, height)
        print(f"wrote {stem} pdf/png  fill={fill}")

    ratio_path = SVG_DIR / "vermut-wordmark-metrics.txt"
    ratio_path.write_text(f"{width:.6f} {height:.6f} {width/height:.6f}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
