local FX = assert(loadfile('Scripts/CR06LaunchFX.lua'))()
local n = 0
local function check(v,why) assert(v,why); n=n+1 end
local function world()
    local w={now=100,systems={},destroyed=0,logs=0,actor={alive=true},placed=0}
    local x={}
    x.CreateParticleSystem=function(name,template,at)
        if w.fail and template:find(w.fail,1,true) then return false end
        w.systems[name]={template=template,at=at,rate=0}; return true
    end
    x.DestroyParticleSystem=function(name)
        check(w.systems[name]~=nil,'only live owned effects are destroyed')
        w.systems[name]=nil; w.destroyed=w.destroyed+1; return true
    end
    x.SetParticleSystemPosition=function(name,at) w.systems[name].at=at; return true end
    x.SetParticleEmitterEmissionRate=function(name,index,rate)
        check(index==0,'correct emitter'); w.systems[name].rate=rate; return true
    end
    x.SetParticleSystemKeepLocalSpace=function(name,value) check(not value,'smoke remains in world space') end
    x.SetParticleSystemNonVisibleUpdateTimeout=function() end
    local a={exu=x,time=function()return w.now end,vector=function(x,y,z)return{x=x,y=y,z=z}end,
        terrain=function()return 20 end,templates=function()return not w.noTemplates end,
        log=function()w.logs=w.logs+1 end}
    a.handle=function()return w.actor end
    a.valid=function(h)return h and h.alive end
    a.transform=function()return{posit_x=10,posit_y=100,posit_z=30}end
    a.place=function(h,pose)check(h==w.actor,'only preplaced rocket moves');w.placed=w.placed+1;w.actorY=pose.posit_y end
    return w,FX.Create(a)
end
local w,f=world()
check(f.Begin(10,100,30,0),'templates create all four layers')
f.Update();check(f.Describe().power==0,'ignition starts from zero')
w.now=101;f.Update()
local d=f.Describe()
check(d.power==1 and d.dustPower==1 and d.nozzleHeight==51.5,'full ignition at original nozzle height')
local ground
for _,s in pairs(w.systems) do if s.template=='CR/M06/Dust' then ground=s.at.y end end
w.now=107;f.Update();d=f.Describe()
check(d.dustPower==0 and d.nozzleHeight==141.5,'ground wash fades as rocket clears pad')
check(w.actorY==190,'peer-local actor and effects use the same climb')
for _,s in pairs(w.systems) do
    if s.template=='CR/M06/Dust' then check(s.at.y==ground,'dust remains at terrain height')
    else check(s.at.y==141.5,'each exhaust layer follows nozzle') end
end
f.Stop();f.Stop()
for _,s in pairs(w.systems) do check(s.rate==0,'stop shuts off every emitter') end
w.now=110;f.Update();check(f.Describe().active,'residual dust and smoke can fade')
w.now=111;f.Update();check(not f.Describe().active and w.destroyed==4,'bounded drain and cleanup')
f.Reset();check(w.destroyed==4,'cleanup is idempotent')
w,f=world();w.fail='Smoke';check(not f.Begin(0,100,0),'partial creation fails cleanly')
check(w.destroyed==2 and next(w.systems)==nil and w.logs==1,'partial system cleanup logged once')
w,f=world();check(f.Begin(0,100,0,7),'resume starts with saved flight age');f.Update()
check(f.Describe().dustPower==0,'resume in ascent does not replay ignition dust')
w.now=113;f.Update();w.now=117;f.Update()
check(not f.Describe().active,'local timeout cleans up if stop event is lost')
w,f=world();w.noTemplates=true;check(not f.Begin(0,100,0),'optional FX can be unavailable')
w.now=105;f.Update();check(w.actorY==140,'rocket still moves when particle templates are unavailable')
print('misn06 launch FX checks passed: '..n)
