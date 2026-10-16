assert(_VERSION=="Lua 5.1")
package.path="Scripts/?.lua;"..package.path
local R=require("CRFuryRoster")
local n=0
local function check(ok,why) assert(ok,why);n=n+1 end
for _,mission in ipairs({17,18}) do
    local state={}
    check(R.Select("boltmine2",state)=="boltmine2" and not state.crFuryIndex,"mine/objective assets never consume a roster slot")
    local fighters,heavies=0,0
    for i=1,12 do
        local old=i%2==0 and "hvsat" or "hvsav"
        local odf=R.Select(old,state)
        if odf=="crfraz" then fighters=fighters+1 else heavies=heavies+1;check(odf==old,"heavy slot preserves original Fury type") end
    end
    check(fighters==8 and heavies==4,"mission "..mission.." has two-thirds light fighters without extra craft")
    local loaded={crFuryIndex=state.crFuryIndex}
    check(R.Select("hvsav",loaded)==R.Select("hvsav",state),"saved counter resumes the same roster")
    -- Exercise the actual mission-local BuildObject adapter through its closure.
    -- NewState/Save are stock; no Update/engine mock can bypass the adapter.
    local built={}
    local env=setmetatable({require=require,BuildObject=function(odf,team,where) built[#built+1]={odf,team,where};return #built end},{__index=_G})
    local chunk=assert(loadfile("Scripts/misn"..mission..".lua"));setfenv(chunk,env);chunk()
    -- The adapter is captured by Spawn (17) or Update (18), not global engine state.
    local entry=env.Update
    local function upvalue(fn,wanted)
        for i=1,60 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==wanted then return value end end
    end
    local build=upvalue(entry,"BuildObject")
    if mission==17 then build=upvalue(upvalue(entry,"Spawn"),"BuildObject") end
    check(type(build)=="function","actual mission adapter is installed")
    build("hvsav",2,"counter");build("hvsat",2,"counter");build("hvsat",2,"counter")
    check(built[1][1]=="crfraz" and built[2][1]=="crfraz" and built[3][1]=="hvsat","actual port uses primary fighter roster")
    build("hvsav",1,"allied");build("hbtran00",2,"transport")
    check(built[4][1]=="hvsav" and built[5][1]=="hbtran00","human units and transport retain their ODFs")
    check(env.Save().crFuryIndex==3,"counter is part of actual mission persistence")
end
print("Fury roster: "..n.." checks passed")
