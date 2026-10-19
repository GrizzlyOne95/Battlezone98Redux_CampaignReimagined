-- CRStorm18: the storm that tears mission 18's moon apart. See Docs/MISN18_STORM.md
-- for the design, the phase table, the tunables and the wiring contract.
--
-- Wiring is CRJungle17's, plus one leader-side call:
--   local Storm = require("CRStorm18").Create({exu = exu, state = function() return M end,
--       players = function() ... end})          -- players: optional, {x, y, z} per human
--   Storm.Reset(saved)                           -- at Start and Load (alias Init, Load)
--   Environment.BindWeatherSensors("Achilles", Storm)
--   Storm.Update(dt, CRCoop.IsAuthority(), function(...) Present("Storm", ...) end)
--   Storm.Apply(...)                             -- Present's receiver, every peer (alias Receive)
--   Storm.SetPhase("core1")                      -- leader only
--   Storm.Quake(magnitude, seconds)              -- every peer: a mission quake request (see below)
--   Storm.Save() / Storm.Stop()
--
-- Only the leader decides anything: its phase, bolt, quake, landslide and tornado
-- events are the whole of the shared state. Every peer renders the storm itself,
-- from those events and the shared seed, around its own camera. The module
-- builds no game object. The one gameplay effect, the tornado's pull, runs on
-- every peer against the replicated funnel and touches only the craft that peer
-- owns (CRStorm18Tornado.EFFECT). While the storm runs it owns the native
-- earthquake: the mission's own quake requests come in through Storm.Quake.
--
-- Every engine call is guarded: no EXU, an EXU without a feature, or a failed
-- script degrades to less storm, never to an error. Update and Apply run inside
-- pcall, because a Lua error in co-op can close the host.
local Rng = require("CRStorm18Rng")
local Tornado = require("CRStorm18Tornado")
local Ground = require("CRStorm18Ground")
local WaterFx = require("CRStorm18Water")

local Storm = {}

Storm.PHASES = { "opening", "search", "found", "core1", "core2", "core3", "collapse", "final", "extract", "ascent", "won", "lost" }
local INDEX = {}
for i, name in ipairs(Storm.PHASES) do INDEX[name] = i end
local FINAL = 8   -- the last rung with its own weather preset (extract and ascent reuse it)
local LAST = 10   -- the last rung with a profile row; won and lost (11, 12) hold it

-- One row per phase (won and lost hold the final look).
--   level    0..1 storm strength: wind, sky, fog and light all follow it
--   bolt     seconds between lightning strikes (min, max)
--   dry      fraction of strikes that stay in the cloud (no ground strike)
--   quake    seconds between quake pulses (min, max); qStr strength, qDur seconds
--   rumble   continuous shake under the pulses (0..1)
--   slide    seconds between landslides (nil: none yet)
--   crack    0..1 how much of the ground has split
--   tornado  the funnel is on the map
--   trans    seconds the weather takes to blend in
--   safe     the tornado's gameplay effect is off (the extraction ending: nothing may hurt the craft)
--   wind     extra wind multiplier (the ascent rushes through the clouds)
--   burstBolt strike interval (min, max) during a burst (default 0.5-1.1)
--   burst    seconds of extra-hard entry (collapse): the phase change plays over the
--            ~6-10 s thruster cinematic, so the storm must read on camera inside it
local PROFILE = {
    { name = "opening",  level = 0.14, bolt = { 26, 48 },  dry = 0.80, quake = { 50, 85 }, qStr = 0.10, qDur = 3.0, rumble = 0.00, crack = 0.00, trans = 10 },
    { name = "search",   level = 0.26, bolt = { 16, 30 },  dry = 0.65, quake = { 32, 58 }, qStr = 0.14, qDur = 3.2, rumble = 0.00, crack = 0.00, trans = 12 },
    { name = "found",    level = 0.40, bolt = { 10, 19 },  dry = 0.45, quake = { 22, 40 }, qStr = 0.22, qDur = 3.5, rumble = 0.03, crack = 0.00, trans = 10 },
    { name = "core1",    level = 0.54, bolt = { 7, 13 },   dry = 0.30, quake = { 16, 28 }, qStr = 0.30, qDur = 4.0, rumble = 0.06, crack = 0.12, trans = 8, slide = { 70, 100 } },
    { name = "core2",    level = 0.68, bolt = { 4.5, 9 },  dry = 0.20, quake = { 11, 20 }, qStr = 0.40, qDur = 4.5, rumble = 0.10, crack = 0.32, trans = 8, slide = { 45, 70 } },
    { name = "core3",    level = 0.82, bolt = { 2.8, 5.5 }, dry = 0.10, quake = { 7, 13 }, qStr = 0.52, qDur = 5.0, rumble = 0.16, crack = 0.58, trans = 7, slide = { 28, 45 } },
    { name = "collapse", level = 0.96, bolt = { 1.4, 3.0 }, dry = 0.00, quake = { 3.5, 7 }, qStr = 0.70, qDur = 5.5, rumble = 0.30, crack = 0.85, trans = 4, slide = { 12, 20 }, tornado = true, burst = 9 },
    { name = "final",    level = 1.00, bolt = { 0.7, 1.8 }, dry = 0.00, quake = { 2.5, 4.5 }, qStr = 0.90, qDur = 6.0, rumble = 0.45, crack = 1.00, trans = 4, slide = { 6, 11 }, tornado = true },
    -- The extraction ending: dropships load at the rendezvous, then climb through the storm. Same look as
    -- final, harmless to craft; the ascent is the most violent rung (strikes every 0.2-0.5 s, hard shake, gale).
    { name = "extract",  level = 1.00, bolt = { 0.7, 1.8 }, dry = 0.00, quake = { 2.5, 4.5 }, qStr = 0.90, qDur = 6.0, rumble = 0.45, crack = 1.00, trans = 3, slide = { 6, 11 }, tornado = true, safe = true },
    { name = "ascent",   level = 1.00, bolt = { 0.2, 0.5 }, dry = 0.00, quake = { 1.2, 2.5 }, qStr = 1.00, qDur = 3.0, rumble = 0.70, crack = 1.00, trans = 2, tornado = true, safe = true, wind = 1.7, burst = 14, burstBolt = { 0.2, 0.5 } },
}
Storm.PROFILE = PROFILE

-- Tunables ---------------------------------------------------------------------
Storm.TUNING = {
    QUAKE_SCALE = 3.0,      -- native earthquake magnitude = strength x this (stock misn18 uses 2 to 6)
    QUAKE_MAX = 3.5,        -- never drive the native shake harder than this
    WAYPOINT_EVERY = 9,     -- s between tornado waypoints (and its resync to the guests)
    RESYNC = 15,            -- s between the leader's phase and tornado repeats (late joiners, drift)
    PUSH_STEP = 0.25,       -- s between tornado effect passes (each peer, its own craft)
    MISSION_QUAKE_SECONDS = 3.5, -- default hold of a mission quake request (the pulse repeats every 3 s)
    CLOUD_D = 1450,         -- sky plane height; fitted to the far clip like Weather.lua
    CLOUD_SCALE = 2400,
    CLOUD_TILING = 24,      -- must match plane.xx = 12 in cr18_swirl.program
    FAR_FRACTION = 0.15,
}
local T = Storm.TUNING

local SKY_MATERIAL = "CR18/StormSwirl"
local GROUND_MATERIAL = "CR18/GroundWind"
local FALLBACK_GROUND = "CR17/GroundWind"
local PAYLOAD = "cr18_storm"
local THUNDER = { near = { "thunder.wav", "thund02.wav" }, mid = { "xlitblt1.wav", "xlitblt2.wav" }, far = { "xlitblt3.wav", "atlas.wav" } }

local floor, sin, cos, sqrt, max, min = math.floor, math.sin, math.cos, math.sqrt, math.max, math.min

local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function smooth(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, a in pairs(v) do t[k] = copy(a) end
    return t
end

local function profile(idx)
    idx = floor(tonumber(idx) or 1)
    if idx > LAST then return PROFILE[FINAL] end -- won and lost hold the final look
    return PROFILE[clamp(idx, 1, LAST)]
end

-- Presets ------------------------------------------------------------------------
-- One preset per storm phase, built at load into the shared preset table under
-- Misn18Storm<n> (no edit to CRWeatherPresets.lua). CRWeather multiplies every
-- emitter rate by the preset's blend weight, so these are the rates at full
-- weight; the phase change crossfades between presets over `trans` seconds.
local function colour(r, g, b, a) return { r = r, g = g, b = b, a = a } end

function Storm.BuildPresets(Presets)
    local table_ = Presets.Presets
    for i = 1, FINAL do
        local P = PROFILE[i]
        local f = P.level
        local p = {
            name = "Misn18Storm" .. i,
            precipitation = {
                { system = "cr18_wx_dust", template = "CR18/Dust", offset = { x = 0, y = 35, z = 0 }, quota = 2200,
                  emitters = { [0] = {
                      rate = lerp(40, 360, f), velocity = { lerp(14, 34, f), lerp(26, 58, f) }, ttl = { 2.0, 3.4 }, angle = 22,
                      color = { start = colour(lerp(0.46, 0.30, f), lerp(0.22, 0.10, f), lerp(0.14, 0.07, f), lerp(0.34, 0.55, f)),
                                finish = colour(lerp(0.34, 0.22, f), lerp(0.14, 0.07, f), lerp(0.10, 0.05, f), lerp(0.20, 0.34, f)) },
                      params = { width = lerp(200, 300, f), height = lerp(60, 110, f), depth = lerp(200, 300, f) } } },
                  affectors = { [0] = { alpha = lerp(-0.22, -0.12, f) },
                                [1] = { randomness = lerp(2, 12, f), scope = lerp(0.2, 0.5, f) } } },
                { system = "cr18_wx_streak", template = "CR18/Streak", offset = { x = 0, y = 12, z = 0 }, quota = 700,
                  emitters = { [0] = {
                      rate = max(0, lerp(-8, 62, f)), velocity = { lerp(40, 62, f), lerp(60, 98, f) }, ttl = { 1.4, 2.2 }, angle = 6,
                      params = { width = lerp(200, 300, f), depth = lerp(200, 300, f) } } },
                  affectors = { [0] = { alpha = lerp(-0.26, -0.14, f) }, [1] = { rate = lerp(1.2, 3.0, f) } } },
                { system = "cr18_wx_haze", template = "CR18/Haze", offset = { x = 0, y = 12, z = 0 }, quota = 380,
                  emitters = { [0] = {
                      rate = lerp(12, 32, f), velocity = { 3, 9 }, ttl = { 6.0, 9.5 }, angle = 60,
                      color = { start = colour(lerp(0.40, 0.30, f), lerp(0.16, 0.08, f), lerp(0.10, 0.05, f), lerp(0.14, 0.26, f)),
                                finish = colour(lerp(0.26, 0.18, f), lerp(0.09, 0.05, f), lerp(0.06, 0.04, f), lerp(0.05, 0.10, f)) } } },
                  affectors = { [0] = { alpha = -0.018 } } },
                { system = "cr18_wx_ash", template = "CR18/Ash", offset = { x = 0, y = 30, z = 0 }, quota = 1400,
                  emitters = { [0] = { rate = lerp(14, 150, f), velocity = { lerp(6, 14, f), lerp(14, 30, f) }, ttl = { 3.0, 5.5 }, angle = 30 } },
                  affectors = { [0] = { alpha = -0.04 } } },
                { system = "cr18_wx_cinder", template = "CR18/Cinder", offset = { x = 0, y = 12, z = 0 }, quota = 700,
                  emitters = { [0] = { rate = lerp(2, 70, f * f), velocity = { lerp(10, 22, f), lerp(24, 50, f) }, ttl = { 1.6, 3.4 }, angle = 24 } },
                  affectors = { [0] = { alpha = -0.28 } } },
                { system = "cr18_wx_debris", template = "CR18/Debris", offset = { x = 0, y = 6, z = 0 }, quota = 420,
                  emitters = { [0] = { rate = max(0, lerp(-14, 52, f)), velocity = { lerp(34, 56, f), lerp(60, 98, f) }, ttl = { 1.1, 2.0 }, angle = 14 } },
                  affectors = { [0] = { alpha = -0.12 }, [2] = { randomness = lerp(3, 10, f), scope = 0.45 } } },
            },
            gusts = { period = lerp(13, 5, f), depth = lerp(0.22, 0.60, f) },
            sky = nil,
            -- Fog stays inside the terrain horizon (Environment caps it at the TRN
            -- visibility, 250 m) and mild: the near-field haze carries the gloom,
            -- because heavy global fog greys the DX11 Enhanced terrain.
            fog = { r = lerp(0.34, 0.10, f), g = lerp(0.16, 0.03, f), b = lerp(0.11, 0.02, f),
                    fogStart = lerp(120, 55, f), fogEnd = lerp(250, 185, f) },
            ambient = { r = lerp(0.40, 0.15, f), g = lerp(0.24, 0.07, f), b = lerp(0.19, 0.05, f) },
            diffuse = { r = lerp(0.66, 0.34, f), g = lerp(0.36, 0.10, f), b = lerp(0.24, 0.05, f) },
            sunPowerScale = lerp(0.72, 0.14, f),
            wind = { x = -0.92, y = 0.06, z = -0.38 },
            windSpeed = 6 + 40 * f,
            lightning = nil, -- bolts are leader events, never CRWeather's local timer
            transitionIn = P.trans,
            transitionOut = 15,
        }
        table_[p.name] = p
    end
end

-- Director ------------------------------------------------------------------------
function Storm.Create(api)
    api = api or {}
    local x = api.exu or rawget(_G, "exu") or {}
    local S = { Initialized = false, Enabled = true }
    local Weather = require("CRWeather")
    local Presets = require("CRWeatherPresets")
    local Glass = require("CRWetGlass")
    local Templates = require("CRParticleTemplates")
    local Foliage = require("CRFoliageWind")
    local Wake = require("CRWake")
    local okS, Sites = pcall(require, "CRStorm18Sites")
    if not okS or type(Sites) ~= "table" then
        print("CRStorm18: site data unavailable (" .. tostring(Sites) .. "); no ground cover")
        Sites = { layers = {}, zones = {}, bounds = { 0, 97280, 2560, 102400 } }
    end
    local okE, E = pcall(require, "Environment")
    if not okE then E = nil end
    local okG, GroundFX = pcall(require, "CRGroundFX")
    if not okG then GroundFX = nil end

    Storm.BuildPresets(Presets)

    local zones = Sites.zones or {}
    local bounds = Sites.bounds or { 0, 97280, 2560, 102400 }
    local state, clock, lvl
    local water, ground, tornadoFx, templatesReady, nextTemplates, errorCount, lastError
    local sky, skyRetry, skyWritten, nextSkyWrite, baseSkyPlane
    local applied, view, nextView, nextWind, nextQuake, nextSkyAnim, nextPush
    local quake, nativeQuake, nextNative, missionQuakes
    local flashAt, flashPower, strokes, sounds, shown
    local boltsSeen, groundMaterial, gctx, burstEnd

    -- Guarded engine access ------------------------------------------------------
    local function call(name, ...)
        local f = x[name]
        if type(f) ~= "function" then return nil end
        local ok, r = pcall(f, ...)
        if ok then return r end
        return nil
    end
    local function call2(name, ...)
        local f = x[name]
        if type(f) ~= "function" then return nil, "EXU " .. name .. " unavailable" end
        local ok, a, b = pcall(f, ...)
        if ok then return a, b end
        return nil, a
    end
    local function vec(a, b, c) return SetVector(a, b, c) end
    local function sound(file, where)
        if type(StartSound) ~= "function" then return end
        pcall(StartSound, file, where)
    end
    local function hash(seed, a, b, c) return Rng.Hash(seed, a, b, c) end
    local function seed() return state and state.seed or 18018 end

    local function terrain(px, pz)
        if type(GetTerrainHeightAndNormal) ~= "function" then return nil end
        local ok, h, n = pcall(GetTerrainHeightAndNormal, vec(px, 0, pz))
        if ok and finite(h) then return h, n end
        return nil
    end

    local function ensureTemplates()
        if templatesReady then return true end
        if clock and clock < (nextTemplates or 0) then return false end
        nextTemplates = (clock or 0) + 20
        local ok, loaded, why = pcall(Templates.EnsureExtra, PAYLOAD)
        templatesReady = ok and loaded == true
        if not templatesReady then
            print("CRStorm18: particle templates unavailable (" .. tostring(ok and why or loaded) .. ")")
        end
        return templatesReady
    end

    -- Where this peer is looking: the camera when EXU can say, else the player.
    local function viewpoint()
        local m = call("GetCameraTransformMatrix")
        if type(m) == "table" or type(m) == "userdata" then
            local ok, px, py, pz = pcall(function()
                if m.posit_x ~= nil then return m.posit_x, m.posit_y, m.posit_z end
                local p = m.posit or m.position
                if p ~= nil then return p.x, p.y, p.z end
            end)
            if ok and finite(px) and finite(pz) then return { x = px, y = py or 0, z = pz } end
        end
        if type(GetPlayerHandle) == "function" and type(GetPosition) == "function" then
            local ok, p = pcall(function() return GetPosition(GetPlayerHandle()) end)
            if ok and p and finite(p.x) and finite(p.z) then return { x = p.x, y = p.y or 0, z = p.z } end
        end
        return nil
    end

    -- Every human's position (leader targeting), or just the local player.
    local function anchors()
        local list = {}
        if type(api.players) == "function" then
            local ok, got = pcall(api.players)
            if ok and type(got) == "table" then
                for _, p in ipairs(got) do
                    if type(p) == "table" and finite(p.x) and finite(p.z) then list[#list + 1] = { x = p.x, z = p.z } end
                end
            end
        end
        if #list == 0 and view then list[1] = { x = view.x, z = view.z } end
        return list
    end

    -- Sky ----------------------------------------------------------------------------
    local function fitPlane(d, scale)
        local ok, _, far = pcall(x.GetCameraClipDistances or function() return nil end)
        far = ok and tonumber(far) or nil
        if far == nil or far <= 0 or d <= far * T.FAR_FRACTION then return d, scale end
        local k = (far * T.FAR_FRACTION) / d
        return d * k, scale * k
    end

    local function skyColours(l, flash)
        local g = l * l
        return {
            ambient = { r = lerp(0.14, 0.012, l), g = lerp(0.045, 0.0, l), b = lerp(0.03, 0.0, l), a = 1 },
            diffuse = { r = lerp(0.95, 0.85, l), g = lerp(0.34, 0.10, l), b = lerp(0.14, 0.03, l), a = lerp(0.25, 0.75, l) },
            emissive = { r = lerp(0.90, 1.00, l) + 0.1 * flash, g = lerp(0.28, 0.16, l) + 0.7 * flash, b = lerp(0.06, 0.02, l) + 0.5 * flash,
                         a = min(1, lerp(0.12, 1.0, g) + 0.8 * flash) },
            specular = { r = lerp(1.5, 9, l), g = 0, b = 0, a = 0 },
        }
    end

    local function writeSky(l, flash)
        if sky ~= "on" then return end
        local c = skyColours(l, flash)
        call("SetMaterialPassColors", SKY_MATERIAL, c, -1, -1, nil, false)
        skyWritten = l
    end

    local function skyAnimation(windSpeed, l)
        if sky ~= "on" then return end
        call("SetMaterialTextureScrollAnimation", SKY_MATERIAL, 0.0035 + 0.0007 * windSpeed, 0.0012 + 0.0002 * windSpeed, 0, 0, 0, "General")
        call("SetMaterialTextureRotateAnimation", SKY_MATERIAL, lerp(0.0015, 0.006, l), 0, 0, 0, "General")
    end

    local function setSky(on)
        if type(x.SetSkyPlane) ~= "function" or type(x.SetSkyPlaneEnabled) ~= "function" then
            if on then sky = "unsupported" end
            return
        end
        if not on then
            if sky == "on" then call("SetSkyPlaneEnabled", false); sky = "off" end
            return
        end
        if sky == "on" or sky == "skipped" or sky == "unsupported" then return end
        if (clock or 0) < (skyRetry or 0) then return end
        if baseSkyPlane then sky = "skipped"; return end
        if call("MaterialExists", SKY_MATERIAL, "General") == false then
            sky, skyRetry = "missing", (clock or 0) + 30
            return
        end
        local d, scale = fitPlane(T.CLOUD_D, T.CLOUD_SCALE)
        local r = call("SetSkyPlane", SKY_MATERIAL, { normal = vec(0, -1, 0), d = d }, scale, T.CLOUD_TILING, true, 0, 8, 8, "General")
        if r == false or r == nil then
            sky, skyRetry = "failed", (clock or 0) + 30
            return
        end
        call("SetSkyPlaneEnabled", true)
        sky = "on"
        writeSky(lvl or 0, 0)
        skyAnimation(6 + 40 * (lvl or 0), lvl or 0)
    end

    -- Calm: every shared material is left as the next mission expects to find it.
    local function calmMaterials()
        local c = skyColours(0, 0)
        c.emissive.a, c.diffuse.a = 0.10, 0.30
        c.specular.r = 0
        call("SetMaterialPassColors", SKY_MATERIAL, c, -1, -1, nil, false)
        call("SetMaterialTextureScrollAnimation", SKY_MATERIAL, 0, 0, 0, 0, 0, "General")
        call("SetMaterialTextureRotateAnimation", SKY_MATERIAL, 0, 0, 0, 0, "General")
    end

    -- Quakes ------------------------------------------------------------------------
    local function envelope(q, age)
        local rise, fall = max(0.15, q.dur * 0.18), max(0.4, q.dur * 0.40)
        if rise + fall > q.dur then local k = q.dur / (rise + fall); rise, fall = rise * k, fall * k end
        if age <= 0 then return 0 end
        if age < rise then return smooth(age / rise) end
        if age < q.dur - fall then return 1 end
        if age < q.dur then return 1 - smooth((age - (q.dur - fall)) / fall) end
        return 0
    end

    local function nativeStop()
        if not nativeQuake then return end
        nativeQuake = false
        if type(StopEarthquake) == "function" then pcall(StopEarthquake) end
    end

    -- Mission quake requests (the stock StartEarthquake / UpdateEarthQuake calls, routed here by
    -- the mission): each is a native-scale magnitude held for its seconds with the same rise and
    -- fall as a storm pulse. The shake is the strongest of the storm's and every live request, so
    -- nothing fights over the one native earthquake. Peer-local: the mission replicates its own
    -- requests, so every peer receives the same ones.
    local function missionMagnitude()
        local best = 0
        for i = #missionQuakes, 1, -1 do
            local q = missionQuakes[i]
            local age = clock - q.start
            if age >= q.dur then
                table.remove(missionQuakes, i)
            else
                best = max(best, q.mag * envelope(q, age))
            end
        end
        return best
    end

    local function updateQuake()
        local P = profile(state.phase)
        local base = P.rumble * smooth(lvl or 0)
        local pulse = 0
        if quake then
            local age = clock - quake.start
            if age >= quake.dur then quake = nil else pulse = quake.strength * envelope(quake, age) end
        end
        local mag = max(min(T.QUAKE_MAX, max(pulse, base) * T.QUAKE_SCALE), missionMagnitude())
        S.quakeMagnitude = mag
        if mag < 0.05 then nativeStop(); return end
        if clock < (nextNative or 0) then return end
        nextNative = clock + 0.05
        if not nativeQuake then
            nativeQuake = true
            if type(StartEarthquake) == "function" then pcall(StartEarthquake, mag) end
        elseif type(UpdateEarthQuake) == "function" then
            pcall(UpdateEarthQuake, mag)
        end
    end

    -- Strikes -----------------------------------------------------------------------
    local function startBolt(n, power, groundStrike)
        flashAt, flashPower = clock, 0.5 + 0.5 * clamp(power, 0, 1)
        local l = lvl or 0
        if groundStrike and view then
            local near = lerp(150, 50, l * l)
            local far = lerp(300, 170, l)
            local a = hash(seed(), n, 1, 21) * 6.2831853
            local d = near + (far - near) * hash(seed(), n, 2, 22)
            local sx, sz = view.x + cos(a) * d, view.z + sin(a) * d
            local gh = terrain(sx, sz)
            if gh then
                local c = { 1.0, 0.80, 0.52 }
                local drawn = false
                if GroundFX then
                    local okb, res = pcall(GroundFX.Bolt, sx, gh, sz, c[1], c[2], c[3])
                    drawn = okb and res == true
                end
                local count = 1 + floor(hash(seed(), n, 3, 23) * 3.4)
                local t = clock
                for k = 1, count do
                    strokes[#strokes + 1] = { at = t, channel = drawn, first = k == 1, x = sx, y = gh, z = sz }
                    t = t + 0.05 + 0.11 * hash(seed(), n, 4 + k, 24)
                end
                local list = d < 130 and THUNDER.near or (d < 240 and THUNDER.mid or THUNDER.far)
                sounds[#sounds + 1] = { at = clock + clamp(d / 343, 0.12, 3.5), file = list[1 + floor(hash(seed(), n, 5, 25) * #list)] }
                if d < 80 and l > 0.5 then
                    pcall(Glass.Splat, 0.35 + 0.4 * hash(seed(), n, 6, 26), 0.2 + 0.6 * hash(seed(), n, 7, 27), 0.3 + 0.3 * hash(seed(), n, 8, 28), hash(seed(), n, 9, 29) < 0.5)
                end
                return
            end
        end
        local list = THUNDER.far
        sounds[#sounds + 1] = { at = clock + 0.4 + 2.2 * hash(seed(), n, 5, 30), file = list[1 + floor(hash(seed(), n, 6, 31) * #list)] }
    end

    local function runStrokes()
        local keep = {}
        for _, s in ipairs(strokes) do
            if clock >= s.at then
                if s.channel and GroundFX then pcall(GroundFX.BoltStroke) end
                if s.first then
                    local pos = vec(s.x, s.y, s.z)
                    if GroundFX then pcall(GroundFX.Event, "strike", pos) end
                    if type(MakeExplosion) == "function" then pcall(MakeExplosion, "xbgndyl", pos) end
                end
            else
                keep[#keep + 1] = s
            end
        end
        strokes = keep
        local rest = {}
        for _, s in ipairs(sounds) do
            if clock >= s.at then sound(s.file) else rest[#rest + 1] = s end
        end
        sounds = rest
        if GroundFX then pcall(GroundFX.Update) end
    end

    local function flashLevel()
        if not flashAt then return 0 end
        local age = clock - flashAt
        if age > 0.45 then return 0 end
        return (flashPower or 1) * max(0, 1 - age / 0.45) ^ 2
    end

    -- Presentation ---------------------------------------------------------------------
    local function presetFor(idx) return "Misn18Storm" .. clamp(idx, 1, FINAL) end

    local function enter(idx)
        if idx >= 7 and applied ~= nil and applied < 7 then burstEnd = clock + profile(7).burst end
        applied = idx
        local P = profile(idx)
        Weather.SetPreset(presetFor(idx), P.trans)
        S.target = P.level
        setSky(true)
    end

    local function updateWind(dt)
        if clock < (nextWind or 0) then return end
        nextWind = clock + 0.25
        local l = lvl or 0
        local age = state.age
        local bearing = math.rad(255 + 30 * sin(age / 41) + 10 * sin(age / 9.3))
        local spike = (1 + 0.3 * clamp(((burstEnd or 0) - clock) / 9, 0, 1)) * (profile(state.phase).wind or 1)
        local speed = (6 + 40 * l) * (0.9 + 0.1 * sin(age / 17 + 1.3)) * spike
        S.wind, S.bearing = speed, math.deg(bearing)
        Weather.SetWindOverride({ x = sin(bearing), y = 0.06, z = cos(bearing) }, speed)
        Weather.SetIntensity(1)
        return speed
    end

    -- Leader: the schedule -------------------------------------------------------------
    local function leaderRng() return state.rngBox end

    local function tick(send)
        local P = profile(state.phase)
        local rng = leaderRng()
        local age = state.age
        local resync = age >= state.nextSync
        if state.sentPhase ~= state.phase or resync then
            if state.sentPhase ~= nil and state.sentPhase ~= state.phase then
                -- A step up the ladder hits at once: a close strike and a hard shake.
                state.nextBolt, state.nextQuake = min(state.nextBolt, age + 0.6), min(state.nextQuake, age + 0.2)
                if state.phase >= 4 and state.phase <= LAST then
                    state.quakeN = state.quakeN + 1
                    send("quake", state.quakeN, clamp(P.qStr + 0.15, 0, 1), P.qDur + 1.5)
                end
                if P.slide then state.nextSlide = min(state.nextSlide, age + 4) end
                if P.burst then
                    -- Collapse: strikes every second or so, a landslide within 2.5 s.
                    state.burstUntil = age + P.burst
                    state.nextBolt, state.nextSlide = age + 0.3, min(state.nextSlide, age + 2.5)
                end
            end
            state.sentPhase = state.phase
            state.nextSync = age + T.RESYNC
            send("phase", state.phase, floor(age * 100 + 0.5) / 100, state.seed)
            if state.tornado then send("tornado", Tornado.Encode(state.tornado)) end
        end
        if age >= state.nextBolt then
            state.boltN = state.boltN + 1
            local ground_ = rng:Float() >= P.dry and 1 or 0
            send("bolt", state.boltN, floor((0.35 + 0.65 * P.level) * 100) / 100, ground_)
            if state.burstUntil and age < state.burstUntil then
                local bb = P.burstBolt or { 0.5, 1.1 }
                state.nextBolt = age + rng:Range(bb[1], bb[2])
            else
                state.nextBolt = age + rng:Range(P.bolt[1], P.bolt[2])
            end
        end
        if age >= state.nextQuake then
            state.quakeN = state.quakeN + 1
            send("quake", state.quakeN, floor(clamp(P.qStr * rng:Range(0.7, 1.15), 0, 1) * 100) / 100,
                floor(P.qDur * rng:Range(0.8, 1.3) * 10) / 10)
            state.nextQuake = age + rng:Range(P.quake[1], P.quake[2])
        end
        if P.slide and age >= state.nextSlide then
            state.slideN = state.slideN + 1
            send("slide", state.slideN, floor(clamp(0.45 + 0.55 * P.level * rng:Range(0.7, 1.2), 0, 1) * 100) / 100)
            state.nextSlide = age + rng:Range(P.slide[1], P.slide[2])
        end
        if P.tornado then
            local t = state.tornado
            if not t then
                state.tornado = Tornado.Spawn(rng, zones, bounds, anchors())
                state.nextWaypoint, state.nextTornadoSync = age + T.WAYPOINT_EVERY, age + T.RESYNC
                send("tornado", Tornado.Encode(state.tornado))
            else
                local dx, dz = t.wx - t.x, t.wz - t.z
                local arrived = dx * dx + dz * dz < 25 * 25
                if arrived or age >= state.nextWaypoint then
                    state.nextWaypoint = age + (Tornado.Pick(t, rng, zones, bounds, anchors()) and T.WAYPOINT_EVERY or 3)
                    send("tornado", Tornado.Encode(t))
                    state.nextTornadoSync = age + T.RESYNC
                elseif resync then
                    send("tornado", Tornado.Encode(t))
                end
            end
        end
    end

    -- Everyone: the picture ---------------------------------------------------------------
    local function localTick(dt)
        if applied ~= state.phase then enter(state.phase) end
        local P = profile(state.phase)
        lvl = lvl + (P.level - lvl) * (1 - math.exp(-dt / max(1, P.trans / 3)))
        if not templatesReady then ensureTemplates() end
        if clock >= nextView then nextView = clock + 0.2; view = viewpoint() or view end
        local wind = updateWind(dt)
        local t = state.tornado
        if t then Tornado.Step(t, dt, zones, bounds) end

        -- sky
        local flash = flashLevel()
        if sky ~= "on" then setSky(true) end
        if sky == "on" then
            if flash > 0.01 or clock >= (nextSkyWrite or 0) then
                nextSkyWrite = clock + (flash > 0.01 and 0.04 or 0.25)
                writeSky(lvl, flash)
            end
            if wind and clock >= (nextSkyAnim or 0) then
                nextSkyAnim = clock + 2
                skyAnimation(wind, lvl)
            end
        end

        updateQuake()
        runStrokes()
        if tornadoFx and ensureTemplates() then tornadoFx.Update(dt, t, view, clock) end
        if water then water.Update(dt, lvl, P.wind or 1) end
        if api.vehicleWakes ~= false then pcall(Wake.Update, dt) end
        if view and ground then ground.Update(dt, view, P.crack * smooth(min(1, lvl / max(0.01, P.level)))) end
        pcall(Glass.Update, 0)
        if state.phase >= 7 and (lvl or 0) > 0.85 then pcall(Glass.SetCrack, min(0.6, (lvl - 0.85) * 4), 0.62, 0.34) end
    end

    -- Public ------------------------------------------------------------------------------
    local function newState(saved)
        local s = type(saved) == "table" and copy(saved) or {}
        s.seed = floor(tonumber(s.seed) or tonumber(api.seed) or 18018)
        s.age = tonumber(s.age) or 0
        s.phase = clamp(floor(tonumber(s.phase) or 1), 1, #Storm.PHASES)
        s.rng = floor(tonumber(s.rng) or s.seed * 7 + 1)
        s.boltN, s.quakeN, s.slideN = floor(tonumber(s.boltN) or 0), floor(tonumber(s.quakeN) or 0), floor(tonumber(s.slideN) or 0)
        s.seenBolt, s.seenQuake, s.seenSlide = floor(tonumber(s.seenBolt) or 0), floor(tonumber(s.seenQuake) or 0), floor(tonumber(s.seenSlide) or 0)
        local P = profile(s.phase)
        s.nextBolt = tonumber(s.nextBolt) or (s.age + P.bolt[1])
        s.nextQuake = tonumber(s.nextQuake) or (s.age + P.quake[1])
        s.nextSlide = tonumber(s.nextSlide) or (s.age + (P.slide and P.slide[1] or 60))
        s.nextSync = 0 -- the leader re-announces after every load
        s.sentPhase = nil
        if type(s.tornado) ~= "table" then s.tornado = nil end
        s.rngBox = Rng.New(s.rng)
        return s
    end

    function S.Stop()
        S.Initialized = false
        nativeStop()
        if ground then ground.Stop() end
        if water then water.Stop() end
        pcall(Wake.Stop)
        if tornadoFx then tornadoFx.Destroy() end
        setSky(false)
        calmMaterials()
        pcall(Foliage.Stop)
        pcall(Weather.ClearWindOverride)
        pcall(Weather.Shutdown)
        pcall(Glass.SetCrack, 0)
        pcall(Glass.Stop)
        if GroundFX then pcall(GroundFX.Stop) end
        if E and type(E.UnregisterEnvironmentModifier) == "function" then pcall(E.UnregisterEnvironmentModifier, "CR18Storm") end
        strokes, sounds, quake, flashAt, missionQuakes = {}, {}, nil, nil, {}
        sky, ground, water, tornadoFx, applied, gctx = nil, nil, nil, nil, nil, nil
        S.quakeMagnitude = 0
    end

    function S.Reset(saved)
        if state then S.Stop() end
        state = newState(saved)
        S.target, S.wind, S.bearing, S.quakeMagnitude = profile(state.phase).level, 0, 255, 0
        clock, lvl = 0, profile(state.phase).level * (saved and 1 or 0.6)
        strokes, sounds, quake, flashAt = {}, {}, nil, nil
        applied, view, nextView, nextWind, nextSkyAnim, nextSkyWrite, nextPush = nil, nil, 0, 0, 0, 0, 0
        nextNative, nativeQuake, missionQuakes = 0, false, {}
        sky, skyRetry, skyWritten = "off", 0, nil
        templatesReady, nextTemplates, errorCount, lastError = false, 0, 0, nil
        boltsSeen, burstEnd = 0, nil
        local planeOn = call("GetSkyPlaneEnabled") == true
        baseSkyPlane = planeOn
        Weather.Init()
        -- Foliage: the dead scrub sways with CRWeather's wind. Registering and
        -- Stop both write calm (Ogre materials outlive the mission's Lua state).
        groundMaterial = GROUND_MATERIAL
        if call("MaterialExists", GROUND_MATERIAL, "General") == false then groundMaterial = FALLBACK_GROUND end
        Foliage.Register(groundMaterial, { slot = "emissive" })
        local points = {}
        for _, layer in ipairs(Sites.layers or {}) do
            for _, p in ipairs(layer.instances) do points[#points + 1] = p end
        end
        Foliage.EnableLitter(points, { rate = 70, saturation = 40, minSpeed = 3 })
        gctx = {
            call = call, call2 = call2, vec = vec, sites = Sites, seed = state.seed, hash = hash,
            ready = ensureTemplates, clock = function() return clock end, height = terrain,
            material = function() return groundMaterial end, sound = sound,
        }
        ground = Ground.Create(gctx)
        -- Water: baked pools, streams and the cascade, muddied by the storm level; its
        -- resolver also tells CRWake where a craft is over water and where over mud.
        water = WaterFx.Create({
            call = call, call2 = call2, vec = vec, sites = Sites, ready = ensureTemplates,
            clock = function() return clock end, quality = function() return Weather.Quality or 1 end,
        })
        if api.vehicleWakes ~= false then pcall(Wake.Init, { surface = water.WakeSurface, surfaces = { "water", "mud" } }) end
        tornadoFx = Tornado.NewFx({
            call = call, vec = vec, ready = ensureTemplates,
            ground = function(px, pz) return (terrain(px, pz)) or 0 end,
            quality = function() return Weather.Quality or 1 end,
        })
        if E and type(E.RegisterEnvironmentModifier) == "function" then
            E.RegisterEnvironmentModifier("CR18Storm", function(frame)
                if not S.Initialized or type(frame) ~= "table" or not frame.ambient then return end
                local fl = flashLevel()
                local l = lvl or 0
                local pulse = 0.55 + 0.25 * sin(clock * 1.7) + 0.2 * sin(clock * 0.61 + 1.1)
                local glow = l * l * pulse
                local a = frame.ambient
                a.r = min(1, a.r + 0.36 * fl + 0.09 * glow)
                a.g = min(1, a.g + 0.32 * fl + 0.03 * glow)
                a.b = min(1, a.b + 0.30 * fl + 0.01 * glow)
            end)
        end
        S.Initialized = true
        if type(S.pendingPhase) == "number" then S.SetPhaseIndex(S.pendingPhase); S.pendingPhase = nil end
    end

    -- Leader only. Never moves backward through the mission phases; won and lost
    -- are final. Returns false for an unknown name or a refused step.
    function S.SetPhaseIndex(idx)
        if not state then S.pendingPhase = idx; return true end
        if idx == state.phase then return true end
        if idx < state.phase and state.phase <= LAST then return false end
        if state.phase > LAST then return false end
        state.phase = idx
        return true
    end

    function S.SetPhase(name)
        local idx = INDEX[tostring(name)]
        if not idx then return false end
        return S.SetPhaseIndex(idx)
    end

    -- Every peer. The mission routes its own earthquake requests here while the storm runs.
    -- Returns true when taken; false (director stopped, disabled or not built) tells the mission to
    -- shake the native earthquake itself. Magnitude is native scale and is clamped to 0..12.
    function S.Quake(magnitude, seconds)
        if S.Enabled == false or not state or not S.Initialized then return false end
        magnitude = tonumber(magnitude)
        if not finite(magnitude) then return false end
        magnitude = clamp(magnitude, 0, 12)
        local dur = clamp(tonumber(seconds) or T.MISSION_QUAKE_SECONDS, 0.5, 12)
        if #missionQuakes >= 12 then table.remove(missionQuakes, 1) end
        missionQuakes[#missionQuakes + 1] = { start = clock, dur = dur, mag = magnitude }
        return true
    end

    function S.GetPhase() return Storm.PHASES[state and state.phase or 1] end

    function S.Apply(kind, a, b, c, d, e2, f2, g2, h2)
        if state == nil then S.Reset() end
        if not S.Initialized then return end
        local ok, err = pcall(function()
            if kind == "phase" then
                local idx = floor(tonumber(a) or 0)
                if idx < 1 or idx > #Storm.PHASES then return end
                if finite(c) and c ~= state.seed then
                    state.seed = floor(c)
                    if gctx then gctx.seed = state.seed end
                end
                if finite(b) then
                    if b < state.age - 5 then state.seenBolt, state.seenQuake, state.seenSlide = 0, 0, 0 end
                    if math.abs(b - state.age) > 1.5 then state.age = b end
                end
                state.phase = idx
            elseif kind == "bolt" then
                if not finite(a) or a <= state.seenBolt then return end
                state.seenBolt = a
                boltsSeen = boltsSeen + 1
                startBolt(a, tonumber(b) or 0.5, c == 1)
            elseif kind == "quake" then
                if not finite(a) or a <= state.seenQuake or not finite(b) or not finite(c) then return end
                state.seenQuake = a
                local str, dur = clamp(b, 0, 1), clamp(c, 0.5, 12)
                if quake and clock - quake.start < quake.dur then
                    quake.strength = max(quake.strength, str)
                    quake.dur = max(quake.dur, clock - quake.start + dur)
                else
                    quake = { start = clock, dur = dur, strength = str }
                end
                if str >= 0.2 then sound("gquak00.wav") end
            elseif kind == "slide" then
                if not finite(a) or a <= state.seenSlide then return end
                state.seenSlide = a
                if ground and view then ground.Slide(tonumber(b) or 0.5, a, view) end
                if view then pcall(Glass.Splat, 0.25, 0.5, 0.45, a % 2 == 0) end
            elseif kind == "tornado" then
                local t = state.tornado
                if t and finite(a) and a < t.n then return end
                local decoded = Tornado.Decode(t, a, b, c, d, e2, f2, g2, h2)
                if decoded then state.tornado = decoded end
            end
        end)
        if not ok then
            errorCount = errorCount + 1
            lastError = tostring(err)
        end
    end

    local function fail(err)
        errorCount = (errorCount or 0) + 1
        lastError = tostring(err)
        if errorCount == 1 or errorCount % 50 == 0 then print("CRStorm18: " .. lastError) end
        if errorCount > 200 then S.Enabled = false end
    end

    function S.Update(dt, authority, send)
        if S.Enabled == false then return end
        if state == nil then S.Reset() end
        if not S.Initialized then return end
        dt = clamp(tonumber(dt) or 0, 0, 1)
        local ok, err = pcall(function()
            clock = clock + dt
            state.age = state.age + dt
            if authority then
                local out = send
                if type(out) ~= "function" then out = function(...) S.Apply(...) end end
                local sent, serr = pcall(tick, out)
                if not sent then fail(serr) end
            end
            localTick(dt)
            -- Every peer pulls the craft it owns toward the (replicated) funnel.
            if state.tornado and not profile(state.phase).safe and clock >= (nextPush or 0) then
                nextPush = clock + T.PUSH_STEP
                pcall(Tornado.Affect, state.tornado, T.PUSH_STEP)
            end
            pcall(Weather.Update, dt)
        end)
        if not ok then fail(err) end
    end

    -- Environment owns sensor writes; severity is the shared phase level, never
    -- local particle quality, geometry readiness or camera position.
    function S.GetSeverity()
        if not state then return 0 end
        return profile(state.phase).level
    end

    function S.Save()
        if not state then return nil end
        local t = copy(state)
        t.rngBox, t.sentPhase, t.nextSync = nil, nil, nil
        t.rng = state.rngBox.state
        if t.tornado then t.tornado.sx, t.tornado.sz, t.tornado.hurt = nil, nil, nil end
        return t
    end

    function S.Describe()
        local t = state and state.tornado
        local g = ground and ground.Describe() or {}
        return {
            phase = state and state.phase or 0, name = S.GetPhase(), level = lvl or 0, target = S.target or 0,
            wind = S.wind or 0, bearing = S.bearing or 0, sky = sky, age = state and state.age or 0, clock = clock or 0,
            bolts = boltsSeen or 0, boltsSent = state and state.boltN or 0, quakes = state and state.seenQuake or 0,
            quakeMagnitude = S.quakeMagnitude or 0, slides = state and state.seenSlide or 0,
            tornado = t ~= nil, tornadoX = t and t.x or 0, tornadoZ = t and t.z or 0, tornadoAge = t and t.t or 0,
            tornadoFx = tornadoFx and tornadoFx.Describe().live or false,
            tiles = g.tiles or 0, totalTiles = g.totalTiles or 0, cracks = g.cracks or 0, errors = errorCount or 0,
            error = lastError, templates = templatesReady or false, groundMaterial = groundMaterial,
            seed = state and state.seed or 0, foliage = Foliage.Describe and Foliage.Describe() or nil,
            groundError = g.lastError, water = water and water.Describe() or nil,
        }
    end

    S.Init, S.Load, S.Receive = S.Reset, S.Reset, S.Apply
    return S
end

return Storm
