-- Full authored Achilles placement fixture. CPU/model test, not an FPS claim.
assert(_VERSION=="Lua 5.1")
package.path="Scripts/?.lua;"..package.path
local t,builds,drains=0,0,0
GetTime=function() return t end
package.loaded.exu={SetExplosionEventsEnabled=function() return true end,
    DrainExplosionEvents=function() drains=drains+1;return {},0 end,
    CreateStaticGeometry=function(_,_,_,instances) builds=builds+1;return {instanceCount=#instances} end,
    DestroyStaticGeometry=function() builds=builds+1;return true end}
local D=require("CRFloraDamage")
local sites=require("CRJungle17Sites")
local all,names={},{}
local started=os.clock()
for li,l in ipairs(sites.layers) do
    if l.mesh:find("^cr17_mire_") or l.mesh:find("^cr17_fl_") then
        local name="stress/"..li;names[#names+1]=name
        D.Register(name,{mesh=l.mesh,points=l.instances,options={}});D.Resident(name,true)
        for pi,p in ipairs(l.instances) do all[#all+1]={name=name,index=pi,p=p} end
    end
end
local registration=os.clock()-started
local blasts={}
for i=1,96 do
    local p=all[math.floor((i-1)*#all/96)+1].p
    local e={x=p[1],y=p[2],z=p[3],radius=16,odf="xcarxpl"}
    assert(D.Notify(e));blasts[#blasts+1]=e
end
started=os.clock()
for _=1,1500 do
    t=t+.101;local prior=D.Describe().candidates;local b=builds
    D.Update()
    assert(D.Describe().candidates-prior<=192,"candidate slice exceeded")
    assert(builds-b<=1,"multiple layer rebuilds in one slice")
    local d=D.Describe();if d.pending==0 and d.dirty==0 then break end
end
local processing=os.clock()-started
local expected=0
for _,a in ipairs(all) do
    local gone=false
    for _,e in ipairs(blasts) do
        if (a.p[1]-e.x)^2+(a.p[2]-e.y)^2+(a.p[3]-e.z)^2<=e.radius^2 then gone=true;break end
    end
    assert(D.IsRemoved(a.name,a.index)==gone,"spatial index differs from full-scan reference")
    if gone then expected=expected+1 end
end
local state=D.Describe()
assert(state.pending==0 and state.dirty==0 and state.removed==expected,"burst failed to settle")
local before=drains;started=os.clock()
for _=1,10000 do D.Update() end
local idle=os.clock()-started
assert(drains==before,"same-time frame calls defeated timer")
for _,name in ipairs(names) do D.Unregister(name) end
print(string.format("CRFLORA STRESS OK: %d plants/%d layers, 96 blasts, %d removed, %d rebuilds; host register=%.2fms, sliced CPU=%.2fms, 10000 timer-gated calls=%.2fms (no Ogre)",
    #all,#names,expected,builds,registration*1000,processing*1000,idle*1000))
