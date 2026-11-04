#!/usr/bin/env python3
"""Draws the Ember app icon from the pixel map in CLAUDE.md.

Writes the light, dark and tinted 1024x1024 PNGs and the Contents.json
of Ember/Resources/Assets.xcassets/AppIcon.appiconset. Square pixels,
no smoothing, no gradients.

Usage: python3 scripts/make-app-icon.py
"""
import json
import os
import sys

from PIL import Image, ImageDraw

FLAME = [
    "....1....",
    "...111...",
    "...1211..",
    "..12211..",
    "..122211.",
    ".1223221.",
    ".1233321.",
    ".1233321.",
    "..12321..",
    "...111...",
]

VARIANTS = {
    # name: (background, {cell: color}, appearance)
    "light": ("#F4E9D8", {"1": "#C83A1E", "2": "#EE6A2A", "3": "#F7B538"}, None),
    "dark": ("#1E1814", {"1": "#EE6A2A", "2": "#F48A3A", "3": "#F7B538"}, "dark"),
    "tinted": ("#1B1B1D", {"1": "#8A8A8E", "2": "#B5B5B9", "3": "#E6E6E8"}, "tinted"),
}

SIZE = 1024
CELL = 72  # 9x10 cells -> 648x720, centered


def draw(background, colors):
    image = Image.new("RGB", (SIZE, SIZE), background)
    pen = ImageDraw.Draw(image)
    rows, cols = len(FLAME), len(FLAME[0])
    left = (SIZE - cols * CELL) // 2
    top = (SIZE - rows * CELL) // 2
    for y, row in enumerate(FLAME):
        for x, cell in enumerate(row):
            if cell in colors:
                x0, y0 = left + x * CELL, top + y * CELL
                pen.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=colors[cell])
    return image


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    out = os.path.join(root, "Ember", "Resources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)

    images = []
    for name, (background, colors, appearance) in VARIANTS.items():
        filename = f"AppIcon-{name}.png"
        draw(background, colors).save(os.path.join(out, filename))
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)

    with open(os.path.join(out, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("wrote", out)


if __name__ == "__main__":
    sys.exit(main())
