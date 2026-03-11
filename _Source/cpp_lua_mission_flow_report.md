# C++ vs Lua Mission Flow Check

Generated: 2026-03-10 10:22:32

Sources:
- C++: C:\Users\istuart\Downloads\from_bz2_dll_src-20260310T151100Z-1-001\from_bz2_dll_src
- Lua: C:\Users\istuart\Documents\GIT\Battlezone98Redux_CampaignReimagined-1\_Source\Scripts

Exclusions:
- misn02b.lua (Tran05Mission.cpp port)
- misn03.lua / Misn03Mission.cpp
- misn04.lua / Misn04Mission.cpp

C++ mission scripts with no detected Lua counterpart in campaignReimagined:
- AISchedMission.cpp
- Inst01Mission.cpp
- Inst02Mission.cpp
- Inst03Mission.cpp
- Inst04Mission.cpp
- MPMission.cpp
- Misn02Mission.cpp
- Misn33Mission.cpp
- Mult01Mission.cpp
- Mult02Mission.cpp
- Mult03Mission.cpp
- Mult04Mission.cpp
- MultDMMission.cpp
- MultGMission.cpp
- MultSTMission.cpp
- Tran01Mission.cpp

Detected objective/audio differences (heuristic: compares first-seen order of AddObjective + .wav strings):

## Misn05Mission.cpp -> misn05.lua
- Extra objectives (in Lua only): hard_diff, easy_diff
- Objective order differs (unique order C++=3 vs Lua=5)
- Audio cue order differs (unique order C++=16 vs Lua=16)

## Misn06Mission.cpp -> misn06.lua
- Missing objectives (in C++ only): misn0607.otf
- Extra objectives (in Lua only): hard_diff, easy_diff
- Objective order differs (unique order C++=8 vs Lua=9)
- Missing audio cues (in C++ only): misn0643.wav, misn0644.wav, misn0645.wav, misn0646.wav, misn0648.wav
- Extra audio cues (in Lua only): misn0615.wav, misn0616.wav, misn0617.wav, misn0625.wav, misn0627.wav
- Audio cue order differs (unique order C++=39 vs Lua=39)

## Misn07Mission.cpp -> misn07.lua
- Extra objectives (in Lua only): hard_diff, easy_diff
- Objective order differs (unique order C++=4 vs Lua=6)
- Missing audio cues (in C++ only): win.wav, misn0705.wav, misn0706.wav
- Audio cue order differs (unique order C++=19 vs Lua=16)

## Misn08Mission.cpp -> misn08.lua
- Missing audio cues (in C++ only): misn0813.wav, misn0812.wav, misn0811.wav
- Audio cue order differs (unique order C++=25 vs Lua=22)

## Misn10Mission.cpp -> misn10.lua
- Audio cue order differs (unique order C++=6 vs Lua=6)

## Misn12Mission.cpp -> misn12.lua
- Missing audio cues (in C++ only): misn1214.wav, misn1230.wav
- Audio cue order differs (unique order C++=27 vs Lua=25)

## Misn14Mission.cpp -> misn14.lua
- Missing audio cues (in C++ only): misn1402.wav
- Audio cue order differs (unique order C++=20 vs Lua=19)

## Misn16Mission.cpp -> misn16.lua
- Missing audio cues (in C++ only): misn1614.wav
- Audio cue order differs (unique order C++=11 vs Lua=10)

## Misn17Mission.cpp -> misn17.lua
- Extra objectives (in Lua only): misn1701.otf, misn1702.otf
- Objective order differs (unique order C++=0 vs Lua=2)
- Audio cue order differs (unique order C++=4 vs Lua=4)

## Misn18Mission.cpp -> misn18.lua
- Audio cue order differs (unique order C++=15 vs Lua=15)

## Misns1Mission.cpp -> misns1.lua
- Extra objectives (in Lua only): misns101.otf, misns102.otf, misn103.otf
- Objective order differs (unique order C++=0 vs Lua=3)
- Missing audio cues (in C++ only): misns117.wav, misns116.wav, misns115.wav, misns113.wav, misns120.wav, misns121.wav
- Audio cue order differs (unique order C++=25 vs Lua=19)

## Misns2Mission.cpp -> misns2.lua
- Extra objectives (in Lua only): misns201.otf, misns202.otf, misns203.otf
- Objective order differs (unique order C++=0 vs Lua=3)

## Misns7Mission.cpp -> misns7.lua
- Missing objectives (in C++ only): misns703.otf, misns701.otf, misns702.otf, misns704.otf, misns705.otf, misns706.otf
- Objective order differs (unique order C++=8 vs Lua=2)
- Missing audio cues (in C++ only): misns724.wav, misns717.wav, misns725.wav, misns718.wav, misns708.wav, misns707.wav, misns721.wav, misns715.wav, misns720.wav, misns716.wav
- Audio cue order differs (unique order C++=23 vs Lua=13)

## Misns8Mission.cpp -> misns8.lua
- Missing audio cues (in C++ only): win.wav
- Audio cue order differs (unique order C++=16 vs Lua=15)

## Tran03Mission.cpp -> tran03.lua
- Missing audio cues (in C++ only): tran0311.wav
- Audio cue order differs (unique order C++=14 vs Lua=13)

## Tran04Mission.cpp -> tran04.lua
- Audio cue order differs (unique order C++=21 vs Lua=21)

No objective/audio diffs detected (heuristic only):
- DemoMission.cpp -> dmisn01.lua
- Misn01Mission.cpp -> misn01.lua
- Misn09Mission.cpp -> misn09.lua
- Misn11Mission.cpp -> misn11.lua
- Misn13Mission.cpp -> misn13.lua
- Misn15Mission.cpp -> misn15.lua
- Misns3Mission.cpp -> misns3.lua
- Misns4Mission.cpp -> misns4.lua
- Misns5Mission.cpp -> misns5.lua
- Misns6Mission.cpp -> misns6.lua
- Tran02Mission.cpp -> tran02.lua