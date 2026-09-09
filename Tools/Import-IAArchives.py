#!/usr/bin/env python3
"""One-shot preservation intake for the IA backlog.

Downloads the original archives from the live Battlezone Map Room catalog,
validates every ZIP without executing its contents, and writes an immutable
source manifest. This helper is temporary CI plumbing for the archive-import
PR and should be removed after the binary intake commit is created.
"""

from __future__ import annotations

import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

CATALOG_URLS = [
    "https://bzmaps.net/missions.php?type=instant_action",
    "https://www.bzmaps.net/missions.php?type=instant_action",
    "https://bzmaps.com/missions.php?type=instant_action",
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
USER_AGENT = "CampaignReimagined-IA-Preservation/1.0 (+https://github.com/GrizzlyOne95/Battlezone98Redux_CampaignReimagined)"


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
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(), response.geturl()


def load_catalog() -> tuple[str, list[tuple[str, str]]]:
    errors: list[str] = []
    for url in CATALOG_URLS:
        try:
            body, final_url = fetch(url)
            text = body.decode("utf-8", errors="replace")
            parser = AnchorParser()
            parser.feed(text)
            if parser.anchors:
                print(f"Catalog: {final_url} ({len(parser.anchors)} links)")
                return final_url, parser.anchors
            errors.append(f"{url}: no links parsed")
        except Exception as exc:  # network diagnostics are intentionally surfaced
            errors.append(f"{url}: {exc}")
    raise RuntimeError("Could not read a Map Room catalog:\n  " + "\n  ".join(errors))


def resolve_sources(catalog_url: str, anchors: list[tuple[str, str]]) -> dict[str, str]:
    wanted = {norm(filename): filename for _, filename in TARGETS}
    found: dict[str, str] = {}
    for href, text in anchors:
        text_key = norm(text)
        href_name = norm(Path(urllib.parse.unquote(urllib.parse.urlparse(href).path)).name)
        for key, filename in wanted.items():
            if key in found:
                continue
            if text_key == key or href_name == key:
                found[key] = urllib.parse.urljoin(catalog_url, href)

    missing = [filename for _, filename in TARGETS if norm(filename) not in found]
    if missing:
        raise RuntimeError("Catalog did not expose download links for:\n  " + "\n  ".join(missing))
    return found


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    ARCHIVE_DIR.mkdir(parents=True)

    catalog_url, anchors = load_catalog()
    sources = resolve_sources(catalog_url, anchors)
    manifest: list[dict[str, object]] = []

    for index, (mission, filename) in enumerate(TARGETS, start=1):
        source = sources[norm(filename)]
        print(f"[{index:02d}/{len(TARGETS)}] {filename}")
        body, final_url = fetch(source, timeout=180)
        path = ARCHIVE_DIR / filename
        path.write_bytes(body)

        try:
            with zipfile.ZipFile(path, "r") as archive:
                bad_member = archive.testzip()
                if bad_member is not None:
                    raise RuntimeError(f"CRC failure in {bad_member!r}")
                members = archive.infolist()
        except zipfile.BadZipFile as exc:
            raise RuntimeError(f"{filename} is not a valid ZIP: {exc}") from exc

        manifest.append(
            {
                "mission": mission,
                "archive": filename,
                "source_url": final_url,
                "bytes": len(body),
                "sha256": sha256(path),
                "members": len(members),
            }
        )

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    README_PATH.write_text(
        "# Instant Action source archives\n\n"
        "This directory preserves the **original, unmodified source ZIPs** used by the "
        "Campaign Reimagined Instant Action porting backlog. They are reference/input "
        "material and are intentionally outside the shipping mission tree.\n\n"
        "- Source catalog: Battlezone Map Room Instant Action catalog.\n"
        "- `ARCHIVE_MANIFEST.json` records the resolved source URL, byte size, SHA-256, "
        "and ZIP member count captured during intake.\n"
        "- Archive contents have only been ZIP/CRC validated; no contained executable or "
        "script has been run.\n"
        "- Original README/license/credit files inside each ZIP remain authoritative for "
        "authorship and redistribution terms. Inclusion here does **not** relicense third-party content.\n"
        "- Ports should copy/adapt files into a dedicated IA namespace only after provenance, "
        "dependencies, and compatibility have been reviewed.\n",
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
