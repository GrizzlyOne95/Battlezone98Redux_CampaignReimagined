# misns5 source archive

Authoritative input: [Battlezone_Source/BZ1/from_bz2_dll_src](https://github.com/GrizzlyOne95/Battlezone_Source/tree/main/BZ1/from_bz2_dll_src).

These are exact original UTF-8 blobs, including CRLF line endings, disabled code,
declarations, comments, and native save/load implementation:

| File | Git blob SHA |
| --- | --- |
| Misns5Mission.cpp | 27a86be1800531bf576a211acb4fdd356458260e |
| Misns5Mission.h | 314b3e0c57b6e561a4d512b3225fffb86b3b6d59 |

`Scripts/misns5.lua` preserves disabled gameplay code inline. The native
serialization is replaced by a LuaMission state table, retaining unused state.
Native target-following `Defend` is mapped to Lua `Defend2`, and strategic AI is
enabled during startup for the source's later `SetAIP` handoff.

Documented fixes capture the first commander walker and guard invalid command
and distance operands. Valid-map commands, strict timer boundaries, spawn order,
wave composition, outcome ordering, and ten-second result delays remain intact.
The camera remains audio-driven despite its unused 17-second timer. The APC
deadline remains relative to mission startup, and waves continue after wave 3.
The active recycler objective marker is retained despite the source's
`should be sam` comment; the intelligence camera pod still spawns.

Validation from the repository root:

```sh
lua5.1 Tools/Test-Misns5.lua
python Tools/Test-Misns5SourceParity.py
python Tools/Validate-CampaignRepository.py
```

Mock-host and provenance checks do not replace in-game validation. Map labels,
paths, audio/camera behavior, native AI production and actual savegame handle
restoration still require a BZR playthrough. This change adds the script under
`Scripts`; it does not alter mission map selection or bless a shipping lock.
