"""Готовит графику стартового экрана из эталона docs/brand/splash_reference.png
(макет телефона 1024×1536):
  assets/splash/background.webp — экран без сферы, надписей, полосы загрузки,
                                  статус-бара и индикатора «домой»;
  assets/splash/orb.webp        — сфера с прозрачным ореолом.
Фон + сфера на исходном месте дают эталон (кроме убранного): надписи, полоса и
анимации рисуются кодом (lib/design_system, lib/features/splash).

Числа раскладки в lib/features/splash/splash_screen.dart сняты с того же эталона:
экран 686×1419 px = 393×812.9 пункта, центр сферы (341, 508) px.

Запуск из корня проекта: python3 tool/build_splash_assets.py
Нужны: pip install pillow numpy opencv-python-headless"""
import os
import sys
import numpy as np
import cv2
from PIL import Image, ImageFilter

src = sys.argv[1] if len(sys.argv) > 1 else 'docs/brand/splash_reference.png'
out = sys.argv[2] if len(sys.argv) > 2 else 'assets/splash'
os.makedirs(out, exist_ok=True)
X0, Y0, X1, Y1 = 169, 57, 855, 1476            # экран в эталоне (без кромки рамки)
ref = np.asarray(Image.open(src).convert('RGB'))
S = ref[Y0:Y1, X0:X1].copy()
H, W, _ = S.shape
orig = S.astype(np.float32) / 255
lum = S.astype(np.float32).sum(-1) / 255
mn = S.min(-1).astype(np.float32) / 255

mask = np.zeros((H, W), np.uint8)

def rect(x0, y0, x1, y1):                        # координаты эталона → экрана
    return slice(y0 - Y0, y1 - Y0), slice(x0 - X0, x1 - X0)

def grow(m, px):
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * px + 1, 2 * px + 1))
    return cv2.dilate(m, k)

# Скруглённые углы макета (за ними рамка телефона).
RC = 99
yy, xx = np.mgrid[0:H, 0:W]
for cx, cy in ((RC, RC), (W - 1 - RC, RC), (RC, H - 1 - RC), (W - 1 - RC, H - 1 - RC)):
    zone = ((xx < RC) if cx == RC else (xx > W - 1 - RC)) & ((yy < RC) if cy == RC else (yy > H - 1 - RC))
    mask[zone & ((xx - cx) ** 2 + (yy - cy) ** 2 > (RC - 5) ** 2)] = 255

# Dynamic Island — только сама чёрная «пилюля»: волна, которая проходит под
# её нижним краем, остаётся нетронутой.
r = rect(396, 62, 628, 142)
pill = np.zeros((H, W), np.uint8)
pill[r] = (S[r].max(-1) < 14).astype(np.uint8) * 255
pill = cv2.morphologyEx(pill, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (41, 41)))
mask[grow(pill, 2) > 0] = 255

def bright(x0, y0, x1, y1, test, px):
    r = rect(x0, y0, x1, y1)
    m = np.zeros((H, W), np.uint8)
    m[r] = (test[r]).astype(np.uint8) * 255
    mask[grow(m, px) > 0] = 255

bright(225, 78, 310, 124, mn > 0.62, 5)          # время
bright(660, 78, 822, 124, mn > 0.62, 5)          # сеть, Wi-Fi, батарея
bright(270, 790, 760, 866, lum > 0.62, 9)        # REPLIKA
bright(350, 868, 690, 914, lum > 0.62, 8)        # MESSENGER
bright(430, 1008, 600, 1056, lum > 0.75, 7)      # Загрузка...
bright(380, 1440, 648, 1476, mn > 0.80, 6)       # индикатор «домой»
mask[rect(322, 962, 704, 996)] = 255             # полоса загрузки

bgr = cv2.cvtColor(S, cv2.COLOR_RGB2BGR)
bgr = cv2.inpaint(bgr, mask, 7, cv2.INPAINT_TELEA)
bg = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.float32) / 255
# Заплатки слегка размываем, чтобы не осталось полос.
soft = cv2.GaussianBlur(bg, (0, 0), 3)
m = cv2.GaussianBlur((mask > 0).astype(np.float32), (0, 0), 3)[..., None]
bg = bg * (1 - m) + soft * m

# Сфера: убираем из фона радиальной «протяжкой» с кольца снаружи.
CX, CY, R_OUT = 510 - X0, 565 - Y0, 266
dx, dy = xx - CX, yy - CY
rr = np.sqrt(dx * dx + dy * dy)
inside = rr < R_OUT
ang = np.arctan2(dy, dx)
sx = np.clip((CX + np.cos(ang) * (R_OUT + 3)).round().astype(int), 0, W - 1)
sy = np.clip((CY + np.sin(ang) * (R_OUT + 3)).round().astype(int), 0, H - 1)
hole = bg.copy()
hole[inside] = bg[sy[inside], sx[inside]]
blur = cv2.GaussianBlur(hole, (0, 0), 22)
w = np.clip((R_OUT + 6 - rr) / 30, 0, 1)[..., None]
bg = hole * (1 - w) + blur * w

HALF = 248
c = orig[CY - HALF:CY + HALF, CX - HALF:CX + HALF]
b = bg[CY - HALF:CY + HALF, CX - HALF:CX + HALF]
r = rr[CY - HALF:CY + HALF, CX - HALF:CX + HALF]
a_min = np.clip(((c - b) / np.maximum(1 - b, 1e-3)).max(-1), 0, 1)
alpha = np.maximum(a_min, np.clip((216 - r) / 12, 0, 1))
f = np.clip(b + (c - b) / np.maximum(alpha, 1e-3)[..., None], 0, 1)
alpha = alpha * np.clip((241 - r) / 12, 0, 1)
orb = np.dstack([f, alpha[..., None]])

Image.fromarray((np.clip(bg, 0, 1) * 255).round().astype(np.uint8)).save(
    f'{out}/background.webp', 'WEBP', quality=92, method=6)
Image.fromarray((orb * 255).round().astype(np.uint8), 'RGBA').save(
    f'{out}/orb.webp', 'WEBP', quality=95, method=6, exact=True)
print('экран', W, H, 'центр сферы', CX, CY, 'сторона картинки сферы', HALF * 2)
