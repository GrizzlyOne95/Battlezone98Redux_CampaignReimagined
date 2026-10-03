# misns3 native source archive

These unmodified files were read from `GrizzlyOne95/Battlezone_Source`, branch
`main`, directory `BZ1/from_bz2_dll_src`. Git blob hashes pin the exact versions,
including original CRLF line endings. This is native DLL mission source.

| File | Original Git blob SHA |
| --- | --- |
| Misns3Mission.cpp | 2805325b14fcd9273f0bd03eb36f0be17b755527 |
| Misns3Mission.h | 394be44569d47ed3b5a4333d87ce6d18d912564a |

All source comments and unused declarations are preserved. This mission has no
commented-out gameplay statements; its block comments also remain inline in
`Scripts/misns3.lua`. The five discarded `IsAlive(bd1)` calls are preserved as
Lua comments beside their original location. Native class scaffolding, array
serialization, and handle conversion remain here for reference; LuaMission's
`Save`/`Load` replace them in the port.

See `Docs/MISNS3_SOURCE_PORT.md` for fidelity decisions and validation. Run
`python3 Tools/Test-Misns3SourceParity.py` to verify the original source hashes.
