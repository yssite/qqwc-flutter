"""从 assets/brand/logo_raw.png 生成启动图标、自适应图标前景与 App 内品牌图。

设计稿（AI 生成，透明底）外侧有一圈柔和投影，这里按 alpha 包络裁掉，
只保留圆角砖本体，保证系统图标边缘与投影由启动器自己处理。

用法：python tool/make_icons.py
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
RAW = os.path.join(ROOT, "assets", "brand", "logo_raw.png")
MASTER = os.path.join(ROOT, "assets", "brand", "logo.png")

# 自适应图标：108dp 画布内，砖体占 0.74（遮罩通常只露出中间 ~72dp，砖角被裁掉，
# 图形完整落在安全区内，视觉上等于一枚满底蓝色圆/圆角方图标）
ADAPTIVE_SCALE = 0.80


def load_tile() -> Image.Image:
    im = Image.open(RAW).convert("RGBA")
    alpha = np.array(im.getchannel("A"))
    # 用较实的像素确定砖体边界，避免把柔和投影算进来
    solid = alpha > 160
    rows = np.where(solid.any(axis=1))[0]
    cols = np.where(solid.any(axis=0))[0]
    box = (int(cols.min()), int(rows.min()), int(cols.max()) + 1, int(rows.max()) + 1)
    tile = im.crop(box)
    # 裁出来宽高差几像素，拉伸成正方形（<1% 形变，肉眼不可见）
    return tile.resize((512, 512), Image.LANCZOS)


def edge_color(tile: Image.Image, where: str) -> tuple[int, int, int]:
    a = np.array(tile.convert("RGB"))
    h, w, _ = a.shape
    band = {
        "top": a[4:10, w // 4: 3 * w // 4],
        "bottom": a[h - 10:h - 4, w // 4: 3 * w // 4],
    }[where]
    mean = band.reshape(-1, 3).mean(axis=0)
    return tuple(int(v) for v in mean)


def draw_foreground(tile: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    art = int(round(size * ADAPTIVE_SCALE))
    scaled = tile.resize((art, art), Image.LANCZOS)
    off = (size - art) // 2
    canvas.alpha_composite(scaled, (off, off))
    return canvas


def check_mask(tile: Image.Image, size: int = 432) -> Image.Image:
    """预览：模拟系统圆形遮罩下的实际观感（仅用于自检，不写入资源）。"""
    fg = draw_foreground(tile, size)
    mask = Image.new("L", (size, size), 0)
    from PIL import ImageDraw

    ImageDraw.Draw(mask).ellipse(
        [size * 0.1667, size * 0.1667, size * 0.8333, size * 0.8333], fill=255
    )
    out = Image.new("RGBA", (size, size), (24, 26, 32, 255))
    out.paste(fg, (0, 0), mask)
    return out


def main():
    tile = load_tile()
    tile.save(MASTER)

    top = edge_color(tile, "top")
    bottom = edge_color(tile, "bottom")

    densities = [
        ("mipmap-mdpi", 48, 108),
        ("mipmap-hdpi", 72, 162),
        ("mipmap-xhdpi", 96, 216),
        ("mipmap-xxhdpi", 144, 324),
        ("mipmap-xxxhdpi", 192, 432),
    ]
    for folder, icon_px, fg_px in densities:
        path = os.path.join(RES, folder)
        os.makedirs(path, exist_ok=True)
        tile.resize((icon_px, icon_px), Image.LANCZOS).save(
            os.path.join(path, "ic_launcher.png")
        )
        draw_foreground(tile, fg_px).save(
            os.path.join(path, "ic_launcher_foreground.png")
        )

    check_mask(tile).save(os.path.join(ROOT, "assets", "brand", "preview_adaptive.png"))

    print("icons written to", RES)
    print("background gradient: #%02X%02X%02X -> #%02X%02X%02X" % (*top, *bottom))


if __name__ == "__main__":
    main()
