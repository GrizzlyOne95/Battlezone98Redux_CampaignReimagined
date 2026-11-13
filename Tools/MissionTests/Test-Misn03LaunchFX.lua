package.path='Scripts/?.lua;'..package.path
-- Mission 03's Moon configuration of the shared launch exhaust: seven bells,
-- Core/Plume/Dust only, flight and drain unchanged from Mission 06.
local FX = assert(loadfile('Scripts/CR06LaunchFX.lua'))()
local Layout = assert(loadfile('Scripts/CR03RocketLayout.lua'))()
local n = 0
local function check(v,why) assert(v,why); n=n+1 end
local function near(a,b) return math.abs(a-b)<1e-6 end
local function world()
    local w={now=100,systems={},lights={},destroyed=0,lightsDestroyed=0,logs=0,actor={alive=true},placed=0,created={}}
    local x={}
    x.CreateParticleSystem=function(name,template,at)
        w.created[#w.created+1]=template
        w.systems[name]={template=template,at=at,rate=0,rates={},offsets={}}; return true
    end
    x.DestroyParticleSystem=function(name)
        check(w.systems[name]~=nil,'only live owned effects are destroyed')
        w.systems[name]=nil; w.destroyed=w.destroyed+1; return true
    end
    x.SetParticleSystemPosition=function(name,at) w.systems[name].at=at; return true end
    x.SetParticleEmitterEmissionRate=function(name,index,rate)
        local s=w.systems[name]
        local jets=s.template=='CR/M06/Core' or s.template=='CR/M06/Plume'
        check(index>=0 and index<(jets and 7 or 1),'only the seven live bells (one for Dust) are driven')
        s.rate=rate;s.rates[index]=rate; return true
    end
    x.SetParticleEmitterPosition=function(name,index,at)w.systems[name].offsets[index]=at;return true end
    x.CreatePointLight=function(name,at,color,range)
        check(range==180 and type(color.r)=='number' and type(color.g)=='number' and type(color.b)=='number','named r/g/b fields')
        w.lights[name]={at=at};return true
    end
    x.SetPointLightPosition=function(name,at)w.lights[name].at=at;return true end
    x.SetPointLightPowerScale=function(name,power)w.lights[name].power=power;return true end
    x.DestroyPointLight=function(name)
        check(w.lights[name]~=nil,'only owned light destroyed');w.lights[name]=nil;w.lightsDestroyed=w.lightsDestroyed+1;return true
    end
    x.SetParticleSystemKeepLocalSpace=function(name,value) check(not value,'exhaust remains in world space') end
    x.SetParticleSystemNonVisibleUpdateTimeout=function() end
    local a={exu=x,time=function()return w.now end,vector=function(x,y,z)return{x=x,y=y,z=z}end,
        terrain=function()return 20 end,templates=function()return true end,
        log=function(text)w.logs=w.logs+1;w.lastLog=text end,
        config={layout=Layout,label='cr03_rocket',prefix='CR03/Launch/',tag='misn03',systems={'Core','Plume','Dust'}}}
    a.handle=function(label)check(label=='cr03_rocket','the CR03 fixture is the actor');return w.actor end
    a.valid=function(h)return h and h.alive end
    a.transform=function()return{posit_x=10,posit_y=100,posit_z=30}end
    a.place=function(h,pose)check(h==w.actor,'only the preplaced rocket moves');w.placed=w.placed+1;w.actorY=pose.posit_y end
    w.api=a
    return w,FX.Create(a)
end
local nozzleY=Layout.nozzleY
check(near(nozzleY,-46.004707336) and #Layout.nozzles==7,'seven anchors at the measured nozzle plane')
local w,f=world()
check(f.Begin(10,100,30,0),'templates create the three layers')
check(#w.created==3 and w.created[1]=='CR/M06/Core' and w.created[2]=='CR/M06/Plume' and w.created[3]=='CR/M06/Dust',
    'shipped Core, Plume and Dust templates only; no smoke on the Moon')
f.Update();check(f.Describe().power==0,'ignition starts from zero')
w.now=101;f.Update()
local d=f.Describe()
check(d.power==1 and d.dustPower==1 and near(d.nozzleHeight,100+nozzleY),'full ignition at the nozzle plane')
check(d.nozzles==7 and d.light,'seven bells and the physical engine light')
local seen=0
for name,s in pairs(w.systems)do
    check(name:find('^CR03/Launch/1/'),'CR03 names cannot collide with Mission 06')
    if s.template=='CR/M06/Core' or s.template=='CR/M06/Plume' then
        seen=seen+1
        check(s.offsets[0].x==0 and s.offsets[0].z==0,'centre bell on the axis')
        for index=0,6 do
            check(s.rates[index]>0,'every bell emits')
            if index>0 then
                local at=s.offsets[index]
                check(near(at.x*at.x+at.z*at.z,81),'ring bells sit on a 9 m radius')
                local angle=(math.deg(math.atan2(at.z,at.x))%360)
                check(near((angle/60)%1,0) or near((angle/60)%1,1),'ring bells sit on the six skirt lobes')
            end
        end
        check(s.rates[7]==nil and s.offsets[7]==nil,'the eighth template emitter stays dormant')
    end
end
check(seen==2,'Core and Plume present')
w.now=107;f.Update();d=f.Describe()
check(d.dustPower==0 and near(d.nozzleHeight,100+nozzleY+2.5*36),'ground wash fades and the nozzle climbs the shared arc')
check(w.actorY==190,'peer-local actor follows Y = base + 2.5*(age-1)^2')
f.Stop();f.Stop()
for _,s in pairs(w.systems) do for _,rate in pairs(s.rates)do check(rate==0,'stop shuts off every emitter')end end
check(next(w.lights)==nil and w.lightsDestroyed==1,'stop removes the engine light')
w.now=110;f.Update();check(f.Describe().active,'the four-second drain keeps the remaining systems')
w.now=111;f.Update();check(not f.Describe().active and w.destroyed==3,'bounded drain and cleanup of three systems')
f.Reset();check(w.destroyed==3,'cleanup is idempotent')
-- The fixture basis places the bells: a quarter-turned rocket.
w,f=world()
w.api.transform=function()return{right_x=0,right_y=0,right_z=-1,front_x=1,front_y=0,front_z=0}end
check(f.Begin(0,100,0),'rotated fixture can launch')
local ring=w.systems['CR03/Launch/1/Core'].offsets[1]
check(math.abs(ring.x)<1e-6 and math.abs(ring.z+9)<1e-6,'bell offsets follow the actual fixture basis')
f.Reset()
-- Resume and loss.
w,f=world();check(f.Begin(0,100,0,7),'resume starts at the saved flight age');f.Update()
check(f.Describe().dustPower==0,'resume in ascent does not replay ignition dust')
w.now=113;f.Update();w.now=117;f.Update()
check(not f.Describe().active,'local timeout cleans up if the stop event is lost')
w,f=world();w.api.templates=function()return false,'no templates' end
check(not f.Begin(0,100,0) and w.logs==1 and w.lastLog:find('^%[misn03%]'),'unavailable FX is logged under the misn03 tag')
w.now=105;f.Update();check(w.actorY==140,'rocket still moves when particle templates are unavailable')
w,f=world();w.api.exu.CreatePointLight=nil
check(f.Begin(0,100,0),'works without the optional point-light API')
f.Update();check(not f.Describe().light,'missing light support does not invent a light');f.Reset()
print('misn03 launch FX checks passed: '..n)
