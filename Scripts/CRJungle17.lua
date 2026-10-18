-- Achilles jungle prototype. Every peer renders the same authored sites;
-- only the campaign leader advances weather and announces lightning.
-- Builds no gameplay objects and never changes AI or mission objectives.
local Jungle={}
function Jungle.Create(api)
    local x=api.exu
    local Weather=require("CRWeather")
    local Presets=require("CRWeatherPresets")
    local Sites=require("CRJungle17Sites")
    local Splash=require("CRSplash")
    local Glass=require("CRWetGlass")
    local Templates=require("CRParticleTemplates")
    local E=require("Environment")
    local J={Initialized=false,Enabled=true}
    local state,phase,nextLayer,groups,water,mist,flash,thunder,rainSound,fallSound,error
    local flashAt,thunderAt,nextRain,nextFalls
    local function copy(v)
        if type(v)~="table" then return v end
        local t={};for k,a in pairs(v) do t[k]=copy(a) end;return t
    end
    for i=1,3 do
        local p=copy(Presets.Presets.AcidRainVisual)
        p.name="AchillesJungle"..i;p.sky=nil;p.lightning=nil
        p.wind={x=.12*i,y=-1,z=.07*i};p.windSpeed=4+4*i
        p.fog={r=.25-.035*i,g=.31-.035*i,b=.27-.025*i,fogStart=25,fogEnd=250-35*(i-1)}
        p.ambient={r=.30-.025*i,g=.36-.025*i,b=.32-.025*i}
        p.diffuse={r=.55-.07*i,g=.61-.07*i,b=.57-.07*i};p.sunPowerScale=.8-.16*i
        local rain=p.precipitation[1].emitters[0]
        rain.rate=150+180*i
        rain.color={start={r=.8,g=.8,b=.8,a=.45},finish={r=.65,g=.65,b=.65,a=.15}}
        Presets.Presets[p.name]=p
    end
    local function call(name,...)
        if type(x[name])~="function" then return nil end
        return x[name](...)
    end
    local function stopSound(h) if h and type(StopSound)=="function" then StopSound(h) end end
    function J.Stop()
        J.Initialized=false
        for _,name in ipairs(groups or {}) do call("DestroyStaticGeometry",name) end
        call("DestroyStaticGeometry","CR17/River")
        call("DestroyParticleSystem","CR17/CascadeMist")
        stopSound(rainSound);stopSound(fallSound)
        rainSound,fallSound=nil,nil
        Weather.Shutdown();Splash.Stop();Glass.Stop()
        groups={};water=false;mist=false;flash=nil;thunder=nil
    end
    function J.Reset(saved)
        if state then J.Stop() end
        state=saved or {age=0,nextBolt=68}
        state.age=tonumber(state.age) or 0
        state.nextBolt=tonumber(state.nextBolt) or 68
        phase=nil;nextLayer=1;groups={};water=false;mist=false;error=nil
        nextRain,nextFalls=0,0
        Weather.Init()
        J.Initialized=true
        E.RegisterEnvironmentModifier("CR17Lightning",function(frame)
            if flash and GetTime()-flashAt<.2 then
                frame.ambient.r=math.min(1,frame.ambient.r+.35)
                frame.ambient.g=math.min(1,frame.ambient.g+.35)
                frame.ambient.b=math.min(1,frame.ambient.b+.40)
            end
        end)
    end
    function J.Apply(kind,a,b)
        if kind=="phase" and type(a)=="number" and a>=1 and a<=3 then
            phase=math.floor(a)
            state.age=tonumber(b) or state.age
            Weather.SetPreset("AchillesJungle"..phase,8)
        elseif kind=="bolt" then
            flash=true;flashAt=GetTime();thunder=true;thunderAt=GetTime()+2.2
        end
    end
    local function geometry()
        if type(x.CreateStaticGeometry)~="function" then error="EXU StaticGeometry unavailable";return end
        if not water then
            local p=Sites.water.position
            local info,reason=x.CreateStaticGeometry("CR17/River",Sites.water.mesh,nil,
                {{position={x=p[1],y=p[2],z=p[3]},scale=1}},
                {origin={x=2048,y=0,z=99328},regionDimensions={x=128,y=256,z=128},renderingDistance=300,castShadows=false,visible=true})
            if info then water=true else error=tostring(reason);return end
        end
        local layer=Sites.layers[nextLayer]
        if layer then
            local instances={}
            for _,p in ipairs(layer.instances) do
                instances[#instances+1]={position={x=p[1],y=p[2],z=p[3]},yaw=p[4],scale=p[5]}
            end
            local name="CR17/Jungle/"..nextLayer
            local info,reason=x.CreateStaticGeometry(name,layer.mesh,nil,instances,
                {origin={x=2048,y=0,z=99328},regionDimensions={x=96,y=256,z=96},renderingDistance=260,castShadows=false,visible=true})
            if info then groups[#groups+1]=name;nextLayer=nextLayer+1 else error=tostring(reason) end
        end
        if not mist and type(x.CreateParticleSystem)=="function" and Templates.EnsureExtra("cr17_jungle") then
            local p=Sites.cascade
            mist=x.CreateParticleSystem("CR17/CascadeMist","CR17/CascadeMist",SetVector(p[1],p[2]-1,p[3]))==true
        end
    end
    function J.Update(dt,authority,send)
        if not state then J.Reset() end
        state.age=state.age+math.max(0,tonumber(dt) or 0)
        if authority then
            local t=state.age%210
            local want=t<55 and 1 or (t<150 and 3 or 2)
            if want~=phase then send("phase",want,state.age) end
            if want==3 and state.age>=state.nextBolt then
                state.nextBolt=state.age+13
                send("bolt",state.age)
            end
        end
        geometry()
        if water and nextLayer>#Sites.layers and mist then error=nil end
        Weather.Update(dt)
        local intensity=phase==3 and 1 or (phase==2 and .65 or .3)
        Splash.Set("rain",intensity);Splash.Update();Glass.Update(intensity)
        if thunder and GetTime()>=thunderAt then
            thunder=false
            if type(StartSound)=="function" then StartSound("thunder.wav") end
        end
        if type(StartSound)=="function" and GetTime()>=nextRain then
            stopSound(rainSound);rainSound=StartSound("erain01.wav");nextRain=GetTime()+12
        end
        if type(StartSound)=="function" and GetTime()>=nextFalls then
            local p=Sites.cascade
            stopSound(fallSound);fallSound=StartSound("c17falls.wav",SetVector(p[1],p[2],p[3]))
            nextFalls=GetTime()+10
        end
    end
    -- Environment owns sensor writes; severity uses shared phase, never local
    -- particle quality, geometry readiness or camera position.
    function J.GetSeverity() return phase and (phase-1)/2 or 0 end
    function J.Save() return copy(state) end
    function J.Describe() return {phase=phase,batches=#groups,totalBatches=#Sites.layers,
        river=water,mist=mist,error=error,age=state and state.age or 0} end
    return J
end
return Jungle
