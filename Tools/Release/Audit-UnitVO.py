"""Audit unit voice-over (VO) slots in ODF/*.odf.

Reports, per ODF:
  MISSING  a *Msg slot names a wav that is in neither the game archives nor this repo
           (the slot plays nothing in game).
  DUP      two or more slots of one ODF play the same wav (VO gets repetitive).

With --unused it also lists, per voice prefix (e.g. "avwalkv"), the transcribed lines no
ODF uses, which are the candidates for fixing a MISSING or DUP slot.

Transcripts come from Tools/TranscriptSources/GoombaBZ/{units,campaigns}.csv. diedMsg is
skipped (Betty lines, intentionally shared). Wavs found in the game's *.zfs archives are
read with the Modding Toolbox (BZ_MODDING_TOOLBOX or ../Battlezone98_Modding_Toolbox).

Exit code 1 if any slot is MISSING.

  python Tools/Release/Audit-UnitVO.py [--game-dir DIR] [--unused] [--csv OUT.csv]
"""
import argparse
import collections
import csv
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
DEFAULT_GAME = Path(r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux")
DEFAULT_TOOLBOX = Path(os.environ.get("BZ_MODDING_TOOLBOX", REPO.parent / "Battlezone98_Modding_Toolbox"))
SLOT_RE = re.compile(r'\s*([A-Za-z0-9]+Msg)\s*=\s*"?([^"\s/;]+)')
SKIP_SLOTS = {"diedMsg"}


def load_transcripts():
    tr = {}
    for name in ("units.csv", "campaigns.csv"):
        path = REPO / "Tools/TranscriptSources/GoombaBZ" / name
        if path.exists():
            with open(path, encoding="utf-8") as h:
                for row in csv.DictReader(h):
                    tr[row["filename"].lower()] = row["transcript"].strip()
    return tr


def known_wavs(game_dir, toolbox):
    names = {p.name.lower() for p in REPO.rglob("*.wav")}
    zfs = sorted(Path(game_dir).glob("*.zfs")) if game_dir and Path(game_dir).is_dir() else []
    if not zfs:
        print(f"warning: no *.zfs in {game_dir}; MISSING only checks repo wavs", file=sys.stderr)
        return names
    sys.path.insert(0, str(toolbox))
    from battlezone.archives.zfs import ZFSArchive  # noqa: E402
    for path in zfs:
        for entry in ZFSArchive(path):
            names.add(entry.name.lower())
    return names


def read_slots():
    out = {}
    for path in sorted((REPO / "ODF").glob("*.odf")):
        slots = []
        for line in open(path, encoding="latin-1"):
            m = SLOT_RE.match(line)
            if m and m.group(1) not in SKIP_SLOTS:
                slots.append((m.group(1), m.group(2).lower()))
        if slots:
            out[path.stem.lower()] = slots
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game-dir", default=DEFAULT_GAME)
    ap.add_argument("--toolbox", default=DEFAULT_TOOLBOX)
    ap.add_argument("--unused", action="store_true", help="list unused transcribed lines per voice prefix")
    ap.add_argument("--csv", help="also write every slot as odf,slot,wav,transcript")
    args = ap.parse_args()

    tr = load_transcripts()
    wavs = known_wavs(args.game_dir, args.toolbox)
    odfs = read_slots()
    say = lambda w: tr.get(w, "?")  # noqa: E731

    missing = dups = 0
    for odf, slots in odfs.items():
        for slot, wav in slots:
            if wav not in wavs:
                missing += 1
                print(f"MISSING {odf:10} {slot:18} {wav}")
        by_wav = collections.defaultdict(list)
        for slot, wav in slots:
            by_wav[wav].append(slot)
        for wav, names in by_wav.items():
            if len(names) > 1:
                dups += 1
                print(f"DUP     {odf:10} {'+'.join(names):40} {wav} \"{say(wav)}\"")

    if args.unused:
        used = {w for slots in odfs.values() for _, w in slots}
        prefixes = {re.sub(r"v[0-9a-z]{1,2}\.wav$", "v", w) for w in used if re.search(r"v[0-9a-z]{1,2}\.wav$", w)}
        for prefix in sorted(prefixes):
            free = sorted(w for w in wavs if w.startswith(prefix) and w not in used
                          and re.fullmatch(re.escape(prefix) + r"[0-9a-z]{1,2}\.wav", w))
            if free:
                print(f"UNUSED  {prefix:10} " + "; ".join(f"{w[len(prefix):-4]}:{say(w)}" for w in free))

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as h:
            w = csv.writer(h)
            w.writerow(("odf", "slot", "wav", "transcript"))
            for odf, slots in odfs.items():
                w.writerows((odf, s, wav, say(wav)) for s, wav in slots)

    print(f"{len(odfs)} ODFs: {missing} missing, {dups} duplicate groups", file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
