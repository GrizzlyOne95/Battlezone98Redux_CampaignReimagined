-- Full campaign runtime, real co-op registry and ordered multi-peer transport.
assert(_VERSION == "Lua 5.1")
local F=dofile("Tools/Misn15Fixture.lua")
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function setup(count)
    local w=F.reset();local peers={}
    for i=1,count do peers[i]=F.makePeer(i,i,count>1) end
    F.connect();F.run(3)
    return w,peers,peers[1].env.Save()
end
local w,p,m=setup(4)
local s=m.cr15
check(m.start_done and not m.lost,"correct map boots")
check(F.count(p[1],"BuildObject")==0,"rescue groups are present before discovery without runtime spawns")
for _,q in ipairs(p) do
    check(F.count(q,"PdaInitialize")==1 and F.count(q,"PdaUpdate")>0,"PDA on every peer")
end
for _,label in ipairs({"cr15_nw_scav","cr15_nw_apc","cr15_ne_scav1","cr15_ne_artillery"}) do
    check(F.team(label)==7,"stranded units remain support-owned")
end
F.nearTo("svtank1_wingman","apcamr5_camerapod")
F.kill("svtank0_wingman")
F.run(2)
check(s.cca and not m.lost,"surviving second tank completes rendezvous")
check(F.team("svtank1_wingman")==1,"allies join shared command force")
F.nearTo(p[2].player,"apcamr1_camerapod");F.run(2)
check(s.nw and F.team("cr15_nw_scav")==1,"guest triggers required NW recovery")
F.nearTo(p[3].player,"apcamr2_camerapod");F.run(2)
check(s.ne and F.team("cr15_ne_artillery")==1,"another guest triggers optional NE recovery")
check(not F.heard(p[1],"misn1514.wav"),"NE arrival does not misuse Tartarus dialogue")
F.run(20)
for i=2,4 do
    check(F.heard(p[i],"misn1501.wav") and F.heard(p[i],"misn1503.wav") and F.heard(p[i],"misn1518.wav"),"shared VO")
    check(F.count(p[i],"CameraPath","rescue_cam1")>0 and F.count(p[i],"CameraPath","rescue_cam2")>0,"both rescue shots replicated")
    check(p[i].camera==0,"shared camera released")
    check((p[i].env.Save().coopUnresolved or 0)==0,"no unresolved presentation targets")
end
w.capacity=70;w.scrap=40;F.run(2)
check(F.heardCount(p[1],"misn1505.wav")==1,"40 reserve report")
w.scrap=20;F.run(2);w.scrap=40;F.run(2)
check(F.heardCount(p[1],"misn1505.wav")==1,"spend and recollect does not replay report")
w.scrap=50;F.run(2)
check(s.withdraw and F.heard(p[1],"misn1506.wav") and F.heard(p[1],"misn1508.wav"),"withdrawal at 50")
w.scrap=65;F.run(2)
check(F.heardCount(p[1],"misn1507.wav")==1,"almost enough report")
F.nearTo(p[4].player,"ubtart0_i76building",140);F.run(2)
check(s.tartarusWarning and not s.tartarusAlert,"warning alone is harmless")
F.run(16);F.nearTo(p[4].player,"ubtart0_i76building",60);F.run(4)
check(not s.tartarusAlert,"brief proximity still safe")
F.nearTo(p[4].player,"ubtart0_i76building",140);F.run(2)
F.nearTo(p[4].player,"ubtart0_i76building",60);F.run(8)
check(s.tartarusAlert and s.tartarusResponseSpawned,"sustained intrusion triggers one response")
check(#F.builds(p[1],0,"hvsav")==2,"two Tartarus guardians")
F.run(3)
check(#F.builds(p[1],0,"hvsav")==2,"Tartarus response once only")
for _,b in ipairs(F.builds(p[1])) do
    check(b.team==6,"all new threats use Fury team")
end
w.scrap=75;w.capacity=80
F.nearTo("avrecy0_recycler","apcamr4_camerapod")
for i=1,3 do F.nearTo(p[i].player,"apcamr4_camerapod",i*10) end
F.run(2);check(not m.won,"missing guest blocks withdrawal win")
F.nearTo(p[4].player,"apcamr4_camerapod",40);F.run(10)
check(m.won and F.count(p[1],"SucceedMission")==1,"all humans and Texas extract with reserve")
for i=2,4 do check(F.count(p[i],"SucceedMission")==1,"one shared result per guest") end
for i=2,4 do check(F.count(p[i],"BuildObject")==0,"guests never spawn mission objects") end

-- Independent failure and optional-loss gates.
w,p,m=setup(1);s=m.cr15
for _,label in ipairs({"cr15_ne_scav1","cr15_ne_scav2","cr15_ne_artillery"}) do F.kill(label) end
F.run(2);check(s.neLost and not m.lost,"optional rescue lost without mission failure")
for _,label in ipairs({"cr15_nw_scav","cr15_nw_apc","cr15_nw_turret"}) do F.kill(label) end
F.run(2);check(m.lost and F.count(p[1],"FailMission")==1,"required rescue cannot silently softlock")
w,p,m=setup(1)
F.kill("avrecy0_recycler");w.scrap=75;F.run(2)
check(m.lost and not m.won and F.heard(p[1],"misn1509.wav"),"Texas loss takes precedence, correct VO")
w,p,m=setup(1)
for _,label in ipairs({"svtank0_wingman","svtank1_wingman","svapc0_apc"}) do F.kill(label) end
F.run(2);check(m.lost,"all allies lost before rendezvous fails clearly")

-- Watched spawn sites postpone, then recover; guests never independently RNG/spawn.
w,p,m=setup(2);s=m.cr15
F.nearTo(p[1].player,"alien1");F.nearTo(p[2].player,"alien2")
s.nextHunter=0;s.nextDenial={0,0};F.run(2)
check(#s.furies==0 and not s.denial[1] and not s.denial[2],"all watched sites defer every wave")
for _,q in ipairs(p) do F.nearTo(q.player,"avrecy0_recycler") end
F.run(18)
check(s.denial[1] and s.denial[2] and #s.furies==6,"deferred two-tank pairs and scaled hunters recover")
check(F.count(p[2],"BuildObject")==0 and F.count(p[2],"random")==0,"guest has no gameplay authority")

-- Damage provokes Tartarus without waiting for proximity, once, with cap/retry.
w,p,m=setup(1);s=m.cr15
w.objects.ubtart0_i76building.health=.5;F.run(2)
check(s.tartarusAlert and s.tartarusResponseSpawned,"damage triggers Tartarus response")
F.nearTo(p[1].player,"ubtart0_i76building",60);F.run(20)
check(s.tartarusMinesPending or s.tartarusMinesComplete,"continued intrusion activates arc-mine grid")
F.nearTo(p[1].player,"ubtart0_i76building",200);F.run(8)
check(s.tartarusMinesComplete and #s.tartarusMines==40,"tight grid completes exactly forty mines with central clearance")
for _,mine in ipairs(s.tartarusMines) do
    check(F.team(mine)==6 and w.objects[mine].odf=="boltmine","grid mines on Fury team")
end
local builds=F.count(p[1],"BuildObject")
local saved=p[1].env.Save();p[1].env.Load(saved);F.run(2)
check(F.count(p[1],"BuildObject")==builds,"load does not duplicate rescued groups or guardians")
check(F.count(p[1],"AddScrap")==1,"load does not replay initial grant")
local weatherInit,weatherUpdates,weatherLoads=nil,0,0
local director={Seed=42,Init=function(options) weatherInit=options end,
    Update=function() weatherUpdates=weatherUpdates+1 end,
    Save=function() return {checkpoint=7} end,
    Load=function(value) weatherLoads=weatherLoads+1;assert(value.checkpoint==7) end}
w=F.reset();local peer=F.makePeer(1,1,false,{titan=director});F.run(3)
check(weatherInit and weatherInit.authority==true,"host initializes Titan authority")
check(weatherInit.sites.mission=="misn15" and weatherInit.sites.sea.level==38.1,"real Mission 15 site table reaches director")
check(weatherUpdates>0 and F.count(peer,"WeatherSensors","Titan")==1,"director and sensor binding update")
local weatherSave=peer.env.Save();peer.env.Load(weatherSave);F.run(2)
check(weatherLoads==1,"saved weather restores once through runtime")
print("misn15 campaign co-op: "..checks.." checks passed")
