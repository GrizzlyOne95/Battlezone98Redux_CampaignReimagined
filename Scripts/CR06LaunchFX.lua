-- Peer-local rocket translation and exhaust. No AI commands or damage.
local FX = {}
function FX.Create(api)
    local state, flight, serial = nil, nil, 0
    local function call(name, ...)
        local fn = api.exu[name]
        if type(fn) ~= "function" then return nil end
        local ok, result = pcall(fn, ...)
        if ok then return result end
    end
    local result = {}
    local function clearParticles()
        if state then
            for _, name in pairs(state.systems) do call("DestroyParticleSystem", name) end
        end
        state = nil
    end
    function result.Reset() clearParticles(); flight=nil end
    local function unavailable(reason)
        clearParticles()
        api.log("[misn06] rocket effects unavailable: " .. tostring(reason))
        return false
    end
    function result.Begin(x, y, z, age)
        result.Reset()
        if api.handle then
            local h=api.handle("cr06_rocket")
            if api.valid(h) then
                local pose=api.transform(h)
                pose.posit_x,pose.posit_y,pose.posit_z=x,y,z
                flight={handle=h,pose=pose,baseY=y,started=api.time()-(age or 0)}
            end
        end
        for _, name in ipairs({"CreateParticleSystem", "DestroyParticleSystem",
                "SetParticleSystemPosition", "SetParticleEmitterEmissionRate"}) do
            if type(api.exu[name]) ~= "function" then return unavailable(name) end
        end
        local ok, loaded, reason = pcall(api.templates)
        if not ok or not loaded then return unavailable(reason or loaded) end
        serial = serial + 1
        state = {x=x,y=y,z=z,started=api.time()-(age or 0),systems={}}
        local ground = api.terrain(api.vector(x,y,z))
        state.ground = ground + 0.5
        for _, kind in ipairs({"Core", "Plume", "Smoke", "Dust"}) do
            local name = "CR06/Launch/" .. serial .. "/" .. kind
            local at = api.vector(x, kind == "Dust" and state.ground or y-48.5, z)
            if call("CreateParticleSystem", name, "CR/M06/" .. kind, at) ~= true then
                return unavailable("particle create " .. kind)
            end
            state.systems[kind] = name
            call("SetParticleSystemKeepLocalSpace", name, false)
            call("SetParticleSystemNonVisibleUpdateTimeout", name, 0)
            call("SetParticleEmitterEmissionRate", name, 0, 0)
        end
        return true
    end
    function result.Stop()
        flight=nil
        if not state or state.stopped then return end
        state.stopped = api.time()
        for _, name in pairs(state.systems) do call("SetParticleEmitterEmissionRate", name, 0, 0) end
    end
    function result.Update()
        if flight then
            local age=math.max(0,api.time()-flight.started)
            if age<20 and api.valid(flight.handle) then
                flight.pose.posit_y=flight.baseY+2.5*math.max(0,age-1)^2
                api.place(flight.handle,flight.pose)
            else flight=nil end
        end
        if not state then return end
        if state.stopped then
            if api.time()-state.stopped >= 4 then result.Reset() end
            return
        end
        local age = math.max(0,api.time()-state.started)
        if age >= 20 then result.Stop(); return end
        local climb = math.max(0,age-1)
        local rise = 2.5*climb*climb
        local at = api.vector(state.x,state.y+rise-48.5,state.z)
        local power = math.min(1,age/0.7)
        for _, kind in ipairs({"Core","Plume","Smoke"}) do
            call("SetParticleSystemPosition",state.systems[kind],at)
        end
        call("SetParticleEmitterEmissionRate",state.systems.Core,0,55*power)
        call("SetParticleEmitterEmissionRate",state.systems.Plume,0,170*power)
        call("SetParticleEmitterEmissionRate",state.systems.Smoke,0,45*power)
        -- Dust stays on Mars and tapers once the engine clears the gantry.
        local dust = power*math.max(0,1-rise/65)
        call("SetParticleEmitterEmissionRate",state.systems.Dust,0,120*dust)
        state.power,state.dustPower,state.height = power,dust,at.y
    end
    function result.Describe()
        return {active=state~=nil,systems=state and state.systems or {},
            power=state and state.power or 0,dustPower=state and state.dustPower or 0,
            nozzleHeight=state and state.height or nil}
    end
    return result
end
return FX
