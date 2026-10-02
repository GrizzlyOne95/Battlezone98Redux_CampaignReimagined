# misns7 native source archive

These unmodified files are from `GrizzlyOne95/Battlezone_Source`, commit
`e7c410573ffedc9e118dd90f402af6d5585955cc`, directory `BZ1/from_bz2_dll_src`.
They are the native DLL mission source, not community or Lua reconstructions.
Original CRLF bytes, comments, declarations, and native serialization are retained.

| File | Original Git blob SHA |
| --- | --- |
| Misns7Mission.cpp | 5d930f36abba9a078ed16b09690553c6b02faa82 |
| Misns7Mission.h | f5606b6c56a8bca4c07b6f30d9906b85e1b4af82 |

`Scripts/misns7.lua` ports Setup, AddObject, and Execute. All 210 native state
fields remain represented, including unused fields. Every disabled gameplay
statement and source comment remains inline near its original trigger. Lua
Save/Load replace the native binary arrays and ConvertHandle pass.

Run `lua5.1 Tools/Test-Misns7.lua` and
`python Tools/Test-Misns7SourceParity.py` from the repository root.
See `Docs/MISNS7_SOURCE_PORT.md` for fidelity decisions and runtime limits.
