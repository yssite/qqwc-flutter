"""给文档截图做隐私打码：把指定矩形区内做马赛克。

用法：python tool/mask_shots.py
"""

from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BUILD = os.path.join(ROOT, "build")
DOCS = os.path.join(ROOT, "docs", "screenshots")

# (源文件, 目标文件, [(x0, y0, x1, y1), ...])
JOBS = [
    (
        "d_v121.png",
        "home.png",
        [],
    ),
    (
        "diag121.png",
        "diagnostics.png",
        [(305, 700, 620, 830)],
    ),
    (
        "set121_bottom.png",
        "settings.png",
        [(310, 1400, 780, 1600)],
    ),
]

BLOCK = 14


def pixelate(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    region = img.crop(box)
    w, h = region.size
    small = region.resize((max(1, w // BLOCK), max(1, h // BLOCK)), Image.BILINEAR)
    img.paste(small.resize((w, h), Image.NEAREST), box)


def main() -> None:
    for src, dst, boxes in JOBS:
        path = os.path.join(BUILD, src)
        if not os.path.exists(path):
            print("missing", src)
            continue
        img = Image.open(path).convert("RGB")
        for box in boxes:
            pixelate(img, box)
        img.save(os.path.join(DOCS, dst))
        print("wrote", dst)


if __name__ == "__main__":
    main()
