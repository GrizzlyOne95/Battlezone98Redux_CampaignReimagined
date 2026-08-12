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

For the first in-game validation pass, all generated faces use the existing `iechunk1_BZBase_iechunks` material from `Assets/chunkMeshes/generic/iechunk1_port.material`. That material already references the shared `iechunks.dds`, `iechunks_n.dds`, `iechunks_s.dds`, and `iechunks_e.dds` texture set, so no new interior texture/material asset is required yet.

Pass `--material iechunk1_BZBase_iechunks` when generating the capped meshes. The material remains configurable so a dedicated burnt-metal interior can replace it later without changing the topology code.

Each boundary is planar-projected for triangulation and UV generation. `--uv-mode stretch` (default) maps each opening across the full `0..1` UV square, which works well for the shared IE-chunk texture. `--uv-mode fit` preserves projected aspect ratio and centers the island in `0..1`.

Cap triangles use flat face normals. Tangents are not authored; the current DX11 base path can derive a cotangent frame from derivatives when normal mapping is active.

## Requirements

- Python 3.9+
- An `OgreXMLConverter` that reads and writes the same mesh format as the stock
  chunk meshes, which are `MeshSerializer_v1.100` (Ogre 1.10)

The script uses only the Python standard library.

### Choosing the converter

The tool resolves a converter automatically, in this order:

1. `--converter`, if given (used verbatim, still preflighted)
2. `$OGRE_XML_CONVERTER`
3. `C:\Tools\OgreXMLConverter.exe`
4. `OgreXMLConverter` on `PATH`
5. `OgreXMLConverter.exe` vendored inside Blender exporter add-ons

Whichever candidate it picks, it first **round-trips one real input mesh** and
confirms the serializer banner survives, printing the winner:

```
Converter: ...\XML_1_10\OgreXMLConverter.exe
  verified: preserves [MeshSerializer_v1.100] (probe: agr11ror.mesh)
```

This matters more than it sounds. Several `OgreXMLConverter.exe` copies on a
typical authoring machine are byte-identical to a *newer* Ogre release, and the
name gives no hint which is which. A newer converter either writes a mesh version
Redux cannot load, or crashes outright on the XML→mesh direction — both silent
until the game fails to show a chunk. The preflight turns that into an
up-front error listing every candidate and why each was rejected.

`--skip-converter-check` bypasses the preflight and prints `UNVERIFIED`. Only
reach for it if the round-trip probe is wrong about your setup, not to make an
error message go away.

## Recommended first pass: audit only

```powershell
python Tools/Cap-ChunkMeshes.py `
  --input Assets/chunkMeshes `
  --audit-only `
  --report chunk_cap_report.csv
```

The CSV records triangle counts, welded topology, boundary components, closed/capped/skipped loops, non-manifold edges, added triangle counts, and skip/error notes.

## Generate capped meshes

```powershell
python Tools/Cap-ChunkMeshes.py `
  --input Assets/chunkMeshes `
  --output Assets/chunkMeshes_capped `
  --material iechunk1_BZBase_iechunks `
  --uv-mode stretch `
  --report chunk_cap_report.csv
```

The output directory mirrors the input tree. Originals are never overwritten by the normal directory workflow. If a mesh needs no changes, its original binary is copied byte-for-byte rather than round-tripped through XML.

`Assets/chunkMeshes_capped` is generated output and is gitignored. It is reproducible from the authored tree at any time, so delete it freely.

## Deployment

### The runtime folder name is fixed

Capped meshes **replace the stock meshes in place**: same filenames, same
subfolders, inside the mod's `chunkMeshes` directory. The `_capped` suffix exists
only in the source repo and never reaches the game.

That is not a stylistic choice. OpenShim registers `<mod>\chunkMeshes` as an Ogre
resource root (`kChunkPayloadModRelativeDirName` in `bzr_hooks.cpp`) and adds it
**recursively**, and Ogre indexes meshes by bare filename within a resource group.
A second copy of the tree anywhere under the mod directory would register ~1,500
duplicate resource names, so the caps must overwrite the stock paths rather than
sit beside them. `Get-DeployRelativePathFromSourcePath` throws if any mapped
runtime path lands on a `chunkMeshes_*` sibling. The same applies to the legacy
alternate root `Chunks`: do not create one alongside `chunkMeshes`.

### Which tree is deployed

`Manage-CampaignFiles.ps1` treats the capped tree as authoritative **whenever it exists**:

| Present | `-deploy` ships | `-sync` writes runtime meshes back to |
| --- | --- | --- |
| `Assets/chunkMeshes_capped` | the capped meshes | `Assets/chunkMeshes_capped` |
| authored tree only | the authored meshes | `Assets/chunkMeshes` |

Both trees map onto the same runtime `chunkMeshes` folder, so only one supplies
`.mesh` files; the other is skipped. Either way the companion
`.material`, `.skeleton`, `.geo` and `.dds` assets keep deploying from
`Assets/chunkMeshes`, because the capped tree contains meshes only.

Two consequences worth knowing:

- Routing `-sync` at the capped tree is deliberate. It keeps the authored meshes
  pristine as the cap tool's input, so a sync after in-game testing can never
  quietly fold generated caps back into the originals.
- Deleting `Assets/chunkMeshes_capped` is the supported way to get back to
  uncapped meshes. The next `-deploy` reverts the runtime.

Both scripts print which tree is active on every run:

```
Chunk meshes: Assets\chunkMeshes_capped (generated caps; regenerate with Tools/Cap-ChunkMeshes.py)
```

## Debugging individual pieces

```powershell
python Tools/Cap-ChunkMeshes.py `
  --input Assets/chunkMeshes/avtank/agr11ror.mesh `
  --output .tmp/agr11ror.capped.mesh `
  --material iechunk1_BZBase_iechunks `
  --keep-xml
```

`--keep-xml` writes the before/after XML into `_chunk_cap_xml` next to the output so the generated interior submesh can be inspected directly.

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
2. Run `--audit-only` over `Assets/chunkMeshes` and inspect the report for non-manifold/skipped outliers. Confirm the converter line reports `verified:`.
3. Generate `Assets/chunkMeshes_capped` with `--material iechunk1_BZBase_iechunks`.
4. Test representative vehicle and building destruction in-game using the existing IE-chunk appearance on the generated interior faces.
5. Replace the IE material later with a dedicated burnt-metal interior only if the visual test shows it is worthwhile.
