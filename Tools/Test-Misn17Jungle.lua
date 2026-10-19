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
-- Stock geyser paths beside the three converter parts (Misn17Fixture).
local paths={part1geizer={3027.2,155,101454},part2geizer={3095.2,155,101454},part3geizer={3149.9,155,101456}}
local player={x=0,y=0,z=0}
GetPosition=function(what)
    if what=="player" then return player end
    local p=assert(paths[what],tostring(what));return {x=p[1],y=p[2],z=p[3]}
end
GetPlayerHandle=function() return "player" end
IsValid=function(h) return h~=nil end
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
local modifiers,systems,rates={},{},{}
local foliage={registered={},litter=nil}
local Foliage={Register=function(m,o) foliage.registered[m]=o.slot;return true end,
    EnableLitter=function(points,o) foliage.litter={points=#points,rate=o.rate} end,
    Describe=function() return {materials=0} end}
local wakeLog={init=0,stop=0,updates=0}
local WakeStub={Init=function(o) wakeLog.init=wakeLog.init+1;wakeLog.opts=o end,
    Stop=function() wakeLog.stop=wakeLog.stop+1 end,Update=function() wakeLog.updates=wakeLog.updates+1 end}
local modules={CRWake=WakeStub,CRWeather=W,CRWeatherPresets=P,CRJungle17Sites=sites,
    CRSplash={Set=noop,Update=noop,Stop=noop,SetWind=function(x,z,s) splashWind=s end},
    CRWetGlass={Update=noop,Stop=noop},
    CRParticleTemplates={EnsureExtra=function() return true end},
    Environment={RegisterEnvironmentModifier=function(name,f) modifiers[name]=f end},CRFoliageWind=Foliage}
local env=setmetatable({require=function(k) return assert(modules[k],k) end},{__index=_G})
local built={}
local m={}
local api={state=function() return m end,exu={CreateStaticGeometry=function(name,mesh,mat,instances,options)
    check(options.origin.z>97000,"static geometry origin follows offset simulation map")
    check(#instances<=256,"static batches bounded")
    check(options.renderingDistance<=360,"culling bounded")
    builds=builds+1;built[name]=true;return {instanceCount=#instances}
end,DestroyStaticGeometry=function(name) destroys=destroys+1;built[name]=nil end,
CreateParticleSystem=function(name,template,p) systems[name]={template=template,p=p};return true end,
DestroyParticleSystem=function(name) systems[name]=nil end,
SetParticleEmitterEmissionRate=function(name,i,r) rates[name]=r end,
MaterialExists=function(name) return name=="CR17/StormCloud" end,
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
check(foliage.registered["CR17/LeavesWind"]=="emissive" and foliage.registered["CR17/GroundWind"]=="emissive"
    and foliage.registered["CR17/CutoutCaster/FoliageWind"]=="emissive","canopy, ground cover and caster sway on the emissive feed")
check(foliage.litter and foliage.litter.points==2 and foliage.litter.rate>0,"leaf litter is seeded from every ground-cover placement")
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
check(next(sky.clones)==nil,"cloud deck uses its own shader, never an Effect-program clone")
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
check(countBolts()==1 and J.Describe().bolts==1,"storm lightning strikes")
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
-- Core vents: a fallen converter part opens a fire vent on its geyser path.
local function ventPackets() local c={};for _,s in ipairs(sent) do if s[1]=="vents" then c[#c+1]=s[2] end end;return c end
check(J.Describe().ventsLit==0 and #ventPackets()==0,"no vent while every converter part stands")
m.factorypart2dead=true;J.Update(.1,true,send)
local vp=ventPackets()
check(vp[#vp]==2 and J.Describe().ventsLit==1,"leader announces the fallen part and lights its vent")
local flame=systems["CR17/Core2/VentFlame"]
check(flame and flame.template=="CR17/VentFlame" and flame.p.x==3095.2 and flame.p.y==155,"vent stands on the part's stock geyser path")
check(systems["CR17/Core2/VentLick"] and systems["CR17/Core2/VentSmoke"] and systems["CR17/Core2/VentPool"]
    and systems["CR17/Core2/VentSpatter"],"vent builds flame, licks, smoke, glow pool and spatter")
check(not systems["CR17/Core1/VentFlame"] and not systems["CR17/Core3/VentFlame"],"standing parts keep their pits closed")
J.Update(.1,true,send)
check(#ventPackets()==#vp,"no vent resend without a change")
local calm=rates["CR17/Core2/VentSpatter"]
now=now+9;J.Update(.1,true,send)
check(calm<10 and rates["CR17/Core2/VentSpatter"]>50,"vent surges throw lava")
check(J.Describe().ventGlow==0,"a distant vent does not light the pilot")
player={x=3100,y=155,z=101460};J.Update(.1,true,send)
check(J.Describe().ventGlow>.5,"standing by a vent lights the pilot")
local frame={ambient={r=.1,g=.1,b=.1}};modifiers.CR17Lightning(frame)
check(frame.ambient.r-.1>frame.ambient.b-.1+.2,"vent light is fire-red")
player={x=0,y=0,z=0}
count=#ventPackets();now=now+16;J.Update(16,true,send)
check(#ventPackets()==count+1,"leader resyncs open vents for late joiners")
local ventSave=J.Save()
check(ventSave.vents==2,"open vents survive save")
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
local leftover=false;for k in pairs(systems) do if k:find("^CR17/Core") then leftover=true end end
check(not leftover,"stop puts out every vent")
J.Reset(ventSave);J.Update(.1,false,noop)
check(J.Describe().ventsLit==1 and systems["CR17/Core2/VentFlame"],"load relights open vents before the leader resyncs")
J.Stop()
-- A guest lights what the leader announces; a stale mask never closes a vent.
local G=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create({exu=api.exu,state=function() error("guest read mission state") end})
G.Reset();G.Update(.1,false,noop)
check(G.Describe().ventsLit==0,"guest waits for the leader's vents")
G.Apply("vents",1);G.Update(.1,false,noop)
check(G.Describe().ventsLit==1 and systems["CR17/Core1/VentFlame"],"guest lights the announced vent")
G.Apply("vents",0);G.Apply("vents",6);G.Update(.1,false,noop)
check(G.Describe().vents==7 and G.Describe().ventsLit==3,"vents only ever open")
G.Apply("vents",99);G.Apply("vents","7")
check(G.Describe().vents==7,"malformed vent packets are ignored")
G.Stop()
-- With EXU point lights each vent gets a real light and leaves the ambient alone.
local lights={}
local lexu=setmetatable({CreatePointLight=function(name,p,c,range)
        if lights[name] then return false end
        lights[name]={p=p,c=c,range=range,power=1};return true end,
    SetPointLightPowerScale=function(name,s) if not lights[name] then return false end;lights[name].power=s;return true end,
    DestroyPointLight=function(name) local had=lights[name]~=nil;lights[name]=nil;return had end},{__index=api.exu})
local L=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create({exu=lexu,state=function() error("guest read mission state") end})
L.Reset();L.Apply("vents",2);L.Update(.1,false,noop)
local lamp=lights["CR17/Core2/Light"]
check(lamp and lamp.p.x==3095.2 and lamp.p.y>155 and lamp.range>=40 and lamp.range<=120,"vent lights a point light above its pit")
check(lamp and lamp.c.r==1 and lamp.c.r>lamp.c.g and lamp.c.g>lamp.c.b,"vent light is fire-coloured")
check(L.Describe().ventLights==1,"describe counts vent lights")
local idle=lamp.power;now=now+9;L.Update(.1,false,noop)
check(lamp.power>idle,"vent light flares with the surge")
player={x=3100,y=155,z=101460};L.Update(.1,false,noop)
local lit={ambient={r=.1,g=.1,b=.1}};modifiers.CR17Lightning(lit)
check(L.Describe().ventGlow==0 and lit.ambient.r==.1,"a real light replaces the ambient tint")
player={x=0,y=0,z=0}
L.Stop()
check(next(lights)==nil,"stop destroys vent lights")
L.Reset({vents=2});L.Update(.1,false,noop)
check(lights["CR17/Core2/Light"]~=nil,"load relights the vent light")
L.Stop()
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
-- Vehicle wakes: the shared module is initialised with the Achilles surface
-- resolver (water over the river corridor, grass elsewhere) and stopped with it.
check(wakeLog.init>=1 and type(wakeLog.opts.surface)=="function","reset initialises vehicle wakes")
check(wakeLog.opts.surfaces[1]=="water" and wakeLog.opts.surfaces[2]=="grass","both Achilles surfaces are loaded")
sites.river={{1440,99480},{1450,99520},{1470,99570}}
-- Stream and pool water come from the generated run-length mask: rows[i] is grid row
-- firstRow+i-1, runs are {startCol,length}; cells are centred on col*5 and row*5+originZ.
sites.watermask={cell=5,originX=0,originZ=97280,firstRow=100,rows={{40,3},{},{10,2,20,4}}}
check(J.WakeSurface(41*5,(100+0)*5+97280)=="water","a stream cell in the mask is water")
check(J.WakeSurface(21*5,(102)*5+97280)=="water","a pool cell in the mask is water")
check(J.WakeSurface(43*5,100*5+97280)=="grass","the cell just past a run is grass")
check(J.WakeSurface(41*5,101*5+97280)=="grass","an empty mask row is grass")
check(J.WakeSurface(21*5,99*5+97280)=="grass","a row above the mask is grass")
sites.watermask=nil
local s1,_,lift=J.WakeSurface(1450,99520)
check(s1=="water" and lift>0,"a craft on the river route is over water, lifted to the surface")
check(J.WakeSurface(1450+6,99520)=="water","inside the river half-width is water")
check(J.WakeSurface(1450+12,99520)=="grass","beyond the bank is grass")
check(J.WakeSurface(1465,99540)=="water","between route points is water")
local sg,scale=J.WakeSurface(1,2)
check(sg=="grass" and scale>=.6,"ground cover raises the grass rate")
local _,bare=J.WakeSurface(3000,100000)
check(bare<scale,"bare ground gets a thinner wake")
sites.river=nil
local before=wakeLog.updates
J.Update(.1,false,noop)
check(wakeLog.updates==before+1,"update drives the wake scan")
J.Stop()
check(wakeLog.stop>=1,"stop stops the wakes")
local off=setfenv(assert(loadfile("Scripts/CRJungle17.lua")),env)().Create({exu={},vehicleWakes=false})
local initsBefore=wakeLog.init
off.Reset();off.Stop()
check(wakeLog.init==initsBefore,"vehicleWakes=false never initialises the wakes")
print("misn17 jungle: "..n.." checks passed")
