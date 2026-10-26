-- Real Environment + CRWeather composition over a mocked renderer, Lua 5.1.
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local function near(a,b) return math.abs(a-b) < 0.00001 end
local function copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local function world(palette, horizon)
    local w = {time=0, writes={}, systems={}, fog={r=0.02,g=0.02,b=0.02,fogStart=175,fogEnd=250}}
    local trn = {NormalView={Intensity=90,Ambient=0,Time=900,FogStart=175,FogEnd=250,VisibilityRange=horizon},
        Color={Palette=palette}, Sun_Diffuse={Red=0.7,Green=0.6,Blue=0.5}}
    local e = setmetatable({}, {__index=_G}); e._G=e
    e.print=function() end
    e.GetTime=function() return w.time end
    e.SetVector=function(x,y,z) return {x=x,y=y,z=z} end
    e.GetMapTRNFilename=function() return 'map.trn' end
    e.OpenODF=function() return trn end
    e.GetODFFloat=function(_,s,k,d) return trn[s] and trn[s][k] or d end
    e.GetODFInt=e.GetODFFloat; e.GetODFString=e.GetODFFloat
    e.AllCraft=function() return function() end end
    local exu={GetFog=function() return copy(w.fog) end,
        GetAmbientLight=function() return {r=0.12,g=0.12,b=0.12} end,
        GetSunDiffuse=function() return {r=0.88,g=0.88,b=0.88} end,
        GetSunSpecular=function() return {r=0.8,g=0.8,b=0.8} end,
        GetSunPowerScale=function() return 1 end,
        GetSunShadowFarDistance=function() return 250 end,
        GetSunDirection=function()
            local u=newproxy(true); getmetatable(u).__index={x=0.5,y=-0.8,z=0.3}; return u
        end,
        CreateParticleSystem=function(name) check(not w.systems[name], 'duplicate live particle system'); w.systems[name]=true; return true end,
        DestroyParticleSystem=function(name) w.systems[name]=nil end,
    }
    for _,name in ipairs({'SetAmbientLight','SetSunDiffuse','SetSunSpecular','SetFog','SetOgreSunDirection',
        'SetSunPowerScale','SetSunShadowFarDistance','SetViewportShadowsEnabled','SetTimeOfDay'}) do
        local n=name
        exu[n]=function(...) w.writes[#w.writes+1]={n,...}; w[n]={...} end
    end
    local modules={exu=exu,RuntimeEnhancements={Initialize=function() end,Update=function() end},
        CRParticleTemplates={Ensure=function() end}}
    e.require=function(name)
        if not modules[name] then modules[name]=setfenv(assert(loadfile('Scripts/'..name..'.lua')),e)() end
        return modules[name]
    end
    w.E=e.require('Environment'); w.W=e.require('CRWeather'); w.P=e.require('CRWeatherPresets')
    w.e,w.trn=e,trn
    return w
end

-- Moon: a captured native baseline, unchanged black horizon, small continuous
-- directional motion, and no night/sensor penalty. Results depend on game time,
-- not frame rate; revisiting the same saved time reproduces the same frame.
local w=world('moon.act',250)
w.E.Init({lightingMode='subtle',nativeBaseline=true,subtleDimming=0.06,subtleSunAngle=4})
w.E.Update(0); local start=copy(w.SetSunDiffuse); local direction=copy(w.SetOgreSunDirection)
check(near(start[1],0.88),'native Moon diffuse preserved')
check(near(w.SetFog[1],0.02) and near(w.SetFog[4],175) and near(w.SetFog[5],250),'Moon fog baseline preserved')
w.time=900; w.E.Update(0.001)
check(w.SetSunDiffuse[1] < start[1] and w.SetSunDiffuse[1] >= start[1]*0.94,'Moon dimming is subtle')
check(math.abs(w.SetOgreSunDirection[1]-direction[1])>0.001,'Moon sun actually moves')
check(w.E.NightBlend==0 and not w.E.IsNight,'subtle TOD never invokes night penalty')
local quarter=copy(w.SetSunDiffuse); w.time=1800; w.E.Update(100)
check(near(w.SetSunDiffuse[1],start[1]*0.94),'Moon minimum illumination is bounded')
w.time=900; w.E.Update(0)
check(near(w.SetSunDiffuse[1],quarter[1]),'load/time rewind reproduces lighting without accumulated dimming')
check(w.SetTimeOfDay==nil,'no quantized native hourly time writes')
local writeCount=#w.writes
w.E.Update(0)
check(#w.writes==writeCount,'identical live frame avoids redundant renderer writes')
w.E.InvalidateRenderer(); w.E.Update(0)
check(#w.writes>writeCount,'same-time load reapplies light/fog after renderer reconstruction')

-- Lunar night: the sun sits below the horizon for the sky, the Earth lights
-- the scene, and the airless horizon keeps its range in the dark.
w=world('moon.act',250)
w.trn.Atlases={MaterialName='MN_DETAIL_ATLAS'}
w.trn.Stars={Texture00='crearth.map',Azimuth00='90',Elevation00='30'}
w.E.Init({lightingMode='night',nativeBaseline=true,nightGameplay=false,skySun={azimuth=270,elevation=-20}})
w.E.Update(0)
local earth={x=math.cos(math.rad(30)),y=math.sin(math.rad(30))}
check(w.E.IsNight and w.E.NightBlend==1,'night mode holds full night')
check(near(w.SetOgreSunDirection[1],-earth.x) and near(w.SetOgreSunDirection[2],-earth.y),'the light falls from the Earth')
local diffuse=copy(w.SetSunDiffuse)
check(diffuse[3]>diffuse[1] and diffuse[3]>0.2 and diffuse[3]<0.5,'the earthlight is blue and moonlit, not daylight')
check(w.SetAmbientLight[3]<diffuse[3]*0.35,'shadows stay dark: the Earth is the light, not a fill')
check(near(w.SetFog[5],250) and w.SetFog[1]<0.01,'the dark keeps the airless horizon')
w.time=5000; w.E.Update(10)
check(near(w.SetSunDiffuse[3],diffuse[3]) and w.E.NightBlend==1,'lunar night does not end with game time')
w=world('moon.act',250)
w.E.Init({lightingMode='night',nativeBaseline=true,nightGameplay=false})
w.E.Update(0)
check(w.E.NightBlend==1 and w.SetSunDiffuse[3]<0.2,'night mode without a shining body falls back to the stock night')

-- Io: the sun's real path past a fixed Jupiter. One day runs through a short
-- eclipse, day, a horizon-sharp dusk and a Jupiter-lit night.
w=world('io.act',250)
w.trn.Atlases={MaterialName='io_detail_atlas'}
w.trn.Stars={Texture30='crjovian.map',Azimuth30='120',Elevation30='32'}
w.E.Init({lightingMode='orbit',orbit={period=1800,startHour=-75}})
check(w.E.LightingMode=='orbit' and w.E.Orbit and near(w.E.Orbit.period,1800),'Io keeps orbit mode')
local phases,eclipseTime,dayTime,nightTime,minDiffuse,nightWarm={},0,0,0,1,true
local last
for t=0,1800,2 do
    w.time=t; w.E.Update(2)
    local phase=w.E.LastPhase
    if phase~=last then phases[#phases+1]=phase; last=phase end
    if phase=='Eclipse' then eclipseTime=eclipseTime+2; minDiffuse=math.min(minDiffuse,w.SetSunDiffuse[1]) end
    if phase=='Day' then dayTime=dayTime+2 end
    if phase=='Night' then
        nightTime=nightTime+2
        nightWarm=nightWarm and w.SetSunDiffuse[1]>w.SetSunDiffuse[3]
    end
end
check(phases[1]=='Day' and phases[2]=='Eclipse' and phases[3]=='Day','the morning starts in sunlight and passes into eclipse')
check(eclipseTime>=60 and eclipseTime<=130,'the eclipse lasts about five per cent of the day ('..eclipseTime..' s)')
check(dayTime>500 and nightTime>600,'day and night each hold a large share of the cycle')
check(minDiffuse<0.2,'the eclipse darkens the scene')
check(nightWarm,'Jupiter-shine lights the night warm')
w.time=0; w.E.Update(0)
local morning=copy(w.SetOgreSunDirection)
check(morning[1]<0 and morning[2]<0,'the morning light falls westward and down, from the eastern sun')
w=world('io.act',250)
w.E.Init({lightingMode='orbit'})
check(w.E.LightingMode=='cycle' and w.E.Orbit==nil,'without Jupiter in the TRN orbit mode falls back to the cycle')

-- Final composition, including a misbehaving local modifier and manual fog,
-- always fits the TRN horizon. Even a ramp starting beyond it stays ordered.
for _,limit in ipairs({100,130,250,700}) do
    w=world('mars.act',limit); w.E.Init()
    check(near(w.E.DayDiffuse.r,0.7),'explicit TRN sunlight RGB read')
    w.E.RegisterEnvironmentModifier('overrun',function(frame)
        frame.fog={r=0.3,g=0.2,b=0.1,fogStart=800,fogEnd=1200}
    end)
    for _,time in ipairs({0,450,700,850}) do
        w.time=time; w.E.Update(0.1)
        check(w.SetFog[5]<=limit and w.SetFog[4]<w.SetFog[5],'final fog fits horizon at every TOD')
    end
end

-- Weather and TOD compose under one renderer writer. Full weather weight must
-- not erase the subtle lighting change or turn an ordinary night back into day.
w=world('venus.act',100)
w.E.Init({lightingMode='subtle',nativeBaseline=true,subtleDimming=0.04,subtleSunAngle=2})
w.W.Init(); check(not w.W.OwnsEnvironment,'Environment owns atmosphere writes')
w.W.Layers={{preset=w.P.Get('VenusCalm'),weight=1}}
w.E.Update(0); local day=w.SetSunDiffuse[1]
local before=#w.writes; w.W.Update(0.1)
check(#w.writes==before,'CRWeather does not issue competing atmosphere writes')
w.time=1800; w.E.Update(0.1)
check(near(w.SetSunDiffuse[1],day*0.96),'TOD survives full Venus weather weight')
check(w.SetFog[5]<=100,'Venus composed fog reaches TRN horizon')
w.E.SetFogState('night',10)
check(near(w.E.FogTransition.from.r,w.E.LastBaseFog.r),'manual fog transition starts from base, not weather-composed fog')
w=world('mars.act',250); w.E.Init(); w.W.Init()
w.W.Layers={{preset=w.P.Get('MarsHaze'),weight=1}}
w.E.Update(0); day=w.SetSunDiffuse[1]
w.time=700; w.E.Update(0.1)
check(w.SetSunDiffuse[1] < day*0.3,'full weather no longer relights nighttime')
w.E.LockDaylight=true; w.E.Update(0)
check(w.E.GetCycleState().nightBlend==0 and w.E.NightBlend==0,'public cycle inspection honors daylight lock')

-- Mission 06 opts into the visual cycle without introducing sensor penalties.
w=world('mars.act',250); w.E.Init({nightGameplay=false}); w.time=700; w.E.Update(0)
check(w.E.NightBlend==1,'visual night remains available without gameplay night')
w.e.IsValid=function() return true end; w.e.IsCraft=function() return true end
local exu=w.e.require('exu'); local sensorWrites=0
for _,name in ipairs({'SetRadarRange','SetRadarPeriod','SetVelocJam'}) do
    exu[name]=function() sensorWrites=sensorWrites+1 end
end
exu.GetRadarRange=function() return 100 end; exu.GetRadarPeriod=function() return 1 end; exu.GetVelocJam=function() return 1 end
w.E.ProcessObjectNightEffects(1)
check(sensorWrites==0,'visual-only night does not alter sensors')
w.E.EnableNightGameplay=true; w.E.ProcessObjectNightEffects(1)
check(sensorWrites==3,'ordinary missions retain existing night gameplay')

-- Standalone Titan uses the TRN view limit rather than its shorter captured
-- fog range, while its baseline and weather still write one composed frame.
w=world('titan.act',250); w.e.Environment=nil; w.fog.fogEnd=175
w.W.Init(); w.W.Layers={{preset={fog={r=0.5,g=0.3,b=0.1,fogStart=50,fogEnd=220}},weight=1}}
w.W.Update(0)
check(near(w.SetFog[5],220),'standalone horizon comes from TRN visibility rather than initial fog')

-- Every shipped preset shares system names deliberately; no preset itself may
-- contain duplicate names (which would double-drive one live particle system).
for name,preset in pairs(w.P.Presets) do
    local seen={}
    for _,spec in ipairs(preset.precipitation or {}) do
        check(not seen[spec.system],name..' duplicates '..spec.system); seen[spec.system]=true
    end
end

-- Rapid weather changes and reversal reuse named systems. Outgoing particles
-- fade, but only one system per name survives and Clear releases them all.
w=world('mars.act',250); w.E.Init(); w.W.Init()
for _,name in ipairs({'MarsHaze','MarsDustRising','MarsDustStorm','MarsHaze','Clear'}) do
    w.W.SetPreset(name,1)
    w.W.Update(0.25); w.E.Update(0.25)
end
w.W.Update(2)
check(next(w.systems)==nil,'Clear releases outgoing weather particle systems')
print('Atmosphere integration passed: '..checks..' checks (native baseline, TOD, weather ownership, horizons).')
