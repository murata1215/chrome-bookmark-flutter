#!/usr/bin/env python3
"""アプリアイコン／スプラッシュのロゴを生成する（手元で一度だけ実行するツール）。

出力:
  assets/icon/app_icon.png             1024x1024 不透明（iOS 用。アルファ付きは App Store Connect が弾く）
  assets/icon/app_icon_foreground.png  1024x1024 透過・中央 66% 以内（Android adaptive icon の前景）
  assets/branding/splash_logo.png      512x512 透過（スプラッシュ中央のロゴ）

モチーフ: 栞（ブックマークのリボン）。Chrome を想起させる円形4色・虹色・"C" の字は使わない。
4倍サイズで描いてから LANCZOS 縮小し、アンチエイリアスを効かせる。
再実行: `python3 tool/gen_icon.py`
"""

from PIL import Image, ImageDraw

OUT = 1024
SS = 4  # supersampling 倍率
W = OUT * SS

BG_TOP = (0x6F, 0x5F, 0xE8)
BG_BOTTOM = (0x4A, 0x3F, 0xB8)
WHITE = (255, 255, 255, 255)
ACCENT = (0xFF, 0xC9, 0x6B, 255)  # ★ と同じアンバー


def _lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _ribbon_polygon(cx, w, top, bot, notch):
    half = w // 2
    return [
        (cx - half, top),
        (cx + half, top),
        (cx + half, bot),
        (cx, bot - notch),
        (cx - half, bot),
    ]


def make_icon(path, *, with_background: bool, alpha: bool):
    mode = "RGBA" if alpha else "RGB"
    fill_bg = (0, 0, 0, 0) if alpha else BG_TOP
    img = Image.new(mode, (W, W), fill_bg)
    draw = ImageDraw.Draw(img)

    if with_background:
        # 斜めグラデーション（行ごとに線形補間）。
        for y in range(W):
            t = y / W
            draw.line([(0, y), (W, y)], fill=_lerp(BG_TOP, BG_BOTTOM, t))

    cx = W // 2
    # Android adaptive icon は中央 66% 以内に主要形状を収める必要があるため、
    # 前景（with_background=False）はリボンを一回り小さく描く。
    scale = 1.0 if with_background else 0.72
    w = int(W * 0.30 * scale)
    top = int(W * (0.50 - 0.29 * scale))
    bot = int(W * (0.50 + 0.29 * scale))
    notch = int(W * 0.145 * scale)

    draw.polygon(_ribbon_polygon(cx, w, top, bot, notch), fill=WHITE)

    # 先端のアンバー点（★ の色と対応させる）。
    r = int(W * 0.045 * scale)
    accent_cy = top + int(W * 0.09 * scale)
    draw.ellipse([cx - r, accent_cy - r, cx + r, accent_cy + r], fill=ACCENT)

    img = img.resize((OUT, OUT), Image.LANCZOS)
    img.save(path)
    print(f"wrote {path} ({img.size[0]}x{img.size[1]}, alpha={alpha})")


def make_splash(path):
    size = 512
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    W2 = size * SS
    cx = W2 // 2
    w = int(W2 * 0.34)
    top = int(W2 * 0.24)
    bot = int(W2 * 0.76)
    notch = int(W2 * 0.16)
    draw.polygon(_ribbon_polygon(cx, w, top, bot, notch), fill=(0x4A, 0x3F, 0xB8, 255))
    r = int(W2 * 0.05)
    accent_cy = top + int(W2 * 0.09)
    draw.ellipse([cx - r, accent_cy - r, cx + r, accent_cy + r], fill=ACCENT)
    img = img.resize((size, size), Image.LANCZOS)
    img.save(path)
    print(f"wrote {path} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    make_icon("assets/icon/app_icon.png", with_background=True, alpha=False)
    make_icon("assets/icon/app_icon_foreground.png", with_background=False, alpha=True)
    make_splash("assets/branding/splash_logo.png")
