-- Run from repository root: lua5.1 Tools/Test-Evolve.lua
-- Decision tests only; original map/assets and debriefs need in-game testing.
local clock, objects, nextHandle, player, calls, timerStart
local assertions=0
local function check(v,msg) assertions=assertions+1; assert(v,msg) end
local function reset()
    clock,objects,nextHandle,player,calls,timerStart=0,{},0,"player",{},0
    objects.player={alive=true,odf="asuser"}
    GetTime=function() return clock end
    GetPlayerHandle=function() return player end
    IsValid=function(h) return objects[h] and not objects[h].removed or false end
    IsAlive=function(h) return IsValid(h) and objects[h].alive end
    GetOdf=function(h) assert(IsValid(h)); return objects[h].odf end
    BuildObject=function(odf,team,path)
        nextHandle=nextHandle+1
        local h=nextHandle
        objects[h]={alive=true,odf=odf,team=team,path=path}
        calls[#calls+1]={"build",odf,team,path,h}
        return h
    end
    Attack=function(h,target)
        assert(IsValid(h) and IsValid(target))
        calls[#calls+1]={"attack",h,target}
    end
    RemoveObject=function(h) assert(IsValid(h)); objects[h].removed=true end
    AllObjects=function()
        local hs={}
        for h in pairs(objects) do if IsValid(h) then hs[#hs+1]=h end end
        local i=0
        return function() i=i+1; return hs[i] end
    end
    StartCockpitTimerUp=function(t) timerStart=clock-t end
    GetCockpitTimer=function() return math.floor(clock-timerStart) end
    for _,name in ipairs({"SetScrap","SetPilot","SetMaxScrap","ClearObjectives","AddObjective","SucceedMission"}) do
        local fn=name
        _G[fn]=function(...) calls[#calls+1]={fn,...} end
    end
    dofile("Scripts/evolve.lua")
    Start()
end
local function step(t) clock=t; Update(0.1) end
local function killwave()
    local s=Save()
    for i=1,s.numOfCurrentAttackers do objects[s.currentAttackers[i]].alive=false end
end
local function count(name)
    local n=0
    for _,c in ipairs(calls) do if c[1]==name then n=n+1 end end
    return n
end
reset(); step(0)
check(Save().numOfCurrentAttackers==3,"initial pilot count")
check(objects[Save().currentAttackers[1]].path=="pilot_1","original spawn label")
step(1); check(Save().round==0,"living wave must not advance")
step(1.01); check(count("build")==15,"12 pickups appear strictly after time 1")
objects[Save().currentAttackers[1]].alive=false
step(2); check(Save().score==1 and Save().round==0,"partial wave scores without advancing")
step(2.1); check(Save().score==1,"no repeated death score")
killwave(); step(3)
check(Save().round==1 and Save().score==3,"scored slots do not stall completed wave")
check(objects[Save().currentAttackers[1]].odf=="cssolda","soldier wave follows pilots")
killwave(); step(4); check(Save().round==2,"sniper wave")
killwave(); step(5); check(Save().round==3 and Save().stateTimer==1,"vehicle gate")
step(100); check(Save().stateTimer==1,"wait indefinitely for first handle change")
objects.tank={alive=true,odf="avtank"}; player="tank"
step(101); check(Save().invehicle and Save().stateTimer==1,"latch applied at native end of update")
step(102); check(Save().stateTimer==132,"vehicle delay starts following update")
step(132); check(Save().stateTimer==132,"strict timer comparison")
step(132.01); check(objects[Save().currentAttackers[1]].odf=="cvfigh","fighter round")
killwave(); step(133)
check(Save().round==4 and Save().itemTimer[13]==163,"cover unlocks at round 4")
step(143.01); step(163.01)
local cover=Save().item[13]
check(objects[cover].odf=="csuserb" and objects[cover].team==2,"cover attacker")
objects[cover].alive=false; step(164)
check(Save().score==13 and Save().itemTimer[13]==194,"cover death scores and queues respawn")
step(164.1); check(Save().score==13,"cover score once")
local state=Save(); dofile("Scripts/evolve.lua"); Load(state)
check(Save().itemUnlocked[13] and Save().itemTimer[13]==194,"unlock/timer survive reload")
-- Finish every vehicle round and repeat until reaching the native cap.
for loop=1,20 do
    while Save().round~=8 do
        if Save().stateTimer~=0 then step(Save().stateTimer+0.01) end
        killwave(); step(clock+0.1)
    end
    if Save().stateTimer~=0 then step(Save().stateTimer+0.01) end
    killwave(); step(clock+0.1)
    check(Save().round==3,"repeat begins with fighters, no infantry")
    check(Save().maxroundattackers==math.min(loop+1,20),"escalation capped at 20 per spawn")
end
step(clock+0.1); step(Save().stateTimer+0.01)
check(Save().numOfCurrentAttackers==60,"three spawn points at cap")
-- Change target during active combat; previously dead handles must be skipped.
objects.newplayer={alive=true,odf="asuser"}; player="newplayer"
step(clock+0.1)
check(calls[#calls][1]~=nil,"retarget completes without invalid-handle command")
local scrap=BuildObject("npscr2",0,"scrap")
local other=BuildObject("npsca",0,"other")
step(clock+0.1)
check(not IsValid(scrap) and IsValid(other),"only native npscr prefix removed")
reset(); objects.player.alive=false; step(0)
check(Save().deadTimer==2,"early death arms two-second timer")
step(2); check(not Save().lost,"strict death timer")
step(2.01); check(Save().lost and count("SucceedMission")==1,"ends early death once")
step(5); check(count("SucceedMission")==1,"no repeated ending")
reset(); step(0); objects.player.alive=false; step(1)
objects.player.alive=true; step(2)
check(Save().deadTimer==0 and not Save().lost,"revival cancels grace timer")
Start(); check(not Save().itemUnlocked[13],"new game does not retain static unlock mutation")
print("evolve: "..assertions.." assertions passed")
