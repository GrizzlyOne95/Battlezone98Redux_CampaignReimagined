# Chunk Mesh Interior Caps

`Tools/Cap-ChunkMeshes.py` closes exposed geometric boundary loops in the standalone Ogre chunk meshes under `Assets/chunkMeshes`.

## Why

Many Battlezone 98 Redux destruction pieces were authored as partial surfaces because the missing sides are hidden while the vehicle/building is intact. Once a piece becomes free-flying debris, those openings expose the empty inside of the mesh. The cap tool adds simple interior surfaces so exploded chunks read as solid objects.

## Origin invariant

The existing chunk meshes were exported with each piece rebased to its corresponding bone/GEO pivot. The cap tool **never moves, recenters, scales, or otherwise rewrites existing vertex coordinates**. Generated interior vertices are added in the same local coordinate frame, so the established chunk pivot at `(0, 0, 0)` is preserved.

## What gets capped

The tool considers every clean geometric boundary loop across the whole mesh, not just boundaries near the origin. Topology detection welds coincident positions *for analysis only* so UV/material seams do not appear to be holes.

A candidate is skipped when it cannot be safely represented as a simple cap, including:

- non-manifold/open boundary components,
- degenerate or self-intersecting projected loops,
- failed triangulation,
- a coplanar-overlap case that looks like the outer perimeter of an existing flat sheet rather than a missing face.

`--allow-coplanar-overlap` disables the last safeguard when intentionally needed.

## Interior material and UVs

All generated faces are written into one new Ogre submesh using `CR_ChunkInterior` by default. Override it with `--material`.

Each boundary is planar-projected for triangulation and UV generation. `--uv-mode stretch` (default) maps each opening across the full `0..1` UV square, which is appropriate for a shared noisy/burnt-metal interior texture. `--uv-mode fit` preserves projected aspect ratio and centers the island in `0..1`.

Cap triangles use flat face normals. Tangents are not authored; the current DX11 base path can derive a cotangent frame from derivatives when normal mapping is active.

## Requirements

- Python 3.9+
- Ogre 1.10 `OgreXMLConverter` (pass its path with `--converter`, or put it on `PATH`)

The script uses only the Python standard library.

## Recommended first pass: audit only

```powershell
python Tools/Cap-ChunkMeshes.py `
  --input Assets/chunkMeshes `
  --converter "C:\Tools\OgreXMLConverter.exe" `
  --audit-only `
  --report chunk_cap_report.csv
```

The CSV records triangle counts, welded topology, boundary components, closed/capped/skipped loops, non-manifold edges, added triangle counts, and skip/error notes.

## Generate capped meshes

```powershell
python Tools/Cap-ChunkMeshes.py `
  --input Assets/chunkMeshes `
  --output Assets/chunkMeshes_capped `
  --converter "C:\Tools\OgreXMLConverter.exe" `
  --material CR_ChunkInterior `
  --uv-mode stretch `
  --report chunk_cap_report.csv
```

The output directory mirrors the input tree. Originals are never overwritten by the normal directory workflow. If a mesh needs no changes, its original binary is copied byte-for-byte rather than round-tripped through XML.

## Debugging individual pieces

```powershell
python Tools/Cap-ChunkMeshes.py `
  --input Assets/chunkMeshes/avtank/agr11ror.mesh `
  --output .tmp/agr11ror.capped.mesh `
  --converter "C:\Tools\OgreXMLConverter.exe" `
  --keep-xml
```

`--keep-xml` writes the before/after XML into `_chunk_cap_xml` next to the output so the generated `CR_ChunkInterior` submesh can be inspected directly.

## Built-in regression checks

The topology core can be validated without Ogre or game assets:

```powershell
python Tools/Cap-ChunkMeshes.py --self-test
```

The self-test verifies:

1. an open cube receives one two-triangle cap,
2. a plain flat sheet is rejected by the coplanar-overlap guard,
3. a tube with two open ends receives two caps.

## Suggested validation order

1. Run `--self-test`.
2. Run `--audit-only` over `Assets/chunkMeshes` and inspect the report for non-manifold/skipped outliers.
3. Generate `Assets/chunkMeshes_capped`.
4. Add/verify the shared `CR_ChunkInterior` material and burnt-metal texture.
5. Test representative vehicle and building destruction in-game before replacing the shipped chunk tree.
