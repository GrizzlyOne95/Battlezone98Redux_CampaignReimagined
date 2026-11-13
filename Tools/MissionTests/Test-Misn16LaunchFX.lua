-- Exercise lifecycle/degradation independently of the native renderer.
assert(_VERSION=="Lua 5.1")
local FX=dofile("Scripts/CRMisn16LaunchFX.lua")
local n=0
local function check(ok,why) assert(ok,why);n=n+1 end
local function setup(options)
    options=options or {}
    local systems,lights,alive,parts={},{},{},{}
    for i=1,4 do
        local label="cr16_engine"..i;alive[label]=true;parts[label]={x=i*20,y=5,z=100}
    end
    alive.cr16_transport=true
    local x={}
    function x.CreateParticleSystem(name,template,at)
        if options.failCreate then return false end
        assert(not systems[name],"duplicate live system")
        systems[name]={template=template,at=at,rate=0};return true
    end
    function x.DestroyParticleSystem(name) systems[name]=nil;return true end
    function x.SetParticleSystemKeepLocalSpace(name,enabled) systems[name].localSpace=enabled end
    function x.SetParticleSystemNonVisibleUpdateTimeout() end
    function x.AttachParticleSystemToObject(name,h,offset)
        systems[name].attached=h;systems[name].offset=offset;return not options.failAttach
    end
    function x.SetParticleEmitterEmissionRate(name,index,rate) assert(index==0);systems[name].rate=rate end
    local function vector(a,b,c) return {x=a,y=b,z=c} end
    local fx=FX.Create({exu=x,vector=vector,handle=function(label) return label end,
        valid=function(h) return alive[h] end,
        position=function(h) local p=parts[h];return vector(p.x,p.y+100,p.z) end,
        terrain=function() return 5 end,
        explosion=function(odf,at) lights[#lights+1]={odf=odf,at=at} end,
        log=function() end,templates=function() return not options.failTemplates,"template error" end})
    return fx,parts,systems,lights,alive
end
local function count(t) local k=0;for _ in pairs(t) do k=k+1 end;return k end
local a,parts,systems,lights,alive=setup()
a.Update(parts,1.5)
check(a.Describe().plumes==4 and a.Describe().cores==4 and a.Describe().dust==4,"four attached nozzles and four ground patches")
for _,s in pairs(systems) do
    if s.attached then check(s.offset.y==12 and s.localSpace==false,"authored nozzle offset; spent exhaust remains in world space")
    else check(s.at.y==5.6 and not s.attached,"dust stays at ground height") end
    check(s.rate>0,"ignition enables emitter")
end
check(#lights==4 and lights[1].odf=="cr16ign" and lights[1].at.y==116,"light follows rising engine")
a.Update(parts,1.6);check(#lights==4,"light pulses bounded independently of frame rate")
a.Update(parts,1.8);check(#lights==8,"bounded light renewal")
a.Update(parts,7)
check(a.Describe().dustPower==0,"ground wash shuts off when ship clears pad")
for name,s in pairs(systems) do if name:match("/Dust$") then check(s.rate==0,"ground emitters stop") end end
a.Update(parts,11);check(a.Describe().dust==0 and count(systems)==8,"dust tails expire while flight exhaust continues")
alive.cr16_engine2=false;a.Update(parts,12)
check(a.Describe().plumes==3 and a.Describe().cores==3,"destroyed engine loses its effects")
alive.cr16_transport=false;a.Update(parts,13)
check(count(systems)==0 and not a.Describe().active,"transport destruction clears every effect")
a.Update(parts,14);check(count(systems)==0,"departed effects do not restart")
for _,option in ipairs({"failTemplates","failCreate","failAttach"}) do
    local fx,p,s=setup({[option]=true});fx.Update(p,2)
    check(fx.Describe().error~=nil and count(s)==0,"optional FX failure cleans partial allocation: "..option)
end
-- A fresh peer/local effect state during a loaded flight does not replay pad ignition.
a,parts,systems,lights,alive=setup();a.Update(parts,15)
check(a.Describe().plumes==4 and a.Describe().dust==0,"late resume rebuilds flight exhaust without dust")
a.Stop();check(count(systems)==0,"result cleanup")
a.Reset();a.Update(parts,2);check(a.Describe().dust==4,"restart can recreate effects without duplicate names")
a.Update(parts,30);check(count(systems)==0,"bounded departure lifetime")
-- Each peer owns the same names in a separate Ogre scene, without wire operations.
local b,bparts,bsystems=setup();b.Update(bparts,2)
check(count(bsystems)==12 and count(systems)==0,"peer-local lifecycle is independent")
print("misn16 launch FX: "..n.." checks passed")
