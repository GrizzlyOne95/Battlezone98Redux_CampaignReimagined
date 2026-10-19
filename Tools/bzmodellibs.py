"""Locate and import the shared Battlezone model-format libraries.

CR tools must not carry their own SDF/VDF/GEO/ANIM or Ogre readers and writers
(AGENTS.md, "Model tooling"). They import them from:

* Battlezone98_Modding_Toolbox: ``battlezone.meshes.legacy`` (read-only).
* BZ98RBlenderToolKit: ``bzrmodelporter`` (read and write). Its package root,
  ``bz98tools``, imports ``bpy``, so ``bz98tools/`` itself goes on ``sys.path``.

Search order for each library: the ``BZ_TOOLBOX_DIR`` / ``BZ_TOOLKIT_DIR``
environment variable, then a sibling checkout next to this repository (or next to
the canonical checkout, for ``Campaign-Reimagined-<topic>`` worktrees). CI sets
the variables to pinned checkouts (.github/workflows/campaign-validation.yml).

Usage::

    from bzmodellibs import legacy, bwd2, bwd2_serializer
    model = legacy.read_sdf(path)
"""

from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent

_TOOLBOX = ("BZ_TOOLBOX_DIR", "Battlezone98_Modding_Toolbox")
_TOOLKIT = ("BZ_TOOLKIT_DIR", "BZ98RBlenderToolKit")


class ModelLibsUnavailable(ImportError):
    """A shared model library could not be found."""


def _find(env_var: str, folder: str) -> Path | None:
    configured = os.environ.get(env_var)
    if configured:
        path = Path(configured)
        return path if path.is_dir() else None
    for parent in (_REPO.parent, _REPO.parent / "Campaign-Reimagined"):
        candidate = parent / folder
        if candidate.is_dir():
            return candidate
    return None


def _root(spec: tuple[str, str]) -> Path:
    path = _find(*spec)
    if path is None:
        raise ModelLibsUnavailable(
            f"{spec[1]} not found; set {spec[0]} or clone it next to this repository"
        )
    return path


def _import(module: str, path: Path):
    entry = str(path)
    if entry not in sys.path:
        sys.path.insert(0, entry)
    return importlib.import_module(module)


def toolbox_root() -> Path:
    return _root(_TOOLBOX)


def toolkit_root() -> Path:
    return _root(_TOOLKIT)


def __getattr__(name: str):
    if name == "legacy":
        return _import("battlezone.meshes.legacy", toolbox_root())
    if name == "legacy_port":
        return _import("battlezone.meshes.legacy_port", toolbox_root())
    porter = {
        "bwd2": "bzbwd2",
        "bwd2_serializer": "bzbwd2_serializer",
        "geo": "bzgeo",
        "geo_serializer": "bzgeo_serializer",
        "ogremesh": "ogremesh",
        "ogremesh_serializer": "ogremesh_serializer",
        "ogreskeleton": "ogreskeleton",
        "ogreskeleton_serializer": "ogreskeleton_serializer",
    }.get(name)
    if porter:
        return _import(f"bzrmodelporter.{porter}", toolkit_root() / "bz98tools")
    raise AttributeError(name)


def require_or_skip(test_name: str) -> bool:
    """Return True when the libraries load. Otherwise skip locally, or fail in CI.

    CI sets ``BZ_MODELLIBS_REQUIRED=1``, so a missing library is an error there
    and never a silently skipped check.
    """
    try:
        toolbox_root()
        toolkit_root()
        return True
    except ModelLibsUnavailable as error:
        if os.environ.get("BZ_MODELLIBS_REQUIRED") == "1":
            raise
        print(f"SKIP {test_name}: {error}")
        return False
