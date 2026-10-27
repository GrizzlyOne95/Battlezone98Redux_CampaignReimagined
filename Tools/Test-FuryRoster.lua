assert(_VERSION=="Lua 5.1")
package.path="Scripts/?.lua;"..package.path
local R=require("CRFuryRoster")
local n=0
local function check(ok,why) assert(ok,why);n=n+1 end
-- Missions 17 and 18 spawn through CRMisn17/CRMisn18.Spawn; Test-Misn17Coop.lua and Test-Misn18Coop.lua cover them.
for _,mission in ipairs({18}) do
    local state={}
    check(R.Select("boltmine2",state)=="crfmine" and not state.crFuryIndex,"Fury mines use their own definition without consuming a craft slot")
    local fighters,heavies=0,0
    for i=1,12 do
        local old=i%2==0 and "hvsat" or "hvsav"
        local odf=R.Select(old,state)
        if odf=="crfraz" then fighters=fighters+1 else heavies=heavies+1;check(odf==old,"heavy slot preserves original Fury type") end
    end
    check(fighters==8 and heavies==4,"mission "..mission.." has two-thirds light fighters without extra craft")
    local loaded={crFuryIndex=state.crFuryIndex}
    check(R.Select("hvsav",loaded)==R.Select("hvsav",state),"saved counter resumes the same roster")
    -- The production closure is CRMisn18.Spawn (Test-Misn18Coop.lua drives it with four real peers and
    -- asserts the crfraz/hvsat cadence and the saved counter). This only proves it still goes through the roster.
    local runtime=assert(io.open("Scripts/CRMisn"..mission..".lua","rb")):read("*a")
    check(runtime:find("roster.Select(odf,M)",1,true)~=nil,"mission "..mission.." co-op spawner selects through the roster")
end
print("Fury roster: "..n.." checks passed")
