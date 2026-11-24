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
  python Tools/Assets/Build-EngineLoops.py --manifest Tools/Assets/engine_loops.json       --input-root <folder holding eng_in/ and eng_in2/> [--repo-out <dir>] [--listen-out <dir>]
  (or ad hoc: --take crcmuf0=<take.wav> ...)
A manifest value is a path, or {"src": path, "pitch": playback-speed factor, "lowpass": Hz} to
derive a loop from an existing sound (the hvturr loops use stock avsave0/avsave6.wav extracted
from bzone.zfs into <input-root>/stock/; pitch relabels the sample rate before the 11025 Hz resample).
--repo-out defaults to this repository's Assets/Sounds, wherever it is run from.
Inputs longer than 2.5 s are first cut to their steadiest 2 s window (smallest
range of the 20 ms RMS envelope).
"""
import argparse
import json
import sys
import wave
from fractions import Fraction
from pathlib import Path

import numpy as np
from scipy.signal import butter, resample_poly, sosfiltfilt

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


def centroid(x, sr=RATE):
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    return float((f * spec).sum() / spec.sum())


def steadiest_window(x, sr, win_s=2.0, hop_s=0.1, frame_s=0.02):
    """Start index of the win_s window whose 20 ms RMS envelope has the least range."""
    fr = int(sr * frame_s)
    nfr = len(x) // fr
    env = 20 * np.log10(np.sqrt(np.mean(x[:nfr * fr].reshape(nfr, fr) ** 2, axis=1)) + 1e-9)
    w = int(win_s / frame_s)
    best, best_i = None, 0
    for s in range(0, int(round((len(x) / sr - win_s) / hop_s)) + 1):
        f0 = int(round(s * hop_s / frame_s))
        seg = env[f0:f0 + w]
        if len(seg) < w:
            break
        r = seg.max() - seg.min()
        if best is None or r < best:
            best, best_i = r, int(s * hop_s * sr)
    return best_i, int(win_s * sr), best


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
    ap.add_argument("--take", action="append", default=[], metavar="NAME=PATH")
    ap.add_argument("--manifest", help="JSON {name: path relative to --input-root}")
    ap.add_argument("--input-root", default=".")
    ap.add_argument("--repo-out", default=None)
    ap.add_argument("--listen-out")
    ap.add_argument("--listen-only", nargs="*", default=[],
                    help="takes written only to --listen-out, not to the repo")
    a = ap.parse_args()
    if a.repo_out is None:
        a.repo_out = str(Path(__file__).resolve().parents[2] / "Assets" / "Sounds")
    ok = True
    specs = list(a.take)
    derive = {}
    if a.manifest:
        for name, rel in json.load(open(a.manifest)).items():
            if isinstance(rel, dict):
                derive[name] = rel
                rel = rel["src"]
            specs.append(f"{name}={Path(a.input_root) / rel}")
    if not specs:
        ap.error("no takes")
    for spec in specs:
        name, _, path = spec.partition("=")
        x48, sr = read_wav(path)
        note = ""
        d = derive.get(name, {})
        if d.get("pitch"):
            sr = int(round(sr * d["pitch"]))
        if d.get("lowpass"):
            x48 = sosfiltfilt(butter(4, d["lowpass"], "low", fs=sr, output="sos"), x48)
        if len(x48) > 2.5 * sr:
            s0, n, rng = steadiest_window(x48, sr)
            x48 = x48[s0:s0 + n]
            note = f" [cut {s0/sr:.1f}-{(s0+n)/sr:.1f}s, env range {rng:.1f} dB]"
        r0, p0 = stats(x48)
        y48m = resample_poly(x48, RATE, sr) if sr != RATE else x48
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
        print(f"{name}{note}: in {len(x48)/sr:.2f}s {sr} Hz  RMS {db(r0):.1f} dB peak {db(p0):.1f} dB"
              f"  ->  out {len(q)/RATE:.3f}s {RATE} Hz u8  RMS {db(r1):.1f} dB peak {db(p1):.1f} dB"
              f"  seam {s:.4f}  centroid {centroid(y48m):.0f}->{centroid(q):.0f} Hz")
        if s > SEAM_MAX or p1 > 10 ** (PEAK_CEIL_DB / 20) + 1e-6:
            print(f"  FAIL: seam {s:.4f} or peak {db(p1):.2f} dB out of range")
            ok = False
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
