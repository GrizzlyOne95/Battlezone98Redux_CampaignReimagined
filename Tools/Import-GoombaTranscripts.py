#!/usr/bin/env python3
"""Generate CR subtitle text files from GoombaBZ's manual transcript corpus.

The source CSV is preserved verbatim. Generated game text is normalized only for
CR's current ASCII-only bitmap subtitle font.
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = REPO_ROOT / "Tools" / "TranscriptSources" / "GoombaBZ" / "campaigns.csv"
DEFAULT_TEXT_DIR = REPO_ROOT / "Text"

EXPECTED_COLUMNS = {
    "filename",
    "relative_path",
    "duration_sec",
    "transcript",
    "notes",
    "character",
}
SUBTITLE_STEM_RE = re.compile(
    r"^(?:misn\d+|misns\d+|minss\d+|tran\d+|bd\d+|ch\d+|intro\d+)$",
    re.IGNORECASE,
)
CYRILLIC_GLOSS_RE = re.compile(
    r"([\u0400-\u04FF][\u0400-\u04FF\s,.'-]*)\{\{([^{}]+)\}\}"
)
ANNOTATION_RE = re.compile(r"\{\{([^{}]+)\}\}")

ASCII_PUNCTUATION = str.maketrans(
    {
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2026": "...",
        "\u2013": "-",
        "\u2014": "-",
        "\u00a0": " ",
    }
)

CYRILLIC_TRANSLITERATION = {
    "А": "A", "а": "a", "Б": "B", "б": "b", "В": "V", "в": "v",
    "Г": "G", "г": "g", "Д": "D", "д": "d", "Е": "E", "е": "e",
    "Ё": "Yo", "ё": "yo", "Ж": "Zh", "ж": "zh", "З": "Z", "з": "z",
    "И": "I", "и": "i", "Й": "Y", "й": "y", "К": "K", "к": "k",
    "Л": "L", "л": "l", "М": "M", "м": "m", "Н": "N", "н": "n",
    "О": "O", "о": "o", "П": "P", "п": "p", "Р": "R", "р": "r",
    "С": "S", "с": "s", "Т": "T", "т": "t", "У": "U", "у": "u",
    "Ф": "F", "ф": "f", "Х": "Kh", "х": "kh", "Ц": "Ts", "ц": "ts",
    "Ч": "Ch", "ч": "ch", "Ш": "Sh", "ш": "sh", "Щ": "Shch", "щ": "shch",
    "Ъ": '"', "ъ": '"', "Ы": "Y", "ы": "y", "Ь": "'", "ь": "'",
    "Э": "E", "э": "e", "Ю": "Yu", "ю": "yu", "Я": "Ya", "я": "ya",
}


def _transliterate_cyrillic(text: str) -> str:
    return "".join(CYRILLIC_TRANSLITERATION.get(ch, ch) for ch in text)


def normalize_for_cr_overlay(text: str) -> str:
    """Convert source transcript text into CR's currently renderable subset."""
    value = text.translate(ASCII_PUNCTUATION)
    value = CYRILLIC_GLOSS_RE.sub(lambda m: m.group(2).strip(), value)
    value = ANNOTATION_RE.sub(lambda m: f" ({m.group(1).strip()})", value)
    value = _transliterate_cyrillic(value).strip()

    unsupported = sorted({ch for ch in value if ord(ch) < 32 or ord(ch) > 126})
    if unsupported:
        formatted = ", ".join(f"U+{ord(ch):04X} {ch!r}" for ch in unsupported)
        raise ValueError(f"generated subtitle still contains unsupported characters: {formatted}")
    return value


def load_campaign_rows(source: Path) -> list[dict[str, str]]:
    with source.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        columns = set(reader.fieldnames or [])
        if columns != EXPECTED_COLUMNS:
            raise ValueError(
                f"unexpected CSV columns: {sorted(columns)}; expected {sorted(EXPECTED_COLUMNS)}"
            )
        rows = list(reader)

    seen: dict[str, int] = {}
    for line_number, row in enumerate(rows, start=2):
        filename = (row.get("filename") or "").strip()
        transcript = row.get("transcript") or ""
        duration = (row.get("duration_sec") or "").strip()

        if not re.fullmatch(r"[A-Za-z0-9_]+\.wav", filename):
            raise ValueError(f"line {line_number}: invalid WAV filename {filename!r}")
        stem = Path(filename).stem.lower()
        if not SUBTITLE_STEM_RE.fullmatch(stem):
            raise ValueError(f"line {line_number}: unexpected campaign subtitle stem {stem!r}")
        if stem in seen:
            raise ValueError(
                f"line {line_number}: duplicate subtitle stem {stem!r}; first seen on line {seen[stem]}"
            )
        seen[stem] = line_number
        if not transcript.strip():
            raise ValueError(f"line {line_number}: empty transcript for {filename}")
        try:
            parsed_duration = float(duration)
        except ValueError as exc:
            raise ValueError(f"line {line_number}: invalid duration {duration!r}") from exc
        if parsed_duration <= 0:
            raise ValueError(f"line {line_number}: non-positive duration {duration!r}")

    return rows


def expected_outputs(rows: list[dict[str, str]]) -> dict[str, str]:
    return {
        f"{Path(row['filename']).stem.lower()}.txt": normalize_for_cr_overlay(row["transcript"])
        for row in rows
    }


def existing_subtitle_files(text_dir: Path) -> set[str]:
    if not text_dir.is_dir():
        return set()
    return {
        path.name.lower()
        for path in text_dir.glob("*.txt")
        if SUBTITLE_STEM_RE.fullmatch(path.stem)
    }


def check_outputs(text_dir: Path, outputs: dict[str, str]) -> int:
    failures: list[str] = []
    expected_names = set(outputs)
    actual_names = existing_subtitle_files(text_dir)

    for missing in sorted(expected_names - actual_names):
        failures.append(f"missing: Text/{missing}")
    for extra in sorted(actual_names - expected_names):
        failures.append(f"unexpected subtitle file: Text/{extra}")

    for name, expected in sorted(outputs.items()):
        path = text_dir / name
        if not path.is_file():
            continue
        actual = path.read_text(encoding="utf-8-sig")
        if actual != expected:
            failures.append(f"out of date: Text/{name}")

    if failures:
        print("GoombaBZ transcript check failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        print("Run: python Tools/Import-GoombaTranscripts.py", file=sys.stderr)
        return 1

    print(f"GoombaBZ transcript check passed: {len(outputs)} campaign subtitles are current.")
    return 0


def write_outputs(text_dir: Path, outputs: dict[str, str]) -> int:
    text_dir.mkdir(parents=True, exist_ok=True)
    changed = 0
    for name, content in sorted(outputs.items()):
        path = text_dir / name
        previous = path.read_text(encoding="utf-8-sig") if path.is_file() else None
        if previous == content:
            continue
        path.write_text(content, encoding="utf-8", newline="")
        changed += 1

    print(
        f"Generated {len(outputs)} campaign subtitles from GoombaBZ source; "
        f"{changed} file(s) changed."
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--text-dir", type=Path, default=DEFAULT_TEXT_DIR)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify Text/*.txt matches the canonical CSV without writing files",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = load_campaign_rows(args.source)
    outputs = expected_outputs(rows)
    if args.check:
        return check_outputs(args.text_dir, outputs)
    return write_outputs(args.text_dir, outputs)


if __name__ == "__main__":
    raise SystemExit(main())
