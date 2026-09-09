#!/usr/bin/env python3
"""One-shot source-archive intake for the IA preservation backlog.

The live Battlezone Map Room database is temporarily returning an application
error, so this importer does not depend on it for binary retrieval.  Mission
names/filenames are the already-reviewed backlog input.  Retrieval prefers the
BZScrap classic Instant Action index supplied by the maintainer, then probes
known legacy static mirrors.  Every recovered file must be a CRC-clean ZIP.
Nothing is committed unless all 42 targets validate.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
from html.parser import HTMLParser
import io
import json
from pathlib import Path
import re
import shutil
import sys
import urllib.parse
import urllib.request
import zipfile

TARGETS = [
    ("The Forbidden Theories", "Chapter 1-2.zip"),
    ("Mars Peak", "Cyborggeffien - Mars Peak.zip"),
    ("Escaped by Scavenger", "Cyborggeffien - Escaped by Scavenger.zip"),
    ("Varia Fields - C Sector", "Cyborggeffien - Varia Fields - C Sector.zip"),
    ("Varia Fields - D Sector", "Cyborggeffien - Varia Fields - D Sector.zip"),
    ("Cold Winter", "cldwntr.zip"),
    ("I Want To Break Free", "i want to break free.zip"),
    ("Specimen 1001", "spec1001.zip"),
    ("CCA Scrap Operation", "cysilorc.zip"),
    ("Death Blow v2", "dethblow_1_5.zip"),
    ("Heat Sink v2", "heatsink_1_5.zip"),
    ("Final Destination", "final destination.zip"),
    ("Chasing the Devil", "chasing the devils.zip"),
    ("Downfall", "downfall.zip"),
    ("Solo Run", "solorun.zip"),
    ("High Command", "highcomm.zip"),
    ("Sector 86C", "sect86c.zip"),
    ("The Last Strike", "tlaststr.zip"),
    ("Europa Snipe", "Europa Snipe.zip"),
    ("Rabbit Hole", "Rabthole 1.1.zip"),
    ("A Call To Arms", "Call2arm.zip"),
    ("Sector 16A", "sect16a.zip"),
    ("Takeover", "takeover.zip"),
    ("Alien Alliance", "alinally.zip"),
    ("MAG King", "magking.zip"),
    ("Venus Badlands Skirmish", "Venus Badlands Skirmish.zip"),
    ("Ace Of Spades", "acespade.zip"),
    ("CCA Fun", "CCA Fun.zip"),
    ("The Io Incident", "The Io Incident.zip"),
    ("Blood and Iron", "bloodiro.zip"),
    ("Infiltration and Destruction", "Infiltration and Destruction.zip"),
    ("Canyon Of Blood", "Canyon of Blood.zip"),
    ("The Return of Eagle's Nest 1", "The Return of Eagle's Nest 1.zip"),
    ("Operation Mest", "opmest.zip"),
    ("Sweet Venegence", "Sweet Vengence.zip"),
    ("Capt. Chaos strikes again! - NSDF", "pacmania.zip"),
    ("Capt. Chaos strikes again! - CCA", "pacmani2.zip"),
    ("Failed Plans", "failplan.zip"),
    ("Fury Recycler", "usrmsnfr.zip"),
    ("Battle for the Alien Anomaly", "abcfrac.zip"),
    ("Absolute Zero", "AbsoZero.ZIP"),
    ("Supply Depot", "Sdepot.zip"),
]

BZSCRAP_INDEXES = [
    "https://bzscrap.org/index?parent=Maps%2FBattlezone%2FInstant%20Action",
    "https://bzscrap.org/downloads/Maps/Battlezone/Instant%20Action/",
]
MAPROOM_CATALOG = "https://bzmaps.net/missions.php?type=instant_action"
DUKEWORLD_ROOT = "https://dukeworld.duke4.net/planetquake/planetbattlezone/launchpad/"
OUT_ROOT = Path("Preservation/InstantAction")
ARCHIVE_DIR = OUT_ROOT / "Archives"
MANIFEST_PATH = OUT_ROOT / "ARCHIVE_MANIFEST.json"
README_PATH = OUT_ROOT / "README.md"
USER_AGENT = "CampaignReimagined-IA-Preservation/1.2 (+https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined)"


def key(value: str) -> str:
    return re.sub(r"\s+", " ", urllib.parse.unquote(value)).strip().casefold()


class AnchorParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.href: str | None = None
        self.text: list[str] = []
        self.items: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "a":
            href = dict(attrs).get("href")
            if href:
                self.href = href
                self.text = []

    def handle_data(self, data: str) -> None:
        if self.href is not None:
            self.text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self.href is not None:
            self.items.append((self.href, "".join(self.text).strip()))
            self.href = None
            self.text = []


def fetch(url: str, timeout: int = 25) -> tuple[bytes, str, str]:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "*/*", "Accept-Encoding": "identity"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read(), response.geturl(), response.headers.get("Content-Type", "")


def validate_zip(body: bytes) -> tuple[bool, str, int]:
    try:
        with zipfile.ZipFile(io.BytesIO(body), "r") as archive:
            bad = archive.testzip()
            if bad:
                return False, f"CRC failure: {bad}", 0
            return True, "", len(archive.infolist())
    except zipfile.BadZipFile as exc:
        return False, str(exc), 0


def discover_bzscrap_links() -> tuple[dict[str, str], list[str]]:
    wanted = {key(filename): filename for _, filename in TARGETS}
    found: dict[str, str] = {}
    diagnostics: list[str] = []

    for index_url in BZSCRAP_INDEXES:
        try:
            body, final_url, content_type = fetch(index_url, timeout=45)
        except Exception as exc:
            diagnostics.append(f"{index_url}: {type(exc).__name__}: {exc}")
            continue

        parser = AnchorParser()
        parser.feed(body.decode("utf-8", errors="replace"))
        diagnostics.append(
            f"{index_url}: {len(body)} bytes, {len(parser.items)} anchors, content-type={content_type!r}"
        )

        for href, label in parser.items:
            absolute = urllib.parse.urljoin(final_url, href)
            path_name = Path(urllib.parse.unquote(urllib.parse.urlparse(absolute).path)).name
            candidates = {key(label), key(path_name)}
            for archive_key in wanted:
                if archive_key in candidates and archive_key not in found:
                    found[archive_key] = absolute

    return found, diagnostics


def direct_candidates(filename: str, discovered: dict[str, str]) -> list[tuple[str, str]]:
    q = urllib.parse.quote(filename, safe="")
    q_plus = urllib.parse.quote_plus(filename)
    candidates: list[tuple[str, str]] = []

    discovered_url = discovered.get(key(filename))
    if discovered_url:
        candidates.append(("bzscrap-index", discovered_url))

    candidates.extend(
        [
            ("bzscrap-static", f"https://bzscrap.org/downloads/Maps/Battlezone/Instant%20Action/{q}"),
            ("bzscrap-static-www", f"https://www.bzscrap.org/downloads/Maps/Battlezone/Instant%20Action/{q}"),
            ("dukeworld-launchpad", f"{DUKEWORLD_ROOT}{q}"),
            # Map Room direct-file layouts seen in successive site generations.
            ("maproom-files", f"https://bzmaps.net/files/{q}"),
            ("maproom-downloads", f"https://bzmaps.net/downloads/{q}"),
            ("maproom-mission-files", f"https://bzmaps.net/files/missions/{q}"),
            ("maproom-download-file", f"https://bzmaps.net/download.php?file={q_plus}"),
            ("maproom-download-filename", f"https://bzmaps.net/download.php?filename={q_plus}"),
            ("maproom-getfile", f"https://bzmaps.net/getfile.php?file={q_plus}"),
        ]
    )

    # Keep order but avoid duplicate URLs.
    result: list[tuple[str, str]] = []
    seen: set[str] = set()
    for source, url in candidates:
        if url not in seen:
            seen.add(url)
            result.append((source, url))
    return result


def retrieve_one(mission: str, filename: str, discovered: dict[str, str]) -> tuple[dict[str, object] | None, list[str], bytes | None]:
    failures: list[str] = []
    for source, url in direct_candidates(filename, discovered):
        try:
            body, final_url, content_type = fetch(url)
        except Exception as exc:
            failures.append(f"{source}: {type(exc).__name__}: {exc}")
            continue

        valid, reason, members = validate_zip(body)
        if not valid:
            failures.append(
                f"{source}: not ZIP ({reason}); bytes={len(body)}; type={content_type!r}; final={final_url}"
            )
            continue

        entry: dict[str, object] = {
            "mission": mission,
            "archive": filename,
            "catalog_provenance": MAPROOM_CATALOG,
            "retrieved_url": final_url,
            "retrieval_source": source,
            "bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
            "members": members,
        }
        return entry, failures, body

    return None, failures, None


def main() -> int:
    discovered, discovery_diag = discover_bzscrap_links()
    print("BZScrap discovery:")
    for line in discovery_diag:
        print(f"  {line}")
    print(f"  matched {len(discovered)}/{len(TARGETS)} target filenames from index anchors")

    # Do all probes so one missing archive does not hide the state of the other 41.
    results: dict[str, tuple[dict[str, object] | None, list[str], bytes | None]] = {}
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {
            pool.submit(retrieve_one, mission, filename, discovered): (mission, filename)
            for mission, filename in TARGETS
        }
        for future in as_completed(futures):
            mission, filename = futures[future]
            try:
                result = future.result()
            except Exception as exc:
                result = (None, [f"internal: {type(exc).__name__}: {exc}"], None)
            results[filename] = result
            entry = result[0]
            if entry:
                print(
                    f"FOUND {filename}: {entry['retrieval_source']} | "
                    f"{int(entry['bytes']):,} bytes | {entry['members']} members"
                )
            else:
                print(f"MISS  {filename}")

    missing = [filename for _, filename in TARGETS if results[filename][0] is None]
    if missing:
        print("\nArchive retrieval incomplete; no preservation directory will be written.", file=sys.stderr)
        print(f"Recovered {len(TARGETS) - len(missing)}/{len(TARGETS)}; missing {len(missing)}:", file=sys.stderr)
        for filename in missing:
            print(f"\n--- {filename} ---", file=sys.stderr)
            for failure in results[filename][1]:
                print(f"  {failure}", file=sys.stderr)
        return 2

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    ARCHIVE_DIR.mkdir(parents=True)

    manifest: list[dict[str, object]] = []
    for mission, filename in TARGETS:
        entry, _, body = results[filename]
        assert entry is not None and body is not None
        (ARCHIVE_DIR / filename).write_bytes(body)
        manifest.append(entry)

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    README_PATH.write_text(
        "# Instant Action source archives\n\n"
        "This directory preserves the **original, unmodified ZIP archives** used as inputs "
        "for the Campaign Reimagined Instant Action preservation backlog. These files are "
        "reference/source material and are intentionally outside the shipping mission tree.\n\n"
        "- Mission identity/provenance was reconciled against the Battlezone Map Room and BZScrap.\n"
        "- `ARCHIVE_MANIFEST.json` records the actual retrieval source, byte size, SHA-256, "
        "and ZIP member count captured during intake.\n"
        "- Every archive passed ZIP structure and member CRC validation. No contained code was run.\n"
        "- Original README/license/credit files remain authoritative. Preservation here does not "
        "relicense third-party content.\n"
        "- Do not move files from these ZIPs into shipping content until provenance, dependencies, "
        "collisions, and Redux compatibility have been reviewed.\n",
        encoding="utf-8",
    )

    total = sum(int(entry["bytes"]) for entry in manifest)
    print(f"Validated all {len(manifest)} archives; total={total:,} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
