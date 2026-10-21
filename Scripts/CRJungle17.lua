-- Achilles jungle weather director. Every peer renders the same authored sites;
-- only the campaign leader reads mission state, picks a storm level and
-- announces lightning. Builds no gameplay objects and never changes AI or
-- mission objectives.
--
-- Levels follow the mission, not a clock:
--   0 clearing   a result has latched
--   1 rain       opening approach
--   2 downpour   towers falling (deepens with each loss)
--   3 storm      all towers or the mine field gone; lightning
--   4 tempest    converter overload or the factory falls; frequent lightning
local Jungle={}
local LEVELS=4
function Jungle.Create(api)
    local x=api.exu
    local Weather=require("CRWeather")
    local Presets=require("CRWeatherPresets")
    local Sites=require("CRJungle17Sites")
    local Splash=require("CRSplash")
    local Glass=require("CRWetGlass")
    local Templates=require("CRParticleTemplates")
    local E=require("Environment")
    local Foliage=require("CRFoliageWind")
    local Wake=require("CRWake")
    local J={Initialized=false,Enabled=true}
    local state,level,intensity,windSpeed,bearing,nextLayer,groups,waters,mist,error
    local flash,flashAt,flashPower,thunder,thunderAt,rainSound,fallSound,nextRain,nextFalls
    local clouds,baseSky,nextSync
    local boltsSeen=0 -- bolts applied on this peer, for diagnostics
    local function copy(v)
        if type(v)~="table" then return v end
        local t={};for k,a in pairs(v) do t[k]=copy(a) end;return t
    end
    local SPEED={2,4,7,11,15}
    local mistSource=Presets.Presets.VenusDenseAtmosphere and Presets.Presets.VenusDenseAtmosphere.precipitation[1]
    for i=0,LEVELS do
        local f=i/LEVELS
        local p=copy(Presets.Presets.AcidRainVisual)
        p.name="AchillesJungle"..i;p.sky=nil;p.lightning=nil
        p.wind={x=.04+.2*f,y=-1,z=.03+.12*f};p.windSpeed=SPEED[i+1]
        p.gusts={period=14-6*f,depth=.1+.35*f}
        p.fog={r=.20-.06*f,g=.31-.07*f,b=.44-.05*f,fogStart=30-15*f,fogEnd=320-170*f}
        p.ambient={r=.24-.08*f,g=.36-.08*f,b=.52-.08*f}
        p.diffuse={r=.50-.24*f,g=.66-.24*f,b=.85-.24*f};p.sunPowerScale=.9-.6*f
        local rain=p.precipitation[1].emitters[0]
        rain.rate=60+420*f
        local a=.3+.2*f
        rain.color={start={r=.8,g=.8,b=.8,a=a},finish={r=.65,g=.65,b=.65,a=a/3}}
        -- Ground mist pools in hollows; one system name lets every level retarget it.
        if mistSource then
            local m=copy(mistSource)
            m.system="cr17_wx_basin_mist"
            local alpha=string.format("%.2f",.12+.28*f)
            m.affectors[0]={
                colour0="0.60 0.75 0.90 0.00",
                colour1={"0.60 0.75 0.90 0.00","0.60 0.75 0.90 "..alpha},
                colour2={"0.54 0.68 0.84 0.00","0.54 0.68 0.84 "..string.format("%.2f",(.12+.28*f)*.7)},
                colour3="0.52 0.64 0.80 0.00",
            }
            p.precipitation[#p.precipitation+1]=m
        end
        Presets.Presets[p.name]=p
    end
    local function call(name,...)
        if type(x[name])~="function" then return nil end
        return x[name](...)
    end
    local function safe(name,...)
        if type(x[name])~="function" then return nil end
        local ok,r=pcall(x[name],...)
        if ok then return r end
    end
    local function stopSound(h) if h and type(StopSound)=="function" then StopSound(h) end end
    local WATERS={{"CR17/River","water"},{"CR17/Streams","streams"},{"CR17/Pools","pools"}}

    -- Core vents. Each converter part taps the planet's core; where one falls,
    -- its pit erupts in fire. The leader announces fallen parts as a bit mask
    -- (a vent never closes); every peer builds the fire locally on the stock
    -- partNgeizer path, beside the stock geyser. No gameplay objects. Each vent
    -- also lights its surroundings with an EXU point light (not saved; relit
    -- with the vent after a load); an older EXU without point lights falls
    -- back to tinting the ambient near the pilot.
    local VENT_FX={"VentPool","VentFlame","VentLick","VentSmoke","VentSpatter"}
    local vents,ventGlow,ventRetry={},0,{}
    local function ventName(i,fx) return "CR17/Core"..i.."/"..fx end
    local VENT_LIGHT={r=1,g=.42,b=.1}
    local VENT_RANGE,VENT_LIFT=80,8
    local function hasVent(mask,i) return math.floor((tonumber(mask) or 0)/2^(i-1))%2==1 end
    local function lightVent(i)
        if vents[i] or GetTime()<(ventRetry[i] or 0) then return end
        ventRetry[i]=GetTime()+5
        if type(x.CreateParticleSystem)~="function" or not Templates.EnsureExtra("cr17_jungle") then return end
        local ok,p=pcall(GetPosition,"part"..i.."geizer")
        if not ok or type(p)~="table" or not p.x then return end
        for _,fx in ipairs(VENT_FX) do
            local name=ventName(i,fx)
            if x.CreateParticleSystem(name,"CR17/"..fx,SetVector(p.x,p.y,p.z))==true then
                safe("SetParticleSystemNonVisibleUpdateTimeout",name,3)
            end
        end
        local light=false
        if type(x.CreatePointLight)=="function" then
            local name=ventName(i,"Light")
            safe("DestroyPointLight",name)
            light=safe("CreatePointLight",name,SetVector(p.x,p.y+VENT_LIFT,p.z),VENT_LIGHT,VENT_RANGE)==true
        end
        vents[i]={x=p.x,y=p.y,z=p.z,surge=0,nextSurge=GetTime()+1.5,light=light}
        if type(StartSound)=="function" then StartSound("gquak00.wav",SetVector(p.x,p.y,p.z)) end
    end
    local function closeVents()
        for i in pairs(vents) do
            for _,fx in ipairs(VENT_FX) do call("DestroyParticleSystem",ventName(i,fx)) end
            safe("DestroyPointLight",ventName(i,"Light"))
        end
        vents,ventGlow,ventRetry={},0,{}
    end
    -- Surges: the column roars higher and throws lava every few seconds, and
    -- the fire lights the air around a pilot standing near it.
    local function updateVents(dt)
        if not next(vents) then ventGlow=0;return end
        local now=GetTime()
        local r=math.rad(bearing or 210)
        local lean=(windSpeed or 0)*.35
        local me=type(GetPlayerHandle)=="function" and GetPlayerHandle()
        local here=me and IsValid and IsValid(me) and GetPosition(me)
        local glow=0
        for i,v in pairs(vents) do
            if now>=v.nextSurge then
                v.surge=1;v.nextSurge=now+3+math.random()*5
                if type(StartSound)=="function" then StartSound("r_exp3.wav",SetVector(v.x,v.y,v.z)) end
            end
            v.surge=math.max(0,v.surge-1.6*dt)
            local flicker=.85+.15*math.sin(now*7.3+i*2.1)
            safe("SetParticleEmitterEmissionRate",ventName(i,"VentFlame"),0,(70+90*v.surge)*flicker)
            safe("SetParticleEmitterEmissionRate",ventName(i,"VentLick"),0,30+50*v.surge)
            safe("SetParticleEmitterEmissionRate",ventName(i,"VentSpatter"),0,6+80*v.surge)
            safe("SetParticleAffectorParameter",ventName(i,"VentSmoke"),2,"force_vector",
                string.format("%.3f 0 %.3f",math.sin(r)*lean,math.cos(r)*lean))
            if v.light then
                safe("SetPointLightPowerScale",ventName(i,"Light"),(1.4+1.6*v.surge)*flicker)
            elseif here then
                local dx,dz=here.x-v.x,here.z-v.z
                local near=1-math.min(1,math.sqrt(dx*dx+dz*dz)/240)
                glow=glow+near*near*flicker*(1+.6*v.surge)
            end
        end
        ventGlow=math.min(1,glow)
    end

    -- Storm cloud deck: the map's own cloud art on a scrolling sky plane, via
    -- cr17_cloud.material. A clone of ACLOUD2.MAP would keep its Effect
    -- programs, which read vertex colour the sky plane lacks, so D3D11 throws
    -- on every draw. Never replaces a sky system the map already enabled.
    local CLOUD="CR17/StormCloud"
    local function setClouds(on)
        if type(x.SetSkyPlane)~="function" or type(x.SetSkyPlaneEnabled)~="function" then
            clouds=on and "unsupported" or clouds;return
        end
        if not on then
            if clouds=="on" then safe("SetSkyPlaneEnabled",false);clouds="off" end
            return
        end
        if baseSky then clouds="skipped";return end
        if clouds~="on" then
            if safe("MaterialExists",CLOUD,"General")==false then clouds="missing";return end
            local mat=CLOUD
            local r=safe("SetSkyPlane",mat,{normal=SetVector(0,-1,0),d=1450},2400,2.2,true,0,8,8,"General")
            if r==false then clouds="failed";return end
            safe("SetSkyPlaneEnabled",true)
            clouds="on";J.cloudMaterial=mat
        end
        safe("SetMaterialTextureScrollAnimation",J.cloudMaterial or CLOUD,.0008+.00009*(windSpeed or 0),.0002,0,0,0,"General")
    end

    -- Vehicle wakes (render only, shared CRWake module). Water is the river
    -- corridor from the authored route plus the generated stream/pool mask;
    -- everything else is grass, thinned
    -- where no ground cover stands within a cell. api.vehicleWakes=false turns it off.
    local RIVER_HALF,CELL=7.5,12
    local cover
    local function cellKey(ix,iz) return ix*20000+iz end
    local function buildCover()
        cover={}
        for _,layer in ipairs(Sites.layers or {}) do
            for _,p in ipairs(layer.instances) do
                local k=cellKey(math.floor(p[1]/CELL),math.floor(p[3]/CELL))
                cover[k]=(cover[k] or 0)+1
            end
        end
    end
    local function segDist2(px,pz,ax,az,bx,bz)
        local dx,dz=bx-ax,bz-az
        local l2=dx*dx+dz*dz
        local t=l2>0 and ((px-ax)*dx+(pz-az)*dz)/l2 or 0
        t=t<0 and 0 or (t>1 and 1 or t)
        local ex,ez=px-(ax+dx*t),pz-(az+dz*t)
        return ex*ex+ez*ez
    end
    -- Stream and pool water: the generated run-length mask of the cells the baked
    -- meshes cover (Tools/Export-Misn17WaterMask.py). rows[i] = {startCol,length,...}
    -- for grid row firstRow+i-1; cells are centred on col*cell, row*cell+originZ.
    local MASK_LIFT=.8 -- the surface sits between the carved bed and ~2 m above it
    local function inMask(px,pz)
        local m=Sites.watermask
        if not m then return false end
        local row=m.rows[math.floor((pz-m.originZ)/m.cell+.5)-m.firstRow+1]
        if not row then return false end
        local col=math.floor((px-m.originX)/m.cell+.5)
        for i=1,#row-1,2 do
            local start=row[i]
            if col<start then return false end
            if col<start+row[i+1] then return true end
        end
        return false
    end
    J.WakeInWaterMask=inMask
    -- resolver(x,z) -> surface, rate scale, lift (the water plane sits above the cut bed)
    function J.WakeSurface(px,pz)
        local r=Sites.river
        if r then
            for i=1,#r-1 do
                if segDist2(px,pz,r[i][1],r[i][2],r[i+1][1],r[i+1][2])<=RIVER_HALF*RIVER_HALF then
                    return "water",1,1.1
                end
            end
        end
        if inMask(px,pz) then return "water",1,MASK_LIFT end
        if not cover then buildCover() end
        local ix,iz=math.floor(px/CELL),math.floor(pz/CELL)
        local n=0
        for dx=-1,1 do for dz=-1,1 do n=n+(cover[cellKey(ix+dx,iz+dz)] or 0) end end
        if n>0 then return "grass",math.min(1,.6+.05*n),0 end
        return "grass",.4,0
    end

    function J.Stop()
        Wake.Stop()
        J.Initialized=false
        for _,name in ipairs(groups or {}) do call("DestroyStaticGeometry",name) end
        for _,w in ipairs(WATERS) do call("DestroyStaticGeometry",w[1]) end
        call("DestroyParticleSystem","CR17/CascadeMist")
        closeVents()
        if clouds=="on" then setClouds(false) end
        stopSound(rainSound);stopSound(fallSound)
        rainSound,fallSound=nil,nil
        Weather.ClearWindOverride();Weather.Shutdown();Splash.Stop();Glass.Stop()
        groups={};waters={};mist=false;flash=nil;thunder=nil;clouds=nil
    end
    function J.Reset(saved)
        if state then J.Stop() end
        state=saved or {}
        state.age=tonumber(state.age) or 0
        state.nextBolt=tonumber(state.nextBolt) or 0
        state.vents=tonumber(state.vents) or 0 -- relit by Update; the leader also resyncs it
        state.sentVents=nil
        state.level=nil -- the leader re-announces after load
        level,intensity,windSpeed,bearing=nil,0,0,210
        nextLayer=1;groups={};waters={};mist=false;error=nil;clouds="off"
        nextRain,nextFalls,nextSync=0,0,0
        baseSky=safe("GetSkyPlaneEnabled")==true or (safe("GetSkyDomeEnabled")==true and not E.ArtSkyOwned) or safe("GetSkyBoxEnabled")==true
        Weather.Init()
        -- Canopies, their shadow casters and the StaticGeometry ground cover sway
        -- with CRWeather's wind (meshes baked by Tools/Bake-FoliageSway.py); the
        -- ground cover also sheds leaves near the camera. Weather.Shutdown in
        -- J.Stop stills them again.
        -- The pack forest's canopies (Tools/Build-Misn17Forest.py) sway the same way.
        -- So do the flower cards (Tools/Build-Misn17Flowers.py); they shed no litter.
        for _,m in ipairs({"CR17/LeavesWind","CR17/GroundWind","CR17/GroundWindCold","CR17/CutoutCaster/FoliageWind",
            "CR17/ForestBranch1Wind","CR17/ForestBranch2Wind",
            "CR17/CutoutCaster/ForestBranch1Wind","CR17/CutoutCaster/ForestBranch2Wind",
            "CR17/FlowerWind","CR17/FlowerTallWind","CR17/CutoutCaster/FlowerTallWind"}) do
            Foliage.Register(m,{slot="emissive"})
        end
        local points={}
        for _,layer in ipairs(Sites.layers) do
            if not layer.mesh:find("^cr17_fl_") then
                for _,p in ipairs(layer.instances) do points[#points+1]=p end
            end
        end
        Foliage.EnableLitter(points,{rate=45,saturation=50,minSpeed=3})
        if api.vehicleWakes~=false then
            pcall(Wake.Init,{surface=J.WakeSurface,surfaces={"water","grass"}})
        end
        J.Initialized=true
        E.RegisterEnvironmentModifier("CR17Lightning",function(frame)
            if flash and GetTime()-flashAt<.2 then
                local k=flashPower or 1
                frame.ambient.r=math.min(1,frame.ambient.r+.35*k)
                frame.ambient.g=math.min(1,frame.ambient.g+.35*k)
                frame.ambient.b=math.min(1,frame.ambient.b+.40*k)
            end
            if ventGlow>.001 and frame.ambient then
                frame.ambient.r=math.min(1,frame.ambient.r+.34*ventGlow)
                frame.ambient.g=math.min(1,frame.ambient.g+.13*ventGlow)
                frame.ambient.b=math.min(1,frame.ambient.b+.02*ventGlow)
            end
        end)
    end

    local function applyLevel(l,pct,deg,speed)
        l=math.max(0,math.min(LEVELS,math.floor(l)))
        local changed=l~=level
        level=l
        intensity=math.max(0,math.min(1,(tonumber(pct) or 100)/100))
        bearing=tonumber(deg) or bearing
        windSpeed=tonumber(speed) or SPEED[l+1]
        if changed then Weather.SetPreset("AchillesJungle"..l,10) end
        local r=math.rad(bearing)
        local lean=windSpeed/30
        Weather.SetWindOverride({x=math.sin(r)*lean,y=-1,z=math.cos(r)*lean},windSpeed)
        Weather.SetIntensity(intensity)
        if type(Splash.SetWind)=="function" then Splash.SetWind(math.sin(r),math.cos(r),windSpeed) end
        setClouds(l>=2)
    end
    function J.Apply(kind,a,b,c,d)
        if kind=="level" and type(a)=="number" and a>=0 and a<=LEVELS then
            applyLevel(a,b,c,d)
        elseif kind=="phase" and type(a)=="number" and a>=1 and a<=3 then
            -- Saves and peers from the timer prototype: 1/2/3 -> rain/downpour/storm.
            applyLevel(a,({35,60,85})[math.floor(a)])
        elseif kind=="bolt" then
            flash=true;flashAt=GetTime();thunder=true;boltsSeen=boltsSeen+1
            flashPower=level==4 and 1.3 or 1
            thunderAt=GetTime()+(level==4 and 1.2 or 2.2)
        elseif kind=="vents" and state and type(a)=="number" and a>=0 and a<8 then
            -- Vents only ever open: merge, so a stale resync cannot close one.
            for i=1,3 do
                if hasVent(a,i) and not hasVent(state.vents,i) then state.vents=state.vents+2^(i-1) end
            end
        end
    end

    -- Leader only: mission flags -> level and intensity percent.
    function J.Target()
        local m=type(api.state)=="function" and api.state() or nil
        if type(m)~="table" then return 1,35 end
        if m.missionwon or m.missionfail or m.coopResult then return 0,15 end
        local crystal=m.cr17Crystals
        if (crystal and crystal.phase=="overload") or m.factorydestroyed then return 4,100 end
        -- A converter falling (the stock win route) also tips the storm over.
        if m.towersdestroyed and type(IsAlive)=="function" then
            for i=1,3 do
                local h=m["factorypart"..i]
                if h and h~=0 and not IsAlive(h) then return 4,100 end
            end
        end
        if m.towersdestroyed or m.minesdestroyed then return 3,85 end
        local dead=0
        for i=1,7 do if m["tower"..i.."dead"] then dead=dead+1 end end
        if dead>0 then return 2,math.min(80,45+8*dead) end
        return 1,35
    end

    -- Leader only: which converter parts have fallen, from the stock latches.
    function J.VentMask()
        local m=type(api.state)=="function" and api.state() or nil
        if type(m)~="table" then return 0 end
        local mask=0
        for i=1,3 do if m["factorypart"..i.."dead"]==true then mask=mask+2^(i-1) end end
        return mask
    end

    local function geometry()
        if type(x.CreateStaticGeometry)~="function" then error="EXU StaticGeometry unavailable";return end
        for _,w in ipairs(WATERS) do
            local site=Sites[w[2]]
            if site and not waters[w[2]] then
                local p=site.position
                local info,reason=x.CreateStaticGeometry(w[1],site.mesh,nil,
                    {{position={x=p[1],y=p[2],z=p[3]},scale=1}},
                    {origin={x=2048,y=0,z=99328},regionDimensions={x=128,y=256,z=128},renderingDistance=w[2]=="pools" and 360 or 300,castShadows=false,visible=true})
                if info then waters[w[2]]=true else error=tostring(reason);return end
            end
        end
        local layer=Sites.layers[nextLayer]
        if layer then
            local instances={}
            for _,p in ipairs(layer.instances) do
                instances[#instances+1]={position={x=p[1],y=p[2],z=p[3]},yaw=p[4],scale=p[5]}
            end
            local name="CR17/Jungle/"..nextLayer
            -- The Mire ground cover (shared with misn18) is cooled for Achilles here.
            local material=layer.mesh:find("^cr17_mire_") and "CR17/GroundWindCold" or nil
            local info,reason=x.CreateStaticGeometry(name,layer.mesh,material,instances,
                {origin={x=2048,y=0,z=99328},regionDimensions={x=192,y=256,z=192},renderingDistance=layer.distance or 260,castShadows=false,visible=true})
            if info then groups[#groups+1]=name;nextLayer=nextLayer+1 else error=tostring(reason) end
        end
        if not mist and type(x.CreateParticleSystem)=="function" and Templates.EnsureExtra("cr17_jungle") then
            local p=Sites.cascade
            mist=x.CreateParticleSystem("CR17/CascadeMist","CR17/CascadeMist",SetVector(p[1],p[2]-1,p[3]))==true
        end
    end
    local function watersReady()
        for _,w in ipairs(WATERS) do if Sites[w[2]] and not waters[w[2]] then return false end end
        return true
    end
    function J.Update(dt,authority,send)
        if not state then J.Reset() end
        state.age=state.age+math.max(0,tonumber(dt) or 0)
        if authority then
            local l,pct=J.Target()
            local deg=math.floor(210+40*math.sin(state.age/90)+.5)
            local speed=math.floor(SPEED[l+1]*(.9+.2*math.sin(state.age/37))*10+.5)/10
            -- Resend periodically so late joiners and drifting wind stay in step.
            local resync=state.age>=nextSync
            local mask=J.VentMask()
            if mask~=(state.sentVents or 0) or (resync and mask>0) then
                state.sentVents=mask
                send("vents",mask)
            end
            if l~=state.level or pct~=state.pct or resync then
                -- Entering the storm waits a beat; escalating to the tempest strikes sooner.
                if l~=state.level and l>=3 then
                    if (state.level or 0)<3 then state.nextBolt=math.max(state.nextBolt,state.age+4)
                    else state.nextBolt=math.min(state.nextBolt,state.age+2) end
                end
                state.level=l;state.pct=pct;nextSync=state.age+15
                send("level",l,pct,deg,speed)
            end
            if l>=3 and state.age>=state.nextBolt then
                state.nextBolt=state.age+(l==4 and 6 or 13)
                send("bolt",state.age)
            end
        end
        geometry()
        for i=1,3 do if hasVent(state.vents,i) then lightVent(i) end end
        updateVents(math.max(0,tonumber(dt) or 0))
        if watersReady() and nextLayer>#Sites.layers and mist then error=nil end
        Weather.Update(dt)
        local splash=level and intensity or 0
        Splash.Set("rain",splash);Splash.Update();Glass.Update(splash)
        Wake.Update(tonumber(dt) or 0)
        if thunder and GetTime()>=thunderAt then
            thunder=false
            if type(StartSound)=="function" then StartSound("thunder.wav") end
        end
        if type(StartSound)=="function" and (level or 0)>=1 and GetTime()>=nextRain then
            stopSound(rainSound);rainSound=StartSound("erain01.wav");nextRain=GetTime()+12
        end
        if type(StartSound)=="function" and GetTime()>=nextFalls then
            local p=Sites.cascade
            stopSound(fallSound);fallSound=StartSound("c17falls.wav",SetVector(p[1],p[2],p[3]))
            nextFalls=GetTime()+10
        end
    end
    -- Environment owns sensor writes; severity uses the shared level, never local
    -- particle quality, geometry readiness or camera position.
    function J.GetSeverity() return level and level/LEVELS or 0 end
    function J.Save() return copy(state) end
    function J.Describe() return {level=level,phase=level,intensity=intensity,wind=windSpeed,bearing=bearing,
        clouds=clouds,batches=#groups,totalBatches=#Sites.layers,river=waters and waters.water or false,
        streams=waters and waters.streams or false,pools=waters and waters.pools or false,
        mist=mist,error=error,age=state and state.age or 0,bolts=boltsSeen,foliage=Foliage.Describe(),
        vents=state and state.vents or 0,ventsLit=(function() local n=0;for _ in pairs(vents) do n=n+1 end;return n end)(),
        ventLights=(function() local n=0;for _,v in pairs(vents) do if v.light then n=n+1 end end;return n end)(),
        ventGlow=ventGlow} end
    return J
end
return Jungle
