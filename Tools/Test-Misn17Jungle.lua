-- Weather ownership and resource lifetime; native appearance is tested separately.
assert(_VERSION=="Lua 5.1")
local n,now,changes,builds,destroys,sounds=0,0,{},0,0,0
local function check(v,s) assert(v,s);n=n+1 end
local function noop() end
GetTime=function() return now end
SetVector=function(x,y,z) return {x=x,y=y,z=z} end
StartSound=function() sounds=sounds+1;return sounds end
StopSound=noop
local W={Init=noop,Update=noop,Shutdown=noop,
    SetPreset=function(name) changes[#changes+1]=name end}
local P={Presets={AcidRainVisual={precipitation={{emitters={[0]={}}}}}}}
local sites={water={mesh="river.mesh",position={1500,0,99600}},cascade={1490,200,99620},
    layers={{mesh="fern.mesh",instances={{1,2,3,0,1}}},{mesh="tree.mesh",instances={{4,5,6,1,2}}}}}
local modules={CRWeather=W,CRWeatherPresets=P,CRJungle17Sites=sites,
    CRSplash={Set=noop,Update=noop,Stop=noop},CRWetGlass={Update=noop,Stop=noop},
    CRParticleTemplates={EnsureExtra=function() return true end},
    Environment={RegisterEnvironmentModifier=noop}}
local env=setmetatable({require=function(k) return assert(modules[k],k) end},{__index=_G})
local api={exu={CreateStaticGeometry=function(name,mesh,mat,instances,options)
    check(options.origin.z>97000,"static geometry origin follows offset simulation map")
    check(#instances<=256,"static batches bounded")
    check(options.renderingDistance<=300,"culling bounded")
    builds=builds+1;return {instanceCount=#instances}
end,DestroyStaticGeometry=function() destroys=destroys+1 end,
CreateParticleSystem=function() return true end,DestroyParticleSystem=noop}}
local J=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create(api)
J.Reset()
check(J.Initialized and J.GetSeverity()==0,"reset establishes neutral sensor provider")
local function send(kind,a,b) J.Apply(kind,a,b) end
J.Update(.1,false,function() error("guest sent weather") end)
check(#changes==0,"guest waits for leader weather")
J.Update(.1,true,send)
check(changes[1]=="AchillesJungle1","leader establishes gentle rain")
check(J.GetSeverity()==0,"gentle first rung keeps clear sensor scales")
check(J.Describe().batches==2 and J.Describe().river and J.Describe().mist,"geometry and cascade layers build")
now=56;J.Update(56,true,send)
check(changes[#changes]=="AchillesJungle3","storm escalates on shared clock")
check(J.GetSeverity()==1,"shared heavy storm drives full sensor severity")
local saved=J.Save()
check(saved.age>55 and saved.nextBolt==68,"weather age and next lightning survive save")
J.Reset(saved)
check(destroys>=3,"load clears old static groups")
J.Update(.1,true,send)
check(J.Describe().phase==3,"load resumes storm rather than restarting drizzle")
now=70;J.Update(14,true,send)
check(J.Save().nextBolt>70,"lightning deadline advances once")
local a=sounds;now=73;J.Update(3,false,noop)
check(sounds>a,"delayed thunder plays locally")
J.Stop()
check(not J.Initialized,"shutdown disables Environment sensor provider")
check(J.Describe().batches==0 and not J.Describe().river,"stop clears render resources")
check(P.Presets.AcidRainVisual.precipitation[1].emitters[0].rate==nil,"shared Venus preset unchanged")
local missing=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create({exu={}})
missing.Reset();missing.Update(.1,false,noop)
check(missing.Describe().error~=nil,"missing optional geometry API reports degraded presentation")
missing.Stop()
print("misn17 jungle: "..n.." checks passed")
