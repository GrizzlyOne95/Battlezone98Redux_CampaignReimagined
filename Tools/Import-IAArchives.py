#!/usr/bin/env python3
"""One-shot preservation intake for the IA backlog.

Downloads the original archives from Battlezone Map Room provenance, validates
every ZIP without executing its contents, and writes an immutable source
manifest. The live Map Room database is occasionally unavailable, so catalog
and file resolution can fall back to archived Map Room snapshots and the
BZScrap classic IA mirror. This helper is temporary CI plumbing for the
archive-import PR and is removed after the binary intake commit is created.
"""

from __future__ import annotations

import hashlib
import html
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

CATALOG_URLS = [
    "https://bzmaps.net/missions.php?type=instant_action",
    "https://www.bzmaps.net/missions.php?type=instant_action",
    "https://bzmaps.com/missions.php?type=instant_action",
    "https://www.bzmaps.com/missions.php?type=instant_action",
]

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

OUT_ROOT = Path("Preservation/InstantAction")
ARCHIVE_DIR = OUT_ROOT / "Archives"
MANIFEST_PATH = OUT_ROOT / "ARCHIVE_MANIFEST.json"
README_PATH = OUT_ROOT / "README.md"
USER_AGENT = "CampaignReimagined-IA-Preservation/1.1 (+https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined)"
WAYBACK_CDX = "https://web.archive.org/cdx/search/cdx"


def norm(value: str) -> str:
    value = html.unescape(value)
    value = re.sub(r"\s+", " ", value).strip()
    return value.casefold()


class AnchorParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.current_href: str | None = None
        self.current_text: list[str] = []
        self.anchors: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        href = dict(attrs).get("href")
        if href:
            self.current_href = href
            self.current_text = []

    def handle_data(self, data: str) -> None:
        if self.current_href is not None:
            self.current_text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a" and self.current_href is not None:
            self.anchors.append((self.current_href, "".join(self.current_text)))
            self.current_href = None
            self.current_text = []


def fetch(url: str, timeout: int = 90) -> tuple[bytes, str]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "*/*", "Accept-Encoding": "identity"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(), response.geturl()


def parse_anchors(body: bytes) -> list[tuple[str, str]]:
    parser = AnchorParser()
    parser.feed(body.decode("utf-8", errors="replace"))
    return parser.anchors


def wayback_snapshot(original_url: str) -> str | None:
    query = urllib.parse.urlencode(
        {
            "url": original_url,
            "output": "json",
            "fl": "timestamp,original,statuscode",
            "filter": "statuscode:200",
            "collapse": "digest",
            "limit": "50",
        }
    )
    try:
        body, _ = fetch(f"{WAYBACK_CDX}?{query}", timeout=90)
        rows = json.loads(body.decode("utf-8"))
    except Exception as exc:
        print(f"Wayback CDX lookup failed for {original_url}: {exc}")
        return None
    if not isinstance(rows, list) or len(rows) < 2:
        return None
    records = [row for row in rows[1:] if len(row) >= 2 and str(row[2]) == "200"]
    if not records:
        return None
    timestamp, captured_url = records[-1][0], records[-1][1]
    return f"https://web.archive.org/web/{timestamp}id_/{captured_url}"


def load_catalog() -> tuple[str, list[tuple[str, str]], str]:
    errors: list[str] = []
    # Prefer current Map Room data. A transient database failure currently
    # returns HTTP 200 with a small error page, so require actual anchors.
    for url in CATALOG_URLS:
        try:
            body, final_url = fetch(url)
            anchors = parse_anchors(body)
            if anchors:
                print(f"Live catalog: {final_url} ({len(anchors)} links)")
                return url, anchors, final_url
            snippet = body[:160].decode("utf-8", errors="replace").replace("\n", " ")
            errors.append(f"{url}: no links parsed ({snippet!r})")
        except Exception as exc:
            errors.append(f"{url}: {exc}")

    # Preserve Map Room provenance even when its live database is down by using
    # a raw Wayback snapshot of the same catalog. id_ avoids replay URL rewriting.
    for url in CATALOG_URLS:
        snapshot = wayback_snapshot(url)
        if not snapshot:
            continue
        try:
            body, final_url = fetch(snapshot, timeout=120)
            anchors = parse_anchors(body)
            if anchors:
                print(f"Archived catalog: {final_url} ({len(anchors)} links)")
                return url, anchors, final_url
            errors.append(f"{snapshot}: no links parsed")
        except Exception as exc:
            errors.append(f"{snapshot}: {exc}")

    raise RuntimeError("Could not read a Map Room catalog:\n  " + "\n  ".join(errors))


def dearchive_href(href: str) -> str:
    match = re.search(r"/web/\d+(?:[a-z_]+)?/(https?://.+)$", href)
    return match.group(1) if match else href


def resolve_sources(catalog_original_url: str, anchors: list[tuple[str, str]]) -> dict[str, str]:
    wanted = {norm(filename): filename for _, filename in TARGETS}
    found: dict[str, str] = {}
    for raw_href, text in anchors:
        href = dearchive_href(html.unescape(raw_href))
        text_key = norm(text)
        href_path = urllib.parse.unquote(urllib.parse.urlparse(href).path)
        href_name = norm(Path(href_path).name)
        for key in wanted:
            if key in found:
                continue
            if text_key == key or href_name == key:
                found[key] = urllib.parse.urljoin(catalog_original_url, href)

    missing = [filename for _, filename in TARGETS if norm(filename) not in found]
    if missing:
        raise RuntimeError("Catalog did not expose download links for:\n  " + "\n  ".join(missing))
    return found


def validate_zip_bytes(body: bytes) -> tuple[bool, str, int]:
    try:
        with zipfile.ZipFile(io.BytesIO(body), "r") as archive:
            bad_member = archive.testzip()
            if bad_member is not None:
                return False, f"CRC failure in {bad_member!r}", 0
            return True, "", len(archive.infolist())
    except zipfile.BadZipFile as exc:
        return False, str(exc), 0


def bzscrap_candidates(filename: str) -> list[str]:
    quoted = urllib.parse.quote(filename, safe="")
    # The first path is the classic BZ1 IA folder supplied as the original
    # discovery source. The second spelling covers the newer directory frontend.
    return [
        f"https://bzscrap.org/downloads/Maps/Battlezone/Instant%20Action/{quoted}",
        f"https://www.bzscrap.org/downloads/Maps/Battlezone/Instant%20Action/{quoted}",
    ]


def obtain_archive(source: str, filename: str) -> tuple[bytes, str, str, int]:
    attempts: list[tuple[str, str]] = [("maproom-live", source)]

    archived_source = wayback_snapshot(source)
    if archived_source:
        attempts.append(("maproom-wayback", archived_source))

    for mirror in bzscrap_candidates(filename):
        attempts.append(("bzscrap", mirror))
        archived_mirror = wayback_snapshot(mirror)
        if archived_mirror:
            attempts.append(("bzscrap-wayback", archived_mirror))

    failures: list[str] = []
    seen: set[str] = set()
    for provenance, url in attempts:
        if url in seen:
            continue
        seen.add(url)
        try:
            body, final_url = fetch(url, timeout=240)
        except Exception as exc:
            failures.append(f"{provenance}: {url}: {exc}")
            continue
        valid, reason, members = validate_zip_bytes(body)
        if valid:
            return body, final_url, provenance, members
        failures.append(f"{provenance}: {final_url}: not a ZIP ({reason}); bytes={len(body)}")

    raise RuntimeError(f"Could not retrieve a valid {filename}:\n    " + "\n    ".join(failures))


def sha256_bytes(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def main() -> int:
    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    ARCHIVE_DIR.mkdir(parents=True)

    catalog_original, anchors, catalog_retrieved = load_catalog()
    sources = resolve_sources(catalog_original, anchors)
    manifest: list[dict[str, object]] = []

    for index, (mission, filename) in enumerate(TARGETS, start=1):
        source = sources[norm(filename)]
        print(f"[{index:02d}/{len(TARGETS)}] {filename}")
        body, final_url, provenance, members = obtain_archive(source, filename)
        path = ARCHIVE_DIR / filename
        path.write_bytes(body)
        manifest.append(
            {
                "mission": mission,
                "archive": filename,
                "catalog_source_url": source,
                "retrieved_url": final_url,
                "retrieval_provenance": provenance,
                "bytes": len(body),
                "sha256": sha256_bytes(body),
                "members": members,
            }
        )
        print(f"  ok: {provenance}; {len(body):,} bytes; {members} members")

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    README_PATH.write_text(
        "# Instant Action source archives\n\n"
        "This directory preserves the **original, unmodified source ZIPs** used by the "
        "Campaign Reimagined Instant Action porting backlog. They are reference/input "
        "material and are intentionally outside the shipping mission tree.\n\n"
        "- Primary provenance: Battlezone Map Room Instant Action catalog. When the live "
        "Map Room database was unavailable during intake, archived Map Room snapshots or "
        "the BZScrap classic IA mirror were used to recover the same named source archive.\n"
        "- `ARCHIVE_MANIFEST.json` records catalog URL, actual retrieval URL/provenance, "
        "byte size, SHA-256, and ZIP member count captured during intake.\n"
        "- Archive contents have only been ZIP/CRC validated; no contained executable or "
        "script has been run.\n"
        "- Original README/license/credit files inside each ZIP remain authoritative for "
        "authorship and redistribution terms. Inclusion here does **not** relicense third-party content.\n"
        "- Ports should copy/adapt files into a dedicated IA namespace only after provenance, "
        "dependencies, and compatibility have been reviewed.\n"
        f"- Catalog retrieval used: `{catalog_retrieved}`.\n",
        encoding="utf-8",
    )

    total = sum(int(entry["bytes"]) for entry in manifest)
    print(f"Validated {len(manifest)} archives; total bytes={total:,}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"IA archive intake failed: {exc}", file=sys.stderr)
        raise
