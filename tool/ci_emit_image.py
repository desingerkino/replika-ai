"""Выводит картинки в сводку запуска GitHub Actions (как base64 в заметках):
так снимок экрана из автотеста можно увидеть без скачивания артефактов.

  python3 tool/ci_emit_image.py <имя> <часть> <файл.png> [<файл2.png> ...]

Картинки ставятся в ряд, уменьшаются до ширины 590 px каждая и сохраняются в
JPEG не больше MAX_BYTES. Один шаг CI показывает не больше 10 заметок, поэтому
вывод разбит на части: шаг с номером <часть> печатает свои 10 кусков."""
import base64
import hashlib
import io
import sys

from PIL import Image

MAX_BYTES = 96_000
CHUNK = 3400
PER_STEP = 10

name, part = sys.argv[1], int(sys.argv[2])
images = [Image.open(p).convert('RGB') for p in sys.argv[3:]]
width = 590
scaled = [im.resize((width, round(im.height * width / im.width)), Image.LANCZOS) for im in images]
sheet = Image.new('RGB', (width * len(scaled) + 8 * (len(scaled) - 1), max(im.height for im in scaled)), (40, 40, 40))
for i, im in enumerate(scaled):
    sheet.paste(im, (i * (width + 8), 0))

data = b''
for quality in range(82, 20, -4):
    buf = io.BytesIO()
    sheet.save(buf, 'JPEG', quality=quality, optimize=True)
    data = buf.getvalue()
    if len(data) <= MAX_BYTES:
        break
text = base64.b64encode(data).decode()
chunks = [text[i:i + CHUNK] for i in range(0, len(text), CHUNK)]
digest = hashlib.md5(data).hexdigest()
for i in range(part * PER_STEP, min(len(chunks), (part + 1) * PER_STEP)):
    print(f"::notice title={name} {i:03d}/{len(chunks):03d} md5={digest}::{chunks[i]}")
print(f'{name}: {len(data)} байт, кусков {len(chunks)}, качество {quality}', file=sys.stderr)
