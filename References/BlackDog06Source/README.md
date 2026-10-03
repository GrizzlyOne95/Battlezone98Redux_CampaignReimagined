# BlackDog06 native source

`blackdog06mission.cpp` is a byte-for-byte snapshot of the source at:

https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/from_bz2_dll_src/blackdog06mission.cpp

Git blob: `4103fbfa8032b89fc3592c46f2366e4f0f115839`.

The upstream filename is lowercase. The snapshot preserves every comment,
disabled fragment, declaration and native Load/PostLoad/Save implementation.
The gameplay cut blocks also remain inert beside their corresponding states
in `Scripts/bd06.lua`. The optional cockpit timer, friendly damage check and
alternate `bd06008.wav` / `bd06005.wav` victory remain disabled.

Run `python Tools/Test-BlackDog06SourceParity.py` to check the archive hash,
source state numbers, mission assets, waves and disabled content.
