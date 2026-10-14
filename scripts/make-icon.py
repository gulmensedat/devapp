#!/usr/bin/env python3
"""DevApp uygulama ikonunu çizer: Support/AppIcon.png (1024) ve Support/AppIcon.icns.

Tasarım: koyu macOS kare-yuvarlak zemin üzerinde 2x2 proje kutusu
(pano kartlarındaki proje renkleri); sağ alttaki kutu terminal istemi "›_".
Kullanım: python3 scripts/make-icon.py   (Pillow gerekir)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # süper örnekleme
SIZE = 1024 * S
OUT = Path(__file__).resolve().parent.parent / "Support"


def hex_rgb(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def rounded(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # macOS ikon ızgarası: 1024 içinde 824'lük gövde, 100 px kenar boşluğu
    m = 100 * S
    body = (m, m, SIZE - m, SIZE - m)
    radius = 185 * S

    # Gölge
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    rounded(sd, (body[0], body[1] + 18 * S, body[2], body[3] + 18 * S), radius, (0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24 * S))
    img.alpha_composite(shadow)

    # Gövde: yukarıdan aşağı hafif koyulaşan zemin
    grad = Image.new("RGBA", (SIZE, SIZE))
    gd = ImageDraw.Draw(grad)
    top, bottom = hex_rgb("#202229"), hex_rgb("#0D0E11")
    for y in range(SIZE):
        t = y / SIZE
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        gd.line([(0, y), (SIZE, y)], fill=c)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    # Yarı saydam çizimler ayrı katmanda (ImageDraw saydamlığı karıştırmaz, üzerine yazar)
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.rounded_rectangle(body, radius=radius, outline=(255, 255, 255, 26), width=3 * S)

    # 2x2 kutular
    pad = 168 * S          # gövde kenarından
    gap = 56 * S
    inner = (body[0] + pad, body[1] + pad, body[2] - pad, body[3] - pad)
    cell = (inner[2] - inner[0] - gap) // 2
    r = 64 * S
    tiles = [
        ("#8E9BFF", 0, 0),
        ("#FF9A5A", 1, 0),
        ("#43D9B8", 0, 1),
    ]
    for color, cx, cy in tiles:
        x0 = inner[0] + cx * (cell + gap)
        y0 = inner[1] + cy * (cell + gap)
        rounded(d, (x0, y0, x0 + cell, y0 + cell), r, hex_rgb(color))

    # Terminal kutusu (sağ alt)
    x0 = inner[0] + cell + gap
    y0 = inner[1] + cell + gap
    rounded(d, (x0, y0, x0 + cell, y0 + cell), r, hex_rgb("#0A0B0C"))
    g.rounded_rectangle((x0, y0, x0 + cell, y0 + cell), radius=r, outline=hex_rgb("#5BE39A", 120), width=6 * S)
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)

    green = hex_rgb("#5BE39A")
    w = 22 * S
    # "›" chevron
    cx0 = x0 + cell * 0.24
    cy_mid = y0 + cell * 0.50
    span = cell * 0.17
    d.line([(cx0, cy_mid - span), (cx0 + span, cy_mid), (cx0, cy_mid + span)], fill=green, width=w, joint="curve")
    for px, py in [(cx0, cy_mid - span), (cx0 + span, cy_mid), (cx0, cy_mid + span)]:
        d.ellipse((px - w / 2, py - w / 2, px + w / 2, py + w / 2), fill=green)
    # "_" imleç
    ux0 = x0 + cell * 0.52
    uy = cy_mid + span
    d.rounded_rectangle((ux0, uy - w / 2, ux0 + cell * 0.24, uy + w / 2), radius=w // 2, fill=green)

    final = img.resize((1024, 1024), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    final.save(OUT / "AppIcon.png")
    final.save(OUT / "AppIcon.icns",
               sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("✓", OUT / "AppIcon.png")
    print("✓", OUT / "AppIcon.icns")


if __name__ == "__main__":
    main()
