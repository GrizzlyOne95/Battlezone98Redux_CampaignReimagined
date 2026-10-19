-- Four independent Lua peers, real CRCoop registry, lossy presentation simulator.
-- Engine AI, rendering and combat remain mocked. Run from the repository root:
--   lua5.1 Tools/Test-Misn18Coop.lua
assert(_VERSION=="Lua 5.1")
local F=dofile("Tools/Misn18Fixture.lua")
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local THRUSTERS={"hbtrn20049_i76building","hbtrn20050_i76building","hbtrn20051_i76building","hbtrn20052_i76building"}
local RECYCLER="avrecy2_recycler"

local function setup(n,options)
    local w=F.reset();local p={}
    if options and options.holdOpening then w.audioBusy=true end
    for i=1,n do p[i]=F.makePeer(i,i,n>1,options) end
    F.connect();F.run(5)
    return w,p,p[1].env.Save()
end
local function furies()
    local list={}
    for h,o in pairs(F.world().objects) do
        if o.alive and o.team==6 and (o.odf=="hvsav" or o.odf=="hvsat" or o.odf=="crfraz") then list[#list+1]=h end
    end
    table.sort(list)
    return list
end
local function killFuries() for _,h in ipairs(furies()) do F.kill(h) end end
local function nearBase(p,dx)
    for i,q in ipairs(p) do F.nearTo(q.player,RECYCLER,(dx or 0)+8*i,0) end
end
local function builtAt(peer,mark)
    local out={}
    for _,b in ipairs(F.builds(peer,mark)) do out[#out+1]=b end
    return out
end
local function allSafe(p,builds)
    for _,b in ipairs(builds) do
        for _,q in ipairs(p) do check(q.env.GetDistance(q.player,b.h)>=460,"no visible spawn beside any human") end
    end
end
local function collapse(p)
    for _,name in ipairs(THRUSTERS) do F.kill(name);F.run(1) end
    F.run(9) -- the transport-destroyed shot (8 s) ends and the countdown starts
end
local function heardAll(p,file,count)
    for i,q in ipairs(p) do check(F.heardCount(q,file)==(count or 1),"peer "..i.." hears "..file.." x"..(count or 1)) end
end

-- ------------------------------------------------------------------ opening, ownership, scaling
local w,p,m=setup(4,{holdOpening=true})
check(m.missionstart and m.coopMissionStarted,"leader starts shared mission")
check(F.count(p[1],"SetScrap")==1 and F.last(p[1],"SetScrap")[3]==110,"four-player shared scrap: 80 + 10 per guest")
for i=1,4 do
    check(F.count(p[i],"DisableStartingRecycler")==1,"disable extra starting recyclers")
    check(F.heardCount(p[i],"misn1801.wav")==1,"briefing once per peer")
    check(F.count(p[i],"StartEarthquake")==1 and F.last(p[i],"StartEarthquake")[2]==2.0,"quake starts on every peer")
    check(F.count(p[i],"SetObjectiveOn")>=1,"transport marker reaches every peer")
    if i>1 then
        for _,name in ipairs({"BuildObject","SetScrap","SetAIP","Goto","Attack","SetIndependence","Damage","AddHealth"}) do
            check(F.count(p[i],name)==0,"guest never mutates gameplay: "..name)
        end
    end
end
-- The opening cinematic is not skipped: the leader films it and every guest follows the streamed shot.
check(p[1].camera==1 and F.last(p[1],"CameraPath")[2]=="opencam3","leader plays the opening cinematic")
for i=2,4 do
    check(p[i].camera==1 and F.last(p[i],"CameraPath")~=nil and F.last(p[i],"CameraPath")[2]=="opencam3","guest "..i.." follows the opening shot")
end
-- A guest, not the host, reaches a wave trigger while the opening plays: the Furies are held back.
F.nearTo(p[3].player,"spawn1a")
F.run(3)
check(m.wave1start and m.cr18.serial>=4,"guest approach queues the wave and its extras")
check(F.count(p[1],"BuildObject")==0,"arrivals are held during the opening")
w.audioBusy=false;F.run(4)
check(m.openingcindone,"opening ends with its narration")
for i=1,4 do check(p[i].camera==0,"opening cameras balanced on peer "..i) end
local builds=builtAt(p[1])
check(#builds==4,"two wave units + floor(4/2) extras, got "..#builds)
for _,b in ipairs(builds) do check(b.team==6,"Furies are team 6") end
allSafe(p,builds)
local toT1,toT2=0,0
for _,c in ipairs(F.callsOf(p[1],"Goto")) do
    if c[3]=="transport1" then toT1=toT1+1 elseif c[3]=="transport2" then toT2=toT2+1 end
end
check(toT1==3 and toT2==1,"extras mirror the first unit's route ("..toT1.."/"..toT2..")")
check(F.count(p[1],"SetIndependence")==4,"every Fury is set independent")
check(F.alive(m.w1u1) and F.alive(m.w1u3),"tickets replaced by the real units")
local fury,odfs=0,{}
for _,b in ipairs(builds) do odfs[#odfs+1]=b.odf;if b.odf=="crfraz" then fury=fury+1 end end
check(fury>0 and (m.crFuryIndex or 0)==4,"co-op Fury spawns use the restored fighter roster: "..table.concat(odfs,","))
check(w.timer==nil and m.spawn1==nil,"no stray timer before the collapse")

-- scaling by head count
for n,expect in ipairs({0,1,1,2}) do
    local w2,p2,m2=setup(n,{})
    F.nearTo(p2[n].player,"spawn1a");F.run(3)
    check(#F.builds(p2[1])==2+expect,n.." humans: "..(2+expect).." wave craft, got "..#F.builds(p2[1]))
end
-- the lone host in a network session and an offline game never get extras
do
    local w2,p2=setup(1,{})
    check(not p2[1].net,"offline peer")
    F.nearTo(p2[1].player,"spawn1a");F.run(3)
    check(#F.builds(p2[1])==2,"offline game keeps the original two units")
end

-- ------------------------------------------------------------------ discovery, thrusters, shared timer
w,p,m=setup(4,{})
F.nearTo(p[2].player,"transfound");F.run(2)
check(m.transportfound,"any player finds the transport")
heardAll(p,"misn1816.wav")
check(m.wave1start and m.wave2start and m.wave3start,"discovery releases all three route waves")
-- cap: three waves = 12 Furies; a timed raid after that adds its primary but no extras
F.run(20)
check(#furies()==12,"three waves with extras fill the live cap exactly: "..#furies())
do
    local fighters,heavies=0,0
    for _,h in ipairs(furies()) do if F.world().objects[h].odf=="crfraz" then fighters=fighters+1 else heavies=heavies+1 end end
    check(fighters==8 and heavies==4 and m.crFuryIndex==12,"two-thirds restored fighters across scaled waves: "..fighters.."/"..heavies)
end
local mark=#p[1].calls
F.run(145)
check(#builtAt(p[1],mark)==1 and #furies()==13,"timed raid at the cap adds only the primary Fury: "..#builtAt(p[1],mark))
killFuries()
-- recycler assault: found + 180 s
local assaultMark=#p[1].calls
F.run(40)
local assault=builtAt(p[1],assaultMark,nil)
local attack=0
for _,c in ipairs(F.callsOf(p[1],"Attack")) do if c[3]==RECYCLER then attack=attack+1 end end
check(m.savwaves and attack==4+2,"assault: four Furies plus two extras attack the Texas, got "..attack)
heardAll(p,"misn1817.wav")
local before=#F.builds(p[1])
F.run(5)
check(#F.builds(p[1])==before,"pending assault Furies are not re-spawned")
for _,name in ipairs({"fury1","fury2","fury3","fury4"}) do F.kill(m[name]) end
F.run(6)
local replaced=0
for _,c in ipairs(F.callsOf(p[1],"Attack")) do if c[3]==RECYCLER then replaced=replaced+1 end end
check(replaced==12,"destroyed assault is replaced (4+2 again): "..replaced)
heardAll(p,"misn1817.wav") -- the warning is the first assault's voice only
-- thrusters: any player, voices on every peer, one shared countdown
killFuries()
check(w.timer==nil,"no countdown before the thrusters")
local phasesBefore=#F.callsOf(p[1],"StartCockpitTimer")
F.kill(THRUSTERS[1]);F.run(2)
heardAll(p,"misn1813.wav")
F.kill(THRUSTERS[2]);F.run(2)
heardAll(p,"misn1814.wav")
F.kill(THRUSTERS[3]);F.run(2)
heardAll(p,"misn1815.wav")
check(not m.transdestroyed,"three thrusters are not enough")
F.kill(THRUSTERS[4]);F.run(2)
check(m.transdestroyed and m.transblownup,"fourth thruster destroys the transport")
heardAll(p,"misn1804.wav")
F.run(8)
check(F.heardCount(p[1],"misn1803.wav")==0,"1803 is a duplicate take of 1804 and stays out")
for i=1,4 do
    check(F.count(p[i],"StartCockpitTimer")==1 and F.last(p[i],"StartCockpitTimer")[2]==180,"shared 180 s countdown on peer "..i)
end
check(phasesBefore==0,"timer only starts at the collapse")
-- hurry lines
F.run(145)
for _,f in ipairs({"misn1809.wav","misn1810.wav","misn1811.wav","misn1812.wav"}) do heardAll(p,f) end
-- earthquake: restored pulse on every peer, bounded
for i=1,4 do
    local pulses=F.callsOf(p[i],"UpdateEarthQuake")
    check(#pulses>40,"quake pulses reach peer "..i..": "..#pulses)
    for _,c in ipairs(pulses) do check(c[2]<=12.0+1e-9,"quake magnitude is bounded") end
end
check(F.callsOf(p[2],"UpdateEarthQuake")[1][2]==6.0 and math.abs(F.callsOf(p[2],"UpdateEarthQuake")[2][2]-1.8)<1e-9,
    "first pulse is level x 3, then level x 0.9")

-- ------------------------------------------------------------------ win needs everyone
w,p,m=setup(4,{})
F.nearTo(p[2].player,"transfound");F.run(2);killFuries()
collapse(p)
nearBase(p,0)
F.nearTo(p[3].player,RECYCLER,250,0) -- inside the 200-400 m band: neither win nor loss
F.run(8)
check(not m.missionwon and not m.fail2,"one human in the band blocks the win")
F.nearTo(p[3].player,RECYCLER,150,0);F.run(5)
check(m.missionwon,"every human within 200 m wins")
F.run(60) -- the extraction ending (two shots) runs before the result
for i=1,4 do
    check(F.count(p[i],"SucceedMission")==1 and F.count(p[i],"FailMission")==0,"one shared victory")
    check(p[i].camera==0,"result balances every camera")
    check((p[i].env.Save().coopUnresolved or 0)==0,"no unresolved presentation identities")
end
heardAll(p,"misn1808.wav")
-- the return wave: sav1 plus the restored sav2/sav3, with extras
w,p,m=setup(4,{})
F.nearTo(p[2].player,"transfound");F.run(2);killFuries();collapse(p);killFuries()
nearBase(p,0);mark=#p[1].calls
F.nearTo(p[3].player,"return1");F.run(4)
local returned=0
for _,b in ipairs(builtAt(p[1],mark)) do if b.where=="spawnreturn" then returned=returned+1 end end
check(m.returnwave and m.sav1 and m.sav2 and m.sav3 and returned==5,"return wave: three craft + two extras, got "..returned)
-- don't-go ambush: path spawn1 does not exist on the 1.5 map
mark=#p[1].calls
F.nearTo(p[4].player,"dontgo");F.run(2)
heardAll(p,"misn1805.wav")
F.nearTo(p[4].player,"dontgo1");F.run(3)
local dg={}
for _,b in ipairs(builtAt(p[1],mark)) do dg[#dg+1]=b.where end
check(m.dg1 and #dg==2+2 and dg[#dg]=="spawn1b","ambush uses the real spawn1b approach: "..table.concat(dg,","))

-- ------------------------------------------------------------------ left behind
w,p,m=setup(4,{})
F.nearTo(p[2].player,"transfound");F.run(2);killFuries();collapse(p);killFuries()
nearBase(p,0)
F.nearTo(p[4].player,RECYCLER,600,0)
F.run(185)
check(m.fail2 and m.blastoff and not m.missionwon,"countdown expires with a human past 400 m")
F.run(10)
heardAll(p,"misn1807.wav")
for i=1,4 do
    check(F.count(p[i],"FailMission")==1 and F.count(p[i],"SucceedMission")==0,"one shared failure")
    check(F.last(p[i],"FailMission")[3]=="misn18l2.des","left-behind description on peer "..i)
    local shots=F.callsOf(p[i],"CameraObject")
    check(#shots>0,"peer "..i.." gets a left-behind shot")
    for _,c in ipairs(shots) do
        check(c[2]==p[i].player and c[6]==p[i].player,"peer "..i.." films its OWN ship, not the leader's")
    end
    check(p[i].camera==0,"result balances the left-behind camera")
end
-- each peer climbs at the leader's streamed height
check(F.callsOf(p[3],"CameraObject")[#F.callsOf(p[3],"CameraObject")][4]>=1500,"guest follows the climb height")

-- ------------------------------------------------------------------ recycler loss: misn1818, not misn1704
w,p,m=setup(4,{})
F.nearTo(p[2].player,"transfound");F.run(2)
F.kill(RECYCLER);F.run(10)
heardAll(p,"misn1818.wav")
for i=1,4 do
    check(F.heardCount(p[i],"misn1704.wav")==0,"the cross-mission line is replaced")
    check(F.count(p[i],"FailMission")==1 and F.last(p[i],"FailMission")[3]=="misn18l3.des","one shared recycler-loss failure")
end
-- 600 s without finding the transport
w,p,m=setup(2,{})
F.run(605)
check(m.fail1,"not found in 600 s fails")
for i=1,2 do check(F.count(p[i],"FailMission")==1 and F.last(p[i],"FailMission")[3]=="misn18l1.des","timeout failure on peer "..i) end

-- ------------------------------------------------------------------ watched entries wait; saves keep them
w,p,m=setup(4,{})
local realDistance=p[1].env.GetDistance
local watched={spawn1b=true,spawnalt1b=true,spawnrand=true,spawnrand2=true,spawn2b=true,spawn3b=true,spawnalt2b=true,spawnalt3b=true}
p[1].env.GetDistance=function(a,b)
    if watched[b] then return 100 end
    return realDistance(a,b)
end
F.nearTo(p[3].player,"spawn1a");F.run(4)
check(m.cr18.serial>=4 and F.count(p[1],"BuildObject")==0,"every watched entrance defers the request")
local pending=m.cr18.serial
for _,q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect();F.run(3)
check(m.cr18.serial==pending and F.count(p[1],"BuildObject")==0,"save/load does not duplicate pending waves")
p[1].env.GetDistance=realDistance
F.run(3)
check(#F.builds(p[1])==4,"requests enter once hidden again")
-- a watched authored entrance falls back to another approach
w,p,m=setup(4,{})
F.nearTo(p[4].player,"spawn1b",120,0)
F.nearTo(p[3].player,"spawn1a");F.run(3)
local fallback=F.builds(p[1])
check(#fallback==4 and fallback[1].where~="spawn1b","watched spawn falls back: "..tostring(fallback[1] and fallback[1].where))
allSafe(p,fallback)

-- ------------------------------------------------------------------ storm interface
local function recordingStorm(shape)
    return function(peer,record)
        local function director()
            local d={Initialized=true}
            function d.Reset(saved) record("StormReset",saved and saved.mark or false) end
            function d.SetPhase(name) record("StormPhase",name) end
            function d.Update(dt,authority,send)
                if authority and not d.sent then d.sent=true;send("ping",7) end
            end
            function d.Apply(...) record("StormApply",...) end
            function d.Stop() record("StormStop") end
            function d.Save() return {mark="saved"} end
            function d.GetSeverity() return 0.5 end
            return d
        end
        if shape=="flat" then return director() end
        return {Create=function(api) assert(api.exu and type(api.state)=="function"); return director() end}
    end
end
local function phases(peer)
    local out={}
    for _,c in ipairs(F.callsOf(peer,"StormPhase")) do out[#out+1]=c[2] end
    return table.concat(out,",")
end
for _,shape in ipairs({"create","flat"}) do
    w,p,m=setup(3,{storm=recordingStorm(shape)})
    check(phases(p[1])=="opening,search" and phases(p[2])=="" and phases(p[3])=="","opening then search; guests never set phases ("..shape..")")
    check(F.count(p[1],"WeatherSensors","Achilles")>=1,"storm binds the weather sensors")
    F.nearTo(p[2].player,"transfound");F.run(2)
    check(F.count(p[1],"StartEarthquake")==1 and F.count(p[3],"StartEarthquake")==1,"a director without Quake leaves the mission's own quake path alone ("..shape..")")
    for _,name in ipairs(THRUSTERS) do F.kill(name);F.run(1) end
    -- Furies may be anywhere; keep the base quiet and let the countdown run
    killFuries()
    for _,q in ipairs(p) do F.nearTo(q.player,RECYCLER,300,0) end -- inside the band: no result yet
    F.run(2)
    check(phases(p[1])=="opening,search,found,core1,core2,core3,collapse","thruster phases in order: "..phases(p[1]))
    F.run(160)
    check(phases(p[1])=="opening,search,found,core1,core2,core3,collapse,final","final at 30 s: "..phases(p[1]))
    nearBase(p,0)
    F.run(60)
    check(m.missionwon and phases(p[1])=="opening,search,found,core1,core2,core3,collapse,final,extract,ascent,won","extract, ascent, then won last: "..phases(p[1]))
    for i=2,3 do
        local applied=F.callsOf(p[i],"StormApply")
        check(#applied==1 and applied[1][2]=="ping" and applied[1][3]==7,"storm events reach guest "..i)
    end
    for i=1,3 do check(F.count(p[i],"StormStop")==1,"storm stops with the result on peer "..i) end
    -- Save/Load: the director gets its saved state back and the leader repeats the current phase
    local resets=#F.callsOf(p[1],"StormReset")
    p[1].env.Load(p[1].env.Save())
    check(#F.callsOf(p[1],"StormReset")==resets+1 and F.last(p[1],"StormReset")[2]=="saved","storm state restored on load")
    check(F.last(p[1],"StormPhase")[2]=="won" and #F.callsOf(p[1],"StormPhase")==12,"load repeats the current phase once")
end
-- loss ends the sequence with "lost"
w,p,m=setup(2,{storm=recordingStorm("create")})
F.nearTo(p[2].player,"transfound");F.run(2);F.kill(RECYCLER);F.run(6)
check(phases(p[1])=="opening,search,found,lost","lost ends the phases: "..phases(p[1]))
-- no director at all (the default everywhere above) and a director that cannot be built
w,p,m=setup(2,{storm=function() return {Create=function() error("storm unavailable") end} end})
F.nearTo(p[2].player,"transfound");F.run(2)
check(m.transportfound and F.count(p[1],"WeatherSensors")==0,"a failing director never stops the mission")
w,p,m=setup(2,{storm=function(peer,record) return {Initialized=true,SetPhase=function() error("boom") end} end})
F.nearTo(p[2].player,"transfound");F.run(2)
check(m.transportfound,"a throwing director never stops the mission")

-- ------------------------------------------------------------------ the REAL storm, four peers
-- Scripts/CRStorm18.lua (with the real CRWeather / CRWeatherPresets / CRFoliageWind) against stubbed EXU.
local RealStorm=dofile("Tools/Misn18RealStorm.lua")(F)
local function stormErrors(p)
    for i,q in ipairs(p) do
        for _,c in ipairs(q.calls) do
            if c[1]=="StormPrint" then check(false,"peer "..i.." storm printed: "..tostring(c[2])) end
            if c[1]=="print" and tostring(c[2]):find("CRStorm18",1,true) then check(false,"peer "..i.." mission printed: "..tostring(c[2])) end
        end
    end
end
local function nativeQuakes(peer)
    local peak,open,overlap=0,false,false
    for _,c in ipairs(F.callsOf(peer,"NativeQuake")) do
        if c[2]=="start" then if open then overlap=true end;open=true elseif c[2]=="stop" then open=false end
        if c[3] and c[3]>peak then peak=c[3] end
    end
    return peak,overlap
end
local function realPhases(peer)
    local out={}
    for _,c in ipairs(F.callsOf(peer,"StormPhase")) do out[#out+1]=c[2] end
    return table.concat(out,",")
end
local FULL="opening,search,found,core1,core2,core3,collapse,final"
do
    w,p,m=setup(4,{storm=RealStorm})
    check(p[1].director~=nil and p[1].director.Initialized and F.count(p[1],"WeatherSensors","Achilles")>=1,"the real director is built and bound")
    F.nearTo(p[2].player,"transfound");F.run(2);killFuries()
    -- the restored/stock mission quakes go INTO the storm: no peer calls the natives itself
    F.run(10)
    for i=1,4 do
        check(F.count(p[i],"StartEarthquake")==0 and F.count(p[i],"UpdateEarthQuake")==0,"peer "..i..": mission quake requests are routed to the storm")
        local peak,overlap=nativeQuakes(p[i])
        check(peak>=5.9 and peak<=12+1e-6 and not overlap,"peer "..i..": the storm shakes the engine, preserving the pulse ("..peak..")")
    end
    for _,name in ipairs(THRUSTERS) do F.kill(name);F.run(1) end
    F.run(9)
    local pre=realPhases(p[1])
    check(pre=="opening,search,found,core1,core2,core3,collapse","phases so far: "..pre)
    for i=2,4 do check(realPhases(p[i])=="","guest "..i.." never sets storm phases") end
    -- guests render the leader's storm from its events: same phase, same funnel, strikes seen
    local lead=p[1].env.Save().cr18Storm
    check(lead and lead.name=="collapse" and lead.tornado,"leader storm is in collapse with a tornado")
    for i=2,4 do
        local g=p[i].env.Save().cr18Storm
        check(g and g.phase==lead.phase and g.seed==lead.seed,"guest "..i.." follows the phase and seed")
        check(g.bolts>3 and g.tornado and math.abs(g.tornadoX-lead.tornadoX)<30 and math.abs(g.tornadoZ-lead.tornadoZ)<30,"guest "..i.." sees strikes and the same funnel")
        check(F.count(p[i],"StormApply","phase")>=1 and F.count(p[i],"StormApply","tornado")>=1,"guest "..i.." received phase and tornado events")
    end
    -- finish: win
    F.run(1)
    nearBase(p,0)
    F.nearTo(p[3].player,RECYCLER,300,0) -- in the band: no result until everyone is home
    F.runUntil(function() return w.timer and w.timer.duration-(w.now-w.timer.start)<=25 end,400)
    check(not m.missionwon and not m.fail2,"the band holds the result "..tostring(m.missionwon).." "..tostring(m.fail2).." "..tostring(m.fail3).." "..tostring(m.coopFailed).." t="..tostring(w.timer and w.timer.duration-(w.now-w.timer.start)))
    F.nearTo(p[3].player,RECYCLER,100,0);F.run(4)
    check(m.missionwon,"every human within 200 m wins")
    F.run(60)
    check(realPhases(p[1])==FULL..",extract,ascent,won","phases in order, won last: "..realPhases(p[1]))
    stormErrors(p)
    for i=1,4 do
        check(F.count(p[i],"SucceedMission")==1,"one victory on peer "..i.." n="..F.count(p[i],"SucceedMission").." ext="..tostring(m.cr18.ext and m.cr18.ext.n).." done="..tostring(m.cr18.extractDone).." pend="..tostring(m.coopPendingResult).." res="..tostring(m.coopResult).." t="..F.world().now.." ready="..tostring(m.coopPendingResult and m.coopPendingResult.ready))
        local peak=nativeQuakes(p[i]);check(peak>0,"quake ran on peer "..i)
        local last=F.callsOf(p[i],"NativeQuake");check(last[#last][2]=="stop","the storm leaves the engine calm on peer "..i)
        check((p[i].env.Save().cr18Storm.errors or 0)==0,"no storm errors on peer "..i)
    end
end
do -- tornado fairness (the result is irrelevant here: everyone stands in the funnel)
    w,p,m=setup(4,{storm=RealStorm})
    F.nearTo(p[2].player,"transfound");F.run(2);killFuries()
    for _,name in ipairs(THRUSTERS) do F.kill(name);F.run(1) end
    F.run(9)
    -- tornado fairness: each peer pulls only what it owns; the leader also pulls AI craft
    local lead=p[1].env.Save().cr18Storm
    local tx,tz=lead.tornadoX,lead.tornadoZ
    for i=1,4 do F.place(p[i].player,tx+6*i,tz+10) end
    local fury=F.spawn("crfraz",6,tx-20,tz)
    for _,q in ipairs(p) do q.calls={} end -- (phases were captured above)
    F.run(6)
    for i=1,4 do
        local pulled={}
        for _,c in ipairs(F.callsOf(p[i],"TornadoVelocity")) do pulled[c[2]]=(pulled[c[2]] or 0)+1 end
        check((pulled[p[i].player] or 0)>0,"peer "..i.." pulls its own ship")
        for j=1,4 do if j~=i then check(pulled[p[j].player]==nil,"peer "..i.." never moves peer "..j.."'s ship") end end
        check((pulled[fury]~=nil)==(i==1),"only the leader pulls the AI craft (peer "..i..")")
    end
    for i=1,4 do
        local total=0
        for _,c in ipairs(F.callsOf(p[i],"TornadoDamage")) do
            check(c[2]==p[i].player or (i==1 and c[2]==fury),"peer "..i.." only hurts craft it owns")
            total=total+c[3]
        end
        check(total<=40,"tornado damage stays low on peer "..i..": "..total)
    end
end
do -- a lost path
    w,p,m=setup(4,{storm=RealStorm})
    F.nearTo(p[2].player,"transfound");F.run(2);killFuries()
    for i=1,2 do F.kill(THRUSTERS[i]);F.run(1) end
    F.kill(RECYCLER);F.run(10)
    check(m.fail3 or m.coopFailed or F.count(p[1],"FailMission")==1,"recycler loss fails")
    check(realPhases(p[1])=="opening,search,found,core1,core2,lost","lost ends the real sequence: "..realPhases(p[1]))
    stormErrors(p)
    for i=1,4 do
        check(F.count(p[i],"FailMission")==1,"one failure on peer "..i)
        check((p[i].env.Save().cr18Storm.errors or 0)==0,"no storm errors on peer "..i)
    end
    -- save/load mid-storm: the director resumes the same phase on the leader
    w,p,m=setup(2,{storm=RealStorm})
    F.nearTo(p[2].player,"transfound");F.run(2);F.kill(THRUSTERS[1]);F.run(40)
    local before=p[1].director.Describe()
    for _,q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect();F.run(3)
    check(p[1].director.Describe().phase==before.phase and p[1].director.Describe().seed==before.seed,"real storm resumes its phase and seed after load")
    stormErrors(p)
end

-- ------------------------------------------------------------------ the extraction ending
local Drop=dofile("Scripts/CRDrop18.lua")
local function hullsOf(peer,mark,odf)
    local out={}
    for _,b in ipairs(F.builds(peer,mark,odf)) do out[#out+1]=b end
    return out
end
local function toWin(n,options)
    options=options or {}
    options.storm=options.storm or RealStorm
    local w2,p2,m2=setup(n,options)
    F.nearTo(p2[n].player,"transfound");F.run(2);killFuries()
    collapse(p2);killFuries()
    if options.factoryDead then F.kill("avmuf2_factory") end
    for i,q in ipairs(p2) do F.nearTo(q.player,RECYCLER,8*i,0) end
    return w2,p2,m2
end
do -- choreography: pure, deterministic, inside the tornado keep-clear zone
    local function ground(x,z) return 100+8*math.sin(x/70)+6*math.cos(z/90) end
    local cx,cz=1875.2,98035.1
    local zones=dofile("Scripts/CRStorm18Sites.lua").zones
    for count=1,5 do
        local a=Drop.Sites(cx,cz,count,ground);local b=Drop.Sites(cx,cz,count,ground)
        check(#a==count and a[1].x==b[1].x and a[count].z==b[count].z,"sites are deterministic ("..count..")")
        for i,s in ipairs(a) do
            local d=math.sqrt((s.x-cx)^2+(s.z-cz)^2)
            check(d<=210+1e-6 and d>=150-1e-6,"site "..i.." sits on the ring")
            check(math.abs(s.sx*s.lx+s.sz*s.lz)<1e-9 and math.abs(s.sx^2+s.sz^2-1)<1e-9,"orthonormal ship frame")
            check(math.abs((cx-s.x)/d-s.sx)<1e-9,"stern faces the Texas")
            for j=i+1,count do
                local o=a[j]
                check(math.sqrt((s.x-o.x)^2+(s.z-o.z)^2)>=120,"ships are clear of each other ("..count..")")
            end
        end
    end
    check(#Drop.Sites(cx,cz,9,ground)==Drop.MAX_SHIPS,"never more than five ships")
    local inside=false
    for _,z in ipairs(zones) do
        if math.sqrt((cx-z[1])^2+(cz-z[2])^2)<60 and z[3]>=300 then inside=true end
    end
    check(inside,"the Texas has the 300 m tornado keep-clear circle the ring fits inside")
    local last
    for i=1,5 do
        local order={}
        for t=0,Drop.Total(),0.5 do
            local s=Drop.Stage(i,t);if s~=order[#order] then order[#order+1]=s end
            local up,back=Drop.Offsets(i,t)
            check(up>=0,"never below the ground")
        end
        check(table.concat(order,",")=="wait,fly,open,load,close,lift" or table.concat(order,",")=="fly,open,load,close,lift","stage order for ship "..i..": "..table.concat(order,","))
    end
    local u0=Drop.Offsets(1,0.01);local u1=Drop.Offsets(1,Drop.FLY_T-0.01);local u2=Drop.Offsets(1,Drop.FLY_T+0.5)
    check(u0>300 and u1<1 and u2==0,"the ship descends to the ground and stays")
    check(Drop.Delay(5)+Drop.FLY_T+Drop.OPEN_T+Drop.LOAD_T+Drop.CLOSE_T<Drop.SHOT1,"the last ramps are closed before shot 1 ends")
end
for _,n in ipairs({1,4}) do
    local w2,p2,m2=toWin(n)
    local mark=#p2[1].calls
    local startY={}
    for i,q in ipairs(p2) do startY[i]=F.world().objects[q.player].pos.y end
    F.runUntil(function() return m2.missionwon end,60)
    F.run(1)
    -- the win latched but the mission has not ended
    check(m2.missionwon and m2.cr18.ext and m2.cr18.ext.n==n+1,n.." humans: one dropship each plus the base ship, got "..tostring(m2.cr18.ext and m2.cr18.ext.n))
    check(n+1<=Drop.MAX_SHIPS,"the fleet is capped")
    for i=1,n do
        check(F.count(p2[i],"SucceedMission")==0,"no success at the win on peer "..i)
        check(p2[i].camera==1,"peer "..i.." is in the extraction shot")
    end
    check(#hullsOf(p2[1],mark,"avdropc")==n+1,"flying dropships built: "..#hullsOf(p2[1],mark,"avdropc"))
    check(F.count(p2[1],"StopCockpitTimer")>=1 and F.count(p2[n],"StopCockpitTimer")>=1,"the countdown is stopped on every peer")
    local podPeer=hullsOf(p2[1],mark,"apcamr")
    check(#podPeer==1,"one camera pod")
    -- shot 1 films the Texas from the pod on every peer
    local shot1=F.last(p2[n],"CameraObject")
    check(shot1~=nil and shot1[2]==podPeer[1].h,"shot 1 is filmed from the pod on peer "..n)
    -- threats are gone and nothing can fail
    F.spawn("hvsav",6,1900,98100);F.kill(RECYCLER) -- the Texas dies mid-ending: the win is final
    F.run(Drop.SHOT1-3)
    for i=1,n do
        check(F.count(p2[i],"FailMission")==0,"nothing fails the mission during the ending (peer "..i..")")
        check(F.heardCount(p2[i],"misn1818.wav")==0 and F.heardCount(p2[i],"misn1704.wav")==0,"no loss line after the win")
        check(F.count(p2[i],"SucceedMission")==0,"still no success in shot 1 (peer "..i..")")
    end
    local landed=#hullsOf(p2[1],mark,"avdropo")
    local closing=#hullsOf(p2[1],mark,"avdropx")
    check(landed==n+1 and closing>=n,"dropships land (avdropo) then fold their ramps (avdropx): "..landed.."/"..closing)
    -- shot 2 follows the lead dropship on every peer
    F.run(3)
    for i=1,n do
        local s2=F.last(p2[i],"CameraObject")
        check(s2~=nil and s2[2]~=podPeer[1].h and F.world().objects[s2[2]] and F.world().objects[s2[2]].odf=="avdropx","shot 2 follows a climbing dropship on peer "..i)
    end
    check(F.count(p2[1],"StormPhase","extract")==1 and F.count(p2[1],"StormPhase","ascent")==1,"the storm is told extract, then ascent")
    for i=1,n do
        local pos=F.world().objects[p2[i].player].pos
        check(pos.y>25,"peer "..i.." rides its own dropship up (y="..math.floor(pos.y)..")")
    end
    -- each peer pins only what it owns; the leader drives the ships and the base cargo
    for i=1,n do
        local own={[p2[i].player]=true}
        if i==1 then own[RECYCLER]=true;own["avmuf2_factory"]=true;for _,c in ipairs(p2[1].calls) do if c[1]=="BuildObject" then own[c[2]]=true end end end
        for _,c in ipairs(F.callsOf(p2[i],"SetTransform")) do check(own[c[2]],"peer "..i.." only moves what it owns: "..tostring(c[2])) end
        check(#F.callsOf(p2[i],"SetTransform")>0,"peer "..i.." pins its ship")
    end
    -- the mission succeeds only after shot 2
    F.run(Drop.SHOT2+Drop.Total())
    for i=1,n do
        check(F.count(p2[i],"SucceedMission")==1 and F.count(p2[i],"FailMission")==0,"one success after the ending on peer "..i)
        check(p2[i].camera==0,"cameras balanced after the ending on peer "..i)
    end
    local ph=F.callsOf(p2[1],"StormPhase");check(ph[#ph][2]=="won","the storm settles into won last")
    stormErrors(p2)
end
-- the Factory died: the base ship still carries the Recycler alone
do
    local w2,p2,m2=toWin(2,{factoryDead=true})
    F.runUntil(function() return m2.missionwon end,60);F.run(Drop.SHOT1)
    local moved={}
    for _,c in ipairs(F.callsOf(p2[1],"SetTransform")) do moved[c[2]]=true end
    check(moved[RECYCLER] and not moved["avmuf2_factory"],"only the surviving Recycler is loaded")
    check(m2.cr18.ext.n==3,"two humans plus the base ship")
end
-- a save/load mid-ending goes straight to success, once, never to failure
do
    local w2,p2,m2=toWin(4)
    F.runUntil(function() return m2.missionwon end,60);F.run(Drop.SHOT1/2)
    check(F.count(p2[1],"SucceedMission")==0,"mid-ending")
    for _,q in ipairs(p2) do q.env.Load(q.env.Save()) end
    F.connect();F.run(12)
    for i=1,4 do
        check(F.count(p2[i],"SucceedMission")==1 and F.count(p2[i],"FailMission")==0,"load mid-ending: success once on peer "..i)
        check(p2[i].camera==0,"load mid-ending: cameras balanced on peer "..i)
    end
end
-- without the choreography module the win ends the mission as before
do
    local w2,p2,m2=toWin(2,{noDrop=true})
    F.runUntil(function() return m2.missionwon end,60);F.run(14)
    check(F.count(p2[1],"SucceedMission")==1 and #hullsOf(p2[1],0,"avdropc")==0,"no dropship module: immediate success")
end

-- ------------------------------------------------------------------ transport-destroyed shot
local function shotScenario(storm)
    local w2,p2,m2=setup(4,{storm=storm})
    F.nearTo(p2[2].player,"transfound");F.run(2);killFuries()
    for i=1,3 do F.kill(THRUSTERS[i]);F.run(1) end
    F.kill(THRUSTERS[4]);F.run(3)
    return w2,p2,m2
end
do
    local w2,p2,m2=shotScenario(recordingStorm("create"))
    check(m2.transdestroyed and w2.timer==nil,"the countdown waits for the shot")
    for i=1,4 do
        check(F.count(p2[i],"StartCockpitTimer")==0,"no countdown yet on peer "..i)
        check(p2[i].camera==1,"peer "..i.." is in the transport-destroyed shot")
        check(F.last(p2[i],"CameraPath")[2]=="transdestroyedcam","peer "..i.." films transdestroyedcam")
    end
    check(F.alive("hbtran0038_i76building"),"the transport still stands early in the shot")
    check(phases(p2[1])=="opening,search,found,core1,core2,core3,collapse","collapse opens the shot: "..phases(p2[1]))
    -- arrivals are held while the camera is away
    local before=#F.builds(p2[1])
    F.nearTo(p2[3].player,"dontgo");F.run(1)
    F.nearTo(p2[3].player,"dontgo1");F.run(1)
    check(#F.builds(p2[1])==before,"no Furies arrive during the shot")
    F.nearTo(p2[3].player,RECYCLER,50,0)
    F.run(2)
    check(not F.alive("hbtran0038_i76building"),"the transport blows up on camera")
    check(F.count(p2[1],"StartCockpitTimer")==0,"still no countdown before the shot ends")
    check(not m2.fail2,"an idle clock never reads as an expired countdown")
    F.run(6)
    for i=1,4 do
        check(F.count(p2[i],"StartCockpitTimer")==1 and F.last(p2[i],"StartCockpitTimer")[2]==180,"countdown starts when the shot ends on peer "..i)
        check(p2[i].camera==0,"shot camera released on peer "..i)
    end
    check(phases(p2[1])=="opening,search,found,core1,core2,core3,collapse","final waits for the countdown")
    F.run(2)
    check(#F.builds(p2[1])>before,"held arrivals enter afterwards")
end
-- load mid-shot: the transport falls and the countdown starts at once, exactly once
do
    local w2,p2,m2=shotScenario(nil)
    check(p2[1].camera==1 and F.count(p2[1],"StartCockpitTimer")==0,"mid-shot")
    for _,q in ipairs(p2) do q.env.Load(q.env.Save()) end
    F.connect();F.run(3)
    check(F.count(p2[1],"StartCockpitTimer")==1 and not F.alive("hbtran0038_i76building"),"load mid-shot starts the countdown immediately")
    check(m2.cr18.cin==nil and m2.cr18.timerStarted,"shot state is cleared and the start is saved")
    F.run(20)
    for i=1,4 do check(F.count(p2[i],"StartCockpitTimer")==1,"one countdown on peer "..i) end
end

-- ------------------------------------------------------------------ artillery-free sanity: restored voice and roster
w,p,m=setup(2,{})
F.run(2)
check(F.heardCount(p[1],"misn1817.wav")==0,"1817 waits for the first assault")
print("misn18 co-op: "..checks.." checks passed")
