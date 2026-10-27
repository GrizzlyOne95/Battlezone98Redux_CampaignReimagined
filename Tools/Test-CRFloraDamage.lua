assert(_VERSION=="Lua 5.1")
package.path="Scripts/?.lua;"..package.path
local clock,drains,enabled,creates,destroys=0,0,false,{},{}
local events,fail={},false
GetTime=function() return clock end
Send=function() error("flora must never send network messages") end
AllObjects=function() error("flora must never scan game objects") end
local exu={
    SetExplosionEventsEnabled=function(on) enabled=on;return true end,
    DrainExplosionEvents=function(limit) drains=drains+1;local out=events;events={};return out,0 end,
    CreateStaticGeometry=function(name,mesh,material,points,options)
        creates[#creates+1]={name=name,points=points,time=clock}
        if fail then return nil,"fixture failure" end
        return {instanceCount=#points}
    end,
    DestroyStaticGeometry=function(name) destroys[#destroys+1]=name;return true end,
}
package.loaded.exu=exu
local D=require("CRFloraDamage")
local n=0
local function check(v,msg) assert(v,msg);n=n+1 end
local function tick(t) clock=clock+t;D.Update() end
local function point(x,y,z) return {x,y or 0,z or 0,0,1} end
local function spec(points,remove) return {mesh="grass.mesh",points=points,onRemove=remove,options={}} end
local function blast(x,r,y) return {x=x,y=y or 0,z=0,radius=r or 16,odf="xcarxpl"} end
check(D.Radius({odf="xbulgnd",radius=0})==1.25,"ground bullets have a bounded footprint")
check(D.Radius({odf="smoke",radius=0})==nil,"cosmetic smoke is not a blast")
check(D.Radius(blast(0,2000))==64,"very large stock blast classes are capped")
check(not D.Notify({radius=10,x=0/0,y=0,z=0}),"invalid native position rejected")
D.Update();check(drains==0,"no layers means no native poll")
local removed=0
local saved=D.Register("meadow",spec({point(0),point(4),point(50)},function() removed=removed+1 end))
D.Resident("meadow",true)
check(enabled,"only flora users opt into native collection")
events={blast(0,16),blast(0,16)};tick(.1)
check(removed==2 and D.IsRemoved("meadow",1) and D.IsRemoved("meadow",2),"repeated blast removes each plant once")
check(#creates==0,"deferred rebuild outside event processing")
for _=1,100 do D.Update() end
check(drains==1,"native poll throttled even with many frame updates")
tick(.35)
check(#creates==1 and #creates[1].points==1,"coalesced replacement preserves the distant plant")
check(creates[1].points[1].position.x==50,"exact survivors passed to Ogre")
D.Notify(blast(50,8));tick(.11);tick(.35)
check(#destroys==1,"empty batch destroyed rather than submitting an invalid empty build")
D.Unregister("meadow");check(not enabled,"last provider releases native collection")
saved=D.Register("meadow",spec({point(0),point(4),point(50)}),saved)
check(#D.Instances("meadow")==0,"all removals persist when streamed/reloaded")
D.Unregister("meadow")
D.Register("meadow",spec({point(0),point(4),point(51)}),saved)
check(#D.Instances("meadow")==3,"changed placement signature cannot delete unrelated new plants")
D.Unregister("meadow")
local stream=D.Register("stream",spec({point(0),point(80)}))
D.Notify(blast(0));tick(.11);tick(.35)
check(#D.Instances("stream")==1,"unbuilt streamed layer records offscreen damage")
check(#creates==1,"unresident layer is not needlessly rebuilt")
D.Resident("stream",true);D.Notify(blast(80));tick(.11);tick(.35)
check(#destroys==2,"future resident batch can become empty")
D.Unregister("stream")
D.Register("air",spec({point(0)}));D.Resident("air",true)
D.Notify(blast(0,16,100));tick(.11);tick(.35)
check(not D.IsRemoved("air",1),"high airburst does not clear ground outside its sphere")
D.Unregister("air")
D.Register("retry",spec({point(0),point(50)}));D.Resident("retry",true)
fail=true;D.Notify(blast(0));tick(.11);tick(.35)
local attempts=#creates
check(D.Describe().failures==1,"failed replacement recorded")
tick(1);check(#creates==attempts,"failed Ogre layer backs off")
fail=false;tick(5);check(#creates==attempts+1 and #creates[#creates].points==1,"retry reconstructs survivors without regrowth")
D.Unregister("retry")
-- Dense fixture proves per-service candidate work is capped, not just event count.
local dense={};for i=1,1000 do dense[i]=point(0) end
D.Register("dense",spec(dense));D.Resident("dense",true)
local before=D.Describe().candidates
D.Notify(blast(0));tick(.11)
check(D.Describe().candidates-before<=192,"dense bucket work budget enforced")
for _=1,12 do tick(.11) end
check(#D.Instances("dense")==0,"sliced dense query eventually completes")
D.Unregister("dense")
-- Two independently dirtied layers get at most one replacement per service call.
for _,name in ipairs({"one","two"}) do D.Register(name,spec({point(0),point(50)}));D.Resident(name,true) end
D.Notify(blast(0));tick(.11);local count=#creates;tick(.35)
check(#creates==count+1,"only one layer replaced in a service slice")
tick(.21);check(#creates==count+2,"second layer eventually rebuilt")
D.Unregister("one");D.Unregister("two")
print("CRFLORA DAMAGE OK ("..n.." checks)")
