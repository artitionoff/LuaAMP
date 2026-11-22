#!/usr/bin/env python3
"""makevis.py - make <track>.vis spectrum files for the Minecraft music player.

usage:  python makevis.py <folder or file> [more folders/files] [--force]

Needs numpy. WAV files are read directly; other formats need ffmpeg (in PATH) or
"pip install soundfile". Every .ogg/.wav/.mp3/.flac/.m4a/.opus gets a small
.vis file next to it (about 40 KB for a 4 minute track). Copy the .vis files into the
same folder as the tracks in the game (e.g. mem/music).
"""
import os
import struct
import subprocess
import sys

import numpy as np

BANDS, FPS, SR = 16, 20, 22050      # 16 bars, 10 frames/s, analysis at 22.05 kHz
FMIN, FMAX = 40.0, 10000.0
WIN = 2048                          # ~93 ms window
EXT = ('.ogg', '.wav', '.mp3', '.flac', '.m4a', '.opus')


def resample(x, rate):
    """mono float32 at `rate` -> SR"""
    if rate == SR:
        return x.astype(np.float32)
    k = max(1, int(rate // SR))
    if k > 1:                                   # cheap low-pass: average k samples
        n = len(x) // k * k
        x = x[:n].reshape(-1, k).mean(axis=1)
        rate = rate / k
    if rate != SR:
        t = np.arange(int(len(x) * SR / rate)) * (rate / SR)
        x = np.interp(t, np.arange(len(x)), x)
    return x.astype(np.float32)


def decode_wav(path):
    """PCM 8/16/24/32 bit and float WAV, any channel count, no ffmpeg needed"""
    d = open(path, 'rb').read()
    if d[:4] != b'RIFF' or d[8:12] != b'WAVE':
        raise ValueError('not a RIFF/WAVE file')
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(d):
        cid, ln = d[pos:pos + 4], struct.unpack_from('<I', d, pos + 4)[0]
        if cid == b'fmt ':
            fmt = d[pos + 8:pos + 8 + ln]
        elif cid == b'data':
            end = pos + 8 + ln
            data = d[pos + 8:] if (ln == 0 or end > len(d)) else d[pos + 8:end]
            break
        pos += 8 + ln + (ln & 1)
    if fmt is None or data is None:
        raise ValueError('no fmt/data chunk')
    tag, ch, rate, _, _, bits = struct.unpack_from('<HHIIHH', fmt)
    if tag == 0xFFFE and len(fmt) >= 26:        # WAVE_FORMAT_EXTENSIBLE
        tag = struct.unpack_from('<H', fmt, 24)[0]
    if tag == 1 and bits == 8:
        x = (np.frombuffer(data, np.uint8).astype(np.float32) - 128.0) / 128.0
    elif tag == 1 and bits == 16:
        x = np.frombuffer(data[:len(data) // 2 * 2], '<i2').astype(np.float32) / 32768.0
    elif tag == 1 and bits == 24:
        b = np.frombuffer(data[:len(data) // 3 * 3], np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        x = np.where(v >= 1 << 23, v - (1 << 24), v).astype(np.float32) / float(1 << 23)
    elif tag == 1 and bits == 32:
        x = np.frombuffer(data[:len(data) // 4 * 4], '<i4').astype(np.float32) / 2147483648.0
    elif tag == 3 and bits == 32:
        x = np.frombuffer(data[:len(data) // 4 * 4], '<f4').astype(np.float32)
    elif tag == 3 and bits == 64:
        x = np.frombuffer(data[:len(data) // 8 * 8], '<f8').astype(np.float32)
    else:
        raise ValueError('unsupported WAV format (tag %d, %d bit)' % (tag, bits))
    ch = max(1, ch)
    x = x[:len(x) // ch * ch].reshape(-1, ch).mean(axis=1)
    return resample(x, rate)


def decode_ffmpeg(path):
    cmd = ['ffmpeg', '-v', 'error', '-i', path, '-vn', '-f', 's16le', '-ac', '1', '-ar', str(SR), '-']
    raw = subprocess.run(cmd, stdout=subprocess.PIPE, check=True).stdout
    return np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768.0


def decode_soundfile(path):
    import soundfile as sf
    x, rate = sf.read(path, dtype='float32', always_2d=True)
    return resample(x.mean(axis=1), rate)


def decode(path):
    errors = []
    if path.lower().endswith('.wav'):
        try:
            return decode_wav(path)
        except Exception as e:
            errors.append('built-in WAV reader: %s' % e)
    try:
        return decode_ffmpeg(path)
    except FileNotFoundError:
        errors.append('ffmpeg is not installed / not in PATH')
    except Exception as e:
        errors.append('ffmpeg: %s' % e)
    try:
        return decode_soundfile(path)
    except ImportError:
        errors.append('soundfile is not installed (pip install soundfile)')
    except Exception as e:
        errors.append('soundfile: %s' % e)
    raise RuntimeError('; '.join(errors))


def analyse(x):
    """returns uint8 array (frames, BANDS)"""
    hop = SR // FPS
    x = np.concatenate([np.zeros(WIN // 2, np.float32), x, np.zeros(WIN, np.float32)])
    frames = max(1, (len(x) - WIN) // hop)
    freqs = np.fft.rfftfreq(WIN, 1.0 / SR)
    edges = np.geomspace(FMIN, FMAX, BANDS + 1)
    idx = []
    for b in range(BANDS):
        sel = np.where((freqs >= edges[b]) & (freqs < edges[b + 1]))[0]
        if len(sel) == 0:
            sel = np.array([int(np.argmin(np.abs(freqs - (edges[b] + edges[b + 1]) / 2)))])
        idx.append(sel)
    window = np.hanning(WIN).astype(np.float32)

    db = np.zeros((frames, BANDS), np.float32)
    for i in range(frames):
        seg = x[i * hop:i * hop + WIN] * window
        spec = np.abs(np.fft.rfft(seg)) / WIN
        for b in range(BANDS):
            db[i, b] = 20 * np.log10(np.sqrt(np.mean(spec[idx[b]] ** 2)) + 1e-9)

    bm = db.mean(axis=0)                    # flatten part of the long-term tilt (highs are quieter)
    db = db - 0.6 * (bm - bm.mean())
    top = np.percentile(db, 99.5)
    level = np.clip((db - (top - 48.0)) / 48.0, 0.0, 1.0)
    return (level * 255).astype(np.uint8)


def make(path, force):
    out = os.path.splitext(path)[0] + '.vis'
    if not force and os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(path):
        print('skip  ', out)
        return
    levels = analyse(decode(path))
    with open(out, 'wb') as f:
        f.write(b'VIS1' + bytes([BANDS, FPS]) + levels.tobytes())
    print('wrote ', out, '(%d frames)' % len(levels))


def safe_make(path, force):
    try:
        make(path, force)
    except Exception as e:                      # keep going with the other files
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
                     for n in sorted(names) if n.lower().endswith(EXT)]
        else:
            files = [a] if a.lower().endswith(EXT) else []
        print('scanning', os.path.abspath(a), '-', len(files), 'audio files')
        for f in files:
            safe_make(f, force)
    print('done')


if __name__ == '__main__':
    main()
