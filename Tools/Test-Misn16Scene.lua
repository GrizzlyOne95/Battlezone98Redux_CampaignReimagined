-- Decisions/transport tests using the real four-peer registry and presentation.
-- Movement is assisted; these are not native pathfinding/rendering evidence.
assert(_VERSION=="Lua 5.1")
local F=dofile("Tools/Misn16Fixture.lua")
local n=0
local function check(ok,why) assert(ok,why);n=n+1 end
local function setup(count)
    local w=F.reset();local peers={}
    for i=1,count do peers[i]=F.makePeer(i,i,count>1) end
    F.connect();F.run(23)
    return w,peers,peers[1].env.Save()
end
local w,p,m=setup(4)
check(m.start_done,"shared mission boots")
for _,q in ipairs(p) do check(q.camera==0,"intro camera balanced") end
check(F.count(p[1],"BuildObject")==0,"transport and evacuees preplaced")
F.kill("alien_hq");F.run(1)
check(m.cr16.evacuating and not m.cr16.victory,"first facility starts evacuation")
check(F.count(p[1],"Goto","cr16_evac1")==1,"first evacuee uses authored route")
check(F.alive("cr16_evac1"),"no premature exposed removal")
F.nearTo("cr16_evac1","cr16_board")
F.nearTo("cr16_evac2","cr16_board")
F.run(1)
check(F.alive("cr16_evac1") and m.cr16.boarded==0,"boarding waits for the final scene")
F.kill("alien_hangar");F.run(20)
check(m.cr16.boarded==2,"boarding removes actors only during the visible finale")
check(m.cr16.finale=="launch" and not m.won,"final facility starts launch rather than immediate result")
check(F.count(p[1],"SetPosition","cr16_transport")>0,"transport hull moves")
for i=1,4 do check(F.count(p[1],"SetPosition","cr16_engine"..i)>0,"engines accompany hull") end
F.run(38)
check(m.won and F.count(p[1],"SucceedMission")==1,"one host win after departure")
for _,q in ipairs(p) do
    check(F.heardCount(q,"misn1615.wav")==1,"boarding VO once per peer")
    check(F.heardCount(q,"misn1616.wav")==1,"hangar confirmation once per peer")
    check(F.heardCount(q,"misn1613.wav")==1,"facility completion VO once per peer")
    check(F.count(q,"SucceedMission")==1,"one shared result")
    check(q.camera==0,"finale camera balanced")
    check((q.env.Save().coopUnresolved or 0)==0,"no unresolved scene handles")
    if q~=p[1] then
        check(F.count(q,"BuildObject")==0,"guest never spawns")
        check(F.count(q,"SetPosition","cr16_transport")>0,"guest moves its local scene too")
    end
end
-- Local skip cannot speed up launch or remove actors left outside the hull.
w,p,m=setup(2);F.kill("alien_hq");F.kill("alien_hangar");F.run(2)
w.cancel=true;F.run(3);w.cancel=false
check(not m.won and m.cr16.finale=="boarding","camera skip leaves shared state running")
check(F.alive("cr16_evac1"),"skip never teleports/removes exposed evacuee")
F.run(90)
check(m.won and F.alive("cr16_evac1"),"stranded actor cannot gate win and is left in place")
-- Texas loss wins a simultaneous combat-objective tie.
w,p,m=setup(1);F.kill("alien_hq");F.kill("alien_hangar");F.kill("avrecy0_recycler");F.run(2)
check(m.lost and not m.won and not m.cr16.victory,"Texas loss has tie precedence")
check(F.count(p[1],"FailMission")==1 and F.count(p[1],"SucceedMission")==0,"one loss result")
-- Destruction of the optional ship cannot block the completed assault.
w,p,m=setup(1);F.kill("cr16_transport");F.kill("alien_hq");F.kill("alien_hangar");F.run(2)
check(m.won and F.count(p[1],"SucceedMission")==1,"missing transport degrades to victory")
-- Save/load during the finale keeps the boarding latch and clock.
w,p,m=setup(1);F.kill("alien_hq");F.kill("alien_hangar");F.run(3)
local before=F.heardCount(p[1],"misn1615.wav")
p[1].env.Load(m);F.run(90)
check(m.won and F.heardCount(p[1],"misn1615.wav")==before,"load resumes finale without replaying boarding VO")
-- A late actor cannot disappear beside a ship that is already lifting off.
w,p,m=setup(1);F.kill("alien_hq");F.kill("alien_hangar");F.run(53)
F.nearTo("cr16_evac1","cr16_board");F.run(1)
check(m.cr16.finale=="launch" and F.alive("cr16_evac1"),"boarding closes before launch; late survivors stay visible")
-- All humans observing both off-map entries postpone arrivals.
w,p,m=setup(2)
F.nearTo(p[1].player,"cr16_enemy_a");F.nearTo(p[2].player,"cr16_enemy_b")
F.run(45)
check(F.count(p[1],"BuildObject")==0,"watched enemy sites defer spawns")
for _,q in ipairs(p) do F.nearTo(q.player,"avrecy0_recycler") end
F.run(2)
check(F.count(p[1],"BuildObject")>0,"hidden arrivals recover")
check(#F.builds(p[1],0,"crfraz")==2,"recurring wave is a pair of restored fighters")
-- Do not steal a player's view while the new enemy is fighting nearby.
w,p,m=setup(1)
local foe=F.spawn("crfraz",6,0,0);F.nearTo(foe,p[1].player)
F.kill("alien_hq");F.kill("alien_hangar");F.run(2)
check(not m.cr16.sceneCamera,"nearby restored fighter prevents optional finale camera")
print("misn16 scene: "..n.." checks passed")
