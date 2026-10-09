#!/usr/bin/env python3
"""Генерирует иконки «Реплики» для Android и iOS из логотипа-сферы
assets/brand/replika_logo.png (PNG с прозрачным фоном). Нужен Pillow:
pip install pillow.

Результат кладётся в tool/android_res/ и tool/ios_res/, откуда его
копируют tool/prepare_android.sh и tool/prepare_ios.sh. Готовые PNG уже
лежат в проекте; запускать скрипт нужно только после смены логотипа.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LOGO = os.path.join(ROOT, "assets", "brand", "replika_logo.png")
OUT = os.path.join(HERE, "android_res")
IOS_OUT = os.path.join(HERE, "ios_res", "AppIcon.appiconset")
DOCS = os.path.join(ROOT, "docs", "brand")

# Фон иконки: глубокий ночной синий — сфера «светится» на нём, как в макете.
BG_TOP = (0x16, 0x1A, 0x3A)
BG_BOTTOM = (0x07, 0x09, 0x18)
BG_HEX = "#0B0F24"

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def background(size):
    """Вертикальный градиент с мягким свечением за сферой."""
    bg = Image.new("RGB", (size, size), BG_BOTTOM)
    draw = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / max(1, size - 1)
        col = tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM))
        draw.line([(0, y), (size, y)], fill=col)
    glow = Image.new("L", (size, size), 0)
    g = ImageDraw.Draw(glow)
    r = size * 0.36
    c = size / 2
    g.ellipse((c - r, c - r, c + r, c + r), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.09))
    tint = Image.new("RGB", (size, size), (0x5B, 0x4B, 0xF0))
    return Image.composite(tint, bg, glow).convert("RGBA")


def sphere(logo, diameter):
    return logo.resize((diameter, diameter), Image.LANCZOS)


def place(canvas, logo, diameter):
    s = sphere(logo, diameter)
    off = ((canvas.width - diameter) // 2, (canvas.height - diameter) // 2)
    canvas.alpha_composite(s, off)
    return canvas


def rounded(img, radius_k=0.225):
    size = img.width
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * 4 - 1, size * 4 - 1), radius=size * 4 * radius_k, fill=255
    )
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def _bezier(points, t):
    pts = list(points)
    while len(pts) > 1:
        pts = [((1 - t) * a[0] + t * b[0], (1 - t) * a[1] + t * b[1]) for a, b in zip(pts, pts[1:])]
    return pts[0]


def _taper(draw, n, ctrl, w0, w1, ease=1.6):
    """Мазок по кривой Безье: тонкое начало, «капля» в конце — как
    завитки на сфере логотипа."""
    steps = 400
    for i in range(steps + 1):
        t = i / steps
        x, y = _bezier(ctrl, t)
        r = (w0 + (w1 - w0) * (t ** ease)) / 2
        draw.ellipse(((x - r) * n, (y - r) * n, (x + r) * n, (y + r) * n), fill=255)


def notification_glyph(size):
    """Значок уведомления Android: белый силуэт сферы-логотипа (кольцо и
    два завитка) на прозрачном фоне. Сплошной круг система показывала бы
    белым пятном — поэтому рисуем узнаваемые завитки."""
    n = size * 4
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((0.04 * n, 0.04 * n, 0.96 * n, 0.96 * n), outline=255, width=int(0.07 * n))
    _taper(d, n, [(0.34, 0.76), (0.16, 0.40), (0.40, 0.16), (0.62, 0.22), (0.84, 0.30), (0.76, 0.52), (0.60, 0.50)],
           0.035, 0.15)
    _taper(d, n, [(0.36, 0.60), (0.52, 0.50), (0.66, 0.58), (0.70, 0.74)], 0.035, 0.12)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def main():
    logo = Image.open(LOGO).convert("RGBA")

    # iOS: квадрат 1024 без прозрачности (скругляет сама система).
    ios = place(background(1024), logo, 840).convert("RGB")
    os.makedirs(IOS_OUT, exist_ok=True)
    ios.save(os.path.join(IOS_OUT, "icon-1024.png"))

    for name, k in DENSITIES.items():
        folder = os.path.join(OUT, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        # Старые лаунчеры: готовая скруглённая плитка 48 dp.
        legacy = int(48 * k)
        tile = place(background(legacy * 4), logo, int(legacy * 4 * 0.84))
        rounded(tile).resize((legacy, legacy), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher.png")
        )
        # Адаптивная иконка: слой 108 dp, безопасная зона 66 dp.
        layer = int(108 * k)
        fg = Image.new("RGBA", (layer, layer), (0, 0, 0, 0))
        place(fg, logo, int(layer * 0.64))
        fg.save(os.path.join(folder, "ic_launcher_foreground.png"))
        # Монохромная (тематические значки Android 13+): белый силуэт сферы.
        mono = Image.new("RGBA", (layer, layer), (0, 0, 0, 0))
        d = int(layer * 0.56)
        alpha = sphere(logo, d).split()[3]
        white = Image.new("RGBA", (d, d), (255, 255, 255, 255))
        white.putalpha(alpha)
        mono.alpha_composite(white, ((layer - d) // 2, (layer - d) // 2))
        mono.save(os.path.join(folder, "ic_launcher_monochrome.png"))

    # Значок в строке состояния и в шторке уведомлений: 24 dp, белый силуэт.
    for name, k in DENSITIES.items():
        folder = os.path.join(OUT, f"drawable-{name}")
        os.makedirs(folder, exist_ok=True)
        notification_glyph(int(24 * k)).save(os.path.join(folder, "ic_notification.png"))

    values = os.path.join(OUT, "values")
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, "ic_launcher_background.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{BG_HEX}</color>\n</resources>\n'
        )

    os.makedirs(DOCS, exist_ok=True)
    rounded(ios.convert("RGBA").resize((512, 512), Image.LANCZOS)).save(
        os.path.join(DOCS, "replika_icon_512.png")
    )
    print("Иконки обновлены.")


if __name__ == "__main__":
    main()
