# misn14 native source archive

The unmodified files here come from `GrizzlyOne95/Battlezone_Source`, commit
`e7c410573ffedc9e118dd90f402af6d5585955cc`, directory `BZ1/from_bz2_dll_src`.
They are the native mission source, not a community reconstruction or an existing
Lua mission. Original line endings and all comments are retained.

| File | Original Git blob SHA |
| --- | --- |
| Misn14Mission.cpp | 77eeffab992d54a4c9a9d7825e1425d996a372db |
| Misn14Mission.h | 08451d92c69746e6a6ba01fec0ea4efc9c58d791 |

`Scripts/misn14.lua` ports active `Setup`, `AddObject`, and `Execute` behavior.
The unused state fields are retained. BZR Lua `Save`/`Load` replace the C++
array serialization and native `ConvertHandle` pass; the original implementation
remains available here. Disabled gameplay statements and mission comments also
remain inline in the Lua file so cut content can be found beside its trigger.

Run `python3 Tools/Test-Misn14SourceParity.py` to audit these exact source bytes,
state-field coverage, mission identifiers, and preservation of every Execute
comment. See `Docs/MISN14_SOURCE_PORT.md` for fidelity decisions and validation.
