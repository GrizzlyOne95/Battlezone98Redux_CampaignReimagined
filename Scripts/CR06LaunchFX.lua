-- Peer-local rocket translation and exhaust. No AI commands or damage.
local FX = {}
local Layout = require("CR06RocketLayout")
function FX.Create(api)
    local state, flight, serial = nil, nil, 0
    local function call(name, ...)
        local fn = api.exu[name]
        if type(fn) ~= "function" then return nil end
        local ok, result = pcall(fn, ...)
        if ok then return result end
        return nil,tostring(result)
    end
    local result = {}
    local function emitters(kind) return (kind=="Core" or kind=="Plume") and #Layout.nozzles or 1 end
    local function rate(kind,value)
        for index=0,emitters(kind)-1 do
            call("SetParticleEmitterEmissionRate",state.systems[kind],index,value)
        end
    end
    local function clearParticles()
        if state then
            for _, name in pairs(state.systems) do call("DestroyParticleSystem", name) end
            if state.light then call("DestroyPointLight",state.light) end
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
                "SetParticleSystemPosition", "SetParticleEmitterEmissionRate", "SetParticleEmitterPosition"}) do
            if type(api.exu[name]) ~= "function" then return unavailable(name) end
        end
        local ok, loaded, reason = pcall(api.templates)
        if not ok or not loaded then return unavailable(reason or loaded) end
        serial = serial + 1
        state = {x=x,y=y,z=z,started=api.time()-(age or 0),systems={},pose=flight and flight.pose}
        local ground = api.terrain(api.vector(x,y,z))
        state.ground = ground + 0.5
        for _, kind in ipairs({"Core", "Plume", "Smoke", "Dust"}) do
            local name = "CR06/Launch/" .. serial .. "/" .. kind
            local at = api.vector(x, kind == "Dust" and state.ground or y+Layout.nozzleY, z)
            if call("CreateParticleSystem", name, "CR/M06/" .. kind, at) ~= true then
                return unavailable("particle create " .. kind)
            end
            state.systems[kind] = name
            call("SetParticleSystemKeepLocalSpace", name, false)
            call("SetParticleSystemNonVisibleUpdateTimeout", name, 0)
            rate(kind,0)
            if emitters(kind)>1 then
                local p=state.pose or {}
                for index,nozzle in ipairs(Layout.nozzles) do
                    local nx,nz=nozzle[1],nozzle[2]
                    local offset=api.vector((p.right_x or 1)*nx+(p.front_x or 0)*nz,
                        (p.right_y or 0)*nx+(p.front_y or 0)*nz,
                        (p.right_z or 0)*nx+(p.front_z or 1)*nz)
                    call("SetParticleEmitterPosition",name,index-1,offset)
                end
            end
        end
        -- One physical engine light, owned locally like the particles. Older
        -- EXU builds keep the clustered exhaust without requiring this API.
        if type(api.exu.CreatePointLight)=="function" and type(api.exu.SetPointLightPosition)=="function"
            and type(api.exu.DestroyPointLight)=="function" then
            local name="CR06/Launch/"..serial.."/Light"
            local rise=2.5*math.max(0,(age or 0)-1)^2
            local created,reason=call("CreatePointLight",name,api.vector(x,y+rise+Layout.nozzleY-2,z),{r=3.2,g=2.5,b=1.4},180)
            if created==true then
                state.light=name
            else
                api.log("[misn06] rocket engine light unavailable: "..tostring(reason or "runtime refusal"))
            end
        end
        return true
    end
    function result.Stop()
        flight=nil
        if not state or state.stopped then return end
        state.stopped = api.time()
        for kind in pairs(state.systems) do rate(kind,0) end
        if state.light then call("DestroyPointLight",state.light);state.light=nil end
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
        local at = api.vector(state.x,state.y+rise+Layout.nozzleY,state.z)
        local power = math.min(1,age/0.7)
        for _, kind in ipairs({"Core","Plume","Smoke"}) do
            call("SetParticleSystemPosition",state.systems[kind],at)
        end
        rate("Core",55*power)
        rate("Plume",45*power)
        rate("Smoke",55*power)
        if state.light then
            call("SetPointLightPosition",state.light,api.vector(state.x,at.y-2,state.z))
            call("SetPointLightPowerScale",state.light,power*(1.3+.08*math.sin(age*41)))
        end
        -- Dust stays on Mars and tapers once the engine clears the gantry.
        local dust = power*math.max(0,1-rise/65)
        rate("Dust",120*dust)
        state.power,state.dustPower,state.height = power,dust,at.y
    end
    function result.Describe()
        return {active=state~=nil,systems=state and state.systems or {},
            power=state and state.power or 0,dustPower=state and state.dustPower or 0,
            nozzleHeight=state and state.height or nil,nozzles=#Layout.nozzles,
            light=state and state.light~=nil or false}
    end
    return result
end
return FX
