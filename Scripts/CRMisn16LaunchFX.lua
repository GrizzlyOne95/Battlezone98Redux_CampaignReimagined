-- Peer-local presentation only. No objects, AI commands, damage or wire events.
local FX = {}
function FX.Create(api)
    local x, state = api.exu, nil
    local function call(name, ...)
        if type(x[name]) ~= "function" then return nil end
        local ok, value = pcall(x[name], ...)
        if ok then return value end
    end
    local function cleanup()
        if not state then return end
        for _, slot in ipairs(state.slots) do
            for _, name in pairs(slot.systems) do call("DestroyParticleSystem", name) end
        end
        state.slots = {};state.active = false
    end
    local function reset()
        cleanup()
        state = {slots={}, attempted=false, active=false, finished=false, lights=0}
    end
    reset()
    local function fail(reason)
        cleanup();state.error = tostring(reason);state.finished = true
        api.log("[misn16] launch effects unavailable: " .. state.error)
    end
    local function system(slot, kind, template, at, attached)
        local name = "CR16/Launch/" .. slot.index .. "/" .. kind
        if call("CreateParticleSystem", name, template, at) ~= true then return false end
        slot.systems[kind] = name
        call("SetParticleSystemKeepLocalSpace", name, false)
        call("SetParticleSystemNonVisibleUpdateTimeout", name, 0)
        if attached and call("AttachParticleSystemToObject", name, slot.handle, api.vector(0,12,0)) ~= true then
            return false
        end
        call("SetParticleEmitterEmissionRate", name, 0, 0)
        return true
    end
    local function start(parts, age)
        state.attempted = true
        for _, name in ipairs({"CreateParticleSystem", "DestroyParticleSystem",
                "AttachParticleSystemToObject", "SetParticleEmitterEmissionRate"}) do
            if type(x[name]) ~= "function" then fail(name .. " missing");return end
        end
        local ok, loaded, reason = pcall(api.templates)
        if not ok or not loaded then fail(reason or loaded or "particle templates");return end
        for i=1,4 do
            local label = "cr16_engine" .. i
            local origin, handle = parts[label], api.handle(label)
            if origin and api.valid(handle) then
                local slot = {index=i,handle=handle,systems={}}
                state.slots[#state.slots+1] = slot
                local at = api.position(handle)
                if not system(slot,"Plume","CR/M16/Exhaust",at,true)
                        or not system(slot,"Core","CR/M16/Nozzle",at,true) then
                    fail("thruster attachment " .. i);return
                end
                -- Grounded dust never follows the rising engines. A resumed
                -- launch past the ground-wash phase must not replay ignition.
                if age < 7 then
                    local ground = api.vector(origin.x,origin.y,origin.z)
                    local height = api.terrain and api.terrain(ground) or origin.y
                    ground = api.vector(origin.x,height+0.6,origin.z)
                    if not system(slot,"Dust","CR/M16/PadDust",ground,false) then
                        fail("ground wash " .. i);return
                    end
                end
            end
        end
        state.active = #state.slots > 0
    end
    local result = {}
    function result.Update(parts, age)
        local hull = api.handle("cr16_transport")
        if state.finished then return end
        if age >= 30 or not api.valid(hull) then result.Stop();return end
        if not state.attempted then start(parts,age) end
        if not state.active then return end
        local power = math.min(1,math.max(0,age/1.5))
        local rise = age*age
        local dust = power * math.min(1,math.max(0,(45-rise)/35))
        state.dustPower = dust
        for _, slot in ipairs(state.slots) do
            if api.valid(slot.handle) then
                call("SetParticleEmitterEmissionRate",slot.systems.Plume,0,125*power)
                call("SetParticleEmitterEmissionRate",slot.systems.Core,0,45*power)
                if slot.systems.Dust then
                    call("SetParticleEmitterEmissionRate",slot.systems.Dust,0,85*dust)
                    if age >= 11 then
                        call("DestroyParticleSystem",slot.systems.Dust);slot.systems.Dust=nil
                    end
                end
            else
                for kind,name in pairs(slot.systems) do call("DestroyParticleSystem",name);slot.systems[kind]=nil end
            end
        end
        -- MakeExplosion is local-only. Zero-damage light particles illuminate
        -- the nozzle/pad briefly on every peer, without spawning gameplay units.
        if api.explosion and age < 17 and power > 0.1 and (not state.lightAt or age >= state.lightAt) then
            state.lightAt = age + 0.2
            for _, slot in ipairs(state.slots) do
                if api.valid(slot.handle) then
                    local p = api.position(slot.handle)
                    api.explosion("cr16ign",api.vector(p.x,p.y+11,p.z))
                    state.lights = state.lights + 1
                end
            end
        end
    end
    function result.Stop() cleanup();state.finished=true end
    function result.Reset() reset() end
    function result.Describe()
        local row = {active=state.active,attempted=state.attempted,error=state.error,
            plumes=0,cores=0,dust=0,lights=state.lights,dustPower=state.dustPower or 0}
        for _, slot in ipairs(state.slots) do
            if slot.systems.Plume then row.plumes=row.plumes+1 end
            if slot.systems.Core then row.cores=row.cores+1 end
            if slot.systems.Dust then row.dust=row.dust+1 end
        end
        return row
    end
    return result
end
return FX
