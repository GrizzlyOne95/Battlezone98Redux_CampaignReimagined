"""Build Assets/Sounds/cr_snd_lhit.wav from a source hit sound (replaces the stock lhit.wav impact).
Mono downmix, 22050 Hz, 16-bit, trailing silence trimmed with a 60 ms fade, RMS matched to stock
(about -13 dBFS) with a soft limiter keeping the peak at or below -0.5 dBFS.
python Tools/Assets/Build-CRLhitSound.py <source.wav> [--stock <stock lhit.wav>] [--copy-to <dir>]"""
import argparse
import math
import pathlib
import shutil
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "Assets" / "Sounds" / "cr_snd_lhit.wav"
RATE, TARGET_RMS_DB, PEAK_DB, FADE_S, SIL_DB = 22050, -13.0, -0.5, 0.060, -50.0


def read(path):
    with wave.open(str(path), "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        assert sw == 2, "16-bit only"
        a = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
    return a.reshape(-1, ch), sr


def db(x):
    return 20 * math.log10(max(x, 1e-9))


def stats(a, sr, label):
    m = a.mean(axis=1) if a.ndim > 1 else a
    print(f"{label}: {sr} Hz, {a.shape[1] if a.ndim > 1 else 1} ch, {len(m) / sr:.3f} s, "
          f"RMS {db(float(np.sqrt(np.mean(m ** 2)))):.1f} dBFS, peak {db(float(np.max(np.abs(m)))):.1f} dBFS")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--stock")
    ap.add_argument("--copy-to")
    ar = ap.parse_args()
    src, sr = read(ar.source)
    stats(src, sr, "source")
    if ar.stock:
        s, ssr = read(ar.stock)
        stats(s, ssr, "stock ")
    x = resample_poly(src.mean(axis=1), RATE, sr)
    thr = 10 ** (SIL_DB / 20) * np.max(np.abs(x))
    last = int(np.nonzero(np.abs(x) > thr)[0][-1])
    x = x[: min(len(x), last + 1 + int(FADE_S * RATE))]
    f = int(FADE_S * RATE)
    x[-f:] *= np.cos(np.linspace(0, math.pi / 2, f)) ** 2
    # gain to target RMS (over the audible part), then tanh soft-limit toward the peak ceiling
    rms = float(np.sqrt(np.mean(x ** 2)))
    x *= 10 ** (TARGET_RMS_DB / 20) / rms
    ceil = 10 ** (PEAK_DB / 20)
    knee = 0.5 * ceil
    over = np.abs(x) > knee
    x[over] = np.sign(x[over]) * (knee + (ceil - knee) * np.tanh((np.abs(x[over]) - knee) / (ceil - knee)))
    x = np.clip(x, -ceil, ceil)
    pcm = np.round(x * 32767).astype("<i2")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    out, osr = read(OUT)
    stats(out, osr, "output")
    if ar.copy_to:
        d = pathlib.Path(ar.copy_to)
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(OUT, d / OUT.name)


if __name__ == "__main__":
    main()
