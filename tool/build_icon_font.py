#!/usr/bin/env python3
"""Собирает assets/fonts/ReplikaIcons.ttf — собственные значки «Реплики».

Запуск (нужны numpy, scipy, scikit-image, fonttools; в приложение они не входят):

    python3 tool/build_icon_font.py

Значки описаны геометрией на сетке 24x24 (галочки статуса — 16x16), ось Y вниз.
Форма строится как маска высокого разрешения, скругления и контур — точными
расстояниями, затем граница переводится в контуры шрифта. Чтобы изменить значок,
правится его функция ниже и скрипт запускается заново; коды символов (E001...)
менять нельзя — на них ссылается lib/core/design/icons.dart.
Образец набора рядом с Material: tool/icon_font_preview.png.
"""
import math
import os
import sys

import numpy as np
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from scipy import ndimage
from skimage import measure

UPM = 2400          # единиц на кегль; значок занимает весь кегль
SAMPLES = 960       # разрешение маски по стороне


class Canvas:
    """Сетка size x size единиц (24 или 16), ось Y вниз."""

    def __init__(self, size):
        self.size = size
        self.res = SAMPLES / size
        c = (np.arange(SAMPLES) + 0.5) / self.res
        self.x, self.y = np.meshgrid(c, c)

    # --- примитивы: возвращают маску (True — внутри) ---
    def circle(self, cx, cy, r):
        return np.hypot(self.x - cx, self.y - cy) < r

    def box(self, x0, y0, x1, y1, r=0.0):
        cx, cy, hx, hy = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
        qx = np.abs(self.x - cx) - (hx - r)
        qy = np.abs(self.y - cy) - (hy - r)
        outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
        inside = np.minimum(np.maximum(qx, qy), 0)
        return outside + inside - r < 0

    def rotated_box(self, cx, cy, hx, hy, r, angle):
        ca, sa = math.cos(angle), math.sin(angle)
        dx, dy = self.x - cx, self.y - cy
        u, v = dx * ca + dy * sa, -dx * sa + dy * ca
        qx, qy = np.abs(u) - (hx - r), np.abs(v) - (hy - r)
        outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
        inside = np.minimum(np.maximum(qx, qy), 0)
        return outside + inside - r < 0

    def stroke(self, points, width):
        """Ломаная со скруглёнными концами и стыками."""
        d = np.full(self.x.shape, 1e9)
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            px, py, vx, vy = self.x - ax, self.y - ay, bx - ax, by - ay
            t = np.clip((px * vx + py * vy) / (vx * vx + vy * vy), 0, 1)
            d = np.minimum(d, np.hypot(px - t * vx, py - t * vy))
        return d < width / 2

    def polygon(self, points):
        inside = np.zeros(self.x.shape, bool)
        n = len(points)
        for i in range(n):
            (x0, y0), (x1, y1) = points[i], points[(i + 1) % n]
            cond = (y0 > self.y) != (y1 > self.y)
            with np.errstate(divide='ignore', invalid='ignore'):
                xi = (x1 - x0) * (self.y - y0) / (y1 - y0) + x0
            inside ^= cond & (self.x < xi)
        return inside

    # --- операции над масками (в единицах сетки) ---
    def grow(self, mask, d):
        return ndimage.distance_transform_edt(~mask) < d * self.res

    def shrink(self, mask, d):
        return ndimage.distance_transform_edt(mask) > d * self.res

    def soften(self, mask, concave=0.0, convex=0.0):
        """Скругляет вогнутые и выпуклые углы."""
        if concave:
            mask = self.shrink(self.grow(mask, concave), concave)
        if convex:
            mask = self.grow(self.shrink(mask, convex), convex)
        return mask

    def outline(self, mask, width):
        """Контур толщиной width внутрь от края формы."""
        return mask & ~self.shrink(mask, width)


# ---------------------------------------------------------------------------
# Значки
# ---------------------------------------------------------------------------

def back():
    c = Canvas(24)
    return c, c.stroke([(14.6, 5.4), (8.4, 12.0), (14.6, 18.6)], 2.2)


def _bubble(c):
    body = c.box(3.0, 3.6, 21.0, 17.8, r=6.4)
    tail = c.polygon([(6.2, 15.2), (5.0, 21.0), (12.2, 17.4)])
    return c.soften(body | tail, concave=0.7, convex=0.55)


def chats():
    c = Canvas(24)
    return c, c.outline(_bubble(c), 2.0)


def chats_active():
    c = Canvas(24)
    return c, _bubble(c)


def _arc(cx, cy, rx, ry, start, end, steps=48):
    """Точки дуги эллипса; углы в градусах, 270 — верх (ось Y вниз)."""
    pts = []
    for i in range(steps + 1):
        a = math.radians(start + (end - start) * i / steps)
        pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


# Пара людей: передний целиком, задний выглядывает справа с зазором.
FRONT_HEAD = (9.0, 8.1, 3.5)
BACK_HEAD = (17.3, 8.4, 3.2)
GAP = 1.3


def _people_solid(c):
    front_head = c.circle(*FRONT_HEAD)
    front_body = c.soften(c.box(2.8, 13.5, 15.2, 30.0, r=5.6) & (c.y < 20.4), convex=0.8)
    back_head = c.circle(*BACK_HEAD)
    back_body = c.soften(c.box(12.0, 14.3, 21.6, 30.0, r=4.6) & (c.y < 20.4), convex=0.8)
    return front_head, front_body, back_head, back_body


def contacts():
    c = Canvas(24)
    fh, fb, _, _ = _people_solid(c)
    keep_out = c.grow(fh | fb, GAP)
    front = c.outline(fh, 2.0) | c.stroke(_arc(9.0, 19.4, 5.2, 4.9, 180, 360), 2.0)
    hx, hy, hr = BACK_HEAD
    behind = c.circle(hx, hy, hr) & ~c.circle(hx, hy, hr - 1.9)
    behind |= c.stroke(_arc(16.8, 19.4, 3.8, 4.1, 262, 360), 2.0)
    return c, front | (behind & ~keep_out)


def contacts_active():
    c = Canvas(24)
    fh, fb, bh, bb = _people_solid(c)
    keep_out = c.grow(fh | fb, GAP)
    return c, fh | fb | ((bh | bb) & ~keep_out)


def _gear(c):
    # Шесть широких коротких зубцов: спокойнее и крупнее в деталях, чем восемь.
    shape = c.circle(12, 12, 7.3)
    for i in range(6):
        a = math.pi / 2 + i * math.pi / 3
        shape |= c.rotated_box(12 + 7.6 * math.cos(a), 12 + 7.6 * math.sin(a), 2.75, 2.2, 0.3, a + math.pi / 2)
    return c.soften(shape, concave=0.8, convex=0.9)


def settings():
    c = Canvas(24)
    gear = _gear(c)
    hub = c.circle(12, 12, 3.3) & ~c.circle(12, 12, 1.4)
    return c, c.outline(gear, 2.0) | hub


def settings_active():
    c = Canvas(24)
    return c, _gear(c) & ~c.circle(12, 12, 3.1)


TICK = [(0.0, 8.7), (3.2, 11.9), (9.3, 4.9)]   # короткое и длинное плечо галочки
TICK_STEP = 4.6                                 # сдвиг второй галочки


def tick_sent():
    c = Canvas(16)
    return c, c.stroke([(x + 3.35, y) for x, y in TICK], 1.8)


def tick_double():
    c = Canvas(16)
    first = c.stroke([(x + 1.0, y) for x, y in TICK], 1.8)
    # Вторая галочка — только длинное плечо: с коротким две сливаются в зигзаг.
    second = c.stroke([(x + 1.0 + TICK_STEP, y) for x, y in TICK[1:]], 1.8)
    return c, first | second


GLYPHS = [
    (0xE001, 'back', back),
    (0xE002, 'chats', chats),
    (0xE003, 'chatsActive', chats_active),
    (0xE004, 'contacts', contacts),
    (0xE005, 'contactsActive', contacts_active),
    (0xE006, 'settings', settings),
    (0xE007, 'settingsActive', settings_active),
    (0xE008, 'tickSent', tick_sent),
    (0xE009, 'tickDouble', tick_double),
]


# ---------------------------------------------------------------------------
# Маска -> контуры шрифта
# ---------------------------------------------------------------------------

def _inside(pt, poly):
    x, y = pt
    n, hit = len(poly), False
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            hit = not hit
    return hit


def contours(canvas, mask):
    """Границы маски в единицах шрифта (ось Y вверх), внешние — по часовой."""
    field = ndimage.distance_transform_edt(mask) - ndimage.distance_transform_edt(~mask)
    field = ndimage.gaussian_filter(field, 1.0)
    scale = UPM / SAMPLES
    result = []
    for line in measure.find_contours(field, 0.0):
        line = measure.approximate_polygon(line, tolerance=0.35)
        pts = [((col + 0.5) * scale, UPM - (row + 0.5) * scale) for row, col in line[:-1]]
        if len(pts) >= 3:
            result.append(pts)
    out = []
    for i, pts in enumerate(result):
        depth = sum(1 for j, other in enumerate(result) if j != i and _inside(pts[0], other))
        area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1])) / 2
        clockwise = area < 0
        if clockwise != (depth % 2 == 0):
            pts = pts[::-1]
        out.append([(round(x), round(y)) for x, y in pts])
    return out


def build(path):
    names = ['.notdef'] + [name for _, name, _ in GLYPHS]
    glyphs, metrics, cmap = {}, {}, {}
    pen = TTGlyphPen(None)
    glyphs['.notdef'] = pen.glyph()
    metrics['.notdef'] = (UPM, 0)
    for code, name, make in GLYPHS:
        canvas, mask = make()
        pen = TTGlyphPen(None)
        total = 0
        for pts in contours(canvas, mask):
            pen.moveTo(pts[0])
            for p in pts[1:]:
                pen.lineTo(p)
            pen.closePath()
            total += len(pts)
        glyph = pen.glyph()
        glyph.recalcBounds(None)
        glyphs[name] = glyph
        # Левый отступ равен левому краю рисунка: иначе значок съезжает влево.
        metrics[name] = (UPM, glyph.xMin)
        cmap[code] = name
        unit = UPM / canvas.size
        print(f'{name:16} U+{code:04X}  точек: {total:4}  края (в единицах сетки): '
              f'x {glyph.xMin / unit:.2f}…{glyph.xMax / unit:.2f}, '
              f'y {canvas.size - glyph.yMax / unit:.2f}…{canvas.size - glyph.yMin / unit:.2f}')
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    # Как у Material Icons: значок занимает кегль целиком, базовая линия внизу.
    fb.setupHorizontalHeader(ascent=UPM, descent=0)
    fb.setupNameTable({
        'familyName': 'ReplikaIcons',
        'styleName': 'Regular',
        'uniqueFontIdentifier': 'ReplikaIcons-Regular',
        'fullName': 'ReplikaIcons Regular',
        'version': 'Version 1.0',
        'psName': 'ReplikaIcons-Regular',
    })
    fb.setupOS2(sTypoAscender=UPM, sTypoDescender=0, sTypoLineGap=0, usWinAscent=UPM, usWinDescent=0)
    fb.setupPost()
    fb.save(path)
    print('записан', path, os.path.getsize(path), 'байт')


if __name__ == '__main__':
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'assets', 'fonts', 'ReplikaIcons.ttf'))
