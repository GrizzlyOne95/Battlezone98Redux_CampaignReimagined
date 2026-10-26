-- CRTitanWeather.lua
-- Titan weather and atmosphere director for Campaign Reimagined (first user:
-- misn14; reusable by any Titan mission that has a generated CRTitanSites file).
--
-- Titan is the one moon in the campaign with a real atmosphere: 1.5 bar of cold
-- nitrogen under a thick orange photochemical haze, about 0.14 g, very little
-- surface wind, and a methane cycle -- drizzle that falls as big slow drops and
-- liquid methane pooled on the lowlands. What the director draws:
--
--   ladder     four HAZE rungs -- still, hazy, drizzle, shroud -- as a seeded
--              timeline (CRVenusMap.NewLadder) with short intense EPISODES.
--              Integer rungs select a CRWeather preset (amber fog, warm dim
--              light, and from rung 3 a sparse methane drizzle); the smoothed
--              fractional position drives every continuous rate.
--   rolls      a thicker bank of haze rolling over for a minute or so: the
--              rung's preset swaps for its "Roll" variant (fog pulled in and
--              deepened, light dimmed) and the haze bank thickens. Host-decided,
--              replicated as one small event.
--   haze bank  a camera-attached drift of large faint amber cards.
--   surface    the liquid itself: one flat sheet laid just over the methane sea
--              through EXU StaticGeometry and shaded by Materials/cr_methane.material
--              (Fresnel sky and haze reflection, low-sun glare and glints, wind
--              chop, drizzle rings), clipped to the generated wet mask. The ladder
--              drives four shader controls through exu.SetMaterialPassColors.
--              Without EXU StaticGeometry or the material the director keeps the
--              particle-only look below.
--   pools      wet methane pools where the MAT painting puts liquid: a pale gold
--              sheen lying flat on the liquid (the reflected sky; reduced while the
--              surface is up), low evaporation mist, and drizzle ripples. Anchors
--              come from Tools/Build-TitanSites.py (pure "Methane Ocean" cells on
--              the flat sea floor), streamed in near the local player.
--   splashes   a wake of methane droplets under any craft or pilot moving
--              across wet ground near the local player (the generated wet
--              mask, not a terrain query).
--
-- GAMEPLAY EFFECTS: NONE. The director never damages, shoves, scrambles, slows,
-- spawns, removes, retargets or re-teams anything, never touches AI perception,
-- sensors, radar, cloaks or stealth, registers no Environment modifier of either
-- kind, and does not call any exu fog / light setter itself. The only state it
-- writes is render state: a CRWeather preset (fog and light go through
-- CRWeather, which contributes through Environment.lua when the mission loads
-- it), particle systems, and one render-only StaticGeometry sheet (no game
-- object: no collision, radar, AI path or targeting, and identical on every peer
-- because it comes from static map data). Reading craft positions is the only
-- thing it asks the simulation. Tools/Test-CRTitanWeather.lua audits this by wrapping every
-- stubbed BZ and exu function.
--
-- CO-OP. The same hybrid as CREuropaWeather / CRIoWeather:
--   * the haze timeline is a pure function of a seed; the host announces the
--     seed and its rung (TitanState) on change and as a heartbeat, and a guest
--     follows that rung for HostOverrideSeconds before falling back to the
--     seeded timeline it has been computing all along;
--   * haze rolls are decided ONLY by the host and sent as one numeric event
--     (TitanRoll); every peer renders on receipt;
--   * the surface, pools, splashes and the haze bank are local, from static map data and the
--     replicated craft positions. They may differ by a frame between peers,
--     which is invisible and has no effect on anything.
--
-- PUBLIC API (host / offline unless noted; a guest's call is ignored)
--   Init{ authority, seed, send, sites, startLevel, targetLevel, enabled, debug,
--         quality, baseSky, drizzle, hazeBank, rolls, randomRolls, pools,
--         poolMist, ripples, splashes, episodes, surface, surfaceMaterial }
--   Start(seed, sites)              shorthand for an offline / host Init
--   Update(dt)                      every frame, every peer
--   Shutdown()                      destroys every system, stands CRWeather down
--   Save() / Load(state)            director scalars (systems do not survive a save)
--   SetTargetLevel(n)               rung the timeline trends toward (1..4)
--   ForceLevel(n, seconds, transition) / ReleaseForcedLevel()
--   Roll(duration, strength)        one haze roll now (5..240 s, 0..1)
--   AnnounceState()                 re-send TitanState (call when the session is ready)
--   ApplyNetEvent(op, ...)          guest receive path; true when handled
--   GetNetState() / ApplyNetState(...) / SetNetwork{send, authority}
--   OnObjectCreated(h)              forwards to CRWeather
--   IsWet(x, z)                     true over a wet methane cell (static data)
--   getters: GetLevel GetLevelName GetTargetLevel IsEpisode GetSeverity
--            GetRollIntensity IsRolling GetPools GetLivePoolCount GetSplashCount
--            GetStats GetSystemCount GetSurface Describe
-- Wire ops (all arguments numbers): TitanState, TitanRoll. See Docs/TITAN_WEATHER.md.
--
-- Ownership rules (same as the other weather directors):
--   * Fog, ambient and sun belong to Environment.lua (or to CRWeather when the
--     mission does not load Environment). We only choose a CRWeather preset.
--   * Nothing in this file calls anything that changes health, ammo, velocity,
--     position, teams, targets, sensors or perception.
--   * Every frame entry point is guarded: a fault in this file is logged once
--     and the director stands itself down rather than raising into the mission.

local exu = require("exu")
local CRWeather = require("CRWeather")
local CRWeatherPresets = require("CRWeatherPresets")
local Map = require("CRVenusMap")

local CRTitanWeather = {}
local V = CRTitanWeather

-- =============================================================================
-- Configuration
-- =============================================================================

V.Enabled              = true
V.Debug                = false

-- Each sub-system is independently switchable.
V.AllowDrizzle         = true    -- the preset drizzle layer (rungs 3-4)
V.AllowHazeBank        = true    -- camera-attached drifting haze cards
V.AllowRolls           = true    -- Roll() and roll events do anything at all
V.AllowRandomRolls     = true    -- the host schedules unscripted rolls
V.AllowPools           = true    -- the sky sheen on the methane pools
V.AllowPoolMist        = true    -- evaporation mist over the pools
V.AllowRipples         = true    -- drizzle rings on the pools
V.AllowSplashes        = true    -- wakes under craft crossing wet ground
V.AllowEpisodes        = true    -- temporary intense spells
V.AllowSurface         = true    -- the reflective liquid sheet (EXU StaticGeometry + cr_methane.material)

-- Hard budgets. These are caps, not targets.
V.MaxSystems           = 26      -- every particle system this module owns, at once
V.MaxLivePools         = 6       -- anchors streamed in (up to 3 systems each)
V.MaxSplashes          = 4       -- craft that may carry a wake at once
V.MaxFailuresPerTemplate = 3

-- Streaming.
V.PoolStreamIn         = 380.0
V.PoolStreamOut        = 500.0
V.StreamInterval       = 1.0
V.RateInterval         = 1.0     -- how often live pool / haze rates are re-sent

-- Activity ladder.
V.SeverityRate         = 0.035   -- rungs per second the smoothed position moves
V.EpisodeChance        = 0.22
V.EpisodePeak          = { 4, 4 }
V.EpisodeStepDwell     = { 10.0, 18.0 }
V.EpisodeHold          = { 35.0, 80.0 }
V.EpisodeCooldown      = 260.0

-- Haze bank (camera-attached).
V.HazeRate             = 10.0    -- particles/second at ladder haze 1.0
V.HazeRollBoost        = 1.6     -- extra (x) haze-bank rate at full roll
V.HazeOffset           = 1.0     -- bank centre relative to the camera (keep it low: cards overhead read as tiles)

-- Haze rolls.
V.RollGap              = { 170.0, 380.0 }  -- seconds between random rolls at roll scale 1
V.RollSeconds          = { 40.0, 95.0 }
V.RollStrength         = { 0.45, 1.00 }
V.RollScriptedDefault  = { 60.0, 0.8 }     -- Roll() with no arguments: duration, strength
V.RollDurationLimit    = { 5.0, 240.0 }
V.RollMinSpacing       = 45.0
V.RollRise             = 0.25    -- fraction of the roll spent thickening
V.RollFall             = 0.35    -- fraction spent clearing
V.RollPresetThreshold  = 0.20    -- roll intensity at which the Roll preset variant is selected
V.RollTransition       = 10.0    -- preset crossfade into / out of a roll variant

-- Pools.
V.PoolSheenRate        = 1.3     -- sheen cards/second at pool weight 1, ladder sheen 1
V.PoolMistRate         = 1.4
V.PoolMistRollBoost    = 1.0     -- extra (x) mist at full roll
V.PoolRippleRate       = 55.0    -- ripples/second at full drizzle
V.PoolSheenHeight      = 0.45    -- above the liquid
V.PoolMistHeight       = 2.0
V.PoolRippleHeight     = 0.55

-- Liquid surface (Shaders/cr_methane.hlsl). The sheet covers the whole terrain and
-- the shader clips it to the wet mask, so it is one draw with no streaming.
V.SurfaceName          = "cr_titan_methane"
V.SurfaceMesh          = "cr_methane_plane.mesh"
V.SurfaceMaterialPrefix = "CR/Titan/Methane"   -- + the mission's digits (misn14: CR/Titan/Methane14)
V.SurfaceLift          = 0.35    -- above the sea level: wet cells lie within 0.3 of it (the generator's
                                 -- tolerance), so the floor's small relief stays under the liquid
V.SurfaceSheenScale    = 0.30    -- pool sheen rate x this while the sheet is up (it carries the reflection)
V.SurfaceChop          = { 0.45, 0.85 }  -- wind chop at severity 0 .. 1
V.SurfaceWetness       = 1.0     -- opacity scale
V.SurfaceRollGlareCut  = 0.55    -- a full haze roll takes this fraction of the glare away
-- The low sun the liquid glares toward (Ogre-space light direction, Environment's titan
-- DaySunDirection) and how far the shader follows it instead of the scene's light 0.
-- misn14 does not load Environment, and its stock sun stands almost overhead.
V.SurfaceHazeSun       = { x = 0.78, y = -0.36, z = -0.51, w = 1.0 }
V.SurfaceRetrySeconds  = 5.0     -- a create that failed because the scene was not ready is retried
V.SurfaceMaxAttempts   = 3

-- Splashes.
V.SplashScanInterval   = 0.2
V.SplashRange          = 230.0   -- only craft this close to the local player
V.SplashMinSpeed       = 3.0     -- below this a craft makes no wake
V.SplashFullSpeed      = 24.0
V.SplashRate           = 90.0    -- droplets/second at full speed
V.SplashMaxClearance   = 7.0     -- a craft higher than this over the liquid is flying, not wading
V.SplashHeight         = 0.4
V.SplashIdleSeconds    = 8.0     -- an unused wake system is destroyed after this

-- Co-op.
V.NetHeartbeat         = 30.0
V.HostOverrideSeconds  = 45.0

-- Fault containment: after this many caught errors the director stands down.
V.MaxFaults            = 3

-- =============================================================================
-- The ladder
--
-- One row per rung. Continuous values interpolate between adjacent rows by the
-- smoothed ladder position.
--   haze       multiplier on the haze-bank emission
--   sheen      multiplier on the pool sheen
--   mist       multiplier on the pool mist
--   drizzle    0..1, drives the pool ripples (the preset carries the drops)
--   rollScale  divides the gap between random rolls
--   glare      strength of the low sun's glare and glow on the liquid surface
-- =============================================================================

V.Levels = {
    { name = "Still",   preset = "TitanStill",   haze = 0.50, sheen = 1.00, mist = 0.80, drizzle = 0.00,
      glare = 1.00, rollScale = 0.60, duration = { 120.0, 220.0 } },
    { name = "Hazy",    preset = "TitanHazy",    haze = 0.90, sheen = 0.90, mist = 1.00, drizzle = 0.00,
      glare = 0.85, rollScale = 1.00, duration = { 90.0, 180.0 } },
    { name = "Drizzle", preset = "TitanDrizzle", haze = 1.00, sheen = 0.75, mist = 1.20, drizzle = 1.00,
      glare = 0.60, rollScale = 0.80, duration = { 70.0, 150.0 } },
    { name = "Shroud",  preset = "TitanShroud",  haze = 1.50, sheen = 0.60, mist = 1.40, drizzle = 0.55,
      glare = 0.45, rollScale = 1.40, duration = { 50.0, 110.0 } },
}

local LEVEL_COUNT = #V.Levels

-- =============================================================================
-- Presets
--
-- Titan's light is a small distant sun seen through a thick orange haze: warm,
-- dim and flat, with the sky itself the brightest thing in view. Fog is amber
-- and never longer than 160 units start-to-end, which is the DX11 Enhanced
-- terrain-IBL reference range (openshim_enhanced_terrain: the terrain diffuse
-- IBL is scaled by 160 / (fogEnd - fogStart), saturating at <= 160), so the
-- haze never starves the terrain's image-based light the way an over-long fog
-- would. Every fog end is also above the stock misn14 FogEnd (175) or within
-- reach of it, and CRWeather clamps all of them to the map's terrain horizon.
--
-- Each rung has a "Roll" variant: the same layers with fog pulled in, deepened
-- toward a darker orange, and the light dimmed. Registered into
-- CRWeatherPresets.Presets at Init rather than appended to CRWeatherPresets.lua,
-- so the shared file stays untouched.
-- =============================================================================

local ROLL_FOG_COLOR = { 0.66, 0.38, 0.12 }
local ROLL_FOG_TINT = 0.30
local ROLL_FOG_START = 0.55
local ROLL_FOG_END = 0.70
local ROLL_LIGHT = 0.80

local PRESET_ROWS = {
    { name = "TitanStill", drizzle = 0.0,
      fog = { 0.60, 0.35, 0.11, 52.0, 190.0 }, ambient = { 0.34, 0.23, 0.11 },
      diffuse = { 0.86, 0.60, 0.30 }, sun = 1.00, tin = 26.0, tout = 30.0 },
    { name = "TitanHazy", drizzle = 0.0,
      fog = { 0.59, 0.34, 0.11, 46.0, 178.0 }, ambient = { 0.33, 0.22, 0.11 },
      diffuse = { 0.78, 0.54, 0.27 }, sun = 0.92, tin = 24.0, tout = 28.0 },
    { name = "TitanDrizzle", drizzle = 55.0,
      fog = { 0.56, 0.33, 0.11, 40.0, 165.0 }, ambient = { 0.30, 0.21, 0.11 },
      diffuse = { 0.64, 0.45, 0.24 }, sun = 0.80, tin = 22.0, tout = 26.0 },
    { name = "TitanShroud", drizzle = 30.0,
      fog = { 0.54, 0.31, 0.10, 28.0, 150.0 }, ambient = { 0.30, 0.20, 0.10 },
      diffuse = { 0.56, 0.38, 0.20 }, sun = 0.72, tin = 20.0, tout = 26.0 },
}

local function Mix(a, b, t)
    return a + ((b - a) * t)
end

local function BuildPreset(row, roll)
    local fog = row.fog
    local light = roll and ROLL_LIGHT or 1.0
    local r, g, b = fog[1], fog[2], fog[3]
    local fogStart, fogEnd = fog[4], fog[5]
    if roll then
        r = Mix(r, ROLL_FOG_COLOR[1], ROLL_FOG_TINT)
        g = Mix(g, ROLL_FOG_COLOR[2], ROLL_FOG_TINT)
        b = Mix(b, ROLL_FOG_COLOR[3], ROLL_FOG_TINT)
        fogStart = fogStart * ROLL_FOG_START
        fogEnd = fogEnd * ROLL_FOG_END
    end

    local precipitation = {}
    if row.drizzle > 0.0 and V.AllowDrizzle then
        precipitation[1] = {
            system   = "cr_wx_titan_drizzle",
            template = "CR/Titan/Drizzle",
            offset   = { x = 0.0, y = 30.0, z = 0.0 },
            quota    = 700,
            emitters = {
                [0] = {
                    rate     = row.drizzle,
                    velocity = { 11.0, 16.0 },     -- big drops in thick air: slow
                    ttl      = { 2.4, 3.6 },
                    angle    = 6.0,
                    color    = {
                        start  = { r = 0.92, g = 0.66, b = 0.34, a = 0.42 },
                        finish = { r = 0.80, g = 0.54, b = 0.26, a = 0.26 },
                    },
                },
            },
        }
    end

    return {
        name          = row.name .. (roll and "Roll" or ""),
        precipitation = precipitation,
        sky           = nil,     -- the CR_titansky dome takes V.SkyState() instead
        fog           = { r = r, g = g, b = b, fogStart = fogStart, fogEnd = fogEnd },
        ambient       = { r = row.ambient[1] * Mix(1.0, light, 0.5), g = row.ambient[2] * Mix(1.0, light, 0.5),
                          b = row.ambient[3] * Mix(1.0, light, 0.5) },
        diffuse       = { r = row.diffuse[1] * light, g = row.diffuse[2] * light, b = row.diffuse[3] * light },
        sunPowerScale = row.sun * light,
        -- Titan's surface wind is weak; the drizzle leans only slightly.
        wind          = { x = 0.10, y = -1.0, z = 0.04 },
        windSpeed     = 2.0,
        lightning     = nil,
        transitionIn  = roll and V.RollTransition or row.tin,
        transitionOut = roll and V.RollTransition or row.tout,
    }
end

-- Exposed so a test (or a settings page) can inspect what was registered.
function V.RegisterPresets()
    local presets = CRWeatherPresets.Presets
    if type(presets) ~= "table" then return 0 end
    local added = 0
    for i = 1, #PRESET_ROWS do
        for _, roll in ipairs({ false, true }) do
            local preset = BuildPreset(PRESET_ROWS[i], roll)
            if presets[preset.name] == nil then
                presets[preset.name] = preset
                added = added + 1
            end
        end
    end
    return added
end

function V.GetPresetNames()
    local names = {}
    for i = 1, #PRESET_ROWS do
        names[#names + 1] = PRESET_ROWS[i].name
        names[#names + 1] = PRESET_ROWS[i].name .. "Roll"
    end
    return names
end

-- =============================================================================
-- Runtime state
-- =============================================================================

V.Initialized      = false
V.Disabled         = false       -- set after MaxFaults caught errors
V.Faults           = 0
V.Seed             = nil
V.Synced           = true
V.IsAuthority      = true
V.NetSend          = nil

V.Clock            = 0.0
V.LastRealTime     = nil
V.Ladder           = nil
V.Level            = 1
V.Episode          = false
V.TargetLevel      = 2
V.LevelValue       = 1.0
V.ForcedLevel      = nil
V.ForcedUntil      = nil
V.HostOverride     = nil
V.AppliedPreset    = nil

V.RollSerial       = 0
V.Roll_            = nil         -- the roll in progress, if any
V.SeenRolls        = {}
V.NextRollAt       = 0.0
V.LastRollEndAt    = -1000.0
V.RollLog          = {}

V.Stats = { rolls = 0, scriptedRolls = 0, randomRolls = 0, mergedRolls = 0, splashes = 0, peakRoll = 0.0 }

V.Systems          = {}          -- name -> kind
V.SystemCount      = 0
V.TemplateFailures = {}
V.TemplatesReady   = false
V.Serial           = 0
V.NextStreamAt     = 0.0
V.NextRateAt       = 0.0
V.NextScanAt       = 0.0
V.NextNetStateAt   = 0.0
V.LastStateKey     = nil

V.Sites            = nil
V.Pools            = {}
V.PoolLive         = {}          -- pool index -> record
V.Wet              = nil         -- decoded wet mask
V.Haze             = nil         -- haze-bank system name
V.HazeRateSent     = nil
V.Splash           = {}          -- slot -> { name, handle, rate, idleSince }
V.Tracked          = {}          -- handle -> { x, z, t, speed }

-- =============================================================================
-- Helpers
-- =============================================================================

local Clamp = Map.Clamp
local SmoothStep = Map.SmoothStep
local floor = math.floor

local function Log(message)
    if V.Debug then
        print("CRTitanWeather: " .. tostring(message))
    end
end

local function Vec(x, y, z)
    if type(SetVector) == "function" then
        return SetVector(x, y, z)
    end
    return { x = x, y = y, z = z }
end

local function Call(name, ...)
    if exu == nil or type(exu[name]) ~= "function" then
        return nil
    end
    local ok, result = pcall(exu[name], ...)
    if not ok then
        Log("exu." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function Level(index)
    return V.Levels[Clamp(index, 1, LEVEL_COUNT)]
end

local function LadderValue(field)
    local position = Clamp(V.LevelValue, 1.0, LEVEL_COUNT)
    local low = floor(position)
    local high = math.min(low + 1, LEVEL_COUNT)
    return Mix(Level(low)[field], Level(high)[field], position - low)
end

function V.GetSeverity()
    if LEVEL_COUNT <= 1 then return 0.0 end
    return Clamp((V.LevelValue - 1.0) / (LEVEL_COUNT - 1), 0.0, 1.0)
end

local function PositionOf(h)
    if h == nil or type(GetPosition) ~= "function" then return nil end
    local ok, p = pcall(GetPosition, h)
    if not ok or p == nil then return nil end
    -- The engine returns a VECTOR_3D userdata, not a table: read the fields
    -- (guarded) and hand back a plain table.
    local okX, x, y, z = pcall(function() return p.x, p.y, p.z end)
    if okX and type(x) == "number" and type(z) == "number" then
        return { x = x, y = tonumber(y) or 0.0, z = z }
    end
    return nil
end

local function ValidHandle(h)
    if h == nil then return false end
    if type(IsValid) == "function" then
        local ok, valid = pcall(IsValid, h)
        return ok and valid and true or false
    end
    return true
end

local function TerrainHeight(x, z)
    if type(GetTerrainHeightAndNormal) ~= "function" then return nil end
    local ok, height = pcall(GetTerrainHeightAndNormal, Vec(x, 0.0, z))
    if not ok or type(height) ~= "number" then return nil end
    return height
end

local function SeaLevel()
    local sea = V.Sites and V.Sites.sea
    return sea and tonumber(sea.level) or 0.0
end

-- Liquid surface height at a point: the terrain where the engine answers, the
-- generated sea level otherwise (wet cells ARE the flat sea floor).
local function LiquidY(x, z)
    return TerrainHeight(x, z) or SeaLevel()
end

local function LocalPlayerHandle()
    if type(GetPlayerHandle) ~= "function" then return nil end
    local ok, h = pcall(GetPlayerHandle)
    if ok and ValidHandle(h) then return h end
    return nil
end

local function Distance2D(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt((dx * dx) + (dz * dz))
end

local function Send(op, ...)
    if V.NetSend ~= nil and V.IsAuthority then
        local ok, err = pcall(V.NetSend, op, ...)
        if not ok then Log("net send failed: " .. tostring(err)) end
    end
end

-- =============================================================================
-- Particle systems (budgeted)
-- =============================================================================

local function Fx_Create(kind, template, x, y, z)
    if V.SystemCount >= V.MaxSystems then
        return nil
    end
    if (V.TemplateFailures[template] or 0) >= V.MaxFailuresPerTemplate then
        return nil
    end

    V.Serial = V.Serial + 1
    local name = "cr_tw_" .. kind .. "_" .. tostring(V.Serial)
    if Call("CreateParticleSystem", name, template, Vec(x, y, z)) ~= true then
        local failures = (V.TemplateFailures[template] or 0) + 1
        V.TemplateFailures[template] = failures
        if failures >= V.MaxFailuresPerTemplate then
            print("CRTitanWeather: " .. template .. " disabled after " .. tostring(failures) ..
                " failed particle creates (template unavailable)")
        end
        return nil
    end

    V.TemplateFailures[template] = 0
    V.Systems[name] = kind
    V.SystemCount = V.SystemCount + 1
    Call("SetParticleSystemKeepLocalSpace", name, false)
    Call("SetParticleSystemNonVisibleUpdateTimeout", name, 3.0)
    return name
end

local function Fx_Destroy(name)
    if name == nil or V.Systems[name] == nil then return end
    Call("DestroyParticleSystem", name)
    V.Systems[name] = nil
    V.SystemCount = V.SystemCount - 1
end

local function Fx_DestroyAll()
    local names = {}
    for name in pairs(V.Systems) do names[#names + 1] = name end
    for i = 1, #names do Fx_Destroy(names[i]) end
    V.SystemCount = 0
    V.PoolLive, V.Splash = {}, {}
    V.Haze, V.HazeRateSent = nil, nil
end

local function SetRate(name, rate)
    if name ~= nil then
        Call("SetParticleEmitterEmissionRate", name, 0, math.max(0.0, rate))
    end
end

-- =============================================================================
-- Wet mask (static, from the generated sites)
-- =============================================================================

local function DecodeWet(sites)
    local sea = sites and sites.sea
    local wet = sites and sites.wet
    if type(sea) ~= "table" or type(wet) ~= "table" or type(wet.rows) ~= "table" then
        return nil
    end
    local cell = tonumber(sea.cell) or 0.0
    if cell <= 0.0 then return nil end
    return {
        originX = tonumber(sea.originX) or 0.0,
        originZ = tonumber(sea.originZ) or 0.0,
        cell = cell,
        rows = wet.rows,
    }
end

-- True when (x, z) lies over a wet methane cell. Pure table lookups; safe to
-- call per craft several times a second.
function V.IsWet(x, z)
    local wet = V.Wet
    if wet == nil or type(x) ~= "number" or type(z) ~= "number" then return false end
    local row = wet.rows[floor((z - wet.originZ) / wet.cell)]
    if row == nil then return false end
    local col = floor((x - wet.originX) / wet.cell)
    for i = 1, #row - 1, 2 do
        local start = row[i]
        if col < start then return false end
        if col < start + row[i + 1] then return true end
    end
    return false
end

-- =============================================================================
-- Ladder
-- =============================================================================

local function LadderConfig()
    local durations = {}
    for i = 1, LEVEL_COUNT do durations[i] = V.Levels[i].duration end
    local cfg = { levels = LEVEL_COUNT, start = 1, durations = durations }
    if V.AllowEpisodes then
        cfg.episode = {
            chance = V.EpisodeChance, minLevel = 3, minTarget = 3,
            peak = V.EpisodePeak, stepDwell = V.EpisodeStepDwell,
            hold = V.EpisodeHold, cooldown = V.EpisodeCooldown,
        }
    end
    return cfg
end

local function BuildLadder(seed)
    V.Seed = seed
    V.Ladder = Map.NewLadder(seed, LadderConfig())
    V.RollRng = Map.NewRng(Map.DeriveSeed(seed, 21))
end

-- =============================================================================
-- Haze rolls
-- =============================================================================

local function RollEnvelopeAt(roll, age)
    if roll == nil or age < 0.0 or age >= roll.duration then return 0.0 end
    local rise = math.max(0.5, roll.duration * V.RollRise)
    local fall = math.max(0.5, roll.duration * V.RollFall)
    local k
    if age < rise then
        k = SmoothStep(age / rise)
    elseif age > roll.duration - fall then
        k = SmoothStep((roll.duration - age) / fall)
    else
        k = 1.0
    end
    return k * roll.strength
end

function V.GetRollIntensity()
    if not V.AllowRolls or V.Roll_ == nil then return 0.0 end
    return RollEnvelopeAt(V.Roll_, V.Clock - V.Roll_.start)
end

function V.IsRolling() return V.Roll_ ~= nil end

-- The sky dome's weather state (CR_titansky): storm is the haze ladder and
-- bank the roll envelope, so Saturn fades as the haze thickens and rolls in.
-- Environment reads it through BindWeatherSensors; this registers nothing.
function V.SkyState()
    if not V.Initialized or V.Disabled or not V.Enabled then return nil end
    return { storm = V.GetSeverity(), bank = V.GetRollIntensity() }
end
function V.GetRoll() return V.Roll_ end

-- A roll begins (host, and by event guests). Purely visual.
function V.BeginRoll(id, strength, duration, kind)
    if not V.AllowRolls then return false end
    id = floor(tonumber(id) or 0)
    if id > 0 then
        if V.SeenRolls[id] then return false end
        V.SeenRolls[id] = true
    end
    strength = Clamp(tonumber(strength) or 0.8, 0.0, 1.0)
    duration = Clamp(tonumber(duration) or 60.0, V.RollDurationLimit[1], V.RollDurationLimit[2])

    local current = V.Roll_
    if current ~= nil then
        -- A roll during a roll extends it rather than restarting the envelope.
        local remaining = current.duration - (V.Clock - current.start)
        current.duration = (V.Clock - current.start) + math.max(remaining, duration)
        current.strength = math.max(current.strength, strength)
        V.Stats.mergedRolls = V.Stats.mergedRolls + 1
    else
        V.Roll_ = { id = id, start = V.Clock, duration = duration, strength = strength }
    end
    V.Stats.rolls = V.Stats.rolls + 1
    if kind == "random" then
        V.Stats.randomRolls = V.Stats.randomRolls + 1
    elseif kind == "scripted" then
        V.Stats.scriptedRolls = V.Stats.scriptedRolls + 1
    end
    V.Stats.peakRoll = math.max(V.Stats.peakRoll, strength)
    V.RollLog[#V.RollLog + 1] = { t = V.Clock, id = id, strength = strength, duration = duration }
    if #V.RollLog > 32 then table.remove(V.RollLog, 1) end
    return true
end

local function StartRoll(strength, duration, kind)
    V.RollSerial = V.RollSerial + 1
    local id = V.RollSerial
    if V.BeginRoll(id, strength, duration, kind) then
        Send("TitanRoll", id, strength, duration)
        return true
    end
    return false
end

-- One haze roll now. Host / offline only.
function V.Roll(duration, strength)
    if not V.IsAuthority or not V.Initialized or not V.AllowRolls then return false end
    duration = tonumber(duration) or V.RollScriptedDefault[1]
    strength = tonumber(strength) or V.RollScriptedDefault[2]
    return StartRoll(Clamp(strength, 0.0, 1.0),
        Clamp(duration, V.RollDurationLimit[1], V.RollDurationLimit[2]), "scripted")
end

local function ScheduleNextRoll()
    local rng = V.RollRng
    local scale = math.max(0.1, LadderValue("rollScale"))
    local gap = rng and rng.Range(V.RollGap[1], V.RollGap[2]) or V.RollGap[2]
    V.NextRollAt = V.Clock + (gap / scale)
end

local function UpdateRandomRolls()
    if not V.IsAuthority or not V.AllowRolls or not V.AllowRandomRolls or not V.Synced then return end
    if V.Roll_ ~= nil or V.Clock < V.NextRollAt then return end
    if (V.Clock - V.LastRollEndAt) < V.RollMinSpacing then
        V.NextRollAt = V.LastRollEndAt + V.RollMinSpacing
        return
    end
    local rng = V.RollRng
    StartRoll(rng.Range(V.RollStrength[1], V.RollStrength[2]),
        rng.Range(V.RollSeconds[1], V.RollSeconds[2]), "random")
    ScheduleNextRoll()
end

local function UpdateRoll()
    local roll = V.Roll_
    if roll ~= nil and (V.Clock - roll.start) >= roll.duration then
        V.Roll_ = nil
        V.LastRollEndAt = V.Clock
    end
end

-- =============================================================================
-- Ladder resolution and the preset in force
-- =============================================================================

local function ResolveLevel()
    if V.Ladder == nil then
        return 1, false
    end

    local scheduled, episode = V.Ladder:Advance(V.Clock, V.TargetLevel)

    if V.ForcedLevel ~= nil then
        if V.ForcedUntil ~= nil and V.Clock >= V.ForcedUntil then
            V.ForcedLevel = nil
            V.ForcedUntil = nil
        else
            return V.ForcedLevel, false
        end
    end

    if not V.IsAuthority and V.HostOverride ~= nil then
        if V.Clock < V.HostOverride.expires then
            return V.HostOverride.level, V.HostOverride.episode
        end
        V.HostOverride = nil
    end

    return scheduled, episode
end

-- The CRWeather preset that should be active: the rung's, or its Roll variant
-- while a roll is thick enough to see.
local function WantedPreset()
    local name = Level(V.Level).preset
    if V.GetRollIntensity() >= V.RollPresetThreshold then
        name = name .. "Roll"
    end
    return name
end

local function SyncPreset(transitionSeconds)
    local wanted = WantedPreset()
    if V.AppliedPreset ~= wanted or CRWeather.GetPreset() ~= wanted then
        CRWeather.SetPreset(wanted, transitionSeconds)
        V.AppliedPreset = wanted
        Log("preset -> " .. wanted)
    end
end

local function UpdateLadder(dt)
    if not V.Synced then
        return
    end

    local level, episode = ResolveLevel()
    V.Episode = episode
    V.Level = Clamp(level, 1, LEVEL_COUNT)

    local step = V.SeverityRate * dt
    local delta = V.Level - V.LevelValue
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.LevelValue = Clamp(V.LevelValue + delta, 1.0, LEVEL_COUNT)
end

-- =============================================================================
-- Haze bank (camera-attached)
-- =============================================================================

local function HazeBankRate()
    return V.HazeRate * LadderValue("haze") * (1.0 + (V.HazeRollBoost * V.GetRollIntensity()))
end

local function UpdateHazeBank()
    if not V.AllowHazeBank or not V.TemplatesReady then return end
    if V.Haze == nil then
        local name = Fx_Create("haze", "CR/Titan/HazeBank", 0.0, 0.0, 0.0)
        if name == nil then return end
        Call("AttachParticleSystemToCamera", name, Vec(0.0, V.HazeOffset, 0.0))
        V.Haze, V.HazeRateSent = name, nil
    end
    local rate = HazeBankRate()
    if V.HazeRateSent == nil or math.abs(rate - V.HazeRateSent) > 0.2 then
        SetRate(V.Haze, rate)
        V.HazeRateSent = rate
    end
end

-- =============================================================================
-- Pools
-- =============================================================================

local function PoolRates(pool)
    local weight = tonumber(pool.weight) or 1.0
    local roll = V.GetRollIntensity()
    local sheen = V.AllowPools and (V.PoolSheenRate * weight * LadderValue("sheen")) or 0.0
    if V.SurfaceUp then sheen = sheen * V.SurfaceSheenScale end
    local mist = V.AllowPoolMist and
        (V.PoolMistRate * weight * LadderValue("mist") * (1.0 + (V.PoolMistRollBoost * roll))) or 0.0
    local ripple = V.AllowRipples and (V.PoolRippleRate * LadderValue("drizzle")) or 0.0
    return sheen, mist, ripple
end

local function PoolCreate(_, pool)
    local y = LiquidY(pool.x, pool.z)
    local record = { pool = pool, y = y }
    local sheen, mist, ripple = PoolRates(pool)
    if V.AllowPools then
        record.sheen = Fx_Create("sheen", "CR/Titan/PoolSheen", pool.x, y + V.PoolSheenHeight, pool.z)
    end
    if V.AllowPoolMist then
        record.mist = Fx_Create("mist", "CR/Titan/PoolMist", pool.x, y + V.PoolMistHeight, pool.z)
    end
    if V.AllowRipples then
        record.ripple = Fx_Create("ripple", "CR/Titan/PoolRipple", pool.x, y + V.PoolRippleHeight, pool.z)
    end
    if record.sheen == nil and record.mist == nil and record.ripple == nil then
        return nil
    end
    SetRate(record.sheen, sheen)
    SetRate(record.mist, mist)
    SetRate(record.ripple, ripple)
    record.rates = { sheen, mist, ripple }
    return record
end

local function PoolDestroy(_, record)
    Fx_Destroy(record.sheen)
    Fx_Destroy(record.mist)
    Fx_Destroy(record.ripple)
end

local function UpdatePoolRates()
    for _, record in pairs(V.PoolLive) do
        local sheen, mist, ripple = PoolRates(record.pool)
        local sent = record.rates
        if math.abs(sheen - sent[1]) > 0.05 then SetRate(record.sheen, sheen); sent[1] = sheen end
        if math.abs(mist - sent[2]) > 0.05 then SetRate(record.mist, mist); sent[2] = mist end
        if math.abs(ripple - sent[3]) > 0.5 then SetRate(record.ripple, ripple); sent[3] = ripple end
    end
end

local function StreamPools(playerPos)
    if playerPos == nil then return end
    local pools, live = V.Pools, V.PoolLive

    local count = 0
    local drop = {}
    for index in pairs(live) do
        local pool = pools[index]
        local d = pool and Distance2D(pool.x, pool.z, playerPos.x, playerPos.z) or nil
        if d == nil or d > V.PoolStreamOut then
            drop[#drop + 1] = index
        else
            count = count + 1
        end
    end
    for i = 1, #drop do
        PoolDestroy(drop[i], live[drop[i]])
        live[drop[i]] = nil
    end
    if count >= V.MaxLivePools then return end

    local best, bestDistance = nil, V.PoolStreamIn
    for index = 1, #pools do
        if live[index] == nil then
            local d = Distance2D(pools[index].x, pools[index].z, playerPos.x, playerPos.z)
            if d < bestDistance then
                best, bestDistance = index, d
            end
        end
    end
    if best ~= nil then
        local record = PoolCreate(best, pools[best])
        if record ~= nil then live[best] = record end
        if V.Debug then
            Log(string.format("pool %d at %.0f m: %s", best, bestDistance, record and "live" or "create failed"))
        end
    end
end

-- =============================================================================
-- Liquid surface (EXU StaticGeometry + Materials/cr_methane.material)
--
-- One sheet over the whole terrain at sea level + SurfaceLift; the shader clips it
-- to the wet mask, and terrain standing above the liquid hides it by depth, so the
-- shore is where the ground rises out of it. It is not a game object: no collision,
-- radar, AI path or targeting, and every peer builds the same sheet from the same
-- static data. Nothing here is fatal: without the API, the material or a terrain
-- extent the director keeps the particle-only look.
-- =============================================================================

local function SurfaceMaterialName()
    if V.SurfaceMaterial ~= nil then return V.SurfaceMaterial end
    local mission = V.Sites and V.Sites.mission
    local digits = type(mission) == "string" and mission:gsub("%D", "") or ""
    if digits == "" then return nil end
    return V.SurfaceMaterialPrefix .. digits
end

local function MaterialLoaded(material)
    if exu == nil or type(exu.MaterialExists) ~= "function" then
        -- Older EXU: no way to ask. Never risk a missing material (Ogre would
        -- draw the sheet flat white), so treat it as absent.
        return false
    end
    return Call("MaterialExists", material) == true
end

local function SurfaceDestroy()
    if V.SurfaceUp or V.SurfaceInfo ~= nil then
        Call("DestroyStaticGeometry", V.SurfaceName)
    end
    V.SurfaceUp, V.SurfaceInfo, V.SurfaceSent = false, nil, nil
end

-- True when the sheet is up; otherwise V.SurfaceReason says why.
local function SurfaceCreate()
    SurfaceDestroy()
    V.SurfaceAttempts = (V.SurfaceAttempts or 0) + 1
    V.SurfaceRetryAt = nil
    local function fail(reason, retry)
        V.SurfaceReason = reason
        if retry and V.SurfaceAttempts < V.SurfaceMaxAttempts then
            V.SurfaceRetryAt = V.Clock + V.SurfaceRetrySeconds
        end
        print("CRTitanWeather: methane surface off (" .. reason .. "); the particle sheen stays")
        return false
    end
    if not V.AllowSurface then V.SurfaceReason = "disabled"; return false end
    local terrain = V.Sites and V.Sites.terrain
    local width = type(terrain) == "table" and tonumber(terrain.width) or nil
    local depth = type(terrain) == "table" and tonumber(terrain.depth) or nil
    if width == nil or depth == nil or width <= 0.0 or depth <= 0.0 then
        return fail("no terrain extent in the site data", false)
    end
    if exu == nil or type(exu.CreateStaticGeometry) ~= "function" then
        return fail("EXU StaticGeometry is unavailable", false)
    end
    local material = SurfaceMaterialName()
    if material == nil then return fail("no surface material for this map", false) end
    if not MaterialLoaded(material) then return fail("material " .. material .. " is not loaded", false) end

    local cx = (tonumber(terrain.minX) or 0.0) + (width * 0.5)
    local cz = (tonumber(terrain.minZ) or 0.0) + (depth * 0.5)
    local y = SeaLevel() + V.SurfaceLift
    local okCall, info, err = pcall(exu.CreateStaticGeometry, V.SurfaceName, V.SurfaceMesh, material,
        { { position = Vec(cx, y, cz), scale = { x = width, y = 1.0, z = depth } } },
        {
            regionDimensions = { x = width + 64.0, y = 64.0, z = depth + 64.0 },
            origin = Vec(cx, y, cz),
            renderingDistance = 0.0,
            castShadows = false,
            visible = true,
        })
    if not okCall then return fail("CreateStaticGeometry raised: " .. tostring(info), false) end
    if type(info) ~= "table" then
        -- "render origin is unavailable" / "SceneManager is unavailable": too early.
        return fail("CreateStaticGeometry: " .. tostring(err), true)
    end
    V.SurfaceUp, V.SurfaceInfo, V.SurfaceReason = true, info, nil
    V.SurfaceBound = material
    Log(string.format("methane surface up: %s at y %.2f over %.0f x %.0f", material, y, width, depth))
    return true
end

-- The four shader controls, from the ladder: drizzle rings, glare, wetness, chop.
local function SurfaceControls()
    local drizzle = V.AllowRipples and LadderValue("drizzle") or 0.0
    local glare = LadderValue("glare") * (1.0 - (V.SurfaceRollGlareCut * V.GetRollIntensity()))
    local chop = Mix(V.SurfaceChop[1], V.SurfaceChop[2], V.GetSeverity())
    return Clamp(drizzle, 0.0, 1.0), Clamp(glare, 0.0, 1.5), Clamp(V.SurfaceWetness, 0.0, 1.0),
        Clamp(chop, 0.0, 1.0)
end

local function UpdateSurface(force)
    if not V.SurfaceUp then
        if V.SurfaceRetryAt ~= nil and V.Clock >= V.SurfaceRetryAt then SurfaceCreate() end
        return
    end
    local r, g, b, a = SurfaceControls()
    local sent = V.SurfaceSent
    if not force and sent ~= nil and math.abs(r - sent[1]) < 0.02 and math.abs(g - sent[2]) < 0.02 and
        math.abs(b - sent[3]) < 0.02 and math.abs(a - sent[4]) < 0.02 then
        return
    end
    -- Without SetMaterialPassColors the material's calm defaults stay (still a lake).
    local sun = V.SurfaceHazeSun
    Call("SetMaterialPassColors", V.SurfaceBound, {
        diffuse = { r = r, g = g, b = b, a = a },
        specular = { r = sun.x, g = sun.y, b = sun.z, a = sun.w },
    }, 0, 0)
    V.SurfaceSent = { r, g, b, a }
end

-- { up, reason, material, controls = { drizzle, glare, wetness, chop } }
function V.GetSurface()
    local s = V.SurfaceSent
    return {
        up = V.SurfaceUp == true,
        reason = V.SurfaceReason,
        material = V.SurfaceBound,
        controls = s and { drizzle = s[1], glare = s[2], wetness = s[3], chop = s[4] } or nil,
    }
end

-- =============================================================================
-- Splashes
-- =============================================================================

local function ForEachMover(fn)
    local seen = {}
    local player = LocalPlayerHandle()
    if player ~= nil then
        seen[player] = true
        fn(player)
    end
    if type(AllCraft) ~= "function" then return end
    local ok, iterator = pcall(AllCraft)
    if not ok or type(iterator) ~= "function" then return end
    for h in iterator do
        if not seen[h] then
            seen[h] = true
            fn(h)
        end
    end
end

-- Measures speed from position deltas (no velocity query) and returns the
-- candidates for a wake this scan: craft near the local player, over wet
-- ground, low enough to be in the liquid and moving.
local function ScanMovers(playerPos)
    local now = V.Clock
    local candidates = {}
    local alive = {}
    ForEachMover(function(h)
        local p = PositionOf(h)
        if p == nil then return end
        alive[h] = true
        local track = V.Tracked[h]
        local speed = 0.0
        if track ~= nil and now > track.t then
            speed = Distance2D(p.x, p.z, track.x, track.z) / (now - track.t)
        end
        V.Tracked[h] = { x = p.x, z = p.z, t = now, speed = speed }
        if Distance2D(p.x, p.z, playerPos.x, playerPos.z) > V.SplashRange then return end
        if speed < V.SplashMinSpeed or not V.IsWet(p.x, p.z) then return end
        local liquid = LiquidY(p.x, p.z)
        if (p.y or liquid) - liquid > V.SplashMaxClearance then return end
        candidates[#candidates + 1] = { h = h, speed = speed, y = liquid }
    end)
    for h in pairs(V.Tracked) do
        if not alive[h] then V.Tracked[h] = nil end
    end
    table.sort(candidates, function(a, b) return a.speed > b.speed end)
    return candidates
end

local function SplashRateFor(speed)
    local k = Clamp((speed - V.SplashMinSpeed) / math.max(0.1, V.SplashFullSpeed - V.SplashMinSpeed), 0.0, 1.0)
    return V.SplashRate * (0.25 + (0.75 * k))
end

local function UpdateSplashAssignments(playerPos)
    local candidates = ScanMovers(playerPos)
    local wanted = {}
    for i = 1, math.min(#candidates, V.MaxSplashes) do
        wanted[candidates[i].h] = candidates[i]
    end

    -- Keep a slot on the craft it already follows, release the rest.
    local free = {}
    for slot = 1, V.MaxSplashes do
        local s = V.Splash[slot]
        if s ~= nil and s.handle ~= nil and wanted[s.handle] ~= nil then
            local c = wanted[s.handle]
            s.y, s.rate = c.y, SplashRateFor(c.speed)
            SetRate(s.name, s.rate)
            wanted[s.handle] = nil
        else
            if s ~= nil and s.handle ~= nil then
                s.handle = nil
                s.rate = 0.0
                s.idleSince = V.Clock
                SetRate(s.name, 0.0)
            end
            free[#free + 1] = slot
        end
    end

    for _, c in pairs(wanted) do
        local slot = table.remove(free, 1)
        if slot == nil then break end
        local s = V.Splash[slot]
        if s == nil then
            local p = PositionOf(c.h)
            local name = p and Fx_Create("splash", "CR/Titan/Splash", p.x, c.y + V.SplashHeight, p.z) or nil
            if name ~= nil then
                s = { name = name }
                V.Splash[slot] = s
            end
        end
        if s ~= nil then
            s.handle, s.y, s.idleSince = c.h, c.y, nil
            s.rate = SplashRateFor(c.speed)
            SetRate(s.name, s.rate)
            V.Stats.splashes = V.Stats.splashes + 1
        end
    end

    -- Idle wakes are released after a while so a quiet map holds no systems.
    for slot = 1, V.MaxSplashes do
        local s = V.Splash[slot]
        if s ~= nil and s.handle == nil and s.idleSince ~= nil and (V.Clock - s.idleSince) > V.SplashIdleSeconds then
            Fx_Destroy(s.name)
            V.Splash[slot] = nil
        end
    end
end

-- Every frame: keep each active wake under its craft.
local function FollowSplashes()
    for slot = 1, V.MaxSplashes do
        local s = V.Splash[slot]
        if s ~= nil and s.handle ~= nil then
            local p = ValidHandle(s.handle) and PositionOf(s.handle) or nil
            if p ~= nil then
                Call("SetParticleSystemPosition", s.name, Vec(p.x, (s.y or p.y) + V.SplashHeight, p.z))
            else
                s.handle, s.rate, s.idleSince = nil, 0.0, V.Clock
                SetRate(s.name, 0.0)
            end
        end
    end
end

function V.GetSplashCount()
    local n = 0
    for slot = 1, V.MaxSplashes do
        local s = V.Splash[slot]
        if s ~= nil and s.handle ~= nil then n = n + 1 end
    end
    return n
end

-- =============================================================================
-- Networking
-- =============================================================================

function V.GetNetState()
    local forcedFor = 0.0
    if V.ForcedLevel ~= nil and V.ForcedUntil ~= nil then
        forcedFor = math.max(0.0, V.ForcedUntil - V.Clock)
    end
    return V.Seed or 0, V.Clock, V.Level, V.Episode and 1 or 0, V.TargetLevel,
        V.ForcedLevel or 0, forcedFor
end

function V.ApplyNetState(seed, clock, level, episode, target, forcedLevel, forcedFor)
    seed = tonumber(seed)
    if seed == nil or seed <= 0 then return false end

    if V.Seed ~= seed or V.Ladder == nil then
        BuildLadder(seed)
        V.Clock = tonumber(clock) or V.Clock
        V.Synced = true
    end

    clock = tonumber(clock) or V.Clock
    if math.abs(clock - V.Clock) > 2.0 then V.Clock = clock end

    V.TargetLevel = Clamp(floor(tonumber(target) or V.TargetLevel), 1, LEVEL_COUNT)
    forcedLevel = tonumber(forcedLevel) or 0
    forcedFor = tonumber(forcedFor) or 0
    if forcedLevel > 0 and forcedFor > 0 then
        V.ForcedLevel = Clamp(floor(forcedLevel), 1, LEVEL_COUNT)
        V.ForcedUntil = V.Clock + forcedFor
    elseif not V.IsAuthority then
        V.ForcedLevel = nil
        V.ForcedUntil = nil
    end

    if not V.IsAuthority then
        V.HostOverride = {
            level = Clamp(floor(tonumber(level) or 1), 1, LEVEL_COUNT),
            episode = tonumber(episode) == 1,
            expires = V.Clock + V.HostOverrideSeconds,
        }
    end
    return true
end

-- Dispatch for the mission adapter's receive path. Returns true when handled.
-- Never raises: a malformed event is dropped.
function V.ApplyNetEvent(op, ...)
    if op ~= "TitanState" and op ~= "TitanRoll" then return false end
    local args = { ... }
    local n = select("#", ...)
    local ok, result = pcall(function()
        if op == "TitanState" then
            return V.ApplyNetState(unpack(args, 1, n))
        end
        if V.IsAuthority then return true end
        return V.BeginRoll(args[1], args[2], args[3], "event")
    end)
    if not ok then
        print("CRTitanWeather: dropped " .. tostring(op) .. " event: " .. tostring(result))
        return true
    end
    return result and true or false
end

local function StateKey()
    return (V.Level * 1) + (V.Episode and 10 or 0) + (V.TargetLevel * 100) + ((V.ForcedLevel or 0) * 1000)
end

local function BroadcastState(force)
    if not V.IsAuthority or V.NetSend == nil then return end
    local key = StateKey()
    if force or key ~= V.LastStateKey or V.Clock >= V.NextNetStateAt then
        V.LastStateKey = key
        V.NextNetStateAt = V.Clock + V.NetHeartbeat
        Send("TitanState", V.GetNetState())
    end
end

function V.AnnounceState()
    BroadcastState(true)
end

function V.SetNetwork(options)
    options = options or {}
    if options.send ~= nil then V.NetSend = options.send end
    if options.authority ~= nil then V.IsAuthority = options.authority and true or false end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

local function Fault(where, err)
    V.Faults = V.Faults + 1
    print("CRTitanWeather: " .. where .. " failed (" .. tostring(V.Faults) .. "/" ..
        tostring(V.MaxFaults) .. "): " .. tostring(err))
    if V.Faults >= V.MaxFaults then
        V.Disabled = true
        print("CRTitanWeather: standing down after repeated faults; the mission continues without Titan weather")
        pcall(Fx_DestroyAll)
        pcall(SurfaceDestroy)
    end
end

-- options:
--   seed            number; the host's. Guests in a network game omit it and wait
--                   for the host's TitanState.
--   authority       true on the host / offline, false on a guest
--   send            function(op, ...) -- delivers a TitanState / TitanRoll event
--                   to every guest (host only)
--   sites           the generated CRTitanSites table (pools, wet mask, bounds)
--   startLevel, targetLevel
--   enabled, debug, quality, baseSky     passthrough
--   drizzle, hazeBank, rolls, randomRolls, pools, poolMist, ripples, splashes,
--   episodes        sub-system switches
local function InitInner(options)
    options = options or {}

    if options.enabled ~= nil then V.Enabled = options.enabled and true or false end
    if options.debug ~= nil then V.Debug = options.debug and true or false end
    local switches = {
        drizzle = "AllowDrizzle", hazeBank = "AllowHazeBank", rolls = "AllowRolls",
        randomRolls = "AllowRandomRolls", pools = "AllowPools", poolMist = "AllowPoolMist",
        ripples = "AllowRipples", splashes = "AllowSplashes", episodes = "AllowEpisodes",
        surface = "AllowSurface",
    }
    for key, field in pairs(switches) do
        if options[key] ~= nil then V[field] = options[key] and true or false end
    end

    V.SetNetwork({ send = options.send, authority = options.authority })

    V.RegisterPresets()
    CRWeather.Init({
        enabled = V.Enabled,
        quality = options.quality,
        debug   = options.debug,
        baseSky = options.baseSky,
    })

    V.TemplatesReady = false
    local okTemplates, templates = pcall(require, "CRParticleTemplates")
    if okTemplates and type(templates) == "table" and type(templates.EnsureExtra) == "function" then
        local ready, reason = templates.EnsureExtra("cr_titan")
        V.TemplatesReady = ready and true or false
        if not ready then
            print("CRTitanWeather: cr_titan particle templates unavailable (" .. tostring(reason) ..
                "); haze bank, pools and splashes are off (the presets still run)")
        end
    end

    V.Clock = 0.0
    V.LastRealTime = nil
    V.TargetLevel = Clamp(floor(tonumber(options.targetLevel) or 2), 1, LEVEL_COUNT)
    V.ForcedLevel, V.ForcedUntil, V.HostOverride = nil, nil, nil
    V.Roll_, V.SeenRolls, V.RollLog = nil, {}, {}
    V.RollSerial = 0
    V.LastRollEndAt = -1000.0
    V.Stats = { rolls = 0, scriptedRolls = 0, randomRolls = 0, mergedRolls = 0, splashes = 0, peakRoll = 0.0 }
    V.Systems, V.SystemCount, V.TemplateFailures = {}, 0, {}
    V.PoolLive, V.Splash, V.Tracked = {}, {}, {}
    V.Haze, V.HazeRateSent = nil, nil
    V.LastStateKey = nil
    V.AppliedPreset = nil
    V.NextStreamAt, V.NextRateAt, V.NextScanAt, V.NextNetStateAt = 0.0, 0.0, 0.0, 0.0
    V.Faults, V.Disabled = 0, false

    local seed = tonumber(options.seed)
    if seed == nil and V.IsAuthority then
        seed = math.random(1, 2000000000)
    end
    if seed ~= nil then
        BuildLadder(seed)
        V.Synced = true
    else
        -- A guest shows the calm rung until the host's state arrives rather
        -- than inventing a timeline that would diverge.
        V.Seed, V.Ladder, V.Synced = nil, nil, false
        V.RollRng = Map.NewRng(21)
    end

    V.Level = Clamp(floor(tonumber(options.startLevel) or 1), 1, LEVEL_COUNT)
    V.LevelValue = V.Level

    V.Sites = options.sites
    V.Pools = (type(V.Sites) == "table" and type(V.Sites.pools) == "table") and V.Sites.pools or {}
    V.Wet = DecodeWet(V.Sites)
    if options.surfaceMaterial ~= nil then V.SurfaceMaterial = tostring(options.surfaceMaterial) end
    V.SurfaceUp, V.SurfaceInfo, V.SurfaceSent, V.SurfaceReason, V.SurfaceBound = false, nil, nil, nil, nil
    V.SurfaceAttempts, V.SurfaceRetryAt, V.NextSurfaceAt = 0, nil, 0.0

    ScheduleNextRoll()
    SyncPreset(0.05)
    if V.Enabled and SurfaceCreate() then UpdateSurface(true) end

    V.Initialized = true
    Log("initialised; seed=" .. tostring(V.Seed) .. " authority=" .. tostring(V.IsAuthority) ..
        " pools=" .. tostring(#V.Pools) .. " wet=" .. tostring(V.Wet ~= nil))
    BroadcastState(true)
end

function V.Init(options)
    if V.Initialized then return end
    local ok, err = pcall(InitInner, options)
    if not ok then
        V.Initialized = true   -- never retry every frame
        Fault("Init", err)
    end
end

-- The simple entry point for an offline or host mission: a seed (nil picks one)
-- and the generated sites table.
function V.Start(seed, sites, options)
    options = options or {}
    options.seed = seed
    options.sites = sites or options.sites
    if options.authority == nil then options.authority = true end
    V.Init(options)
    return V.Seed
end

-- Same real-clock treatment as the other directors: adapters may pass a fixed
-- 1/TPS dt that is really a frame count, so take elapsed time from GetTime.
local function RealDelta(fallbackDt)
    if type(GetTime) ~= "function" then return fallbackDt end
    local now = GetTime()
    if type(now) ~= "number" then return fallbackDt end
    local last = V.LastRealTime
    V.LastRealTime = now
    if last == nil then return 0.0 end
    local delta = now - last
    if delta <= 0.0 or delta > 1.0 then return 0.0 end
    return delta
end

local function UpdateInner(dt)
    dt = tonumber(dt) or 0.0
    if dt > 0.0 then dt = RealDelta(dt) end
    if dt <= 0.0 then
        CRWeather.Update(0.0)
        return
    end

    V.Clock = V.Clock + dt

    UpdateLadder(dt)
    UpdateRandomRolls()
    UpdateRoll()
    if V.Synced then SyncPreset(nil) end
    if V.Clock >= (V.NextSurfaceAt or 0.0) then
        V.NextSurfaceAt = V.Clock + V.RateInterval
        UpdateSurface(false)
    end

    local playerPos = PositionOf(LocalPlayerHandle())
    if V.TemplatesReady then
        if V.Clock >= V.NextRateAt then
            V.NextRateAt = V.Clock + V.RateInterval
            UpdateHazeBank()
            UpdatePoolRates()
        end
        if V.Clock >= V.NextStreamAt then
            V.NextStreamAt = V.Clock + V.StreamInterval
            if (V.AllowPools or V.AllowPoolMist or V.AllowRipples) and #V.Pools > 0 then
                StreamPools(playerPos)
            end
        end
        if V.AllowSplashes and V.Wet ~= nil and playerPos ~= nil then
            if V.Clock >= V.NextScanAt then
                V.NextScanAt = V.Clock + V.SplashScanInterval
                UpdateSplashAssignments(playerPos)
            end
            FollowSplashes()
        end
    end

    BroadcastState(false)
    CRWeather.Update(dt)
end

function V.Update(dt)
    if V.Disabled then return end
    if not V.Initialized then V.Init() end
    if V.Disabled or not V.Enabled then return end
    local ok, err = pcall(UpdateInner, dt)
    if not ok then Fault("Update", err) end
end

function V.Shutdown()
    if not V.Initialized then return end
    pcall(Fx_DestroyAll)
    pcall(SurfaceDestroy)
    V.Tracked = {}
    pcall(CRWeather.Shutdown)
    V.Initialized = false
end

-- =============================================================================
-- Mission API
-- =============================================================================

function V.SetTargetLevel(index)
    if not V.IsAuthority then return V.TargetLevel end
    V.TargetLevel = Clamp(floor(tonumber(index) or 1), 1, LEVEL_COUNT)
    BroadcastState(true)
    return V.TargetLevel
end

function V.GetTargetLevel()
    return V.TargetLevel
end

function V.ForceLevel(index, seconds, transitionSeconds)
    if not V.Initialized then V.Init() end
    if not V.IsAuthority or V.Disabled then return false end
    index = Clamp(floor(tonumber(index) or 1), 1, LEVEL_COUNT)
    V.ForcedLevel = index
    V.ForcedUntil = V.Clock + math.max(1.0, tonumber(seconds) or 60.0)
    V.Level = index
    pcall(SyncPreset, transitionSeconds)
    BroadcastState(true)
    return true
end

function V.ReleaseForcedLevel()
    V.ForcedLevel = nil
    V.ForcedUntil = nil
    BroadcastState(true)
end

function V.GetLevel() return V.Level end
function V.GetLevelName() return Level(V.Level).name end
function V.IsEpisode() return V.Episode end
function V.GetPools() return V.Pools end
function V.GetStats() return V.Stats end
function V.GetSystemCount() return V.SystemCount end

function V.GetLivePoolCount()
    local n = 0
    for _ in pairs(V.PoolLive) do n = n + 1 end
    return n
end

function V.OnObjectCreated(h)
    pcall(CRWeather.OnObjectCreated, h)
end

function V.Describe()
    return string.format("%s (%.2f)%s roll %.2f preset %s systems %d pools %d wakes %d surface %s",
        Level(V.Level).name, V.LevelValue, V.Episode and " EPISODE" or "",
        V.GetRollIntensity(), tostring(V.AppliedPreset), V.SystemCount, V.GetLivePoolCount(),
        V.GetSplashCount(), V.SurfaceUp and "on" or ("off: " .. tostring(V.SurfaceReason)))
end

-- =============================================================================
-- Save / load
-- =============================================================================

function V.Save()
    return {
        seed        = V.Seed,
        clock       = V.Clock,
        level       = V.Level,
        levelValue  = V.LevelValue,
        targetLevel = V.TargetLevel,
        forcedLevel = V.ForcedLevel,
        forcedFor   = V.ForcedUntil and (V.ForcedUntil - V.Clock) or nil,
        ladder      = V.Ladder and V.Ladder:Save() or nil,
        rollSerial  = V.RollSerial,
        nextRollIn  = math.max(0.0, V.NextRollAt - V.Clock),
    }
end

local function LoadInner(state)
    if state.seed ~= nil and (V.Seed ~= state.seed or V.Ladder == nil) then
        BuildLadder(state.seed)
        V.Synced = true
    end
    V.Clock = tonumber(state.clock) or 0.0
    V.TargetLevel = Clamp(floor(tonumber(state.targetLevel) or 2), 1, LEVEL_COUNT)
    if V.Ladder ~= nil and state.ladder ~= nil then V.Ladder:Load(state.ladder) end
    V.RollSerial = tonumber(state.rollSerial) or 0

    if state.forcedLevel ~= nil and (tonumber(state.forcedFor) or 0.0) > 0.0 then
        V.ForcedLevel = Clamp(floor(tonumber(state.forcedLevel)), 1, LEVEL_COUNT)
        V.ForcedUntil = V.Clock + tonumber(state.forcedFor)
    else
        V.ForcedLevel, V.ForcedUntil = nil, nil
    end

    -- Loading rebuilds the Ogre scene: every system we held is already gone.
    Fx_DestroyAll()
    V.Tracked = {}
    V.Roll_ = nil
    V.LastRollEndAt = V.Clock
    V.NextRollAt = V.Clock + (tonumber(state.nextRollIn) or V.RollGap[1])
    if type(CRWeather.ResetSystems) == "function" then CRWeather.ResetSystems() end

    V.Level = Clamp(floor(tonumber(state.level) or 1), 1, LEVEL_COUNT)
    V.LevelValue = Clamp(tonumber(state.levelValue) or V.Level, 1.0, LEVEL_COUNT)
    V.AppliedPreset = nil
    SyncPreset(0.05)
    CRWeather.Blend = 1.0
    -- The sheet went with the old scene too: build it again (StaticGeometry
    -- replaces a stale record by name).
    V.SurfaceAttempts = 0
    if V.Enabled and SurfaceCreate() then UpdateSurface(true) end
    V.LastStateKey = nil
end

function V.Load(state)
    if type(state) ~= "table" then return end
    if not V.Initialized then V.Init() end
    if V.Disabled then return end
    local ok, err = pcall(LoadInner, state)
    if not ok then Fault("Load", err) end
end

return CRTitanWeather
