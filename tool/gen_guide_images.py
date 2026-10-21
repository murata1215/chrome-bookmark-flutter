#!/usr/bin/env python3
"""ペアリング手順ガイド（アプリ内マニュアル）用の画像を加工する。

入力: tool/guide_raw/step{1,2,3}_raw.png（Chrome 拡張の実機スクショ。gitignore 済み・
未コミット。拡張の UI が変わったら撮り直して同じファイル名で置き換え、再実行するだけでよい）。

出力: assets/guide/step{1,2,3}_*.png（アプリに同梱・コミット対象）。

加工内容:
  - step1: URL バー（識別子らしき文字列）を黒帯でマスク。パズルアイコン（拡張機能ボタン）に
    丸枠+①、「Chrome Bookmark Launcher」の行に角丸枠+②を付けて、どこを操作するか明示する。
  - step2: メールアドレスをマスク（●●●●@example.com）。「スマホとペアリング」ボタンを
    角丸枠で強調する。
  - step3: QR コードは実際に読み取り可能なまま同梱すると、ガイド画面自体に向けてユーザーが
    スキャンしてしまい「コードが無効か期限切れです」を引く罠になる。そのため強くぼかし+白で
    薄めてスキャン不能にした上で「サンプル」の斜めスタンプを重ねる。8桁コード・残り秒数の
    テキストはそのまま（機密性が無く、かつ「期限は約5分」という情報価値があるため）。

実行: python3 tool/gen_guide_images.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "tool", "guide_raw")
OUT_DIR = os.path.join(ROOT, "assets", "guide")

ACCENT = (91, 79, 209)  # AppTheme.seed (#5B4FD1) と合わせる
ACCENT_SOFT = (91, 79, 209, 60)
MASK_DARK = (30, 32, 40)
SS = 3  # supersampling 倍率（線・文字のアンチエイリアス用）

_FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
]


def _font(size: int) -> ImageFont.FreeTypeFont:
    for path in _FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _badge(draw: ImageDraw.ImageDraw, center: tuple[int, int], radius: int, label: str) -> None:
    cx, cy = center
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=ACCENT,
        outline=(255, 255, 255),
        width=max(2, radius // 8),
    )
    font = _font(int(radius * 1.15))
    bbox = draw.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(
        (cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1]),
        label,
        fill=(255, 255, 255),
        font=font,
    )


def _rounded_outline(
    draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int, width: int
) -> None:
    draw.rounded_rectangle(box, radius=radius, outline=ACCENT, width=width)


def process_step1() -> Image.Image:
    im = Image.open(os.path.join(RAW_DIR, "step1_raw.png")).convert("RGB")
    w, h = im.size
    up = im.resize((w * SS, h * SS), Image.LANCZOS)
    draw = ImageDraw.Draw(up)

    def S(v: float) -> int:
        return int(round(v * SS))

    # URL バー（識別子らしき文字列）をマスク。
    draw.rounded_rectangle(
        [S(6), S(10), S(300), S(60)], radius=S(8), fill=MASK_DARK
    )
    font = _font(S(13))
    draw.text((S(14), S(28)), "• • • • • • • •", fill=(200, 200, 200), font=font)

    # ① 拡張機能アイコン（パズルのピース）を丸枠で囲む。
    _rounded_outline(draw, [S(513), S(14), S(567), S(68)], radius=S(27), width=S(4))
    _badge(draw, (S(506), S(10)), S(16), "1")

    # ② 「Chrome Bookmark Launcher」の行を角丸枠で囲む。
    _rounded_outline(draw, [S(16), S(576), S(572), S(622)], radius=S(10), width=S(4))
    _badge(draw, (S(10), S(576)), S(16), "2")

    return up.resize((w, h), Image.LANCZOS)


def process_step2() -> Image.Image:
    im = Image.open(os.path.join(RAW_DIR, "step2_raw.png")).convert("RGB")
    w, h = im.size
    up = im.resize((w * SS, h * SS), Image.LANCZOS)
    draw = ImageDraw.Draw(up)

    def S(v: float) -> int:
        return int(round(v * SS))

    # メールアドレスをマスク（背景が白いカードなので白帯+再描画で自然に馴染ませる）。
    draw.rectangle([S(128), S(118), S(390), S(148)], fill=(255, 255, 255))
    font = _font(S(17))
    draw.text((S(130), S(122)), "●●●●@example.com", fill=(40, 40, 40), font=font)

    # 「スマホとペアリング」ボタンを角丸枠で強調。
    _rounded_outline(draw, [S(14), S(520), S(292), S(588)], radius=S(10), width=S(4))

    return up.resize((w, h), Image.LANCZOS)


def process_step3() -> Image.Image:
    im = Image.open(os.path.join(RAW_DIR, "step3_raw.png")).convert("RGB")
    w, h = im.size

    qr_box = (58, 148, 392, 462)  # QR コードの外接矩形（実測）

    # QR 部分を強くぼかし、白で薄めてスキャン不能にする。
    qr_region = im.crop(qr_box)
    blurred = qr_region.filter(ImageFilter.GaussianBlur(radius=6))
    whiteout = Image.new("RGB", blurred.size, (255, 255, 255))
    faded = Image.blend(blurred, whiteout, alpha=0.72)
    im.paste(faded, qr_box)

    up = im.resize((w * SS, h * SS), Image.LANCZOS)
    draw = ImageDraw.Draw(up)

    def S(v: float) -> int:
        return int(round(v * SS))

    # 「サンプル」の斜めスタンプ。別レイヤーで回転してから合成する。
    stamp_w, stamp_h = S(260), S(90)
    stamp = Image.new("RGBA", (stamp_w, stamp_h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stamp)
    sd.rounded_rectangle(
        [0, 0, stamp_w, stamp_h], radius=S(14), outline=ACCENT, width=S(5)
    )
    font = _font(S(34))
    label = "サンプル"
    bbox = sd.textbbox((0, 0), label, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    sd.text(
        ((stamp_w - tw) / 2 - bbox[0], (stamp_h - th) / 2 - bbox[1]),
        label,
        fill=ACCENT,
        font=font,
    )
    stamp = stamp.rotate(-18, expand=True, resample=Image.BICUBIC)
    qr_cx = S((qr_box[0] + qr_box[2]) / 2)
    qr_cy = S((qr_box[1] + qr_box[3]) / 2)
    up.paste(
        stamp,
        (qr_cx - stamp.width // 2, qr_cy - stamp.height // 2),
        stamp,
    )

    return up.resize((w, h), Image.LANCZOS)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    outputs = {
        "step1_extensions.png": process_step1,
        "step2_popup.png": process_step2,
        "step3_qr_sample.png": process_step3,
    }
    for filename, fn in outputs.items():
        img = fn()
        path = os.path.join(OUT_DIR, filename)
        img.save(path)
        print(f"wrote {path} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
