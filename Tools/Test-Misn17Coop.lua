-- Four independent Lua peers, real CRCoop registry, lossy presentation simulator.
-- Engine AI, rendering and combat remain mocked.
assert(_VERSION=="Lua 5.1")
local F=dofile("Tools/Misn17Fixture.lua")
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function setup(n)
    local w=F.reset();local p={}
    for i=1,n do p[i]=F.makePeer(i,i,n>1) end
    F.connect();F.run(5)
    return w,p,p[1].env.Save()
end
local w,p,m=setup(4)
check(m.missionstart and m.coopMissionStarted,"leader starts shared mission")
check(m.minesmade and m.MINE[53]=="cr17_mine53","preplaced field bound")
check(m.tower7=="cr17_tower7","seven preplaced towers used")
check(F.count(p[1],"SetScrap")==1 and F.last(p[1],"SetScrap")[3]==70,"four-player bounded shared scrap")
check(F.last(p[1],"SetAIP")[3]==6,"strategic AI targets Fury team")
for i=1,4 do
    check(F.count(p[i],"DisableStartingRecycler")==1,"disable extra starting recyclers")
    check(F.heardCount(p[i],"misn1701.wav")==1,"briefing once per peer")
    if i>1 then
        check(F.count(p[i],"BuildObject")==0 and F.count(p[i],"SetScrap")==0 and F.count(p[i],"SetAIP")==0,"guest never mutates gameplay")
    end
end
-- A guest, not the host, reaches a tower and earns its defenders.
F.nearTo(p[4].player,m.tower1)
F.run(4)
check(m.tower1spawn and m.deftow1a and m.deftow1b,"guest approach activates tower defense")
for _,b in ipairs(F.builds(p[1])) do
    check(b.team==6,"spawn ownership isolated from human teams")
    for _,q in ipairs(p) do check(q.env.GetDistance(q.player,b.h)>=460,"no visible spawn beside any human") end
end
check(F.count(p[1],"Defend2")==2,"concealed defenders keep their destination orders")
-- The full 54-position shipped field collapses; no mine survives the tower gate.
for i=1,7 do F.kill("cr17_tower"..i) end
F.run(18)
check(m.towersdestroyed and not m.minesdestroyed,"tower gate completes mine sweep")
for i=1,54 do check(not F.alive("cr17_mine"..i),"mine swept "..i) end
for i=1,4 do check(F.heardCount(p[i],"misn1730.wav")==1,"collapse VO reaches every peer") end
-- Results latch once, after the three visual factory detonations.
for i=1,3 do F.kill("factorypart"..i) end
F.run(12)
check(m.missionwon and m.sf2gone and m.sf3gone and m.sf4gone,"factory finale detonates all three shells")
for i=1,4 do
    check(F.count(p[i],"SucceedMission")==1 and F.count(p[i],"FailMission")==0,"one shared victory")
    check(p[i].camera==0,"result balances every camera")
    check((p[i].env.Save().coopUnresolved or 0)==0,"no unresolved presentation identities")
end
-- Loss takes precedence when recycler and converters fall on the same tick.
w,p,m=setup(4)
F.kill("avrecy18_recycler")
for i=1,3 do F.kill("factorypart"..i) end
F.run(8)
check(not m.missionwon and not F.heard(p[1],"misn1703.wav"),"loss suppresses victory narrative and explosions")
for i=1,4 do check(F.count(p[i],"FailMission")==1 and F.count(p[i],"SucceedMission")==0,"loss wins simultaneous result race") end
-- Requests survive save/load and remain deferred while every entry is watched.
w,p,m=setup(4)
F.nearTo(p[1].player,"counter")
F.nearTo(p[2].player,"savfactory1")
F.nearTo(p[3].player,"cr17_tower1")
F.nearTo(p[4].player,"cr17_tower2")
F.run(8)
check(m.cr17.serial>=4,"watched requests queued")
check(F.count(p[1],"BuildObject")==0,"all watched entrances defer")
local pending=m.cr17.serial
for _,q in ipairs(p) do q.env.Load(q.env.Save()) end
F.connect();F.run(3)
check(m.cr17.serial==pending,"save/load does not duplicate pending waves")
for i=1,4 do F.place(p[i].player,1813-25*i,99354) end
F.run(5)
check(F.count(p[1],"BuildObject")>=4,"requests enter once hidden again")
-- Artillery counters include a guest-built artillery and ignore hostile craft.
w,p,m=setup(4)
local art=F.spawn("avartl",4,1800,99320)
F.run(2)
check(m.art1==art and m.desart1,"guest artillery receives host-owned counter")
check(F.count(p[4],"BuildObject")==0,"guest never owns counter spawn")
local a=m.art1
F.spawn("avartl",6,3500,101000)
check(m.art1==a and m.art2==nil,"hostile artillery never enters human registry")
print("misn17 co-op: "..checks.." checks passed")
