#!/usr/bin/env python3
"""Генерирует иконки «Реплики» для Android из той же геометрии, что и
lib/core/brand/logo.dart. Нужен Pillow: pip install pillow.

Результат кладётся в tool/android_res/, откуда его копирует
tool/prepare_android.sh. Готовые PNG уже лежат в проекте; запускать
скрипт нужно только после изменения логотипа.
"""
import os
from PIL import Image, ImageChops, ImageDraw

PETROL = (0x15, 0x5E, 0x75, 255)
INK = (0x15, 0x20, 0x2B, 255)
TUNGSTEN = (0xE3, 0xA1, 0x3B, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
SS = 4  # суперсэмплинг для гладких краёв

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "android_res")
IOS_OUT = os.path.join(HERE, "ios_res", "AppIcon.appiconset")
DOCS = os.path.join(os.path.dirname(HERE), "docs", "brand")

SLATE = [(10, 26), (86, 8), (89, 19), (13, 37)]
TAIL = [(22, 84), (15, 97), (40, 84)]
DOTS = [34, 50, 66]


def _scaled(points, k, ox, oy):
    return [(ox + x * k, oy + y * k) for x, y in points]


def logo_layer(canvas, box, ox, oy, mono=False):
    """Рисует знак в квадрат box×box с левым верхним углом (ox, oy)."""
    k = box / 100.0
    slate_col, stripe_col = (TUNGSTEN, INK)
    bubble_col, dot_col = (WHITE, PETROL)
    if mono:
        slate_col = bubble_col = WHITE

    layer = Image.new("RGBA", (canvas, canvas), CLEAR)
    d = ImageDraw.Draw(layer)
    d.polygon(_scaled(SLATE, k, ox, oy), fill=slate_col)

    # Полосы хлопушки только внутри планки.
    slate_mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(slate_mask).polygon(_scaled(SLATE, k, ox, oy), fill=255)
    stripes = Image.new("L", (canvas, canvas), 0)
    ds = ImageDraw.Draw(stripes)
    x = 2
    while x < 100:
        ds.line([(ox + x * k, oy + 44 * k), (ox + (x + 22) * k, oy)],
                fill=255, width=max(1, round(7 * k)))
        x += 16
    stripes = ImageChops.multiply(stripes, slate_mask)

    if mono:
        # Монохромная иконка: полосы и точки вырезаются прозрачностью.
        alpha = layer.split()[3]
        layer.putalpha(ImageChops.subtract(alpha, stripes))
    else:
        layer.paste(Image.new("RGBA", (canvas, canvas), stripe_col), (0, 0), stripes)

    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([ox + 10 * k, oy + 40 * k, ox + 90 * k, oy + 86 * k],
                        radius=16 * k, fill=bubble_col)
    d.polygon(_scaled(TAIL, k, ox, oy), fill=bubble_col)
    r = 5.5 * k
    for cx in DOTS:
        bbox = [ox + cx * k - r, oy + 63 * k - r, ox + cx * k + r, oy + 63 * k + r]
        if mono:
            hole = Image.new("L", (canvas, canvas), 0)
            ImageDraw.Draw(hole).ellipse(bbox, fill=255)
            alpha = layer.split()[3]
            layer.putalpha(ImageChops.subtract(alpha, hole))
            d = ImageDraw.Draw(layer)
        else:
            d.ellipse(bbox, fill=dot_col)
    return layer


def legacy_icon(size):
    """Иконка для Android 7 и ниже: скруглённый квадрат петроль + знак."""
    c = size * SS
    img = Image.new("RGBA", (c, c), CLEAR)
    margin = c * 0.04
    ImageDraw.Draw(img).rounded_rectangle([margin, margin, c - margin, c - margin],
                                          radius=c * 0.22, fill=PETROL)
    box = c * 0.66
    img = Image.alpha_composite(img, logo_layer(c, box, (c - box) / 2, (c - box) / 2 + c * 0.01))
    return img.resize((size, size), Image.LANCZOS)


def adaptive_layer(size, mono=False):
    """Передний слой адаптивной иконки: знак в безопасной зоне 66dp из 108dp."""
    c = size * SS
    box = c * 0.50
    img = logo_layer(c, box, (c - box) / 2, (c - box) / 2, mono=mono)
    return img.resize((size, size), Image.LANCZOS)


def ios_icon(size=1024):
    """Иконка iOS: полный квадрат петроль без скруглений и без прозрачности
    (скругляет система) + знак."""
    c = size * SS
    img = Image.new("RGBA", (c, c), PETROL)
    box = c * 0.62
    img = Image.alpha_composite(img, logo_layer(c, box, (c - box) / 2, (c - box) / 2 + c * 0.01))
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


def write_ios_icon():
    os.makedirs(IOS_OUT, exist_ok=True)
    ios_icon(1024).save(os.path.join(IOS_OUT, "icon-1024.png"))
    with open(os.path.join(IOS_OUT, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(
            '{\n  "images" : [\n    {\n      "filename" : "icon-1024.png",\n'
            '      "idiom" : "universal",\n      "platform" : "ios",\n'
            '      "size" : "1024x1024"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')


def main():
    write_ios_icon()
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, scale in densities.items():
        folder = os.path.join(OUT, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        legacy_icon(round(48 * scale)).save(os.path.join(folder, "ic_launcher.png"))
        adaptive_layer(round(108 * scale)).save(os.path.join(folder, "ic_launcher_foreground.png"))
        adaptive_layer(round(108 * scale), mono=True).save(
            os.path.join(folder, "ic_launcher_monochrome.png"))

    anydpi = os.path.join(OUT, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n')

    values = os.path.join(OUT, "values")
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, "ic_launcher_background.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <color name="ic_launcher_background">#155E75</color>\n'
            '</resources>\n')

    os.makedirs(DOCS, exist_ok=True)
    legacy_icon(512).save(os.path.join(DOCS, "replika_icon_512.png"))
    print("Иконки записаны в", OUT)


if __name__ == "__main__":
    main()
