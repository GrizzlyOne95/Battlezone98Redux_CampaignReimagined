-- CRVenusWeather.lua
-- Venus weather and atmosphere director for Campaign Reimagined.
--
-- CRMarsWeather decides what the Martian sky does minute to minute. This is its
-- Venusian counterpart, and it is not Mars with a different palette: Venus has
-- no wind to speak of and nothing that falls to the ground, and what it has in
-- its place is a thick, dim, sulphurous overcast, pooled fog in the lowlands,
-- boiling sulphur, volcanoes, and lightning that is the point of the place.
--
-- Parts:
--
--   ladder       five rungs -- calm, haze, rising, storm, severe -- as a
--                seeded timeline (CRVenusMap.NewLadder) with temporary intense
--                storm EPISODES. The fractional position drives everything
--                continuous; integer rungs select a CRWeather preset.
--   fog pools    the playable ground is height-sampled once, the lowest enclosed
--                ground is found, and dense sulphur-tinted fog systems are
--                streamed in there. The global fog thickens as the local player
--                descends into a pool and thins as they climb out, through
--                Environment's modifier hook.
--   lightning    telegraph (St Elmo's fire) -> bolt -> flash -> thunder. Lightning
--                Power generators draw the overwhelming share of strikes, as if
--                harvesting the storm. A strike shoves nearby craft away and
--                scrambles their radar for a few seconds. It NEVER damages.
--   clouds       a churning cloud deck overhead, counter-rotating in two layers.
--   acid rain    streaks and splashes tied to severity. Visual only.
--   sulfur       bubbling pools and periodic burps on liquid-sulphur tiles.
--   vents        constant smoke plumes at the map's volcano / geyser sites and
--                periodic eruptions. Visual only.
--   fog banks    RARE, short dense sulphur-green fog moments ("pea soup", about
--                100-150 m of sight, a bright smeared sun, a glowing ground-haze
--                sheet). A seeded schedule every peer computes, plus a host
--                trigger (RequestFogBank / the drama hook) that rides one event.
--                Fog is a visual state: nothing in it touches a sensor.
--   lighting     dim orange-yellow overcast that goes dark and green in storms,
--                through the CRWeather presets plus this module's own Environment
--                modifier. Fog, ambient and sun still belong to Environment.lua:
--                this module only contributes.
--
-- CO-OP. Things that must match on every peer are decided once and shared:
--   * The severity timeline is a pure function of a seed. The host sends the
--     seed (GetNetState) and every peer derives the same timeline, so rung
--     changes cost no traffic and a lost packet cannot freeze a guest's sky.
--     The host also sends its actual rung on every change and as a heartbeat,
--     and a guest follows it, so the seeded timeline is a fallback that heals,
--     not a second authority.
--   * Strikes and eruptions depend on world state (which generators exist, where
--     the players are), so only the HOST chooses them and sends each as one
--     small event. Every peer renders it, and every peer applies the knockback
--     and radar scramble to the craft IT owns, which is where those craft are
--     simulated.
--   * Fog pools, sulfur, rain, clouds and ambient smoke are cosmetic and run
--     locally from static map data.
-- See Docs/VENUS_WEATHER.md for the wire protocol and the mission wiring.
--
-- Ownership rules this module obeys (same as CRMarsWeather):
--   * Fog, ambient and sun belong to Environment.lua. We set a CRWeather preset
--     and register Environment modifiers; we never call exu.SetFog and friends.
--   * Radar range/period and velocity jamming belong to Environment.lua. We add
--     a gameplay modifier for the global storm and Environment.SetObjectScramble
--     for per-craft strike scrambles.
--   * Nothing in this file calls anything that changes health or ammo.

local exu = require("exu")
local CRWeather = require("CRWeather")
local Wake = require("CRWake")
local Map = require("CRVenusMap")
local PoolFX = require("CRPoolFX")

local CRVenusWeather = {}
local V = CRVenusWeather

-- =============================================================================
-- Configuration
-- =============================================================================

V.Enabled              = true
V.Debug                = false

-- Each sub-system is independently switchable.
V.AllowFogPools        = true    -- pooled fog systems in the lowlands
V.AllowAltitudeFog     = true    -- global fog density follows the player's altitude
V.AllowLightning       = true
V.AllowKnockback       = true    -- strike shove on nearby craft (no damage)
V.AllowRadarScramble   = true
V.AllowFlash           = true    -- local scene flash on a strike
V.AllowClouds          = true
V.AllowAcidRain        = true    -- visual only
V.AllowSulfur          = true
V.AllowPoolFx          = true    -- yellow bubble pops, motes and pale fumes on the liquid-sulphur pools (CRPoolFX)
V.AllowVents           = true
V.AllowEruptions       = true
V.AllowSensorDegrade   = true    -- storm-wide radar / velocity-jam scales
V.AllowEpisodes        = true    -- temporary intense storms
V.AllowFogBanks        = true    -- rare dense-fog moments (scheduled and requested)
V.AllowFogDrama        = true    -- the host may PICK THE TIMING of a bank when big hostiles close in

-- Hard budgets. These are caps, not targets.
V.MaxSystems           = 36      -- every particle system this module owns, at once
V.MaxLiveFog           = 6
V.MaxLiveSulfur        = 8
V.MaxLivePlumes        = 6
V.MaxLiveStrikes       = 3       -- simultaneous strike visuals
V.MaxLiveHaze          = 7       -- ground-haze systems a fog bank streams around the player
V.MaxFailuresPerTemplate = 3

-- Streaming: a system is created inside StreamIn and destroyed beyond StreamOut.
V.FogStreamIn          = 520.0
V.FogStreamOut         = 660.0
V.SulfurStreamIn       = 360.0
V.SulfurStreamOut      = 460.0
V.PlumeStreamIn        = 1000.0
V.PlumeStreamOut       = 1250.0
V.StreamInterval       = 1.0     -- seconds between streaming passes

-- Severity ladder.
V.SeverityRate         = 0.050   -- rungs per second the smoothed position moves
V.EpisodeChance        = 0.30    -- per rung change at "rising" or worse
V.EpisodePeak          = { 4, 5 }
V.EpisodeStepDwell     = { 7.0, 12.0 }
V.EpisodeHold          = { 35.0, 80.0 }
V.EpisodeCooldown      = 170.0
V.EpisodeStrikeBoost   = 1.8     -- strike rate multiplier inside an episode

-- Fog by altitude.
V.ScanColumns          = 64
V.ScanRows             = 56
V.ScanBudget           = 160     -- terrain queries per frame while scanning
V.ScanInset            = 60.0    -- stay this far inside the playable box
V.PoolFogEndScale      = 0.62    -- fog end distance multiplier at full pool depth
V.PoolFogStartScale    = 0.55
V.PoolFogTint          = 0.30    -- how far pool fog colour moves toward PoolFogColor
V.PoolFogColor         = { r = 0.58, g = 0.54, b = 0.15 }
V.PoolBand             = nil     -- metres over the pool level where it is gone; nil = from terrain
V.PoolResponse         = 0.55    -- factor change per second (smoothing)
V.FogDensity           = 1.0     -- scales the pooled-fog emission rate

-- Fog banks. A bank is a rare, short moment, not a rung: the seeded schedule
-- (a pure function of the seed, identical on every peer) puts a few in a mission,
-- each closing the air to pea soup in sulphur green-yellow while the sun stays a
-- bright smeared disk. All colours are DISPLAY RGB (the Enhanced renderer decodes
-- fog colour itself); the fog distances are clamped to the map's terrain horizon
-- exactly as the ladder's are, and a bank only ever makes fog THICKER, never
-- clearer than the rung already is.
V.FogBankFirstDelay    = { 150.0, 330.0 }   -- seconds into the mission
V.FogBankGap           = { 300.0, 660.0 }   -- end of one -> start of the next
V.FogBankSeconds       = { 30.0, 75.0 }     -- first roll-in to fully clear
V.FogBankRollIn        = { 8.0, 14.0 }
V.FogBankRollOut       = { 10.0, 18.0 }
V.FogBankPower         = { 0.85, 1.0 }
V.FogBankFogEnd        = 120.0     -- target fog end (metres), clamped to the horizon
V.FogBankFogStart      = 4.0       -- fog begins almost at the camera: pea soup
V.FogBankColor         = { r = 0.40, g = 0.44, b = 0.17 }   -- sulphur green-yellow
V.FogBankColorMix      = 0.92
V.FogBankSunPower      = 0.44      -- the sun is never allowed below this inside a bank
V.FogBankAmbient       = { r = 0.40, g = 0.36, b = 0.13 }   -- glowing ochre ground light
V.FogBankDiffuse       = { r = 0.62, g = 0.58, b = 0.22 }
V.FogBankLightMix      = 0.50
V.FogBankGloomRelief   = 0.80      -- how much of the storm gloom a bank washes out
V.FogBankSuppress      = { 3.0, 4.0 }   -- ladder position over which a bank fades 1 -> 0 (storm)
V.FogBankAllowRate     = 0.12      -- allow-factor change per second (a storm eases a bank away)
V.FogBankPoolBoost     = 1.6       -- extra emission on the basin fog pools while a bank is up
V.FogBankHazeRate      = 7.0       -- emission per ground-haze system at full strength
V.FogBankHazeQuota     = 70
V.FogBankHazeCell      = 55.0      -- grid spacing of the ground-haze systems
V.FogBankHazeIn        = 115.0     -- create inside, destroy beyond FogBankHazeOut
V.FogBankHazeOut       = 160.0
V.FogBankHazeLinger    = 36.0      -- seconds to keep haze systems after the bank ends (they fade out)
V.FogBankHazeColor     = { r = 0.86, g = 0.76, b = 0.22 }   -- yellow-ochre
V.FogBankHazeAlpha     = 0.30

-- The drama hook. The host (only) may start a bank early when large hostile
-- units or a hostile group are closing on a human. It chooses TIMING only: it
-- never moves, orders or alters a unit, and what it decides travels as the same
-- single VenusFog event a mission script's RequestFogBank sends.
V.DramaScanInterval    = 2.0
V.DramaChance          = 0.5       -- per qualifying scan
V.DramaCooldown        = 150.0     -- seconds clear after any bank before another is requested
V.DramaClearance       = 45.0      -- keep this far from a scheduled bank (before it starts)
V.DramaMinClock        = 90.0
V.DramaMaxPerMission   = 3
V.DramaRange           = { 150.0, 380.0 }   -- hostile to nearest human, metres
V.DramaClosingSpeed    = 2.5       -- metres/second of closing needed to count as "approaching"
V.DramaOdfPatterns     = { "walk", "artl" } -- large units: walkers, artillery (ODF names truncate)
V.DramaGroupSize       = 4         -- this many closing hostile craft count as a group
V.DramaMaxScan         = 240

-- Lightning.
V.TelegraphSeconds     = { 1.2, 2.0 }
V.StrikeMinGap         = 1.2     -- never two strikes closer than this
V.PowerWeight          = 100.0   -- per Lightning Power generator
V.ExposedWeight        = 2.5     -- per tall / exposed craft or turret
V.GroundWeight         = 1.0     -- per random ground candidate near a player
V.GroundCandidates     = 4
V.GroundRing           = { 35.0, 210.0 }
V.PowerRateBoost       = 1.6     -- strike rate multiplier while a generator exists
V.PowerRodHeight       = 14.0    -- the bolt lands this far above a generator's base
V.PowerAfterglow       = 3.0     -- seconds a struck generator keeps crackling
V.LightningPowerOdfs   = { "ablpow", "bblpow", "cblpow", "sblpow", "sblpowa", "sblpowb" }
V.ExposedOdfPatterns   = { "towe", "turr", "comm" }   -- ODF names truncate: sbtowe, svturr, sbcomm
V.ExposedAltitude      = 22.0    -- a craft this far above the pool level counts as exposed
V.ThunderSound         = "lstart.wav"
V.ThunderSpeed         = 340.0   -- world units per second
V.ThunderMaxDelay      = 6.0
V.ThunderVolume        = 100
V.ThunderRate          = 70      -- percent playback rate: lower reads as heavier

-- Strike consequences. NEVER damage; these are shove and sensors only.
V.KnockRadius          = 70.0
V.KnockMaxSpeed        = 16.0    -- velocity added at the epicentre, units/second
V.KnockLift            = 0.22    -- fraction of the shove applied upward
V.KnockSpeedCap        = 34.0    -- horizontal speed is never pushed past this
V.KnockReferenceMass   = 1000.0
V.ScrambleRadius       = 110.0
V.ScrambleSeconds      = { 3.0, 5.5 }
V.ScrambleRadarRange   = 0.10
V.ScrambleVelocJam     = 2.5

-- Flash.
V.FlashNear            = 160.0   -- full flash inside this distance of the local player
V.FlashFar             = 1500.0
V.FlashFloor           = 0.10    -- everybody sees a little, even a far strike
V.FlashAmbient         = { r = 0.46, g = 0.43, b = 0.34 }
V.FlashDiffuse         = { r = 0.52, g = 0.48, b = 0.36 }
V.FlashSunBoost        = 0.9
V.FlashSeconds         = 0.42

-- Storm lighting beyond the presets.
V.GloomDim             = 0.14
V.GloomGreen           = 0.06

-- Wind. Venus surface wind is slow but the air is thick, so it is for dressing:
-- it leans plumes, drifts the fog and tilts rain. It never pushes anything.
V.BearingWander        = 0.8
V.BearingRate          = 0.04

-- Clouds.
V.CloudHeights         = { 38.0, 62.0 }
V.CloudPrecession      = { 0.020, -0.013 }   -- radians per second, per layer
V.CloudDrift           = 1.1                 -- LinearForce strength

-- Acid rain.
V.RainMaxRate          = 520.0
V.RainMaxQuota         = 4000
V.RainSplashRate       = 55.0
V.RainTint             = { r = 0.50, g = 0.68, b = 0.22 }

-- Sulfur.
V.SulfurSteamRate      = 5.0
V.SulfurBurpGap        = { 2.5, 9.0 }
V.SulfurBurpRate       = 90.0
V.SulfurBurpSeconds    = 0.35
V.SulfurBurpSound      = "lburn1.wav"
V.SulfurSoundRange     = 90.0
V.SulfurSoundVolume    = 45
-- Pool pops (CRPoolFX through CRGroundFX "sulfur"): at most PoolFxNear pools within
-- PoolFxRange of the player fire one event each every PoolFxGap seconds, quicker as
-- the storm builds (1 + 0.5 x severity). CRGroundFX caps the live emitters (4 systems).
V.PoolFxRange          = 170.0
V.PoolFxNear           = 3
V.PoolFxGap            = { 2.0, 5.0 }
V.PoolFxRadius         = 24.0
V.PoolFxMask           = {}

-- Vents.
V.VentMergeRadius      = 45.0
V.PlumeMajorRate       = 9.0
V.PlumeMinorRate       = 3.5
V.EruptionGap          = { 75.0, 165.0 }
V.EruptionSeconds      = { 14.0, 26.0 }
V.EruptionMajorWeight  = 5.0
V.EruptionBurstRate    = 120.0
V.EruptionEmberRate    = 90.0
V.EruptionRumbleSound  = "gquak00.wav"
V.EruptionBurstSound   = "r_exp3.wav"
V.EruptionSoundRange   = 1400.0
V.EruptionVolume       = 85

-- Co-op. The host re-announces its state this often even when nothing changed;
-- a guest trusts the host's rung for 1.5 heartbeats and then falls back to the
-- seeded timeline it has been computing all along.
V.NetHeartbeat         = 30.0
V.HostOverrideSeconds  = 45.0

-- Optional hook for OpenShim render intents. Nothing renders them yet; this is a
-- no-op until OpenShim implements depth_haze, and costs nothing until then.
V.AllowRenderIntents   = true

-- =============================================================================
-- The ladder
--
-- One row per rung. Continuous values interpolate between adjacent rows by the
-- smoothed ladder position, so nothing steps when a preset swaps.
-- =============================================================================

V.Levels = {
    { name = "Calm",    preset = "VenusCalm",   windSpeed = 3.0,  strikesPerMinute = 0.0,
      rain = 0.00, cloud = 0.20, gloom = 0.00, visibility = 100.0,
      radarRange = 1.00, velocJam = 1.00, duration = { 80.0, 170.0 } },
    { name = "Haze",    preset = "VenusHaze",   windSpeed = 5.0,  strikesPerMinute = 0.0,
      rain = 0.00, cloud = 0.40, gloom = 0.12, visibility = 92.0,
      radarRange = 0.97, velocJam = 1.03, duration = { 70.0, 150.0 } },
    { name = "Rising",  preset = "VenusRising", windSpeed = 9.0,  strikesPerMinute = 3.0,
      rain = 0.30, cloud = 0.65, gloom = 0.38, visibility = 84.0,
      radarRange = 0.88, velocJam = 1.10, duration = { 60.0, 130.0 } },
    { name = "Storm",   preset = "VenusStorm",  windSpeed = 14.0, strikesPerMinute = 9.0,
      rain = 0.70, cloud = 0.88, gloom = 0.72, visibility = 72.0,
      radarRange = 0.72, velocJam = 1.22, duration = { 50.0, 110.0 } },
    { name = "Severe",  preset = "VenusSevere", windSpeed = 20.0, strikesPerMinute = 18.0,
      rain = 1.00, cloud = 1.00, gloom = 1.00, visibility = 56.0,
      radarRange = 0.55, velocJam = 1.40, duration = { 35.0, 80.0 } },
}

local LEVEL_COUNT = #V.Levels

-- =============================================================================
-- Runtime state
-- =============================================================================

V.Initialized      = false
V.Seed             = nil
V.Synced           = true        -- false on a guest until the host's state arrives
V.IsAuthority      = true        -- host / offline; guests only follow
V.NetSend          = nil         -- function(op, ...) the mission adapter provides
V.OwnerTest        = nil         -- optional override: function(h) -> boolean

V.Clock            = 0.0
V.LastRealTime     = nil
V.Ladder           = nil
V.Level            = 1
V.Episode          = false
V.TargetLevel      = 2
V.LevelValue       = 1.0
V.ForcedLevel      = nil
V.ForcedUntil      = nil
V.HostOverride     = nil         -- guest: { level, episode, expires }

V.Bearing          = 0.0
V.BearingTarget    = 0.0
V.NextBearingAt    = 0.0
V.WindSpeed        = 0.0

V.Basins           = nil
V.Scan             = nil
V.PoolFactor       = 0.0
V.PoolFactorTarget = 0.0
V.NextPoolSampleAt = 0.0

V.Powers           = {}          -- handle -> true
V.NextPowerScanAt  = 0.0
V.NextStrikeAt     = 0.0
V.StrikeSerial     = 0
V.Strikes          = {}          -- id -> strike record
V.SeenStrikes      = {}
V.Flashes          = {}
V.Thunder          = {}
V.LastStrikeAt     = -100.0

V.EruptionSerial   = 0
V.NextEruptionAt   = 0.0
V.Eruptions        = {}

V.FogBanks         = nil         -- seeded schedule (Map.NewFogBanks)
V.FogRng           = nil         -- host-only stream for requested banks
V.FogRequests      = {}          -- explicit / drama banks: { start, rollIn, hold, rollOut, power, force }
V.SeenFogs         = {}
V.FogSerial        = 0
V.FogAllow         = 0.0         -- 0..1, how much a bank may show right now (storm / forced level)
V.FogIntensity     = 0.0         -- 0..1, the bank in force this frame
V.FogLastActiveAt  = -1000.0
V.HazeLive         = {}          -- "ix:iz" -> record
V.NextDramaAt      = 0.0
V.DramaCount       = 0
V.DramaTrack       = {}
V.LastDrama        = nil

V.Stats = {
    strikes = 0, powerStrikes = 0, exposedStrikes = 0, groundStrikes = 0,
    knocked = 0, scrambled = 0, eruptions = 0,
}

V.PlayersProvider  = nil         -- optional: function() -> array of player handles
V.Systems          = {}          -- name -> kind
V.SystemCount      = 0
V.TemplateFailures = {}
V.TemplatesReady   = false
V.GameplayRegistered = false
V.EnvModifierRegistered = false
V.LastSyncSeverity = -1.0
V.Serial           = 0
V.NextStreamAt     = 0.0
V.NextNetStateAt   = 0.0
V.LastStateKey     = nil

V.FogLive          = {}          -- anchor index -> record
V.SulfurSites      = {}
V.SulfurLive       = {}          -- site index -> record
V.VentSites        = {}
V.PlumeLive        = {}          -- site index -> record
V.Rain             = nil
V.Clouds           = {}          -- layer index -> record
V.LastBurpSoundAt  = -10.0

-- =============================================================================
-- Helpers
-- =============================================================================

local Clamp = Map.Clamp
local SmoothStep = Map.SmoothStep

local function Lerp(a, b, t)
    return a + ((b - a) * t)
end

local function Log(message)
    if V.Debug then
        print("CRVenusWeather: " .. tostring(message))
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
    local low = math.floor(position)
    local high = math.min(low + 1, LEVEL_COUNT)
    return Lerp(Level(low)[field], Level(high)[field], position - low)
end

-- 0 at the bottom of the ladder, 1 at the top.
function V.GetSeverity()
    if LEVEL_COUNT <= 1 then return 0.0 end
    return Clamp((V.LevelValue - 1.0) / (LEVEL_COUNT - 1), 0.0, 1.0)
end

-- The engine hands back VECTOR_3D userdata, not a table: read x/y/z inside a
-- pcall and return a plain table (nil unless x and z are numbers).
local function ReadVector(p)
    if p == nil then return nil end
    local okX, x, y, z = pcall(function() return p.x, p.y, p.z end)
    if okX and type(x) == "number" and type(z) == "number" then
        return { x = x, y = tonumber(y) or 0.0, z = z }
    end
    return nil
end

local function PositionOf(h)
    if h == nil or type(GetPosition) ~= "function" then return nil end
    local ok, p = pcall(GetPosition, h)
    if not ok then return nil end
    return ReadVector(p)
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

local function LocalPlayerHandle()
    if type(GetPlayerHandle) ~= "function" then return nil end
    local ok, h = pcall(GetPlayerHandle)
    if ok and ValidHandle(h) then return h end
    return nil
end

local function LocalPlayerPosition()
    return PositionOf(LocalPlayerHandle())
end

local function Distance2D(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt((dx * dx) + (dz * dz))
end

-- Does THIS peer simulate the craft? Knockback and sensor scrambles must be
-- applied by the owner: a replica's velocity is overwritten by its owner on the
-- next update, and Environment refuses to write a replica's sensors.
local function OwnsLocally(h)
    if V.OwnerTest ~= nil then
        return V.OwnerTest(h) and true or false
    end
    if type(IsNetGame) == "function" and IsNetGame() then
        if type(IsLocal) == "function" then
            local ok, own = pcall(IsLocal, h)
            return ok and own and true or false
        end
        return false
    end
    return true
end

local function NormalizeOdf(name)
    if type(name) ~= "string" then return "" end
    return (string.lower(name):gsub("%.odf$", ""))
end

local LightningOdfSet = {}
local function RebuildPowerSet()
    LightningOdfSet = {}
    for i = 1, #V.LightningPowerOdfs do
        LightningOdfSet[NormalizeOdf(V.LightningPowerOdfs[i])] = true
    end
end
RebuildPowerSet()

function V.IsLightningPower(h)
    if type(GetOdf) ~= "function" then return false end
    local ok, odf = pcall(GetOdf, h)
    if not ok then return false end
    return LightningOdfSet[NormalizeOdf(odf)] == true
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
    local name = "cr_vw_" .. kind .. "_" .. tostring(V.Serial)
    if Call("CreateParticleSystem", name, template, Vec(x, y, z)) ~= true then
        local failures = (V.TemplateFailures[template] or 0) + 1
        V.TemplateFailures[template] = failures
        if failures >= V.MaxFailuresPerTemplate then
            print("CRVenusWeather: " .. template .. " disabled after " .. tostring(failures) ..
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
end

local function WindVector()
    return math.sin(V.Bearing), math.cos(V.Bearing)
end

-- =============================================================================
-- Wind
-- =============================================================================

local function UpdateWind(dt)
    local rng = V.WindRng
    if V.Clock >= V.NextBearingAt then
        V.BearingTarget = V.PrevailingBearing + rng.Range(-V.BearingWander, V.BearingWander)
        V.NextBearingAt = V.Clock + rng.Range(18.0, 50.0)
    end

    local delta = V.BearingTarget - V.Bearing
    while delta > math.pi do delta = delta - (2.0 * math.pi) end
    while delta < -math.pi do delta = delta + (2.0 * math.pi) end
    local maxStep = V.BearingRate * dt
    if delta > maxStep then delta = maxStep end
    if delta < -maxStep then delta = -maxStep end
    V.Bearing = V.Bearing + delta

    local wanted = LadderValue("windSpeed")
    V.WindSpeed = Lerp(V.WindSpeed, wanted, Clamp(dt * 1.2, 0.0, 1.0))

    local wx, wz = WindVector()
    local fall = -0.10 - (0.14 * Clamp(V.WindSpeed / 20.0, 0.0, 1.0))
    local horizontal = math.sqrt(math.max(0.0, 1.0 - (fall * fall)))
    CRWeather.SetWindOverride({ x = wx * horizontal, y = fall, z = wz * horizontal }, V.WindSpeed)
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
    V.WindRng = Map.NewRng(Map.DeriveSeed(seed, 4))
    V.StrikeRng = Map.NewRng(Map.DeriveSeed(seed, 2))
    V.EruptionRng = Map.NewRng(Map.DeriveSeed(seed, 3))
    V.FxRng = Map.NewRng(Map.DeriveSeed(seed, 5))
    V.FogRng = Map.NewRng(Map.DeriveSeed(seed, 7))
    V.FogBanks = Map.NewFogBanks(seed, {
        firstDelay = V.FogBankFirstDelay, gap = V.FogBankGap, total = V.FogBankSeconds,
        rollIn = V.FogBankRollIn, rollOut = V.FogBankRollOut, power = V.FogBankPower,
    })
    V.PrevailingBearing = V.WindRng.Range(0.0, 2.0 * math.pi)
    V.Bearing = V.PrevailingBearing
    V.BearingTarget = V.PrevailingBearing
    V.NextBearingAt = 0.0
end

local function ApplyRung(index, transitionSeconds)
    index = Clamp(index, 1, LEVEL_COUNT)
    local row = Level(index)
    if V.Level ~= index or CRWeather.GetPreset() ~= row.preset then
        CRWeather.SetPreset(row.preset, transitionSeconds)
        Log("level -> " .. row.name .. " (" .. row.preset .. ")")
    end
    V.Level = index
end

-- The rung in force right now, and whether it is part of a storm episode.
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

local function UpdateLadder(dt)
    if not V.Synced then
        return
    end

    local level, episode = ResolveLevel()
    V.Episode = episode
    if level ~= V.Level then
        ApplyRung(level, nil)
    end

    local step = V.SeverityRate * dt
    local delta = V.Level - V.LevelValue
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.LevelValue = Clamp(V.LevelValue + delta, 1.0, LEVEL_COUNT)
end

-- =============================================================================
-- Terrain scan and fog pools
-- =============================================================================

local function ResolveBounds(options)
    if options.bounds ~= nil then
        return options.bounds
    end
    local sites = options.sites
    if sites ~= nil and sites.bounds ~= nil then
        return sites.bounds
    end
    if type(GetPathPointCount) == "function" and type(GetPosition) == "function" then
        local ok, count = pcall(GetPathPointCount, "edge_path")
        if ok and type(count) == "number" and count >= 2 then
            local minX, maxX, minZ, maxZ = 1e30, -1e30, 1e30, -1e30
            for i = 0, count - 1 do
                local okPoint, p = pcall(GetPosition, "edge_path", i)
                if okPoint then p = ReadVector(p) end
                if okPoint and p ~= nil then
                    if p.x < minX then minX = p.x end
                    if p.x > maxX then maxX = p.x end
                    if p.z < minZ then minZ = p.z end
                    if p.z > maxZ then maxZ = p.z end
                end
            end
            if maxX > minX and maxZ > minZ then
                return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
            end
        end
    end
    return nil
end

local function StartTerrainScan(bounds)
    if bounds == nil or type(GetTerrainHeightAndNormal) ~= "function" then
        return
    end
    V.Bounds = bounds
    V.Scan = Map.NewHeightScan(bounds, V.ScanColumns, V.ScanRows, TerrainHeight, V.ScanInset)
    V.Basins = nil
end

local function UpdateTerrainScan()
    local scan = V.Scan
    if scan == nil then return end
    if scan:Step(V.ScanBudget) then
        V.Basins = Map.AnalyseBasins(scan, { maxAnchors = 24 })
        V.Scan = nil
        if V.Basins ~= nil then
            Log(string.format("basins: %d clusters, %d anchors, pool level %.1f, ridge %.1f",
                #V.Basins.clusters, #V.Basins.anchors, V.Basins.poolLevel, V.Basins.ridgeLevel))
        end
    end
end

local function UpdatePoolFactor(dt)
    if not V.AllowAltitudeFog or V.Basins == nil then
        V.PoolFactorTarget = 0.0
    elseif V.Clock >= V.NextPoolSampleAt then
        V.NextPoolSampleAt = V.Clock + 0.25
        local p = LocalPlayerPosition()
        if p ~= nil then
            V.PoolFactorTarget = Map.PoolFactor(V.Basins, p.x, p.y, p.z, { band = V.PoolBand })
        end
    end

    local step = V.PoolResponse * dt
    local delta = V.PoolFactorTarget - V.PoolFactor
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.PoolFactor = Clamp(V.PoolFactor + delta, 0.0, 1.0)
end

-- Nearest local player distance, or nil if there is no player to stream around.
local function NearestPlayerDistance(x, z, playerPos)
    if playerPos == nil then return nil end
    return Distance2D(x, z, playerPos.x, playerPos.z)
end

-- Generic streaming pass: keep up to `maxLive` systems for the sites nearest the
-- player, create inside `inRange`, destroy beyond `outRange`. One creation per
-- pass, so a long list never costs a frame spike.
local function StreamSites(sites, live, maxLive, inRange, outRange, create, destroy, playerPos)
    if playerPos == nil then return end

    local count = 0
    local drop = {}
    for index, record in pairs(live) do
        local site = sites[index]
        local d = NearestPlayerDistance(site.x, site.z, playerPos)
        if d == nil or d > outRange then
            drop[#drop + 1] = index
        else
            count = count + 1
        end
    end
    for i = 1, #drop do
        destroy(drop[i], live[drop[i]])
        live[drop[i]] = nil
    end

    if count >= maxLive then return end

    local best, bestDistance = nil, inRange
    for index = 1, #sites do
        if live[index] == nil then
            local d = NearestPlayerDistance(sites[index].x, sites[index].z, playerPos)
            if d ~= nil and d < bestDistance then
                best, bestDistance = index, d
            end
        end
    end
    if best ~= nil then
        local record = create(best, sites[best])
        if record ~= nil then live[best] = record end
    end
end

local function SetWindOnSystem(name, strength, affector)
    local wx, wz = WindVector()
    Call("SetParticleAffectorParameter", name, affector or 2, "force_vector",
        string.format("%.3f 0 %.3f", wx * strength, wz * strength))
end

-- ---- fog pool systems -------------------------------------------------------

local function FogCreate(index, anchor)
    local y = TerrainHeight(anchor.x, anchor.z) or anchor.y
    local name = Fx_Create("fog", "CR/Venus/FogPool", anchor.x, y + 3.0, anchor.z)
    if name == nil then return nil end
    Call("SetParticleSystemParticleQuota", name, 90)
    return { name = name, x = anchor.x, z = anchor.z, weight = anchor.weight, wind = -1.0 }
end

local function FogDestroy(_, record)
    Fx_Destroy(record.name)
end

local function UpdateFogSystems(dt)
    if not V.AllowFogPools or V.Basins == nil or not V.TemplatesReady then
        for index, record in pairs(V.FogLive) do
            Fx_Destroy(record.name)
            V.FogLive[index] = nil
        end
        return
    end

    -- Fog thickens as the weather does, and with how deep the basin is.
    local severity = V.GetSeverity()
    for _, record in pairs(V.FogLive) do
        local rate = 2.6 * V.FogDensity * (0.55 + (0.9 * severity)) * (0.6 + (0.8 * record.weight))
        rate = rate * (1.0 + (V.FogBankPoolBoost * V.FogIntensity))
        Call("SetParticleEmitterEmissionRate", record.name, 0, rate)

        -- Re-aim only when the wind has moved enough to see.
        if math.abs(V.Bearing - record.wind) > 0.06 then
            record.wind = V.Bearing
            local wx, wz = WindVector()
            Call("SetParticleEmitterDirection", record.name, 0, Vec(wx, 0.0, wz))
            SetWindOnSystem(record.name, 0.35 + (V.WindSpeed * 0.04), 2)
        end
    end
end

-- =============================================================================
-- Fog banks (visual only)
--
-- Three layers decide what a bank looks like on this peer:
--   FogAllow      0..1  whether a bank may show right now. It falls to 0 as the
--                 ladder climbs through the storm rungs and while a ForceLevel
--                 set piece is pinned, so a bank never stacks on the lightning
--                 peak or fights a scripted beat. Smoothed, so a storm eases a
--                 bank away instead of cutting it.
--   FogIntensity  0..1  the bank in force this frame: the larger of the seeded
--                 schedule and any requested (host / script / drama) bank,
--                 each shaped by smooth roll-in and roll-out.
--   Modifier      fog, light and sun through Environment (EnvironmentModifier);
--                 plus a ring of ground-haze systems streamed around the player.
-- Nothing here reads or writes a sensor, a unit or a health value.
-- =============================================================================

local function FogHorizon()
    local environment = rawget(_G, "Environment")
    if environment ~= nil and type(environment.GetFogHorizon) == "function" then
        local ok, horizon = pcall(environment.GetFogHorizon)
        horizon = ok and tonumber(horizon) or nil
        if horizon ~= nil and horizon > 0.0 then return horizon end
    end
    return nil
end

local function FogAllowTarget()
    if not V.AllowFogBanks or not V.Synced or V.FogBanks == nil then return 0.0 end
    if V.ForcedLevel ~= nil then return 0.0 end
    local low, high = V.FogBankSuppress[1], V.FogBankSuppress[2]
    return 1.0 - SmoothStep((V.LevelValue - low) / math.max(0.01, high - low))
end

local function RequestedFogEnvelope(allow)
    local best = 0.0
    for i = #V.FogRequests, 1, -1 do
        local r = V.FogRequests[i]
        if V.Clock >= (r.start + r.rollIn + r.hold + r.rollOut) then
            table.remove(V.FogRequests, i)
        else
            local e = Map.FogEnvelope(r, V.Clock) * r.power
            if not r.force then e = e * allow end
            if e > best then best = e end
        end
    end
    return best
end

local function UpdateFogBank(dt)
    local step = V.FogBankAllowRate * dt
    local delta = FogAllowTarget() - V.FogAllow
    if delta > step then delta = step end
    if delta < -step then delta = -step end
    V.FogAllow = Clamp(V.FogAllow + delta, 0.0, 1.0)

    local natural, requested = 0.0, 0.0
    if V.AllowFogBanks then
        if V.FogBanks ~= nil and V.Synced then
            local bank = V.FogBanks:Active(V.Clock)
            if bank ~= nil then natural = Map.FogEnvelope(bank, V.Clock) * bank.power * V.FogAllow end
        end
        requested = RequestedFogEnvelope(V.FogAllow)
    end
    V.FogIntensity = Clamp(math.max(natural, requested), 0.0, 1.0)
    if V.FogIntensity > 0.02 then V.FogLastActiveAt = V.Clock end
end

-- Starts a bank with explicit phase lengths on THIS peer, from now. This is the
-- receive path for the host's VenusFog event and what RequestFogBank runs locally.
function V.BeginFogBank(id, rollIn, hold, rollOut, power, force)
    id = tonumber(id)
    if id == nil or V.SeenFogs[id] then return true end
    V.SeenFogs[id] = true
    if not V.AllowFogBanks then return true end
    if #V.FogRequests >= 4 then table.remove(V.FogRequests, 1) end
    V.FogRequests[#V.FogRequests + 1] = {
        start = V.Clock,
        rollIn = math.max(1.0, tonumber(rollIn) or 10.0),
        hold = math.max(1.0, tonumber(hold) or 20.0),
        rollOut = math.max(1.0, tonumber(rollOut) or 14.0),
        power = Clamp(tonumber(power) or 1.0, 0.0, 1.0),
        force = tonumber(force) == 1,
    }
    Log("fog bank " .. tostring(id))
    return true
end

-- ---- ground haze -------------------------------------------------------------

local function HazeCreate(cell)
    local y = TerrainHeight(cell.x, cell.z)
    if y == nil then
        local p = LocalPlayerPosition()
        y = p and p.y or 0.0
    end
    local name = Fx_Create("haze", "CR/Venus/FogPool", cell.x, y + 2.0, cell.z)
    if name == nil then return nil end
    Call("SetParticleSystemParticleQuota", name, V.FogBankHazeQuota)
    local c, a = V.FogBankHazeColor, V.FogBankHazeAlpha
    Call("SetParticleEmitterColor", name, 0,
        { r = c.r, g = c.g, b = c.b, a = a }, { r = c.r * 0.9, g = c.g * 0.9, b = c.b * 0.85, a = a * 0.4 })
    -- The template's ColourInterpolator would otherwise repaint the cards
    -- olive; it is told the same ochre. Spelling is judged live (see the doc).
    Call("SetParticleAffectorParameter", name, 0, "colour1", string.format("%.2f %.2f %.2f %.2f", c.r, c.g, c.b, a))
    Call("SetParticleAffectorParameter", name, 0, "colour2",
        string.format("%.2f %.2f %.2f %.2f", c.r * 0.92, c.g * 0.92, c.b * 0.9, a * 0.8))
    return { name = name, x = cell.x, z = cell.z, rate = -1.0 }
end

local function HazeDestroy(key)
    local record = V.HazeLive[key]
    if record ~= nil then Fx_Destroy(record.name) end
    V.HazeLive[key] = nil
end

local function HazeCount()
    local n = 0
    for _ in pairs(V.HazeLive) do n = n + 1 end
    return n
end

-- Streams a ring of haze systems around the player while a bank is up, and for
-- FogBankHazeLinger seconds after (so the haze fades instead of vanishing).
local function StreamHaze(playerPos)
    local f = V.FogIntensity
    local active = V.AllowFogBanks and V.TemplatesReady and playerPos ~= nil
        and (f > 0.02 or (V.Clock - V.FogLastActiveAt) < V.FogBankHazeLinger)
    if not active then
        local keys = {}
        for key in pairs(V.HazeLive) do keys[#keys + 1] = key end
        for i = 1, #keys do HazeDestroy(keys[i]) end
        return
    end

    local far = {}
    for key, record in pairs(V.HazeLive) do
        if Distance2D(record.x, record.z, playerPos.x, playerPos.z) > V.FogBankHazeOut then
            far[#far + 1] = key
        end
    end
    for i = 1, #far do HazeDestroy(far[i]) end
    if f <= 0.02 then return end   -- fading out: no new systems

    local size = V.FogBankHazeCell
    local cx, cz = math.floor(playerPos.x / size), math.floor(playerPos.z / size)
    local desired = {}
    for dx = -3, 3 do
        for dz = -3, 3 do
            local ix, iz = cx + dx, cz + dz
            local x, z = (ix + 0.5) * size, (iz + 0.5) * size
            local d = Distance2D(x, z, playerPos.x, playerPos.z)
            if d <= V.FogBankHazeIn then
                desired[#desired + 1] = { key = ix .. ":" .. iz, x = x, z = z, d = d }
            end
        end
    end
    table.sort(desired, function(a, b) return a.d < b.d end)

    local created = 0
    for i = 1, #desired do
        local cell = desired[i]
        if created >= 2 then break end
        if V.HazeLive[cell.key] == nil then
            if HazeCount() >= V.MaxLiveHaze then
                -- Make room only when a nearer cell is missing: drop the farthest.
                local farKey, farDist = nil, -1.0
                for key, record in pairs(V.HazeLive) do
                    local d = Distance2D(record.x, record.z, playerPos.x, playerPos.z)
                    if d > farDist then farKey, farDist = key, d end
                end
                if farKey ~= nil and farDist > (cell.d + size) then HazeDestroy(farKey) else break end
            end
            local record = HazeCreate(cell)
            if record == nil then break end
            V.HazeLive[cell.key] = record
            created = created + 1
        end
    end
end

local function UpdateHazeRates()
    local rate = V.FogBankHazeRate * V.FogIntensity
    if rate < 0.05 then rate = 0.0 end
    for _, record in pairs(V.HazeLive) do
        if math.abs(rate - record.rate) > 0.25 or (rate == 0.0 and record.rate ~= 0.0) then
            record.rate = rate
            Call("SetParticleEmitterEmissionRate", record.name, 0, rate)
            local wx, wz = WindVector()
            Call("SetParticleEmitterDirection", record.name, 0, Vec(wx, 0.0, wz))
        end
    end
end

-- ---- the drama hook (host only) ---------------------------------------------
--
-- "Prefers to start a bank when something big is coming": it looks at hostile
-- walkers / artillery and hostile groups closing on a human, and may choose the
-- MOMENT a bank starts. It never moves or commands anything, it only reads
-- positions, and its only output is the same VenusFog event a script's
-- RequestFogBank sends -- so what peers see is a pure function of that event.

local function IsHostileTo(h, human)
    if type(GetTeamNum) ~= "function" then return false end
    local okA, teamA = pcall(GetTeamNum, h)
    local okB, teamB = pcall(GetTeamNum, human)
    if not (okA and okB) or type(teamA) ~= "number" or type(teamB) ~= "number" then return false end
    if teamA == 0 or teamA == teamB then return false end
    if type(IsAlly) == "function" then
        local ok, ally = pcall(IsAlly, h, human)
        if ok and ally then return false end
    end
    return true
end

local function IsLargeUnit(h)
    if type(GetOdf) ~= "function" then return false end
    local ok, odf = pcall(GetOdf, h)
    if not ok then return false end
    local lower = NormalizeOdf(odf)
    for i = 1, #V.DramaOdfPatterns do
        if string.find(lower, V.DramaOdfPatterns[i], 1, true) then return true end
    end
    return false
end

local function HumanHandles()
    local humans = {}
    if V.PlayersProvider ~= nil then
        local ok, list = pcall(V.PlayersProvider)
        if ok and type(list) == "table" then
            for i = 1, #list do
                if ValidHandle(list[i]) and PositionOf(list[i]) ~= nil then humans[#humans + 1] = list[i] end
            end
        end
    end
    if #humans == 0 then
        local mine = LocalPlayerHandle()
        if mine ~= nil and PositionOf(mine) ~= nil then humans[1] = mine end
    end
    return humans
end

-- Counts hostile large units and hostile craft that are inside the drama range
-- of a human AND closing. Returns walkers, group. Keeps a short distance history
-- per handle, so it needs two scans to see a closing speed.
function V.ScanDrama()
    local humans = HumanHandles()
    local isHuman = {}
    for i = 1, #humans do isHuman[humans[i]] = true end
    local iterate = AllCraft or AllObjects
    if #humans == 0 or type(iterate) ~= "function" then return 0, 0 end

    local now = V.Clock
    local seen = {}
    local walkers, group, scanned = 0, 0, 0
    local lo, hi = V.DramaRange[1], V.DramaRange[2]
    local reach = hi * 1.5
    for h in iterate() do
        scanned = scanned + 1
        if scanned > V.DramaMaxScan then break end
        if not isHuman[h] and ValidHandle(h) then
            local p = PositionOf(h)
            if p ~= nil then
                local nearest = nil
                for i = 1, #humans do
                    local hp = PositionOf(humans[i])
                    if hp ~= nil and IsHostileTo(h, humans[i]) then
                        local d = Distance2D(p.x, p.z, hp.x, hp.z)
                        if nearest == nil or d < nearest then nearest = d end
                    end
                end
                if nearest ~= nil and nearest <= reach then
                    seen[h] = { d = nearest, t = now }
                    local prev = V.DramaTrack[h]
                    if prev ~= nil and nearest >= lo and nearest <= hi then
                        local dt = now - prev.t
                        if dt >= 0.5 and dt <= (V.DramaScanInterval * 4.0)
                            and ((prev.d - nearest) / dt) >= V.DramaClosingSpeed
                        then
                            if IsLargeUnit(h) then
                                walkers = walkers + 1
                            elseif not (type(IsPerson) == "function" and IsPerson(h)) then
                                group = group + 1
                            end
                        end
                    end
                end
            end
        end
    end
    V.DramaTrack = seen
    return walkers, group
end

-- Host: is the scheduled timeline clear of [now, now + seconds] plus the
-- clearance before the next bank and the cooldown after the last? Every peer has
-- the same schedule, so this is the one rule that keeps requested and scheduled
-- banks from stacking.
function V.FogScheduleClear(now, seconds)
    if V.FogBanks == nil then return false end
    local events = V.FogBanks:Events(now + seconds + V.DramaClearance + 1.0)
    for i = 1, #events do
        local e = events[i]
        if now < (e.start + e.dur + V.DramaCooldown) and (now + seconds + V.DramaClearance) > e.start then
            return false
        end
    end
    return true
end

local function UpdateFogDrama()
    if not (V.AllowFogDrama and V.AllowFogBanks and V.IsAuthority and V.Synced and V.FogBanks ~= nil) then return end
    if V.Clock < V.NextDramaAt then return end
    V.NextDramaAt = V.Clock + V.DramaScanInterval

    if V.Clock < V.DramaMinClock or V.DramaCount >= V.DramaMaxPerMission then return end
    if V.Clock < (V.DramaCooldownUntil or 0.0) then return end
    if V.ForcedLevel ~= nil or V.FogAllow < 0.9 or V.FogIntensity > 0.02 or #V.FogRequests > 0 then
        V.DramaTrack = {}
        return
    end
    if not V.FogScheduleClear(V.Clock, V.FogBankSeconds[2]) then return end

    local walkers, group = V.ScanDrama()
    if walkers < 1 and group < V.DramaGroupSize then return end
    if not V.FogRng.Chance(V.DramaChance) then return end

    local ok = V.RequestFogBank({ reason = "drama" })
    if ok then
        V.DramaCount = V.DramaCount + 1
        V.LastDrama = { at = V.Clock, walkers = walkers, group = group }
        Log(string.format("drama fog bank (walkers %d, group %d)", walkers, group))
    end
end

-- =============================================================================
-- Acid rain (visual only)
-- =============================================================================

local function EnsureRain()
    if V.Rain ~= nil then return V.Rain end
    local rain = Fx_Create("rain", "CR/Weather/Rain", 0.0, 0.0, 0.0)
    if rain == nil then return nil end
    local splash = Fx_Create("splash", "CR/Weather/RainSplash", 0.0, 0.0, 0.0)
    Call("SetParticleSystemParticleQuota", rain, V.RainMaxQuota)
    Call("AttachParticleSystemToCamera", rain, Vec(0.0, 34.0, 0.0))
    if splash ~= nil then
        Call("AttachParticleSystemToCamera", splash, Vec(0.0, 0.5, 0.0))
    end
    local t = V.RainTint
    Call("SetParticleEmitterColor", rain, 0,
        { r = t.r, g = t.g, b = t.b, a = 0.50 }, { r = t.r * 0.8, g = t.g * 0.8, b = t.b * 0.8, a = 0.26 })
    V.Rain = { rain = rain, splash = splash, rate = -1.0 }
    return V.Rain
end

local function DestroyRain()
    if V.Rain == nil then return end
    Fx_Destroy(V.Rain.rain)
    Fx_Destroy(V.Rain.splash)
    V.Rain = nil
end

function V.GetRainIntensity()
    if not V.AllowAcidRain then return 0.0 end
    return Clamp(LadderValue("rain"), 0.0, 1.0)
end

local function UpdateRain()
    local intensity = V.GetRainIntensity()
    if intensity < 0.02 then
        if V.Rain ~= nil then
            Call("SetParticleSystemEmitting", V.Rain.rain, false)
            Call("SetParticleSystemVisible", V.Rain.rain, false)
            if V.Rain.splash then
                Call("SetParticleSystemEmitting", V.Rain.splash, false)
                Call("SetParticleSystemVisible", V.Rain.splash, false)
            end
            V.Rain.rate = 0.0
        end
        return
    end

    local rain = EnsureRain()
    if rain == nil then return end

    local rate = V.RainMaxRate * intensity
    if math.abs(rate - rain.rate) > 6.0 then
        rain.rate = rate
        Call("SetParticleSystemEmitting", rain.rain, true)
        Call("SetParticleSystemVisible", rain.rain, true)
        Call("SetParticleEmitterEmissionRate", rain.rain, 0, rate)
        if rain.splash then
            Call("SetParticleSystemEmitting", rain.splash, true)
            Call("SetParticleSystemVisible", rain.splash, true)
            Call("SetParticleEmitterEmissionRate", rain.splash, 0, V.RainSplashRate * intensity)
        end
        -- Rain leans with the wind: slow air on Venus, so a gentle slant.
        local wx, wz = WindVector()
        local lean = Clamp(V.WindSpeed / 40.0, 0.0, 0.5)
        Call("SetParticleEmitterDirection", rain.rain, 0, Vec(wx * lean, -0.93, wz * lean))
    end
end

-- =============================================================================
-- Cloud deck
-- =============================================================================

local function UpdateClouds(dt)
    if not V.AllowClouds or not V.TemplatesReady then
        for i, record in pairs(V.Clouds) do
            Fx_Destroy(record.name)
            V.Clouds[i] = nil
        end
        return
    end

    local amount = Clamp(LadderValue("cloud"), 0.0, 1.0)
    for layer = 1, #V.CloudHeights do
        local record = V.Clouds[layer]
        if record == nil then
            local name = Fx_Create("cloud", "CR/Venus/CloudDeck", 0.0, 0.0, 0.0)
            if name ~= nil then
                Call("AttachParticleSystemToCamera", name, Vec(0.0, V.CloudHeights[layer], 0.0))
                record = { name = name, phase = (layer - 1) * 2.1, tint = -1.0, rate = -1.0, next = 0.0 }
                V.Clouds[layer] = record
            end
        end

        if record ~= nil and V.Clock >= record.next then
            record.next = V.Clock + 0.5
            record.phase = record.phase + (V.CloudPrecession[layer] * 0.5)

            local fx = math.cos(record.phase) * V.CloudDrift
            local fz = math.sin(record.phase) * V.CloudDrift
            Call("SetParticleAffectorParameter", record.name, 2, "force_vector",
                string.format("%.3f 0 %.3f", fx, fz))

            local rate = 3.0 * amount
            if math.abs(rate - record.rate) > 0.15 then
                record.rate = rate
                Call("SetParticleEmitterEmissionRate", record.name, 0, rate)
                Call("SetParticleSystemEmitting", record.name, rate > 0.05)
            end

            -- Darker and greener as the storm builds.
            local gloom = LadderValue("gloom")
            if math.abs(gloom - record.tint) > 0.05 then
                record.tint = gloom
                local r = Lerp(0.40, 0.18, gloom)
                local g = Lerp(0.30, 0.22, gloom)
                local b = Lerp(0.14, 0.08, gloom)
                local alpha = Lerp(0.14, 0.30, gloom)
                Call("SetParticleAffectorParameter", record.name, 0, "colour1",
                    string.format("%.3f %.3f %.3f %.3f", r, g, b, alpha))
                Call("SetParticleAffectorParameter", record.name, 0, "colour2",
                    string.format("%.3f %.3f %.3f %.3f", r * 0.9, g * 0.9, b * 0.9, alpha * 0.8))
            end
        end
    end
end

-- =============================================================================
-- Lightning
-- =============================================================================

local KIND_POWER, KIND_EXPOSED, KIND_GROUND = 1, 2, 3

local function ScanPowers()
    if type(AllObjects) ~= "function" then return end
    local found = {}
    for h in AllObjects() do
        if ValidHandle(h) and V.IsLightningPower(h) then
            found[h] = true
        end
    end
    V.Powers = found
end

function V.OnObjectCreated(h)
    CRWeather.OnObjectCreated(h)
    if V.Initialized and V.IsAuthority and ValidHandle(h) and V.IsLightningPower(h) then
        V.Powers[h] = true
    end
end

function V.GetLightningPowerCount()
    local n = 0
    for h in pairs(V.Powers) do
        if ValidHandle(h) then n = n + 1 end
    end
    return n
end

-- Builds the weighted candidate list. Returned separately from the pick so the
-- weighting itself can be asserted: the share a generator draws is a design
-- statement ("they harvest the storm"), not an accident of the random roll.
function V.BuildStrikeCandidates()
    local candidates = {}

    for h in pairs(V.Powers) do
        if ValidHandle(h) then
            local p = PositionOf(h)
            if p ~= nil then
                candidates[#candidates + 1] = {
                    kind = KIND_POWER, weight = V.PowerWeight, handle = h,
                    x = p.x, y = p.y + V.PowerRodHeight, z = p.z,
                }
            end
        else
            V.Powers[h] = nil
        end
    end

    local playerPos = LocalPlayerPosition()
    local poolLevel = V.Basins and V.Basins.poolLevel or nil

    -- Every human player, not just this machine's: a strike near a guest's tank
    -- is the host's decision to make. The adapter supplies the list; alone, it
    -- is just the local player.
    local players = {}
    if V.PlayersProvider ~= nil then
        local okList, list = pcall(V.PlayersProvider)
        if okList and type(list) == "table" then
            for i = 1, #list do
                local p = ValidHandle(list[i]) and PositionOf(list[i]) or nil
                if p ~= nil then players[#players + 1] = p end
            end
        end
    end
    if #players == 0 and playerPos ~= nil then players[1] = playerPos end

    -- Exposed means tall or standing high: towers, turrets and radar masts by
    -- ODF name, and anything (craft included) well above the pool level. Both
    -- structures and craft count, so the whole object list is walked.
    local iterate = AllObjects or AllCraft
    if type(iterate) == "function" then
        local scanned = 0
        for h in iterate() do
            scanned = scanned + 1
            if scanned > 240 then break end
            if ValidHandle(h) and not V.Powers[h] then
                local p = PositionOf(h)
                if p ~= nil then
                    local exposed = false
                    if type(GetOdf) == "function" then
                        local ok, odf = pcall(GetOdf, h)
                        if ok then
                            local lower = NormalizeOdf(odf)
                            for i = 1, #V.ExposedOdfPatterns do
                                if string.find(lower, V.ExposedOdfPatterns[i], 1, true) then
                                    exposed = true
                                    break
                                end
                            end
                        end
                    end
                    if not exposed and poolLevel ~= nil and (p.y - poolLevel) >= V.ExposedAltitude then
                        exposed = true
                    end
                    if exposed then
                        candidates[#candidates + 1] = {
                            kind = KIND_EXPOSED, weight = V.ExposedWeight, handle = h,
                            x = p.x, y = p.y, z = p.z,
                        }
                    end
                end
            end
        end
    end

    if #players > 0 then
        local rng = V.StrikeRng
        for _ = 1, V.GroundCandidates do
            local anchor = players[rng.Int(1, #players)]
            local angle = rng.Range(0.0, 2.0 * math.pi)
            local range = rng.Range(V.GroundRing[1], V.GroundRing[2])
            local x = anchor.x + (math.sin(angle) * range)
            local z = anchor.z + (math.cos(angle) * range)
            local y = TerrainHeight(x, z) or anchor.y
            candidates[#candidates + 1] = {
                kind = KIND_GROUND, weight = V.GroundWeight, x = x, y = y, z = z,
            }
        end
    end

    return candidates
end

function V.PickStrikeTarget()
    local candidates = V.BuildStrikeCandidates()
    local pick = Map.PickWeighted(V.StrikeRng, candidates)
    return pick, candidates
end

local function StrikeRate()
    local row = LadderValue("strikesPerMinute")
    if row <= 0.001 then return 0.0 end
    if V.Episode then row = row * V.EpisodeStrikeBoost end
    if next(V.Powers) ~= nil then row = row * V.PowerRateBoost end
    return row
end

local function ScheduleNextStrike()
    local rate = StrikeRate()
    if rate <= 0.0 then
        V.NextStrikeAt = V.Clock + 4.0
        return
    end
    local gap = (60.0 / rate) * V.StrikeRng.Range(0.5, 1.5)
    V.NextStrikeAt = V.Clock + math.max(V.StrikeMinGap, gap)
end

-- Shove and scramble. Every peer calls this for the same strike and each one
-- affects only the craft it owns, so the whole map is covered exactly once.
-- Returns the number of craft shoved, for tests.
function V.ApplyStrikeEffects(x, y, z, power)
    local shoved = 0
    if type(AllCraft) ~= "function" then return 0 end
    local environment = rawget(_G, "Environment")

    for h in AllCraft() do
        if ValidHandle(h) and OwnsLocally(h)
            and not (type(IsPerson) == "function" and IsPerson(h))
        then
            local p = PositionOf(h)
            if p ~= nil then
                local d = Distance2D(p.x, p.z, x, z)

                if V.AllowKnockback and d < V.KnockRadius then
                    local fall = 1.0 - ((d / V.KnockRadius) * (d / V.KnockRadius))
                    local dx, dz = p.x - x, p.z - z
                    local len = math.sqrt((dx * dx) + (dz * dz))
                    if len < 0.5 then
                        local a = V.FxRng.Range(0.0, 2.0 * math.pi)
                        dx, dz, len = math.sin(a), math.cos(a), 1.0
                    end
                    dx, dz = dx / len, dz / len

                    -- Heavier craft move less; clamp so a scout is not flung.
                    local massScale = 1.0
                    if type(exu.GetMass) == "function" then
                        local okMass, mass = pcall(exu.GetMass, h)
                        if okMass and type(mass) == "number" and mass > 1.0 then
                            massScale = Clamp(math.sqrt(V.KnockReferenceMass / mass), 0.35, 1.2)
                        end
                    end

                    local speed = V.KnockMaxSpeed * fall * (power or 1.0) * massScale
                    local velocity = (type(GetVelocity) == "function") and GetVelocity(h) or nil
                    local vx = (velocity and velocity.x or 0.0) + (dx * speed)
                    local vz = (velocity and velocity.z or 0.0) + (dz * speed)
                    local vy = (velocity and velocity.y or 0.0) + (speed * V.KnockLift)

                    -- A strike is a shove, not a launch: never push horizontal
                    -- speed past the cap (a craft already faster keeps its speed).
                    local horizontal = math.sqrt((vx * vx) + (vz * vz))
                    local before = velocity and math.sqrt((velocity.x * velocity.x) + (velocity.z * velocity.z)) or 0.0
                    local cap = math.max(V.KnockSpeedCap, before)
                    if horizontal > cap then
                        vx, vz = vx * (cap / horizontal), vz * (cap / horizontal)
                    end

                    if type(SetVelocity) == "function" then
                        SetVelocity(h, Vec(vx, vy, vz))
                        shoved = shoved + 1
                        V.Stats.knocked = V.Stats.knocked + 1
                    end
                end

                if V.AllowRadarScramble and d < V.ScrambleRadius
                    and environment ~= nil and type(environment.SetObjectScramble) == "function"
                then
                    local fall = 1.0 - (d / V.ScrambleRadius)
                    local seconds = Lerp(V.ScrambleSeconds[1], V.ScrambleSeconds[2], fall)
                    environment.SetObjectScramble(h, seconds, {
                        radarRange = V.ScrambleRadarRange,
                        velocJam   = V.ScrambleVelocJam,
                    })
                    V.Stats.scrambled = V.Stats.scrambled + 1
                end
            end
        end
    end
    return shoved
end

local function FlashStrength(x, z)
    local p = LocalPlayerPosition()
    if p == nil then return V.FlashFloor end
    local d = Distance2D(x, z, p.x, p.z)
    local t = 1.0 - Clamp((d - V.FlashNear) / math.max(1.0, V.FlashFar - V.FlashNear), 0.0, 1.0)
    return Clamp(V.FlashFloor + ((1.0 - V.FlashFloor) * t * t), 0.0, 1.0)
end

local function PlayThunder(x, z, strength)
    if type(StartSound) ~= "function" or V.ThunderSound == nil then return end
    local p = LocalPlayerPosition()
    local d = p and Distance2D(x, z, p.x, p.z) or 400.0
    local delay = Clamp(d / V.ThunderSpeed, 0.15, V.ThunderMaxDelay)
    local volume = math.floor(Clamp(V.ThunderVolume - (d / 18.0), 28, V.ThunderVolume))
    V.Thunder[#V.Thunder + 1] = { at = V.Clock + delay, volume = volume }
end

local function ServiceThunder()
    if #V.Thunder == 0 then return end
    local keep = {}
    for i = 1, #V.Thunder do
        local t = V.Thunder[i]
        if V.Clock >= t.at then
            pcall(StartSound, V.ThunderSound, nil, 1, false, t.volume, V.ThunderRate)
        else
            keep[#keep + 1] = t
        end
    end
    V.Thunder = keep
end

-- A strike begins: the telegraph. Called on the host and, from an event, on
-- every guest. `delay` is the telegraph length; the impact lands that long
-- after this peer receives the event.
function V.BeginStrike(id, x, y, z, kind, delay, power)
    if V.SeenStrikes[id] then return false end
    V.SeenStrikes[id] = true
    -- Keep the dedupe set from growing for the life of a long mission.
    V.SeenStrikes[id - 200] = nil

    local strike = {
        id = id, x = x, y = y, z = z, kind = kind, power = power or 1.0,
        impactAt = V.Clock + (delay or 1.5), startedAt = V.Clock, state = "telegraph",
    }
    V.Strikes[id] = strike

    local live = 0
    for _, s in pairs(V.Strikes) do
        if s.elmo ~= nil or s.bolt ~= nil then live = live + 1 end
    end
    local p = LocalPlayerPosition()
    local near = (p == nil) or Distance2D(x, z, p.x, p.z) < 1300.0
    if V.TemplatesReady and near and live < V.MaxLiveStrikes then
        strike.elmo = Fx_Create("elmo", "CR/Venus/StElmo", x, y, z)
    end
    return true
end

local function ImpactStrike(strike)
    strike.state = "impact"
    strike.impactedAt = V.Clock
    V.LastStrikeAt = V.Clock
    V.Stats.strikes = V.Stats.strikes + 1
    if strike.kind == KIND_POWER then V.Stats.powerStrikes = V.Stats.powerStrikes + 1
    elseif strike.kind == KIND_EXPOSED then V.Stats.exposedStrikes = V.Stats.exposedStrikes + 1
    else V.Stats.groundStrikes = V.Stats.groundStrikes + 1 end

    if strike.elmo ~= nil then
        Call("SetParticleEmitterEmissionRate", strike.elmo, 0, 0.0)
        if strike.kind ~= KIND_POWER then
            Fx_Destroy(strike.elmo)
            strike.elmo = nil
        end
    end

    if V.TemplatesReady and strike.bolt == nil then
        local live = 0
        for _, s in pairs(V.Strikes) do
            if s.bolt ~= nil then live = live + 1 end
        end
        if live < V.MaxLiveStrikes then
            local ground = TerrainHeight(strike.x, strike.z) or strike.y
            strike.bolt = Fx_Create("bolt", "CR/Venus/Bolt", strike.x, ground + 120.0, strike.z)
            if strike.bolt ~= nil then
                Call("SetParticleEmitterEmissionRate", strike.bolt, 0, 900.0)
                Call("SetParticleEmitterEmissionRate", strike.bolt, 1, 420.0)
            end
            strike.glow = Fx_Create("glow", "CR/Venus/BoltGlow", strike.x, ground + 3.0, strike.z)
            if strike.glow ~= nil then
                Call("SetParticleEmitterEmissionRate", strike.glow, 0, 220.0)
            end
        end
    end

    if V.AllowFlash then
        V.Flashes[#V.Flashes + 1] = { at = V.Clock, strength = FlashStrength(strike.x, strike.z) }
        if #V.Flashes > 6 then table.remove(V.Flashes, 1) end
    end
    PlayThunder(strike.x, strike.z, strike.power)
    V.ApplyStrikeEffects(strike.x, strike.y, strike.z, strike.power)
end

local function UpdateStrikes()
    ServiceThunder()

    -- Prune flashes that are over.
    if #V.Flashes > 0 then
        local keep = {}
        for i = 1, #V.Flashes do
            if (V.Clock - V.Flashes[i].at) < V.FlashSeconds then keep[#keep + 1] = V.Flashes[i] end
        end
        V.Flashes = keep
    end

    local done = {}
    for id, strike in pairs(V.Strikes) do
        if strike.state == "telegraph" then
            local span = math.max(0.1, strike.impactAt - strike.startedAt)
            local t = Clamp((V.Clock - strike.startedAt) / span, 0.0, 1.0)
            if strike.elmo ~= nil then
                -- The corona builds toward the strike, which is the warning.
                Call("SetParticleEmitterEmissionRate", strike.elmo, 0, 10.0 + (70.0 * t * t))
            end
            if V.Clock >= strike.impactAt then
                ImpactStrike(strike)
            end
        elseif strike.state == "impact" then
            local age = V.Clock - strike.impactedAt
            -- The bolt is a burst: shut the emitters after a tenth of a second.
            if strike.bolt ~= nil and age > 0.11 then
                Call("SetParticleEmitterEmissionRate", strike.bolt, 0, 0.0)
                Call("SetParticleEmitterEmissionRate", strike.bolt, 1, 0.0)
            end
            if strike.glow ~= nil and age > 0.10 then
                Call("SetParticleEmitterEmissionRate", strike.glow, 0, 0.0)
            end
            -- A generator keeps crackling for a few seconds: it is harvesting.
            if strike.elmo ~= nil then
                local left = 1.0 - Clamp(age / V.PowerAfterglow, 0.0, 1.0)
                Call("SetParticleEmitterEmissionRate", strike.elmo, 0, 45.0 * left)
            end
            local lifetime = (strike.kind == KIND_POWER) and V.PowerAfterglow or 0.9
            if age > math.max(0.9, lifetime) then
                done[#done + 1] = id
            end
        end
    end
    for i = 1, #done do
        local strike = V.Strikes[done[i]]
        Fx_Destroy(strike.elmo)
        Fx_Destroy(strike.bolt)
        Fx_Destroy(strike.glow)
        V.Strikes[done[i]] = nil
    end
end

local function UpdateLightning()
    if not V.AllowLightning then return end

    if V.IsAuthority and V.Synced then
        if V.Clock >= V.NextPowerScanAt then
            V.NextPowerScanAt = V.Clock + 5.0
            ScanPowers()
        end

        if V.Clock >= V.NextStrikeAt then
            if StrikeRate() <= 0.0 then
                ScheduleNextStrike()
            else
                local target = V.PickStrikeTarget()
                ScheduleNextStrike()
                if target ~= nil then
                    V.StrikeSerial = V.StrikeSerial + 1
                    local delay = V.StrikeRng.Range(V.TelegraphSeconds[1], V.TelegraphSeconds[2])
                    local power = V.StrikeRng.Range(0.8, 1.0) * (V.Episode and 1.15 or 1.0)
                    V.BeginStrike(V.StrikeSerial, target.x, target.y, target.z, target.kind, delay, power)
                    Send("VenusStrike", V.StrikeSerial, target.x, target.y, target.z, target.kind, delay, power)
                end
            end
        end
    end

    -- Heat lightning: cosmetic sheet flashes behind the cloud, every peer's own.
    if V.AllowFlash and V.AllowLightning and LadderValue("strikesPerMinute") > 0.5 then
        if V.Clock >= (V.NextDistantAt or 0.0) then
            V.NextDistantAt = V.Clock + V.FxRng.Range(5.0, 16.0)
            if V.FxRng.Chance(0.5) then
                V.Flashes[#V.Flashes + 1] = { at = V.Clock, strength = 0.14 }
            end
        end
    end
end

-- =============================================================================
-- Sulfur pools
-- =============================================================================

local function SulfurCreate(index, site)
    local y = TerrainHeight(site.x, site.z) or 0.0
    local name = Fx_Create("sulfur", "CR/Venus/SulfurPool", site.x, y + 0.6, site.z)
    if name == nil then return nil end
    return { name = name, x = site.x, z = site.z, weight = site.weight,
             nextBurp = V.Clock + V.FxRng.Range(V.SulfurBurpGap[1], V.SulfurBurpGap[2]),
             burpUntil = 0.0, steam = -1.0 }
end

local function SulfurDestroy(_, record)
    Fx_Destroy(record.name)
end

-- Yellow bubble pops, drifting motes and pale fumes on the nearest sulphur pools.
local function UpdatePoolFx(dt)
    if V.PoolFx == nil then return end
    PoolFX.Update(V.PoolFx, dt, LocalPlayerPosition(), {
        enabled = V.AllowPoolFx and V.AllowSulfur and V.TemplatesReady,
        scale = 1.0 + (0.5 * V.GetSeverity()),
        quality = CRWeather.Quality,
    })
end

local function UpdateSulfur()
    if not V.AllowSulfur or not V.TemplatesReady then
        for index, record in pairs(V.SulfurLive) do
            Fx_Destroy(record.name)
            V.SulfurLive[index] = nil
        end
        return
    end

    local storm = 1.0 + (0.5 * V.GetSeverity())
    for _, record in pairs(V.SulfurLive) do
        local steam = V.SulfurSteamRate * (0.5 + (0.5 * record.weight)) * storm
        if math.abs(steam - record.steam) > 0.2 then
            record.steam = steam
            Call("SetParticleEmitterEmissionRate", record.name, 0, steam)
            SetWindOnSystem(record.name, 0.4 + (V.WindSpeed * 0.03), 2)
        end

        if record.burpUntil > 0.0 and V.Clock >= record.burpUntil then
            record.burpUntil = 0.0
            Call("SetParticleEmitterEmissionRate", record.name, 1, 0.0)
        end
        if V.Clock >= record.nextBurp then
            record.nextBurp = V.Clock + V.FxRng.Range(V.SulfurBurpGap[1], V.SulfurBurpGap[2]) / storm
            record.burpUntil = V.Clock + V.SulfurBurpSeconds
            Call("SetParticleEmitterEmissionRate", record.name, 1, V.SulfurBurpRate)

            -- A pool right next to the player blurps audibly; others are silent.
            local p = LocalPlayerPosition()
            if p ~= nil and type(StartSound) == "function"
                and V.SulfurBurpSound ~= nil
                and Distance2D(record.x, record.z, p.x, p.z) < V.SulfurSoundRange
                and (V.Clock - V.LastBurpSoundAt) > 1.5
            then
                V.LastBurpSoundAt = V.Clock
                pcall(StartSound, V.SulfurBurpSound, nil, 1, false, V.SulfurSoundVolume, 90)
            end
        end
    end
end

-- =============================================================================
-- Volcanic vents
-- =============================================================================

local function PlumeCreate(index, site)
    local name = Fx_Create("plume", "CR/Venus/Plume", site.x, site.y + 1.0, site.z)
    if name == nil then return nil end
    local rate = site.major and V.PlumeMajorRate or V.PlumeMinorRate
    Call("SetParticleEmitterEmissionRate", name, 0, rate)
    SetWindOnSystem(name, 0.6 + (V.WindSpeed * 0.08), 2)
    return { name = name, site = index, rate = rate, windAt = V.Bearing }
end

local function PlumeDestroy(index, record)
    Fx_Destroy(record.name)
    if record.embers ~= nil then
        Fx_Destroy(record.embers)
        record.embers = nil
    end
end

local function EruptionEnvelope(e)
    local age = V.Clock - e.start
    local rise = 1.6
    local fall = math.min(8.0, e.duration * 0.4)
    if age < 0.0 then return 0.0 end
    if age < rise then return SmoothStep(age / rise) end
    if age < (e.duration - fall) then return 1.0 end
    if age < e.duration then return 1.0 - SmoothStep((age - (e.duration - fall)) / fall) end
    return 0.0
end

-- An eruption begins (host and, by event, guests). Purely visual and audible.
function V.BeginEruption(id, siteIndex, duration, power)
    if not V.AllowEruptions then return false end
    local site = V.VentSites[siteIndex]
    if site == nil then return false end
    V.Eruptions[#V.Eruptions + 1] = {
        id = id, site = siteIndex, start = V.Clock, duration = duration or 18.0,
        power = power or 1.0, bursted = false,
    }
    V.Stats.eruptions = V.Stats.eruptions + 1

    local p = LocalPlayerPosition()
    if p ~= nil and type(StartSound) == "function" then
        local d = Distance2D(site.x, site.z, p.x, p.z)
        if d < V.EruptionSoundRange then
            local volume = math.floor(Clamp(V.EruptionVolume * (1.0 - (d / V.EruptionSoundRange)) + 20, 20, V.EruptionVolume))
            if V.EruptionRumbleSound then pcall(StartSound, V.EruptionRumbleSound, nil, 1, false, volume, 80) end
        end
    end
    return true
end

local function UpdateEruptions()
    if #V.Eruptions == 0 then return end

    local keep = {}
    for i = 1, #V.Eruptions do
        local e = V.Eruptions[i]
        local envelope = EruptionEnvelope(e)
        local record = V.PlumeLive[e.site]

        if record ~= nil then
            Call("SetParticleEmitterEmissionRate", record.name, 1, V.EruptionBurstRate * e.power * envelope)
            local site = V.VentSites[e.site]
            local base = site.major and V.PlumeMajorRate or V.PlumeMinorRate
            Call("SetParticleEmitterEmissionRate", record.name, 0, base * (1.0 + (1.5 * envelope)))

            -- Embers are only worth a system while something is being thrown.
            if (V.Clock - e.start) < 4.0 and record.embers == nil then
                record.embers = Fx_Create("embers", "CR/Venus/Embers", site.x, site.y + 2.0, site.z)
            end
            if record.embers ~= nil then
                local age = V.Clock - e.start
                local rate = (age < 3.5) and (V.EruptionEmberRate * e.power * envelope) or 0.0
                Call("SetParticleEmitterEmissionRate", record.embers, 0, rate)
                if age > 8.0 then
                    Fx_Destroy(record.embers)
                    record.embers = nil
                end
            end

            if not e.bursted and (V.Clock - e.start) > 0.6 then
                e.bursted = true
                local p = LocalPlayerPosition()
                if p ~= nil and V.EruptionBurstSound and type(StartSound) == "function"
                    and Distance2D(site.x, site.z, p.x, p.z) < V.EruptionSoundRange
                then
                    pcall(StartSound, V.EruptionBurstSound, nil, 1, false, math.floor(V.EruptionVolume * 0.8), 70)
                end
            end
        end

        if (V.Clock - e.start) < e.duration then
            keep[#keep + 1] = e
        elseif record ~= nil then
            Call("SetParticleEmitterEmissionRate", record.name, 1, 0.0)
            local site = V.VentSites[e.site]
            Call("SetParticleEmitterEmissionRate", record.name, 0, site.major and V.PlumeMajorRate or V.PlumeMinorRate)
            if record.embers ~= nil then
                Fx_Destroy(record.embers)
                record.embers = nil
            end
        end
    end
    V.Eruptions = keep
end

local function UpdateVents()
    if not V.AllowVents or not V.TemplatesReady then
        for index, record in pairs(V.PlumeLive) do
            PlumeDestroy(index, record)
            V.PlumeLive[index] = nil
        end
        return
    end

    for _, record in pairs(V.PlumeLive) do
        if math.abs(V.Bearing - record.windAt) > 0.08 then
            record.windAt = V.Bearing
            SetWindOnSystem(record.name, 0.6 + (V.WindSpeed * 0.08), 2)
        end
    end

    if V.IsAuthority and V.Synced and V.AllowEruptions and #V.VentSites > 0 and V.Clock >= V.NextEruptionAt then
        local rng = V.EruptionRng
        V.NextEruptionAt = V.Clock + rng.Range(V.EruptionGap[1], V.EruptionGap[2])
        local items = {}
        for i = 1, #V.VentSites do
            items[i] = { weight = V.VentSites[i].major and V.EruptionMajorWeight or 1.0, index = i }
        end
        local pick = Map.PickWeighted(rng, items)
        if pick ~= nil then
            V.EruptionSerial = V.EruptionSerial + 1
            local duration = rng.Range(V.EruptionSeconds[1], V.EruptionSeconds[2])
            local power = rng.Range(0.7, 1.0)
            V.BeginEruption(V.EruptionSerial, pick.index, duration, power)
            Send("VenusErupt", V.EruptionSerial, pick.index, duration, power)
        end
    end
    UpdateEruptions()
end

-- =============================================================================
-- Environment contribution
-- =============================================================================

local function FlashCurve()
    local total = 0.0
    for i = 1, #V.Flashes do
        local f = V.Flashes[i]
        local age = V.Clock - f.at
        if age >= 0.0 and age < V.FlashSeconds then
            -- A strike flickers: a hard first pulse, a dip, a weaker second.
            local first = math.exp(-age * 11.0)
            local second = 0.0
            if age > 0.13 then second = 0.55 * math.exp(-(age - 0.13) * 13.0) end
            total = total + (f.strength * math.max(first, second))
        end
    end
    return Clamp(total, 0.0, 1.0)
end

local function EnvironmentModifier(frame)
    if not V.Enabled then return end

    -- Darker and greener between flashes as the storm builds.
    local gloom = LadderValue("gloom") * (1.0 - (V.FogBankGloomRelief * V.FogIntensity))
    if gloom > 0.001 then
        local dim = 1.0 - (V.GloomDim * gloom)
        local green = 1.0 + (V.GloomGreen * gloom)
        local blue = 1.0 - (0.5 * V.GloomGreen * gloom)
        for _, key in ipairs({ "ambient", "diffuse" }) do
            local c = frame[key]
            if c ~= nil then
                c.r = c.r * dim
                c.g = c.g * dim * green
                c.b = c.b * dim * blue
            end
        end
    end

    -- Thicker fog down in the pools, clearer on the ridges.
    local f = V.PoolFactor
    if V.AllowAltitudeFog and f > 0.001 and frame.fog ~= nil then
        local fog = frame.fog
        fog.fogEnd = fog.fogEnd * Lerp(1.0, V.PoolFogEndScale, f)
        fog.fogStart = math.min(fog.fogEnd - 1.0, fog.fogStart * Lerp(1.0, V.PoolFogStartScale, f))
        local tint = V.PoolFogTint * f
        fog.r = Lerp(fog.r, V.PoolFogColor.r, tint)
        fog.g = Lerp(fog.g, V.PoolFogColor.g, tint)
        fog.b = Lerp(fog.b, V.PoolFogColor.b, tint)
    end

    -- A fog bank: pea-soup fog in sulphur green-yellow, a glowing ochre light
    -- and a sun that is never allowed to dim. It only ever thickens the fog (the
    -- target end is the nearest of the rung's end, FogBankFogEnd and the map's
    -- terrain horizon), so it cannot clear the air or push fog past the horizon.
    local bank = V.FogIntensity
    if V.AllowFogBanks and bank > 0.002 then
        local fog = frame.fog
        if fog ~= nil then
            local endTarget = math.min(fog.fogEnd, V.FogBankFogEnd)
            local horizon = FogHorizon()
            if horizon ~= nil then endTarget = math.min(endTarget, horizon) end
            fog.fogEnd = Lerp(fog.fogEnd, endTarget, bank)
            fog.fogStart = math.min(Lerp(fog.fogStart, math.min(fog.fogStart, V.FogBankFogStart), bank),
                fog.fogEnd - 1.0)
            local mix = bank * V.FogBankColorMix
            fog.r = Lerp(fog.r, V.FogBankColor.r, mix)
            fog.g = Lerp(fog.g, V.FogBankColor.g, mix)
            fog.b = Lerp(fog.b, V.FogBankColor.b, mix)
        end
        local light = bank * V.FogBankLightMix
        if frame.ambient ~= nil then
            frame.ambient.r = Lerp(frame.ambient.r, V.FogBankAmbient.r, light)
            frame.ambient.g = Lerp(frame.ambient.g, V.FogBankAmbient.g, light)
            frame.ambient.b = Lerp(frame.ambient.b, V.FogBankAmbient.b, light)
        end
        if frame.diffuse ~= nil then
            frame.diffuse.r = Lerp(frame.diffuse.r, V.FogBankDiffuse.r, light)
            frame.diffuse.g = Lerp(frame.diffuse.g, V.FogBankDiffuse.g, light)
            frame.diffuse.b = Lerp(frame.diffuse.b, V.FogBankDiffuse.b, light)
        end
        if frame.sunPowerScale ~= nil then
            frame.sunPowerScale = Lerp(frame.sunPowerScale, math.max(frame.sunPowerScale, V.FogBankSunPower), bank)
        end
    end

    -- The strike flash: an additive lift on ambient and sun, local to the
    -- distance of the strike from THIS peer's player.
    if V.AllowFlash and #V.Flashes > 0 then
        local c = FlashCurve()
        if c > 0.0005 then
            if frame.ambient then
                frame.ambient.r = frame.ambient.r + (V.FlashAmbient.r * c)
                frame.ambient.g = frame.ambient.g + (V.FlashAmbient.g * c)
                frame.ambient.b = frame.ambient.b + (V.FlashAmbient.b * c)
            end
            if frame.diffuse then
                frame.diffuse.r = frame.diffuse.r + (V.FlashDiffuse.r * c)
                frame.diffuse.g = frame.diffuse.g + (V.FlashDiffuse.g * c)
                frame.diffuse.b = frame.diffuse.b + (V.FlashDiffuse.b * c)
            end
            if frame.sunPowerScale then
                frame.sunPowerScale = frame.sunPowerScale * (1.0 + (V.FlashSunBoost * c))
            end
        end
    end
end

V.EnvironmentModifier = EnvironmentModifier

local function GameplayContribution(frame)
    if not V.AllowSensorDegrade then return end
    frame.radarRange = frame.radarRange * LadderValue("radarRange")
    frame.velocJam   = frame.velocJam * LadderValue("velocJam")
end

local function UpdateSensors()
    local environment = rawget(_G, "Environment")
    if environment == nil or not V.GameplayRegistered then return end
    local severity = V.GetSeverity()
    if math.abs(severity - V.LastSyncSeverity) > 0.10 then
        V.LastSyncSeverity = severity
        if type(environment.RequestGameplaySync) == "function" then
            environment.RequestGameplaySync()
        end
    end
end

local function UpdateRenderIntents()
    if not V.AllowRenderIntents or type(exu.SetRenderEffectFloat) ~= "function" then return end
    if V.Clock < (V.NextIntentAt or 0.0) then return end
    V.NextIntentAt = V.Clock + 2.0
    -- Depth haze strength follows severity. Status "not-implemented" today.
    pcall(exu.SetRenderEffectFloat, "depth_haze", "strength", 0.35 + (0.5 * V.GetSeverity()))
end

-- =============================================================================
-- Networking
--
-- Primitive arguments only; the mission adapter owns transport and ordering.
-- =============================================================================

-- Everything a peer needs to rebuild the same weather: ten numbers.
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

    V.TargetLevel = Clamp(tonumber(target) or V.TargetLevel, 1, LEVEL_COUNT)
    forcedLevel = tonumber(forcedLevel) or 0
    forcedFor = tonumber(forcedFor) or 0
    if forcedLevel > 0 and forcedFor > 0 then
        V.ForcedLevel = Clamp(forcedLevel, 1, LEVEL_COUNT)
        V.ForcedUntil = V.Clock + forcedFor
    elseif not V.IsAuthority then
        V.ForcedLevel = nil
        V.ForcedUntil = nil
    end

    if not V.IsAuthority then
        V.HostOverride = {
            level = Clamp(tonumber(level) or 1, 1, LEVEL_COUNT),
            episode = tonumber(episode) == 1,
            expires = V.Clock + V.HostOverrideSeconds,
        }
    end
    return true
end

-- Dispatch for the mission adapter's receive path. Returns true when handled.
function V.ApplyNetEvent(op, ...)
    if op == "VenusState" then
        return V.ApplyNetState(...)
    elseif op == "VenusStrike" then
        if V.IsAuthority then return true end
        return V.BeginStrike(...)
    elseif op == "VenusErupt" then
        if V.IsAuthority then return true end
        return V.BeginEruption(...)
    elseif op == "VenusFog" then
        if V.IsAuthority then return true end
        return V.BeginFogBank(...)
    end
    return false
end

local function StateKey()
    return (V.Level * 1) + (V.Episode and 10 or 0) + (V.TargetLevel * 100) + ((V.ForcedLevel or 0) * 1000)
end

local function BroadcastState(force)
    if not V.IsAuthority or V.NetSend == nil then return end
    -- Announce on a change of rung / episode / target / forced level, and as a
    -- heartbeat. Comparing one number keeps the idle frame allocation-free.
    local key = StateKey()
    if force or key ~= V.LastStateKey or V.Clock >= V.NextNetStateAt then
        V.LastStateKey = key
        V.NextNetStateAt = V.Clock + V.NetHeartbeat
        Send("VenusState", V.GetNetState())
    end
end

-- The host re-announces on demand: call this when a guest reports it is ready,
-- so a guest that initialised after the first announcement is not left on calm
-- weather until the next heartbeat.
function V.AnnounceState()
    BroadcastState(true)
end

function V.SetNetwork(options)
    options = options or {}
    if options.send ~= nil then V.NetSend = options.send end
    if options.authority ~= nil then V.IsAuthority = options.authority and true or false end
    if options.isLocal ~= nil then V.OwnerTest = options.isLocal end
    if options.players ~= nil then V.PlayersProvider = options.players end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

-- options:
--   seed            number; the host's. Guests in a network game omit it and wait
--                   for the host's VenusState.
--   authority       true on the host / offline, false on a guest
--   send            function(op, ...) -- delivers a VenusState / VenusStrike /
--                   VenusErupt event to every guest (host only)
--   isLocal         function(handle) -> boolean override for "do I simulate this"
--   players         function() -> array of every human player's handle (host only);
--                   strikes near players are chosen from all of them
--   sites           the generated CRVenusSites table (bounds, sulfur, vents)
--   bounds          { minX, maxX, minZ, maxZ } override for the playable box
--   startLevel, targetLevel
--   enabled, debug, quality, baseSky     passthrough
--   fogPools, lightning, clouds, acidRain, sulfur, vents, sensorDegrade, ...
--                   sub-system switches
function V.Init(options)
    if V.Initialized then return end
    options = options or {}

    if options.enabled ~= nil then V.Enabled = options.enabled and true or false end
    if options.debug ~= nil then V.Debug = options.debug and true or false end
    local switches = {
        fogPools = "AllowFogPools", altitudeFog = "AllowAltitudeFog", lightning = "AllowLightning",
        knockback = "AllowKnockback", radarScramble = "AllowRadarScramble", flash = "AllowFlash",
        clouds = "AllowClouds", acidRain = "AllowAcidRain", sulfur = "AllowSulfur", poolFx = "AllowPoolFx",
        vents = "AllowVents", eruptions = "AllowEruptions", sensorDegrade = "AllowSensorDegrade",
        episodes = "AllowEpisodes", fogBanks = "AllowFogBanks", fogDrama = "AllowFogDrama",
    }
    for key, field in pairs(switches) do
        if options[key] ~= nil then V[field] = options[key] and true or false end
    end

    V.SetNetwork({ send = options.send, authority = options.authority, isLocal = options.isLocal,
                   players = options.players })

    CRWeather.Init({
        enabled = V.Enabled,
        quality = options.quality,
        debug   = options.debug,
        baseSky = options.baseSky,
    })

    -- Vehicle wakes: render-only debris under low, moving craft near the viewer
    -- (shared CRWake module). options.vehicleWakes = false switches them off.
    pcall(Wake.Init, {
        surface = "ash", enabled = options.vehicleWakes ~= false, quality = options.quality,
        debug = options.debug,
    })

    -- Our particle templates are an opt-in payload, so a build that has not
    -- shipped it degrades to presets + gameplay rather than failing weather.
    V.TemplatesReady = false
    local okTemplates, templates = pcall(require, "CRParticleTemplates")
    if okTemplates and type(templates) == "table" and type(templates.EnsureExtra) == "function" then
        local ready, reason = templates.EnsureExtra("cr_venus")
        V.TemplatesReady = ready and true or false
        if not ready then
            print("CRVenusWeather: cr_venus particle templates unavailable (" .. tostring(reason) ..
                "); pools, lightning visuals, vents and clouds are off")
        end
    end

    V.Clock = 0.0
    V.LastRealTime = nil
    V.TargetLevel = Clamp(tonumber(options.targetLevel) or 2, 1, LEVEL_COUNT)
    V.ForcedLevel = nil
    V.ForcedUntil = nil
    V.HostOverride = nil
    V.Strikes, V.SeenStrikes, V.Flashes, V.Thunder = {}, {}, {}, {}
    V.Eruptions = {}
    V.Powers = {}
    V.Stats = { strikes = 0, powerStrikes = 0, exposedStrikes = 0, groundStrikes = 0,
                knocked = 0, scrambled = 0, eruptions = 0 }
    V.FogLive, V.SulfurLive, V.PlumeLive, V.Clouds = {}, {}, {}, {}
    V.Rain = nil
    V.PoolFactor, V.PoolFactorTarget = 0.0, 0.0
    V.StrikeSerial, V.EruptionSerial = 0, 0
    V.FogRequests, V.SeenFogs, V.HazeLive, V.DramaTrack = {}, {}, {}, {}
    V.FogSerial, V.FogAllow, V.FogIntensity, V.FogLastActiveAt = 0, 0.0, 0.0, -1000.0
    V.NextDramaAt, V.DramaCount, V.DramaCooldownUntil, V.LastDrama = 0.0, 0, 0.0, nil
    V.LastStateKey = nil
    V.NextStreamAt, V.NextNetStateAt = 0.0, 0.0

    -- A guest in a network game has no seed until the host's state arrives; it
    -- shows calm weather until then rather than inventing a timeline that
    -- would diverge. Offline and host always have one.
    local seed = tonumber(options.seed)
    if seed == nil and V.IsAuthority then
        seed = math.random(1, 2000000000)
    end
    if seed ~= nil then
        BuildLadder(seed)
        V.Synced = true
    else
        V.Seed = nil
        V.Ladder = nil
        V.Synced = false
        V.WindRng = Map.NewRng(1)
        V.StrikeRng = Map.NewRng(2)
        V.EruptionRng = Map.NewRng(3)
        V.FxRng = Map.NewRng(5)
        V.FogRng = Map.NewRng(7)
        V.FogBanks = nil
        V.PrevailingBearing = 0.0
        V.Bearing, V.BearingTarget = 0.0, 0.0
    end

    V.Level = Clamp(tonumber(options.startLevel) or 1, 1, LEVEL_COUNT)
    V.LevelValue = V.Level
    V.WindSpeed = Level(V.Level).windSpeed

    -- Map data.
    local sites = options.sites
    V.SulfurSites, V.VentSites = {}, {}
    V.PoolFx, V.SulfurCells, V.SulfurGeom = nil, {}, nil
    if sites ~= nil then
        if sites.sulfur ~= nil then
            local cells = Map.ExpandRuns(sites.sulfur)
            local clustered = Map.ClusterSulfur(cells, sites.sulfur, {})
            V.SulfurSites = clustered.emitters
            V.SulfurClusters = clustered.clusters
            V.SulfurCells = cells
            V.SulfurGeom = {
                cols = sites.sulfur.cols, rows = sites.sulfur.rows, cell = sites.sulfur.cell,
                originX = sites.sulfur.originX, originZ = sites.sulfur.originZ,
            }
            -- The rng is looked up per call: BuildLadder replaces V.FxRng when a guest's seed arrives.
            local poolRng = { Range = function(lo, hi)
                if V.FxRng == nil then return (lo + hi) * 0.5 end
                return V.FxRng.Range(lo, hi)
            end }
            V.PoolFx = PoolFX.New({
                kind = "sulfur", sites = V.SulfurSites, rng = poolRng, weightAt = V.SulfurWeightAt,
                heightAt = TerrainHeight, range = V.PoolFxRange, maxNear = V.PoolFxNear,
                gap = V.PoolFxGap, radius = V.PoolFxRadius, mask = V.PoolFxMask,
            })
        end
        if sites.vents ~= nil then
            V.VentSites = Map.MergeVents(sites.vents, V.VentMergeRadius)
        end
    end
    StartTerrainScan(ResolveBounds(options))

    local environment = rawget(_G, "Environment")
    if environment ~= nil and type(environment.RegisterEnvironmentModifier) == "function" then
        environment.RegisterEnvironmentModifier("CRVenusWeather", EnvironmentModifier)
        V.EnvModifierRegistered = true
    end
    if environment ~= nil and type(environment.RegisterGameplayModifier) == "function" then
        environment.RegisterGameplayModifier("CRVenusWeather", GameplayContribution)
        V.GameplayRegistered = true
    end

    V.NextStrikeAt = 20.0
    V.NextEruptionAt = 35.0
    V.NextPowerScanAt = 0.0

    ApplyRung(V.Level, 0.05)
    CRWeather.SetWindOverride({ x = 0.0, y = -0.1, z = 1.0 }, V.WindSpeed)

    V.Initialized = true
    Log("initialised; seed=" .. tostring(V.Seed) .. " authority=" .. tostring(V.IsAuthority))
    BroadcastState(true)
end

-- Same real-clock treatment as CRMarsWeather: misn04-style adapters pass a fixed
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

function V.Update(dt)
    if not V.Initialized then V.Init() end
    if not V.Enabled then return end

    dt = tonumber(dt) or 0.0
    if dt > 0.0 then dt = RealDelta(dt) end
    if dt <= 0.0 then
        CRWeather.Update(0.0)
        return
    end

    V.Clock = V.Clock + dt

    UpdateLadder(dt)
    UpdateFogBank(dt)
    UpdateFogDrama()
    UpdateWind(dt)
    UpdateTerrainScan()
    UpdatePoolFactor(dt)
    UpdateSensors()
    UpdateRain()
    UpdateClouds(dt)
    UpdateLightning()
    UpdateStrikes()
    UpdateSulfur()
    UpdatePoolFx(dt)
    UpdateVents()
    UpdateFogSystems(dt)
    UpdateHazeRates()

    if V.Clock >= V.NextStreamAt then
        V.NextStreamAt = V.Clock + V.StreamInterval
        local playerPos = LocalPlayerPosition()
        if V.TemplatesReady then
            if V.AllowFogPools and V.Basins ~= nil then
                StreamSites(V.Basins.anchors, V.FogLive, V.MaxLiveFog, V.FogStreamIn, V.FogStreamOut,
                    FogCreate, FogDestroy, playerPos)
            end
            if V.AllowSulfur then
                StreamSites(V.SulfurSites, V.SulfurLive, V.MaxLiveSulfur, V.SulfurStreamIn, V.SulfurStreamOut,
                    SulfurCreate, SulfurDestroy, playerPos)
            end
            if V.AllowVents then
                StreamSites(V.VentSites, V.PlumeLive, V.MaxLivePlumes, V.PlumeStreamIn, V.PlumeStreamOut,
                    PlumeCreate, PlumeDestroy, playerPos)
            end
        end
        StreamHaze(playerPos)
        UpdateRenderIntents()
    end

    BroadcastState(false)
    Wake.Update(dt)
    CRWeather.Update(dt)
end

function V.Shutdown()
    if not V.Initialized then return end

    Fx_DestroyAll()
    PoolFX.Stop(V.PoolFx)
    V.FogLive, V.SulfurLive, V.PlumeLive, V.Clouds = {}, {}, {}, {}
    V.HazeLive, V.FogRequests, V.FogIntensity, V.FogAllow = {}, {}, 0.0, 0.0
    V.Strikes, V.Rain = {}, nil

    local environment = rawget(_G, "Environment")
    if V.EnvModifierRegistered and environment ~= nil
        and type(environment.UnregisterEnvironmentModifier) == "function"
    then
        environment.UnregisterEnvironmentModifier("CRVenusWeather")
    end
    V.EnvModifierRegistered = false

    if V.GameplayRegistered and environment ~= nil
        and type(environment.UnregisterGameplayModifier) == "function"
    then
        environment.UnregisterGameplayModifier("CRVenusWeather")
        if type(environment.RequestGameplaySync) == "function" then
            environment.RequestGameplaySync()
        end
        if type(environment.SyncGameplayImpacts) == "function" then
            pcall(environment.SyncGameplayImpacts)
        end
    end
    V.GameplayRegistered = false

    -- Strike scrambles must not outlive the mission.
    if environment ~= nil and type(environment.ClearObjectScramble) == "function"
        and type(environment.ObjectScrambles) == "table"
    then
        local handles = {}
        for h in pairs(environment.ObjectScrambles) do handles[#handles + 1] = h end
        for i = 1, #handles do environment.ClearObjectScramble(handles[i]) end
    end

    if V.AllowRenderIntents and type(exu.SetRenderEffectFloat) == "function" then
        pcall(exu.SetRenderEffectFloat, "depth_haze", "strength", 0.0)
    end

    CRWeather.ClearWindOverride()
    Wake.Stop()
    CRWeather.Shutdown()
    V.Initialized = false
end

-- =============================================================================
-- Mission API
-- =============================================================================

-- The rung the weather trends toward. Host / offline only; a guest ignores it
-- because the host's state event carries the target.
function V.SetTargetLevel(index)
    if not V.IsAuthority then return V.TargetLevel end
    V.TargetLevel = Clamp(tonumber(index) or 1, 1, LEVEL_COUNT)
    BroadcastState(true)
    return V.TargetLevel
end

function V.GetTargetLevel()
    return V.TargetLevel
end

-- Pins the ladder to a rung for a fixed time -- for a set piece on cue.
function V.ForceLevel(index, seconds, transitionSeconds)
    if not V.Initialized then V.Init() end
    if not V.IsAuthority then return false end
    index = Clamp(tonumber(index) or 1, 1, LEVEL_COUNT)
    V.ForcedLevel = index
    V.ForcedUntil = V.Clock + math.max(1.0, tonumber(seconds) or 60.0)
    ApplyRung(index, transitionSeconds)
    BroadcastState(true)
    return true
end

function V.ReleaseForcedLevel()
    V.ForcedLevel = nil
    V.ForcedUntil = nil
    BroadcastState(true)
end

-- Forces one strike now, from the host. For set pieces and for tests.
-- target: { x, y, z, kind }; kind defaults to ground.
function V.TriggerStrike(target)
    if not V.IsAuthority or not V.Initialized then return false end
    V.StrikeSerial = V.StrikeSerial + 1
    local delay = V.StrikeRng.Range(V.TelegraphSeconds[1], V.TelegraphSeconds[2])
    V.BeginStrike(V.StrikeSerial, target.x, target.y, target.z, target.kind or KIND_GROUND, delay, 1.0)
    Send("VenusStrike", V.StrikeSerial, target.x, target.y, target.z, target.kind or KIND_GROUND, delay, 1.0)
    return true
end

-- Starts a fog bank now: a rare dense sulphur-fog moment with a smooth roll-in
-- and roll-out. Host / offline only (a guest returns false; the host's VenusFog
-- event reaches it). One small event, whatever the length.
--
-- opts (all optional):
--   seconds  total length, default drawn from FogBankSeconds
--   power    0..1 strength, default drawn from FogBankPower
--   force    true: ignore the storm / ForceLevel precedence (a set piece that
--            WANTS fog in a storm); default false
--   reason   free text, for the log
-- Returns true, serial on success; false, reason when refused (not the host,
-- fog already up, a storm or forced level in force, banks disabled).
function V.RequestFogBank(opts)
    if not V.Initialized then V.Init() end
    opts = opts or {}
    if not V.IsAuthority then return false, "guest" end
    if not V.AllowFogBanks or not V.Synced or V.FogRng == nil then return false, "disabled" end
    local force = opts.force == true
    if not force then
        if V.ForcedLevel ~= nil or V.FogAllow < 0.5 then return false, "storm" end
        if V.FogIntensity > 0.05 or #V.FogRequests > 0 then return false, "active" end
    end

    local rng = V.FogRng
    local total = tonumber(opts.seconds) or rng.Range(V.FogBankSeconds[1], V.FogBankSeconds[2])
    total = math.max(12.0, total)
    local rollIn = math.min(rng.Range(V.FogBankRollIn[1], V.FogBankRollIn[2]), total * 0.35)
    local rollOut = math.min(rng.Range(V.FogBankRollOut[1], V.FogBankRollOut[2]), total * 0.4)
    local hold = math.max(1.0, total - rollIn - rollOut)
    local power = Clamp(tonumber(opts.power) or rng.Range(V.FogBankPower[1], V.FogBankPower[2]), 0.0, 1.0)

    V.FogSerial = V.FogSerial + 1
    local flag = force and 1 or 0
    V.BeginFogBank(V.FogSerial, rollIn, hold, rollOut, power, flag)
    Send("VenusFog", V.FogSerial, rollIn, hold, rollOut, power, flag)
    V.DramaCooldownUntil = V.Clock + rollIn + hold + rollOut + V.DramaCooldown
    return true, V.FogSerial
end

function V.TriggerEruption(siteIndex)
    if not V.IsAuthority or not V.Initialized then return false end
    V.EruptionSerial = V.EruptionSerial + 1
    local rng = V.EruptionRng
    local duration = rng.Range(V.EruptionSeconds[1], V.EruptionSeconds[2])
    local power = rng.Range(0.7, 1.0)
    V.BeginEruption(V.EruptionSerial, siteIndex, duration, power)
    Send("VenusErupt", V.EruptionSerial, siteIndex, duration, power)
    return true
end

function V.GetLevel() return V.Level end
function V.GetLevelName() return Level(V.Level).name end
function V.IsEpisode() return V.Episode end
function V.GetVisibility() return LadderValue("visibility") end
function V.GetWindSpeed() return V.WindSpeed end
function V.GetPoolFactor() return V.PoolFactor end
function V.GetFogIntensity() return V.FogIntensity end
function V.GetFogAllow() return V.FogAllow end
function V.IsFogBankActive() return V.FogIntensity > 0.02 end
-- The scheduled banks that start at or before `untilT` (clock seconds).
function V.GetFogSchedule(untilT)
    if V.FogBanks == nil then return {} end
    return V.FogBanks:Events(untilT or 0.0)
end
function V.GetDramaStats() return V.DramaCount, V.LastDrama end
function V.GetBasins() return V.Basins end
-- Liquid-sulphur weight of the .mat cell under (x, z): 0 off the pool, 1 solid pool.
function V.SulfurWeightAt(x, z)
    local g = V.SulfurGeom
    if g == nil then return 0.0 end
    local col = math.floor((x - g.originX) / g.cell)
    local row = math.floor((z - g.originZ) / g.cell)
    if row < 0 or row >= g.rows or col < 0 or col >= g.cols then return 0.0 end
    return V.SulfurCells[(row * g.cols) + col] or 0.0
end

function V.GetSulfurSites() return V.SulfurSites end
function V.GetVentSites() return V.VentSites end
function V.GetStats() return V.Stats end
function V.GetSystemCount() return V.SystemCount end

function V.Describe()
    return string.format("%s (%.2f)%s wind %.1f pool %.2f systems %d strikes %d",
        Level(V.Level).name, V.LevelValue, V.Episode and " EPISODE" or "",
        V.WindSpeed, V.PoolFactor, V.SystemCount, V.Stats.strikes)
end

-- =============================================================================
-- Save / load
--
-- Particle systems do not survive a save; only the director's scalars persist.
-- =============================================================================

function V.Save()
    return {
        seed        = V.Seed,
        clock       = V.Clock,
        level       = V.Level,
        levelValue  = V.LevelValue,
        targetLevel = V.TargetLevel,
        bearing     = V.Bearing,
        prevailing  = V.PrevailingBearing,
        windSpeed   = V.WindSpeed,
        forcedLevel = V.ForcedLevel,
        forcedFor   = V.ForcedUntil and (V.ForcedUntil - V.Clock) or nil,
        ladder      = V.Ladder and V.Ladder:Save() or nil,
        strikeSerial = V.StrikeSerial,
        eruptionSerial = V.EruptionSerial,
        fogSerial   = V.FogSerial,
        fogRequests = V.FogRequests,
        dramaCount  = V.DramaCount,
        dramaUntil  = V.DramaCooldownUntil,
    }
end

function V.Load(state)
    if type(state) ~= "table" then return end
    if not V.Initialized then V.Init() end

    if state.seed ~= nil and (V.Seed ~= state.seed or V.Ladder == nil) then
        BuildLadder(state.seed)
        V.Synced = true
    end
    V.Clock = tonumber(state.clock) or 0.0
    V.TargetLevel = Clamp(tonumber(state.targetLevel) or 2, 1, LEVEL_COUNT)
    if V.Ladder ~= nil and state.ladder ~= nil then V.Ladder:Load(state.ladder) end
    V.Bearing = tonumber(state.bearing) or V.Bearing
    V.PrevailingBearing = tonumber(state.prevailing) or V.PrevailingBearing
    V.BearingTarget = V.PrevailingBearing
    V.NextBearingAt = V.Clock
    V.WindSpeed = tonumber(state.windSpeed) or V.WindSpeed
    V.StrikeSerial = tonumber(state.strikeSerial) or 0
    V.EruptionSerial = tonumber(state.eruptionSerial) or 0
    V.FogSerial = tonumber(state.fogSerial) or 0
    V.DramaCount = tonumber(state.dramaCount) or 0
    V.DramaCooldownUntil = tonumber(state.dramaUntil) or 0.0
    V.FogRequests, V.SeenFogs, V.HazeLive, V.DramaTrack = {}, {}, {}, {}
    if type(state.fogRequests) == "table" then
        for i = 1, #state.fogRequests do
            local r = state.fogRequests[i]
            if type(r) == "table" and tonumber(r.start) ~= nil then
                V.FogRequests[#V.FogRequests + 1] = {
                    start = tonumber(r.start), rollIn = tonumber(r.rollIn) or 10.0,
                    hold = tonumber(r.hold) or 20.0, rollOut = tonumber(r.rollOut) or 14.0,
                    power = tonumber(r.power) or 1.0, force = r.force == true,
                }
            end
        end
    end

    if state.forcedLevel ~= nil and (tonumber(state.forcedFor) or 0.0) > 0.0 then
        V.ForcedLevel = Clamp(tonumber(state.forcedLevel), 1, LEVEL_COUNT)
        V.ForcedUntil = V.Clock + tonumber(state.forcedFor)
    else
        V.ForcedLevel, V.ForcedUntil = nil, nil
    end

    -- Loading rebuilds the Ogre scene: every system we held is already gone.
    Fx_DestroyAll()
    PoolFX.Stop(V.PoolFx)
    V.FogLive, V.SulfurLive, V.PlumeLive, V.Clouds = {}, {}, {}, {}
    V.HazeLive = {}
    V.Strikes, V.Eruptions, V.Rain, V.Flashes, V.Thunder = {}, {}, nil, {}, {}
    V.Powers = {}
    V.NextStrikeAt = V.Clock + 20.0
    V.NextEruptionAt = V.Clock + 35.0
    if type(CRWeather.ResetSystems) == "function" then CRWeather.ResetSystems() end

    V.Level = Clamp(tonumber(state.level) or 1, 1, LEVEL_COUNT)
    V.LevelValue = Clamp(tonumber(state.levelValue) or V.Level, 1.0, LEVEL_COUNT)
    CRWeather.SetPreset(Level(V.Level).preset, 0.05)
    CRWeather.Blend = 1.0
    V.LastSyncSeverity = -1.0
    V.LastStateKey = nil
end

return CRVenusWeather
