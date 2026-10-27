-- Loads the REAL Scripts/CRStorm18.lua (with the real CRWeather, CRWeatherPresets and CRFoliageWind) into a
-- Misn18Fixture peer, against a recording EXU stub. Particle templates, ground FX and wet glass are stubbed
-- (their payloads are linted by Test-CRStorm18.lua). Each peer gets its own module instances in its own
-- environment, so nothing is shared between peers except the fixture world.
--
--   local RealStorm = dofile("Tools/Misn18RealStorm.lua")(F)
--   F.makePeer(id, team, net, {storm = RealStorm})
--
-- What it records on each peer (peer.calls): NativeQuake <start|update|stop> <magnitude> (the storm's own
-- engine calls; the mission's are StartEarthquake/UpdateEarthQuake), TornadoVelocity, TornadoDamage, and
-- StormPrint for anything the storm printed. peer.stormModule is the loaded module.
return function(F)
    local function owner(W, peer, h)
        -- Players belong to their own machine; everything else (AI, built craft) to the host.
        for _, q in pairs(W.peers) do
            if q.player == h then return q == peer end
        end
        return peer.hosting
    end
    return function(peer, record, e, modules)
        local W = F.world()
        local se = setmetatable({}, {__index = e})
        se._G = se
        se.print = function(...)
            local t = {}
            for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
            record("StormPrint", table.concat(t, " "))
        end
        se.StartSound = function(file) record("StormSound", file) end
        se.StartEarthquake = function(m) record("NativeQuake", "start", m) end
        se.UpdateEarthQuake = function(m) record("NativeQuake", "update", m) end
        se.StopEarthquake = function() record("NativeQuake", "stop", 0) end
        se.MakeExplosion = function() end
        se.IsBuilding = function(h) return W.objects[h] and not W.objects[h].craft end
        se.IsLocal = function(h) return owner(W, peer, h) end
        se.GetVelocity = function(h) W.objects[h].vel = W.objects[h].vel or {x = 0, y = 0, z = 0}; return W.objects[h].vel end
        se.SetVelocity = function(h, v)
            W.objects[h].vel = {x = v.x, y = v.y, z = v.z}
            record("TornadoVelocity", h)
        end
        se.Damage = function(h, amount)
            if W.objects[h] and W.objects[h].odf:match("^c17frst") then
                record("TreeDamage",h,amount);W.objects[h].alive=false
            else record("TornadoDamage", h, amount) end
        end

        -- A recording EXU: only the calls the storm and CRWeather make. Everything is permissive.
        local x = modules.exu
        local function def(name, fn) x[name] = x[name] or fn end
        def("GetFog", function() return {r = .5, g = .4, b = .3, fogStart = 100, fogEnd = 250} end)
        def("SetFog", function() return true end)
        def("GetAmbientLight", function() return {r = .5, g = .5, b = .5} end)
        def("SetAmbientLight", function() return true end)
        def("GetSunDiffuse", function() return {r = .6, g = .6, b = .6} end)
        def("SetSunDiffuse", function() return true end)
        def("GetSunPowerScale", function() return 1 end)
        def("SetSunPowerScale", function() return true end)
        def("GetCameraClipDistances", function() return 0.5, 1125 end)
        def("MaterialExists", function() return true end)
        def("GetSkyPlaneEnabled", function() return false end)
        def("GetSkyDomeEnabled", function() return false end)
        def("GetSkyBoxEnabled", function() return false end)
        local systems = {}
        def("CreateParticleSystem", function(name) if systems[name] then return false end systems[name] = true; return true end)
        def("DestroyParticleSystem", function(name) local had = systems[name]; systems[name] = nil; return had == true end)
        for _, n in ipairs({"SetMaterialPassColors", "SetMaterialTextureScrollAnimation", "SetMaterialTextureRotateAnimation",
            "SetSkyPlane", "SetSkyPlaneEnabled", "DetachParticleSystem", "SetParticleSystemKeepLocalSpace",
            "SetParticleSystemNonVisibleUpdateTimeout", "SetParticleSystemParticleQuota", "AttachParticleSystemToCamera",
            "SetParticleEmitterEnabled", "SetParticleEmitterVelocity", "SetParticleEmitterTimeToLive",
            "SetParticleEmitterAngle", "SetParticleEmitterColor", "SetParticleEmitterParameter",
            "SetParticleAffectorParameter", "SetParticleSystemPosition", "SetParticleSystemDirection",
            "SetParticleSystemEmitting", "SetParticleSystemVisible", "SetParticleEmitterEmissionRate",
            "SetParticleEmitterPosition", "SetParticleEmitterDirection", "CreateStaticGeometry", "DestroyStaticGeometry",
            "CreatePointLight", "SetPointLightPosition", "SetPointLightPowerScale", "DestroyPointLight"}) do
            def(n, function() return true end)
        end
        def("UpdateParticleFollowers", function() return 0 end)
        def("GetParticleSystemEmitterCount", function() return 6 end)
        def("GetParticleSystemAffectorCount", function() return 6 end)
        def("SetEntityRenderingDistance", function(h,d) record("TreeCull",h,d);return true end)

        local stubs = {
            exu = x,
            CRParticleTemplates = {Ensure = function() return true end, EnsureExtra = function() return true end},
            CRGroundFX = {Bolt = function() return true end, BoltStroke = function() end, Event = function() end,
                Update = function() end, Stop = function() end},
            CRWetGlass = {Update = function() end, Stop = function() end, Splat = function() end, SetCrack = function() end},
            Environment = modules.Environment,
        }
        local loaded = {}
        se.require = function(name)
            if stubs[name] then return stubs[name] end
            if loaded[name] == nil then
                local f = assert(loadfile("Scripts/" .. name .. ".lua"))
                setfenv(f, se)
                loaded[name] = f() or true
            end
            return loaded[name]
        end
        se.package = {loaded = {}}
        local real = se.require("CRStorm18")
        peer.stormModule = real
        -- Same module, with the mission-facing calls recorded (the real behaviour is untouched).
        return {Create = function(api)
            local d = real.Create(api)
            local setPhase, apply = d.SetPhase, d.Apply
            d.SetPhase = function(name) record("StormPhase", name); return setPhase(name) end
            d.Apply = function(kind, ...) record("StormApply", kind); return apply(kind, ...) end
            peer.director = d
            return d
        end}
    end
end
