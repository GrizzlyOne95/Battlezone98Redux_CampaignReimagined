-- Weather ownership and resource lifetime; native appearance is tested separately.
assert(_VERSION=="Lua 5.1")
local n,now,changes,builds,destroys,sounds=0,0,{},0,0,0
local function check(v,s) assert(v,s);n=n+1 end
local function noop() end
GetTime=function() return now end
SetVector=function(x,y,z) return {x=x,y=y,z=z} end
StartSound=function() sounds=sounds+1;return sounds end
StopSound=noop
local alive={}
IsAlive=function(h) return alive[h]~=false end
local wind,windSpeed,intensity,splashWind
local W={Init=noop,Update=noop,Shutdown=noop,
    SetPreset=function(name) changes[#changes+1]=name end,
    SetWindOverride=function(d,s) wind=d;windSpeed=s end,ClearWindOverride=function() wind=nil end,
    SetIntensity=function(s) intensity=s end}
local P={Presets={AcidRainVisual={precipitation={{emitters={[0]={}}}}},
    VenusDenseAtmosphere={precipitation={{system="cr_wx_venus_dense_mist",affectors={[0]={},[1]={rate={0,1.25}}}}}}}}
local sites={water={mesh="river.mesh",position={1500,0,99600}},cascade={1490,200,99620},
    streams={mesh="streams.mesh",position={1500,0,99600}},pools={mesh="pools.mesh",position={1500,0,99600}},
    layers={{mesh="fern.mesh",instances={{1,2,3,0,1}}},{mesh="tree.mesh",instances={{4,5,6,1,2}}}}}
local sky={plane=false,clones={},enabled=nil,scroll=nil}
local modules={CRWeather=W,CRWeatherPresets=P,CRJungle17Sites=sites,
    CRSplash={Set=noop,Update=noop,Stop=noop,SetWind=function(x,z,s) splashWind=s end},
    CRWetGlass={Update=noop,Stop=noop},
    CRParticleTemplates={EnsureExtra=function() return true end},
    Environment={RegisterEnvironmentModifier=noop}}
local env=setmetatable({require=function(k) return assert(modules[k],k) end},{__index=_G})
local built={}
local m={}
local api={state=function() return m end,exu={CreateStaticGeometry=function(name,mesh,mat,instances,options)
    check(options.origin.z>97000,"static geometry origin follows offset simulation map")
    check(#instances<=256,"static batches bounded")
    check(options.renderingDistance<=360,"culling bounded")
    builds=builds+1;built[name]=true;return {instanceCount=#instances}
end,DestroyStaticGeometry=function(name) destroys=destroys+1;built[name]=nil end,
CreateParticleSystem=function() return true end,DestroyParticleSystem=noop,
MaterialExists=function(name) return name=="ACLOUD2.MAP" or sky.clones[name]==true end,
CloneMaterial=function(base,name) sky.clones[name]=true;return true end,
SetSkyPlane=function(mat) sky.plane=mat;return true end,
SetSkyPlaneEnabled=function(on) sky.enabled=on end,
GetSkyPlaneEnabled=function() return false end,GetSkyDomeEnabled=function() return false end,
GetSkyBoxEnabled=function() return false end,
SetMaterialTextureScrollAnimation=function(mat,u) sky.scroll=u end}}
local J=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create(api)
check(P.Presets.AchillesJungle0 and P.Presets.AchillesJungle4,"five storm rungs registered")
check(P.Presets.AchillesJungle4.precipitation[1].emitters[0].rate>P.Presets.AchillesJungle1.precipitation[1].emitters[0].rate,"rain deepens with level")
check(P.Presets.AchillesJungle4.fog.fogEnd<P.Presets.AchillesJungle1.fog.fogEnd,"fog closes in with level")
check(P.Presets.AchillesJungle4.windSpeed>P.Presets.AchillesJungle0.windSpeed,"wind builds with level")
local mist=P.Presets.AchillesJungle2.precipitation[2]
check(mist and mist.system=="cr17_wx_basin_mist" and mist.terrainPool==nil or mist.system=="cr17_wx_basin_mist","basin mist layer shares one system name")
check(P.Presets.VenusDenseAtmosphere.precipitation[1].system=="cr_wx_venus_dense_mist","shared Venus preset unchanged")
J.Reset()
check(J.Initialized and J.GetSeverity()==0,"reset establishes neutral sensor provider")
local sent={}
local function send(kind,...)
    sent[#sent+1]={kind,...}
    for _,v in ipairs({...}) do check(type(v)=="number","weather packets carry numbers only") end
    J.Apply(kind,...)
end
J.Update(.1,false,function() error("guest sent weather") end)
check(#changes==0,"guest waits for leader weather")
J.Update(.1,true,send)
check(changes[1]=="AchillesJungle1","leader opens with jungle rain")
check(J.Describe().level==1 and math.abs(intensity-.35)<1e-6,"opening approach is light rain")
check(wind and windSpeed>0 and splashWind==windSpeed,"wind override and splash slant follow the leader")
check(J.Describe().clouds=="off" and not sky.enabled,"no storm deck in light rain")
check(J.Describe().batches==2 and J.Describe().river and J.Describe().mist,"geometry and cascade layers build")
check(J.Describe().streams and J.Describe().pools,"terrain streams and standing pools build")
local count=#sent
J.Update(1,true,send)
check(#sent==count,"no resend without a change")
-- Towers start falling: downpour, deepening per loss.
m.tower1dead=true;J.Update(.1,true,send)
check(J.Describe().level==2 and changes[#changes]=="AchillesJungle2","first tower loss brings downpour")
local first=intensity
m.tower2dead=true;J.Update(.1,true,send)
check(intensity>first and #changes==2,"each loss deepens without changing preset")
check(J.Describe().clouds=="on" and sky.enabled and sky.plane=="CR17/StormCloud","storm cloud deck rolls in")
check(sky.scroll and sky.scroll>0,"cloud deck drifts with the wind")
check(J.GetSeverity()==.5,"sensor severity follows level")
-- Timed resync for late joiners.
count=#sent;now=now+16;J.Update(16,true,send)
check(#sent>count and sent[#sent][1]=="level","leader periodically resyncs level")
-- All towers down: storm with lightning.
m.towersdestroyed=true;m.minesdestroyed=true;J.Update(.1,true,send)
check(J.Describe().level==3,"tower collapse brings the storm")
local bolts=0;for _,s in ipairs(sent) do if s[1]=="bolt" then bolts=bolts+1 end end
check(bolts==0,"first bolt waits a beat after the storm arrives")
now=now+5;J.Update(5,true,send)
local function countBolts() local c=0;for _,s in ipairs(sent) do if s[1]=="bolt" then c=c+1 end end;return c end
check(countBolts()==1,"storm lightning strikes")
local a=sounds;now=now+3;J.Update(3,false,noop)
check(sounds>a,"delayed thunder plays locally")
now=now+5;J.Update(5,true,send)
check(countBolts()==1,"storm lightning keeps a 13 second cadence")
local saved=J.Save()
check(saved.age>20 and saved.level==3 and saved.nextBolt>saved.age,"level and lightning survive save")
-- Overload: tempest with rapid lightning.
m.cr17Crystals={phase="overload"};J.Update(.1,true,send)
check(J.Describe().level==4 and J.GetSeverity()==1 and intensity==1,"converter overload brings the tempest")
local b=countBolts();now=now+20;for i=1,20 do now=now+1;J.Update(1,true,send) end
check(countBolts()-b>=4,"tempest lightning is frequent")
m.cr17Crystals=nil
-- Converter destroyed by the stock route.
alive[77]=false;m.factorypart1=77;J.Update(.1,true,send)
check(J.Describe().level==4,"a fallen converter keeps the tempest")
-- Result latches: clearing.
m.missionwon=true;J.Update(.1,true,send)
check(J.Describe().level==0 and changes[#changes]=="AchillesJungle0","victory clears the storm")
check(J.Describe().clouds=="off" and sky.enabled==false,"clearing removes our cloud deck")
-- Load resumes from the leader without a drizzle restart.
J.Reset(saved)
check(destroys>=5,"load clears old static groups and water")
m.missionwon=nil;m.factorypart1=nil
J.Update(.1,true,send)
check(J.Describe().level==3,"load resumes storm rather than restarting drizzle")
-- Legacy phase packets from the timer prototype.
J.Apply("phase",2)
check(J.Describe().level==2,"legacy phase packet maps onto levels")
J.Stop()
check(not J.Initialized,"shutdown disables Environment sensor provider")
check(J.Describe().batches==0 and not J.Describe().river and not J.Describe().pools,"stop clears render resources")
check(next(built)==nil,"every static group destroyed")
check(wind==nil,"stop releases the wind override")
check(P.Presets.AcidRainVisual.precipitation[1].emitters[0].rate==nil,"shared acid rain preset unchanged")
-- A map that already owns a sky keeps it.
local own=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create({state=function() return {towersdestroyed=true} end,
    exu={SetSkyPlane=function() error("replaced map sky") end,SetSkyPlaneEnabled=noop,
    GetSkyDomeEnabled=function() return true end}})
own.Reset();own.Update(.1,true,function(k,...) own.Apply(k,...) end)
check(own.Describe().clouds=="skipped","existing map sky is never replaced")
own.Stop()
local missing=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create({exu={}})
missing.Reset();missing.Update(.1,false,noop)
check(missing.Describe().error~=nil,"missing optional geometry API reports degraded presentation")
missing.Stop()
print("misn17 jungle: "..n.." checks passed")
