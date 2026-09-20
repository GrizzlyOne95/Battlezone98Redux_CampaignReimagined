#!/usr/bin/env python3
"""Validate Battlezone 98 Redux Campaign Reimagined repository invariants.

This validator intentionally focuses on engine/project constraints that can be
checked without a live Battlezone runtime. Runtime behavior remains covered by
GOG/Steam qualification before publishing.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_PARTS = {".git", "Local", "References", "_deps"}
STRICT_ENGINE_EXTENSIONS = {".odf", ".wav", ".trn", ".bzn"}
EXTERNAL_LUA_MODULES = {"bzfile", "exu"}
STOCK_API_DEFINITION_FILES = {"scripts/scriptutils.lua"}


def project_files():
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        try:
            relative = path.relative_to(ROOT)
        except ValueError:
            continue
        if any(part in EXCLUDED_PARTS for part in relative.parts):
            continue
        yield path, relative


def strip_lua_comments(text: str) -> str:
    # Remove long comments first, then line comments. This is deliberately
    # conservative: it is only used to detect forbidden language constructs.
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.DOTALL)
    return re.sub(r"--[^\r\n]*", "", text)


def check_case_collisions(files) -> list[str]:
    errors: list[str] = []
    seen: dict[str, Path] = {}
    for _path, relative in files:
        key = str(relative).replace("\\", "/").casefold()
        previous = seen.get(key)
        if previous is not None and previous != relative:
            errors.append(f"case-insensitive path collision: {previous} <-> {relative}")
        else:
            seen[key] = relative
    return errors


def check_engine_filenames(files) -> list[str]:
    errors: list[str] = []
    for _path, relative in files:
        suffix = relative.suffix.casefold()
        if suffix == ".odf" and len(relative.stem) > 8:
            errors.append(
                f"ODF filename exceeds the engine 8-character basename limit: {relative}"
            )
    return errors


def check_lua(files) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    lua_files = [(path, relative) for path, relative in files if relative.suffix.casefold() == ".lua"]
    local_module_names: set[str] = set()
    local_module_paths: set[str] = set()
    for _path, relative in lua_files:
        local_module_names.add(relative.stem.casefold())
        without_suffix = relative.with_suffix("")
        local_module_paths.add(".".join(without_suffix.parts).casefold())
        if without_suffix.parts and without_suffix.parts[0].casefold() == "scripts":
            local_module_paths.add(".".join(without_suffix.parts[1:]).casefold())

    asset_literal = re.compile(
        r"(?P<quote>['\"])(?P<value>[^'\"\r\n]+\.(?:odf|wav|trn|bzn))(?P=quote)",
        flags=re.IGNORECASE,
    )
    require_literal = re.compile(
        r"\brequire\s*\(?\s*['\"]([^'\"]+)['\"]",
        flags=re.IGNORECASE,
    )

    for path, relative in lua_files:
        text = path.read_text(encoding="utf-8", errors="replace")
        code = strip_lua_comments(text)
        relative_key = relative.as_posix().casefold()

        # scriptutils.lua is the stock/editor API declaration file. It must
        # document ObjectiveObjects() even though project gameplay code must not
        # call the engine-broken iterator.
        if relative_key not in STOCK_API_DEFINITION_FILES and re.search(r"\bObjectiveObjects\s*\(", code):
            errors.append(f"broken ObjectiveObjects() iterator used in {relative}")
        if re.search(r"\bgoto\b", code):
            errors.append(f"Lua 5.1-incompatible goto used in {relative}")
        if re.search(r"::[A-Za-z_][A-Za-z0-9_]*::", code):
            errors.append(f"Lua label syntax used in {relative}")

        for match in asset_literal.finditer(code):
            value = match.group("value").replace("\\", "/")
            leaf = value.rsplit("/", 1)[-1]
            stem, dot, ext = leaf.rpartition(".")
            if dot and f".{ext.casefold()}" in STRICT_ENGINE_EXTENSIONS and len(stem) > 8:
                errors.append(
                    f"Lua references engine file with basename >8 chars in {relative}: {value}"
                )

        for module in require_literal.findall(code):
            normalized = module.replace("/", ".").casefold()
            leaf = normalized.rsplit(".", 1)[-1]
            if normalized in EXTERNAL_LUA_MODULES or leaf in EXTERNAL_LUA_MODULES:
                continue
            if normalized in local_module_paths or leaf in local_module_names:
                continue
            # Battlezone and Workshop DLLs can provide modules that are not
            # repository files. Surface these for review without blocking CI.
            warnings.append(f"unresolved/external require in {relative}: {module}")

    return errors, sorted(set(warnings))


def _load_shipping_lock() -> tuple[list[dict], list[str]]:
    lock_path = ROOT / "Shipping" / "shipping.lock.json"
    if not lock_path.exists():
        return [], ["Shipping/shipping.lock.json is missing"]
    try:
        data = json.loads(lock_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        return [], [f"Shipping/shipping.lock.json is unreadable: {exc}"]
    entries = data.get("files")
    if not isinstance(entries, list):
        return [], ["Shipping/shipping.lock.json has no 'files' list"]
    return entries, []


def check_shipping_lock_resolves() -> list[str]:
    """Every row in the shipping lock must name a file that exists.

    The lock is the definition of what the campaign installs, and the deploy
    copies exactly what it lists. A row for a file the repository does not have
    is a broken install for anyone who clones fresh -- and worse, regenerating
    the lock on such a clone quietly *deletes* those rows, because -bless
    rebuilds membership by scanning disk.

    That is not hypothetical. Assets/chunkMeshes_capped was gitignored as
    "regenerated from Assets/chunkMeshes" long after the meshes it would have
    been regenerated from were deleted, so 1532 shipped files lived only in one
    developer's worktree. A -bless from a fresh clone dropped all 1532 rows and
    the loss had to be spotted by eye in a 21,000-line diff.
    """
    entries, errors = _load_shipping_lock()
    missing = []
    for entry in entries:
        source = entry.get("source")
        if not source:
            errors.append("shipping lock has a row with no 'source'")
            continue
        if not (ROOT / source.replace("\\", os.sep).replace("/", os.sep)).exists():
            missing.append(source)

    if missing:
        errors.append(
            f"shipping lock names {len(missing)} file(s) that do not exist; "
            f"a fresh clone cannot deploy them and -bless would silently drop "
            f"them. First few: {', '.join(missing[:5])}")
    return errors


def check_shipped_materials_ship_their_textures(files) -> list[str]:
    """A shipped material must not reference a repo texture the lock omits.

    A new file is excluded from the deploy until the lock names it. Ship a
    material that points at a texture which is in the repository but not in the
    lock and the deploy updates the material, copies no texture, and leaves the
    install referencing something that is not there -- strictly worse than the
    placeholder it replaced.

    That happened with the weather art: CR_reactive.material was updated to
    cr_dust.dds and friends, and the first deploy reported "0 added".

    Only textures that exist in this repository are checked. A material naming
    a stock engine texture such as smoke.png is fine and is not our business.
    """
    entries, errors = _load_shipping_lock()
    if errors:
        return []  # check_shipping_lock_resolves reports lock problems.

    shipped = {e.get("source", "").replace("\\", os.sep).replace("/", os.sep)
               for e in entries}
    by_name: dict[str, str] = {}
    for _path, relative in files:
        by_name.setdefault(relative.name.lower(), str(relative))

    pattern = re.compile(
        r"^\s*(?:set_texture_alias\s+\S+|texture)\s+(\S+)", re.MULTILINE)

    problems: list[str] = []
    for path, relative in files:
        if path.suffix.lower() != ".material":
            continue
        if str(relative).replace("/", os.sep) not in shipped:
            continue  # not a shipped material
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for texture in set(pattern.findall(text)):
            located = by_name.get(texture.lower())
            if located is None:
                continue  # stock engine texture, not ours
            if located.replace("/", os.sep) not in shipped:
                problems.append(
                    f"{relative} references {texture}, which exists at "
                    f"{located} but is not in the shipping lock")

    return sorted(set(problems))


def main() -> int:
    files = list(project_files())
    errors: list[str] = []
    errors.extend(check_case_collisions(files))
    errors.extend(check_engine_filenames(files))
    lua_errors, warnings = check_lua(files)
    errors.extend(lua_errors)
    errors.extend(check_shipping_lock_resolves())
    errors.extend(check_shipped_materials_ship_their_textures(files))

    print(f"Validated {len(files)} repository files.")
    if warnings:
        print("\nDependency notes (non-fatal; may be engine/Workshop modules):")
        for warning in warnings:
            print(f"  WARN: {warning}")

    if errors:
        print("\nCampaign repository validation FAILED:", file=sys.stderr)
        for error in errors:
            print(f"  ERROR: {error}", file=sys.stderr)
        return 1

    print("Campaign repository invariants passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
