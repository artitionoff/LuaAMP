#!/usr/bin/env python3
"""makecov.py - make <track>.cov cover files for the Minecraft music player.

usage:  python makecov.py <folder or file> [more folders/files] [--force]

Needs Pillow (pip install pillow). Covers inside ogg, wav (id3 chunk), mp3 and flac are
read directly; ffmpeg (optional) is only a fallback for other files (m4a ...). Where a cover comes from, in this order:
  1. a picture next to the track: <track>.jpg/.png ... or cover/folder/front/album.jpg/.png in the same folder
  2. the picture embedded in the file (ogg: METADATA_BLOCK_PICTURE; others via ffmpeg)
Copy the .cov files next to the tracks in the game (e.g. mem/music).
"""
import base64
import colorsys
import io
import math
import os
import struct
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit('Pillow is missing. Run:  pip install pillow')

AUDIO_EXT = ('.ogg', '.wav', '.mp3', '.flac', '.m4a', '.opus')
IMG_EXT = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')
SIDE_NAMES = ('cover', 'folder', 'front', 'album', 'albumart')

# sizes in character cells (w, h); a cell is 2x3 sub-pixels, so the image stays square.
# the game picks the biggest one that fits the screen
SIZES = [(6, 4), (9, 6), (12, 8), (18, 12)]
NCOL = 9    # the 9 palette slots the game keeps free for covers
NOTES = []  # why no cover was found (printed for files without one)


# ------------------------------------------------------------------ finding the picture
def sidecar(path):
    base, _ = os.path.splitext(path)
    folder = os.path.dirname(path) or '.'
    names = os.listdir(folder)
    lower = {n.lower(): n for n in names}
    cands = [os.path.basename(base).lower() + e for e in IMG_EXT]
    cands += [n + e for n in SIDE_NAMES for e in IMG_EXT]
    for c in cands:
        if c in lower:
            return Image.open(os.path.join(folder, lower[c]))
    images = [n for n in names if n.lower().endswith(IMG_EXT)]
    if len(images) == 1:                      # a single picture in the folder: take it
        return Image.open(os.path.join(folder, images[0]))
    NOTES.append('no picture next to the track (tried <track>.jpg/png and cover/folder/front/album.jpg/png)')
    return None


def ogg_packets(f):
    packet = b''
    while True:
        head = f.read(27)
        if len(head) < 27 or head[:4] != b'OggS':
            return
        lacing = f.read(head[26])
        for n in lacing:
            packet += f.read(n)
            if n < 255:
                yield packet
                packet = b''


def ogg_embedded(path):
    """METADATA_BLOCK_PICTURE of an Ogg Vorbis / Opus file"""
    try:
        with open(path, 'rb') as f:
            it = ogg_packets(f)
            next(it)
            p = next(it)
    except (StopIteration, OSError):
        return None
    if p.startswith(b'\x03vorbis'):
        i = 7
    elif p.startswith(b'OpusTags'):
        i = 8
    else:
        return None
    vlen = struct.unpack_from('<I', p, i)[0]
    i += 4 + vlen
    count = struct.unpack_from('<I', p, i)[0]
    i += 4
    best = None
    for _ in range(count):
        ln = struct.unpack_from('<I', p, i)[0]
        entry = p[i + 4:i + 4 + ln]
        i += 4 + ln
        if entry.upper().startswith(b'METADATA_BLOCK_PICTURE='):
            try:
                blk = base64.b64decode(entry.split(b'=', 1)[1])
                ptype, mlen = struct.unpack_from('>II', blk, 0)
                o = 8 + mlen
                dlen = struct.unpack_from('>I', blk, o)[0]
                o += 4 + dlen + 16                      # description, width, height, depth, colors
                size = struct.unpack_from('>I', blk, o)[0]
                data = blk[o + 4:o + 4 + size]
                if best is None or ptype == 3:
                    best = data
            except (struct.error, ValueError):
                continue
    if not best:
        NOTES.append('ogg: no embedded picture tag')
    return Image.open(io.BytesIO(best)) if best else None


# ---- covers read without ffmpeg: ID3v2 (mp3, "id3 " chunk of a WAV) and FLAC
def to_image(data, where):
    try:
        return Image.open(io.BytesIO(data))
    except Exception as e:
        NOTES.append('%s: picture found but unreadable (%s)' % (where, e))
        return None


def skip_text(b, i, enc):
    """index after a zero-terminated string starting at i (ID3 text encodings 0-3)"""
    if enc in (1, 2):
        while i + 1 < len(b):
            if b[i] == 0 and b[i + 1] == 0:
                return i + 2
            i += 2
        return len(b)
    j = b.find(b'\x00', i)
    return len(b) if j < 0 else j + 1


def id3_picture(tag):
    """APIC (or v2.2 PIC) frame of an ID3v2 tag -> image bytes, preferring the front cover"""
    if tag[:3] != b'ID3':
        return None
    ver = tag[3]
    size = (tag[6] << 21) | (tag[7] << 14) | (tag[8] << 7) | tag[9]
    body = tag[10:10 + size]
    if tag[5] & 0x40 and len(body) >= 4 and ver >= 3:          # extended header: skip it
        ext = struct.unpack_from('>I', body, 0)[0]
        body = body[(ext if ver == 3 else ((body[0] << 21) | (body[1] << 14) | (body[2] << 7) | body[3])) + (4 if ver == 3 else 0):]
    best, i = None, 0
    hlen = 6 if ver == 2 else 10
    while i + hlen <= len(body) and body[i] != 0:
        if ver == 2:
            fid, fsize = body[i:i + 3], int.from_bytes(body[i + 3:i + 6], 'big')
        else:
            fid = body[i:i + 4]
            raw = body[i + 4:i + 8]
            fsize = ((raw[0] << 21) | (raw[1] << 14) | (raw[2] << 7) | raw[3]) if ver == 4 else int.from_bytes(raw, 'big')
        frame = body[i + hlen:i + hlen + fsize]
        i += hlen + fsize
        if fid in (b'APIC', b'PIC') and frame:
            enc = frame[0]
            if fid == b'PIC':
                j, ptype = 4, frame[4]
            else:
                end = frame.find(b'\x00', 1)
                j = end + 1
                ptype = frame[j]
            j = skip_text(frame, j + 1, enc)
            if best is None or ptype == 3:
                best = frame[j:]
    return best


def wav_embedded(path):
    with open(path, 'rb') as f:
        head = f.read(12)
        if head[:4] != b'RIFF' or head[8:12] != b'WAVE':
            return None
        while True:
            h = f.read(8)
            if len(h) < 8:
                break
            cid, ln = h[:4], struct.unpack('<I', h[4:])[0]
            if cid.lower() == b'id3 ':
                data = id3_picture(f.read(ln))
                return to_image(data, 'wav id3') if data else None
            f.seek(ln + (ln & 1), 1)
    NOTES.append('wav: no "id3 " chunk with a picture')
    return None


def mp3_embedded(path):
    with open(path, 'rb') as f:
        h = f.read(10)
        if h[:3] != b'ID3':
            return None
        size = (h[6] << 21) | (h[7] << 14) | (h[8] << 7) | h[9]
        data = id3_picture(h + f.read(size))
    return to_image(data, 'mp3 id3') if data else None


def flac_embedded(path):
    with open(path, 'rb') as f:
        if f.read(4) != b'fLaC':
            return None
        best = None
        while True:
            h = f.read(4)
            if len(h) < 4:
                break
            last, btype, ln = h[0] & 0x80, h[0] & 0x7F, int.from_bytes(h[1:], 'big')
            body = f.read(ln)
            if btype == 6:
                try:
                    ptype, mlen = struct.unpack_from('>II', body, 0)
                    o = 8 + mlen
                    dlen = struct.unpack_from('>I', body, o)[0]
                    o += 4 + dlen + 16
                    size = struct.unpack_from('>I', body, o)[0]
                    if best is None or ptype == 3:
                        best = body[o + 4:o + 4 + size]
                except struct.error:
                    pass
            if last:
                break
    return to_image(best, 'flac') if best else None


def native_embedded(path):
    low = path.lower()
    try:
        if low.endswith('.wav'):
            return wav_embedded(path)
        if low.endswith('.mp3'):
            return mp3_embedded(path)
        if low.endswith('.flac'):
            return flac_embedded(path)
    except Exception as e:
        NOTES.append('reading the tags failed: %s' % e)
    return None


def ffmpeg_embedded(path):
    cmd = ['ffmpeg', '-v', 'error', '-i', path, '-an', '-map', '0:v:0', '-frames:v', '1',
           '-f', 'image2pipe', '-vcodec', 'png', '-']
    try:
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
    except OSError:
        NOTES.append('ffmpeg not found (only needed for m4a and unusual files now)')
        return None
    if not out:
        NOTES.append('ffmpeg: the file has no picture')
    return Image.open(io.BytesIO(out)) if out else None


def find_cover(path):
    img = sidecar(path)
    if img is None and path.lower().endswith(('.ogg', '.opus')):
        img = ogg_embedded(path)
    if img is None:
        img = native_embedded(path)
    if img is None:
        img = ffmpeg_embedded(path)
    return img


# ------------------------------------------------------------------ conversion
def square(img, px):
    img = img.convert('RGB')
    s = min(img.size)
    l, t = (img.width - s) // 2, (img.height - s) // 2
    return img.crop((l, t, l + s, t + s)).resize((px, px), Image.LANCZOS)


def make_palette(img):
    q = square(img, 48).quantize(colors=NCOL, method=Image.MEDIANCUT)
    flat = q.getpalette()[:NCOL * 3]
    pal = [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]
    while len(pal) < NCOL:
        pal.append(pal[-1] if pal else (0, 0, 0))
    return pal


def dither(img, pal):
    """Floyd-Steinberg to the 9 colors -> rows of palette indices"""
    w, h = img.size
    px = [[list(map(float, img.getpixel((x, y)))) for x in range(w)] for y in range(h)]
    out = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            old = px[y][x]
            k = min(range(len(pal)), key=lambda i: sum((old[c] - pal[i][c]) ** 2 for c in range(3)))
            out[y][x] = k
            err = [old[c] - pal[k][c] for c in range(3)]
            for dx, dy, f in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    for c in range(3):
                        px[ny][nx][c] += err[c] * f
    return out


def cover_accent(img):
    """dominant tint of the whole picture -> (r, g, b), or None for a really gray picture.
    Every pixel votes for its hue with weight saturation*brightness, so a big pale-blue area
    beats a small vivid spot, and a faint cast over a white cover still counts."""
    BINS = 24
    wsum, ssum, vx, vy = [0.0] * BINS, [0.0] * BINS, [0.0] * BINS, [0.0] * BINS
    total = 0.0
    small = img.convert('RGB').resize((96, 96))
    px = list(small.get_flattened_data() if hasattr(small, 'get_flattened_data') else small.getdata())
    for r, g, b in px:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if v < 0.2 or s < 0.02:
            continue
        w = s * v
        k = int(h * BINS) % BINS
        wsum[k] += w
        ssum[k] += w * s
        vx[k] += w * math.cos(h * 2 * math.pi)
        vy[k] += w * math.sin(h * 2 * math.pi)
        total += w
    if total < len(px) * 0.006:                 # average chroma under 0.6 %: gray
        return None
    smooth = [wsum[(k - 1) % BINS] + wsum[k] + wsum[(k + 1) % BINS] for k in range(BINS)]
    peak = max(range(BINS), key=lambda k: smooth[k])
    ks = [(peak - 1) % BINS, peak, (peak + 1) % BINS]
    h = (math.atan2(sum(vy[k] for k in ks), sum(vx[k] for k in ks)) / (2 * math.pi)) % 1.0
    w = sum(wsum[k] for k in ks)
    s = sum(ssum[k] for k in ks) / w
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, max(s * 1.2 + 0.08, 0.45)), 0.9)
    return int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5)


def dist(pal, a, b):
    return sum((pal[a][c] - pal[b][c]) ** 2 for c in range(3))


def encode_cell(pal, pix):
    """pix = 6 palette indices in CC order: TL TR ML MR BL BR -> (char, fg index, bg index)"""
    colors = sorted(set(pix))
    if len(colors) == 1:
        return 128, colors[0], colors[0]
    best = None
    for i, a in enumerate(colors):
        for b in colors[i + 1:]:
            cost = sum(min(dist(pal, p, a), dist(pal, p, b)) for p in pix)
            if best is None or cost < best[0]:
                best = (cost, a, b)
    _, a, b = best
    bits = [1 if dist(pal, p, a) <= dist(pal, p, b) else 0 for p in pix]   # 1 = foreground (a)
    fg, bg = a, b
    if bits[5]:                      # the bottom-right pixel can only be background: swap roles
        fg, bg = bg, fg
        bits = [1 - v for v in bits]
    code = 128 + sum(bits[i] << i for i in range(5))
    return code, fg, bg


def encode_size(img, pal, cw, ch):
    idx = dither(square(img, 2 * cw if 2 * cw == 3 * ch else 3 * ch).resize((2 * cw, 3 * ch), Image.LANCZOS), pal)
    rows = []
    for cy in range(ch):
        text, fg, bg = bytearray(), bytearray(), bytearray()
        for cx in range(cw):
            x, y = cx * 2, cy * 3
            pix = [idx[y][x], idx[y][x + 1], idx[y + 1][x], idx[y + 1][x + 1], idx[y + 2][x], idx[y + 2][x + 1]]
            code, f, b = encode_cell(pal, pix)
            text.append(code)
            fg.append(f)
            bg.append(b)
        rows.append(bytes(text) + bytes(fg) + bytes(bg))
    return bytes([cw, ch]) + b''.join(rows)


def make(path, force):
    out = os.path.splitext(path)[0] + '.cov'
    if not force and os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(path):
        print('skip   ', out)
        return
    NOTES.clear()
    img = find_cover(path)
    if img is None:
        print('no cover', path)
        for n in NOTES:
            print('         -', n)
        return
    pal = make_palette(img)
    data = b'COV1' + bytes([NCOL]) + b''.join(bytes(c) for c in pal) + bytes([len(SIZES)])
    for cw, ch in SIZES:
        data += encode_size(img, pal, cw, ch)
    acc = cover_accent(img)                       # flag 1 + rgb = accent, flag 0 = gray picture
    data += b'ACC1' + (bytes([1, *acc]) if acc else bytes([0, 0, 0, 0]))
    with open(out, 'wb') as f:
        f.write(data)
    print('wrote  ', out, '(%d bytes)' % len(data),
          'accent #%02X%02X%02X' % acc if acc else 'gray, no accent')


def safe_make(path, force):
    try:
        make(path, force)
    except Exception as e:                    # keep going with the other files
        print('ERROR  ', path, '-', e)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')] or ['.']
    force = '--force' in sys.argv
    for a in args:
        if not os.path.exists(a):
            print('NOT FOUND:', a, '  (put paths with spaces in "quotes")')
            continue
        if os.path.isdir(a):
            files = [os.path.join(root, n) for root, _, names in os.walk(a)
                     for n in sorted(names) if n.lower().endswith(AUDIO_EXT)]
        else:
            files = [a] if a.lower().endswith(AUDIO_EXT) else []
        print('scanning', os.path.abspath(a), '-', len(files), 'audio files')
        if not files:
            print('  no audio files found (%s)' % ', '.join(AUDIO_EXT))
        for f in files:
            safe_make(f, force)
    print('done')


if __name__ == '__main__':
    main()
