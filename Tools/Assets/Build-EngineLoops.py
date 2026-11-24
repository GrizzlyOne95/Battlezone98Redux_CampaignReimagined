#!/usr/bin/env python3
"""Build seamless engine-thrust loops in the stock 11025 Hz / 8-bit mono format.

The engine plays soundThrust as a continuous loop and scales its sample rate and
volume by throttle, so the file must be a flat, seamless loop (no rev baked in).

Per take: mono downmix -> resample to 11025 Hz -> equal-power crossfade of the
tail into the head (the loop shrinks by the fade length) -> cyclic rotation to
the lowest seam step -> look-ahead limiter (computed on a tiled copy so it wraps)
and gain search to the target RMS -> 8-bit unsigned PCM, like the other
Assets/Sounds files.

Usage:
  python Tools/Assets/Build-EngineLoops.py \
      --take cr_snd_sov_recy_e0=<takeA.wav> --take cr_snd_eng_b_e0=<takeB.wav> \
      [--repo-out Assets/Sounds] [--listen-out <dir>] [--listen-only NAME ...]
"""
import argparse
import sys
import wave
from fractions import Fraction
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly

RATE = 11025
FADE_MS = 40.0
TARGET_RMS_DB = -6.0
PEAK_CEIL_DB = -0.5
SEAM_MAX = 0.05
PREVIEW_REPEATS = 5


def db(x):
    return 20 * np.log10(max(x, 1e-12))


def stats(x):
    rms = float(np.sqrt(np.mean(x ** 2)))
    peak = float(np.max(np.abs(x)))
    return rms, peak


def seam(x):
    rms = float(np.sqrt(np.mean(x ** 2)))
    return abs(float(x[0] - x[-1])) / rms


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if sw == 2:
        a = np.frombuffer(raw, "<i2").astype(np.float64) / 32768
    elif sw == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3)
        a = ((b[:, 0].astype(np.int32) | b[:, 1].astype(np.int32) << 8 | b[:, 2].astype(np.int32) << 16) << 8 >> 8) / 8388608
    elif sw == 1:
        a = (np.frombuffer(raw, np.uint8).astype(np.float64) - 128) / 128
    else:
        raise SystemExit(f"unsupported sample width {sw}")
    return a.reshape(-1, ch).mean(axis=1), sr


def write_u8(path, x):
    q = np.clip(np.round(x * 127) + 128, 0, 255).astype(np.uint8)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(q.tobytes())
    return (q.astype(np.float64) - 128) / 127


def crossfade_loop(x, fade):
    """Blend the last `fade` samples into the first `fade`; drop the tail."""
    t = (np.arange(fade) + 0.5) / fade
    fin, fout = np.sin(t * np.pi / 2), np.cos(t * np.pi / 2)
    head = x[:fade] * fin + x[-fade:] * fout
    return np.concatenate([head, x[fade:-fade]])


def best_rotation(x):
    """Rotate so the wrap step (last -> first sample) is the smallest in the loop."""
    steps = np.abs(x - np.roll(x, 1))  # steps[k] = |x[k] - x[k-1]|
    k = int(np.argmin(steps))
    return np.roll(x, -k)


def limit(x, ceil, win=int(RATE * 0.004)):
    """Smooth look-ahead limiter that wraps around the loop."""
    n = len(x)
    t = np.concatenate([x, x, x])
    need = np.minimum(1.0, ceil / np.maximum(np.abs(t), 1e-9))
    # hold the minimum over +-win samples, then smooth with a Hann window
    from scipy.ndimage import minimum_filter1d
    held = minimum_filter1d(need, size=2 * win + 1, mode="nearest")
    h = np.hanning(2 * win + 1)
    g = np.convolve(held, h / h.sum(), mode="same")
    return (t * g)[n:2 * n]


def process(x48, sr):
    frac = Fraction(RATE, sr)
    x = resample_poly(x48, frac.numerator, frac.denominator)
    x = x - np.mean(x)  # drop DC
    x = crossfade_loop(x, int(RATE * FADE_MS / 1000))
    x = best_rotation(x)
    ceil = 10 ** (PEAK_CEIL_DB / 20) - 1 / 254  # headroom for 8-bit rounding
    target = 10 ** (TARGET_RMS_DB / 20)
    lo, hi = 0.01, 100.0
    for _ in range(40):  # gain search so the limited result hits the target RMS
        g = np.sqrt(lo * hi)
        y = limit(x * g, ceil)
        if np.sqrt(np.mean(y ** 2)) < target:
            lo = g
        else:
            hi = g
    return limit(x * np.sqrt(lo * hi), ceil)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--take", action="append", required=True, metavar="NAME=PATH")
    ap.add_argument("--repo-out", default="Assets/Sounds")
    ap.add_argument("--listen-out")
    ap.add_argument("--listen-only", nargs="*", default=[],
                    help="takes written only to --listen-out, not to the repo")
    a = ap.parse_args()
    ok = True
    for spec in a.take:
        name, _, path = spec.partition("=")
        x48, sr = read_wav(path)
        r0, p0 = stats(x48)
        y = process(x48, sr)
        out_dirs = []
        if name not in a.listen_only:
            out_dirs.append(Path(a.repo_out))
        if a.listen_out:
            out_dirs.append(Path(a.listen_out))
        q = None
        for d in out_dirs:
            d.mkdir(parents=True, exist_ok=True)
            q = write_u8(d / f"{name}.wav", y)
        q = q if q is not None else y
        if a.listen_out:
            write_u8(Path(a.listen_out) / f"{name}_preview10s.wav", np.tile(q, PREVIEW_REPEATS))
        r1, p1 = stats(q)
        s = seam(q)
        print(f"{name}: in {len(x48)/sr:.2f}s {sr} Hz  RMS {db(r0):.1f} dB peak {db(p0):.1f} dB"
              f"  ->  out {len(q)/RATE:.3f}s {RATE} Hz u8  RMS {db(r1):.1f} dB peak {db(p1):.1f} dB"
              f"  seam {s:.4f}")
        if s > SEAM_MAX or p1 > 10 ** (PEAK_CEIL_DB / 20) + 1e-6:
            print(f"  FAIL: seam {s:.4f} or peak {db(p1):.2f} dB out of range")
            ok = False
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
