# BlackDog05 native source

`BlackDog05Mission.cpp` is the complete, byte-for-byte source snapshot from:

https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/from_bz2_dll_src/BlackDog05Mission.cpp

Git blob: `4446a98596a903f1f7764a0a65ff909645913061`.

The Lua port is `Scripts/bd05.lua`. The archive retains every comment, both
`#if 0` blocks, unused variables and native Load/PostLoad/Save scaffolding.
Both cut blocks also appear in inert Lua long comments next to their original
logical locations. The seven-offensive-unit gate and 40-minute cockpit timer
remain disabled, as does the debug shortcut. The commented portal construction
line remains disabled; the portal comes from the original map.

Run `python Tools/Test-BlackDog05SourceParity.py` to verify the snapshot hash and
mission data against the Lua port.
