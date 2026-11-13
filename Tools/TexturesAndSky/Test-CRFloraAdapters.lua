-- Exercises actual provider modules with the real removal service; no engine.
assert(_VERSION=="Lua 5.1")
package.path="Scripts/?.lua;"..package.path
local time,events,builds,removed=0,{}, {},0
GetTime=function() return time end
SetVector=function(x,y,z) return {x=x,y=y,z=z} end
GetTerrainHeightAndNormal=function() return 0,SetVector(0,1,0) end
local exu={SetExplosionEventsEnabled=function() return true end,
    DrainExplosionEvents=function() local out=events;events={};return out,0 end,
    CreateStaticGeometry=function(name,mesh,material,instances,options)
        builds[#builds+1]={name=name,count=#instances};return {instanceCount=#instances}
    end,DestroyStaticGeometry=function() return true end,
    DestroyAllStaticGeometry=function() return 0 end}
package.loaded.exu=exu
local D=require("CRFloraDamage")
local T=require("TerrainClutter")
local spec={name="MoonGrass",mesh="grass.mesh",material="grass",center=SetVector(0,0,0),radius=1,
    density=10,maxInstances=12,minScale=1,maxScale=1}
assert(T.BuildLayer(spec))
events={{odf="xcarxpl",x=0,y=0,z=0,radius=20}}
for _=1,8 do time=time+.11;D.Update() end
assert(#D.Instances("MoonGrass")==0,"TerrainClutter damage reaches all plants")
local saved=T.Save();T.Load(saved)
local count=#builds
assert(T.BuildLayer(spec));assert(#builds==count,"restoring empty TerrainClutter does not regrow or upload source plants")
T.Shutdown()
local Ground=require("CRStorm18Ground")
local localSaved={}
local ctx={sites={origin={0,0,0},layers={{mesh="scrub.mesh",cx=0,cz=0,instances={{0,0,0,0,1},{50,0,0,0,1}}}}},
    flora=localSaved,clock=function() return time end,material=function() return "scrub" end,
    vec=SetVector,removeLitter=function() removed=removed+1 end,ready=function() return false end,
    call=function(name,...) local f=exu[name];if f then return f(...) end end,
    call2=function(name,...) local f=exu[name];if f then return f(...) end end}
local g=Ground.Create(ctx)
g.Update(.1,{x=0,y=0,z=0},0)
events={{odf="xmslgnd",x=0,y=0,z=0,radius=10}}
for _=1,8 do time=time+.11;g.Update(.11,{x=0,y=0,z=0},0) end
assert(#D.Instances("CR18/Scrub/1")==1 and removed==1,"streamed scrub loses only struck plant and litter")
time=time+1;g.Update(.1,{x=2000,y=0,z=0},0)
assert(g.Describe().tiles==0,"scrub streams out")
time=time+1;g.Update(.1,{x=0,y=0,z=0},0)
assert(builds[#builds].count==1,"streaming back in preserves removed plant")
g.Stop();g=Ground.Create(ctx)
time=time+1;g.Update(.1,{x=0,y=0,z=0},0)
assert(builds[#builds].count==1,"reloading scrub uses client save membership")
g.Stop()
-- Real Mission 17 adapter: only plant prefixes register; rocks stay untouched.
local function noop() end
local litter=0
local modules={CRFloraDamage=D,CRWeather={Init=noop,Update=noop,Shutdown=noop,SetPreset=noop,
    SetWindOverride=noop,ClearWindOverride=noop,SetIntensity=noop},
    CRWeatherPresets={Presets={AcidRainVisual={precipitation={{emitters={[0]={}}}}}}},
    CRJungle17Sites={cascade={0,0,0},layers={
        {mesh="cr17_mire_fern.mesh",instances={{0,0,0,0,1},{50,0,0,0,1}}},
        {mesh="cr17_fl_flower.mesh",instances={{1,0,0,0,1},{50,0,0,0,1}}},
        {mesh="cr17_frock1.mesh",instances={{0,0,0,0,1}}}}},
    CRSplash={Set=noop,Update=noop,Stop=noop},CRWetGlass={Update=noop,Stop=noop},
    CRParticleTemplates={EnsureExtra=function() return false end},
    Environment={RegisterEnvironmentModifier=noop},
    CRFoliageWind={Register=noop,EnableLitter=noop,Describe=function() return {} end,
        RemoveLitterSource=function() litter=litter+1 end},
    CRWake={Stop=noop,Update=noop}}
local env=setmetatable({require=function(name) return assert(modules[name],name) end},{__index=_G})
local chunk=assert(loadfile("Scripts/CRJungle17.lua"));setfenv(chunk,env)
local j=chunk().Create({exu=exu,state=function() return {} end,vehicleWakes=false})
j.Reset()
for _=1,3 do time=time+.11;j.Update(.11,false,noop) end
assert(D.Has("CR17/Jungle/1") and D.Has("CR17/Jungle/2") and not D.Has("CR17/Jungle/3"),"only vegetation is registered")
events={{odf="xcarxpl",x=0,y=0,z=0,radius=10}}
for _=1,10 do time=time+.11;j.Update(.11,false,noop) end
assert(#D.Instances("CR17/Jungle/1")==1 and #D.Instances("CR17/Jungle/2")==1,"jungle flowers and ground cover independently filtered")
assert(litter==1,"flowers do not incorrectly subtract leaf litter")
local savedJungle=j.Save();j.Reset(savedJungle)
assert(#D.Instances("CR17/Jungle/1")==1,"jungle reset/save preserves bare patch")
j.Stop()
print("CRFLORA ADAPTERS OK (clutter, scrub stream/reload, jungle save and litter)")
