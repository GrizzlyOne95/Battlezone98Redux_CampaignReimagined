-- Chinese08Mission.cpp -> stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/chinese08mission.cpp
-- Source blob: 319372874b7b9379401b4199562d1fd5c16dbe21.
-- All native comments/cut code and serialization declarations are preserved in
-- References/Chinese08Source/Chinese08Mission.cpp. No EXU/helper dependency.
-- Attach to the original chmisn08 map; its labels, paths and assets are required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/CHMISN08_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Chmisn08CoopSourceParity.py).
-- CR co-op layer <<

local MS_STARTUP, MS_WAITFORCLOAK, MS_WAITFORTRIGGER, MS_CAMERATRIGGER = 1, 2, 3, 4
local MS_SPAWNAPC1, MS_SPAWNAPC2, MS_SPAWNAPC3, MS_SPAWNAPC4 = 5, 6, 7, 8
local MS_SPAWNAPC5, MS_WAITFORSCAP, MS_WAITSTARTSOUND4, MS_DISPLAYOBJ6 = 9, 10, 11, 12
local MS_WAITFORSOUND4, MS_DISPLAYOBJ1, MS_TRIGGER1, MS_WAITFORJUMPOUT = 13, 14, 15, 16
local MS_WAITFORWRECKER, MS_BANGCAMERA, MS_BANGCAMERA2, MS_DISPODJ5 = 17, 18, 19, 20
local MS_TRIGGERNWNE, MS_DISPOBJ7, MS_DESTROYPOWERS, MS_DISPOBJ2 = 21, 22, 23, 24
local MS_WAITFORSOUND8, MS_DESTROYTOWERS, MS_WRECKER10, MS_WRECKER22 = 25, 26, 27, 28
local MS_WRECKER33, MS_WRECKER42, MS_WRECKER55, MS_WRECKER70 = 29, 30, 31, 32
local MS_WRECKER85, MS_WRECKER92, MS_WRECKER100, MS_WRECKER106 = 33, 34, 35, 36
local MS_END = 100

local function NewState()
    -- Native Load (missionSave) clears bools to false, floats to 99999, handles
    -- and ints to 0, then Setup() assigns the rest. Null handles/audio IDs are
    -- nil here: user, olduser, recycler, factory, soundHandle, coreFailSound.
    return {
        lost = false, -- unused in source
        spawn_1 = false, spawn_2 = false, spawn_3 = false,
        spawn_4 = false, spawn_5 = false, spawn_6 = false,
        west_powerDead = false, east_powerDead = false,
        west_commDead = false, east_commDead = false,
        startwalker = false, -- only set by the #if 0 walker blocks
        apc3objectiveon = false, howitzerobjectiveon = false,
        stateTimer = 99999.0, apcInLine = 0,
        missionState = MS_STARTUP, userCloakState = 0,
        apc = {}, magpull = {}, west_mag = {}, east_mag = {}, snipers = {},
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/CHMISN08_COOP.md lists every wrapped call.
-- Update() alone needs 37 MS_* state constants plus M as upvalues, leaving no room under Lua 5.1's
-- 60-upvalue-per-function limit for ~25 shadowed natives too, so the shadows below are chunk globals, not
-- locals (zero upvalue cost). CRCoop.lua and CRCCARuntime.lua share this engine's default global table, and
-- both call some of these same names (GetPlayerHandle, BuildObject, SetObjectiveOn/Off, RemoveObject, ...)
-- as bare globals internally, so writing these shadows into the shared table would silently reroute THEIR
-- internal bookkeeping through this mission's wrapper too (one such path recurses forever). Sandbox this
-- chunk into a private environment for the shadow definitions and the faithful body only: both read/write
-- the private table first, falling back to the real shared globals for anything not listed here, so
-- CRCoop.lua/CRCCARuntime.lua keep seeing the true natives, unaware this mission ever shadowed anything.
-- RealEnv is restored (see "CR co-op callbacks" below) before Start/Update/Save/Load/etc are redefined as
-- the engine's actual entry points: a Lua function's environment is fixed at the moment it is created, so
-- the faithful body's functions (created here, while MissionEnv is active) keep resolving shadows forever
-- regardless of what the chunk's "current" environment becomes afterward, while the NEW wrapper functions
-- the host engine calls (created after restoring RealEnv) land in the real global table exactly like every
-- other mission's, so lua_getglobal("Update") etc still finds them. Without this restore, every mission
-- entry point would silently live only in MissionEnv -- invisible to the engine, which reads globals
-- straight from the Lua state's real table regardless of any setfenv a loaded chunk did to itself.
local RealEnv = getfenv(1)
local MissionEnv = setmetatable({}, { __index = RealEnv })
setfenv(1, MissionEnv)
local Restored = {}
-- Reinforcement waves (CheckSpawns) become concealed, head-count-scaled tickets, keyed by their spawn path
-- (svfigh is used both for a wave and for the two direct convoy escorts, so the ODF alone cannot tell them
-- apart). The convoy's five APCs and their escorts are built directly on the real enemy team: unique,
-- individually tracked handles the body names and drives (SetName/Goto/IsUser), never duplicated.
local SCALED_PATHS = {
    wave_1 = true, wave_2 = true, wave_3 = true, wave_4 = true, wave_5 = true, wave_6 = true,
}
-- campaignRuntime.Spawn only tickets/scales an odf listed in config.scaledOdfs; everything else is an
-- immediate direct build. svfigh is shared between a wave (must scale) and the two apc_escort builds (must
-- stay direct, real handles), so the odf alone cannot gate it: BuildObject below routes by SCALED_PATHS
-- (where), calling campaignRuntime.Spawn only for the wave paths above. A direct (non-wave) team-2 build
-- therefore never reaches campaignRuntime.Spawn's own team-2 -> team-5 remap, so it is repeated here.
local DIRECT_ENEMY_TEAM = 5
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "chmisn08cr", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "coop_spawn1" }, -- respawn at the co-op start buoys
    scrapPerGuest = 10,
    -- Only the reinforcement-wave odfs are ticketed/scaled (concealed arrival, head-count extras); the
    -- convoy's svapc and its apc_escort svfigh stay out of this set and are built directly (see BuildObject).
    scaledOdfs = { svfigh = true, svtank = true, svwalk = true },
    -- The largest simultaneous count if every reinforcement wave were up at once and none had died yet:
    -- wave_1 (3) + wave_2 (8) + wave_3 (8) + wave_4 (3) + wave_5 (8) + wave_6 (8) = 38.
    liveCap = 40,
    -- No shipped generic "ch08lose.des": the stock .des set is all state-specific. A runtime-only failure
    -- (for example the leader departing) reports the broadest one, "both recycler and factory destroyed".
    failDes = "ch08lsea.des",
    wonFlags = { "coopWon" },
    endedFlags = { "coopWon", "coopLost" },
    orders = { "Attack" },
    presentationOps = {
        CH8Cloak = function(h) Restored.OpCloak(h) end,
        CH8Decloak = function(h) Restored.OpDecloak(h) end,
        CH8EnableCloak = function(h, on) Restored.OpEnableCloak(h, on) end,
        CH8Perceived = function(h, team) Restored.OpPerceived(h, team) end,
        CH8Boom = function(odf, where) Restored.OpBoom(odf, where) end,
    },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesCH08", startLevel = 1, targetLevel = 1,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local function raise(level)
                if europa.GetTargetLevel() < level then europa.SetTargetLevel(level) end
            end
            -- The convoy rolls out toward the fort: the ice begins to stir.
            if (not beats.convoy) and state.missionState >= MS_SPAWNAPC1 then
                beats.convoy = true
                raise(2)
            end
            -- The bang: the decoy wrecker detonates and the fight for the fort opens.
            if (not beats.bang) and state.missionState >= MS_TRIGGERNWNE then
                beats.bang = true
                raise(3)
                europa.Quake(0.4, 3.0)
            end
            -- A power plant or comm tower falls: the surge begins.
            if (not beats.power) and (state.west_powerDead or state.east_powerDead
                or state.west_commDead or state.east_commDead) then
                beats.power = true
                raise(4)
                europa.Surge(6.0, 0.8)
                if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end
            end
            -- Everything calms while the result counts down; a loss leaves the ice restless.
            if (not beats.calm) and state.coopWon then
                beats.calm = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
            if (not beats.lost) and state.coopLost and not state.coopWon then
                beats.lost = true
                raise(4)
            end
        end },
})
local NativeBuildObject, NativeGetNearestUnitOnTeam = BuildObject, GetNearestUnitOnTeam
local NativeCloak, NativeDecloak, NativeEnableCloaking = Cloak, Decloak, EnableCloaking
local NativeSetPerceivedTeam, NativeMakeExplosion = SetPerceivedTeam, MakeExplosion
-- The body's "player" is whoever captures APC #5: IsUser(apc[4]) gates the capture/jump-out beat, but the
-- faithful body also leans on M.user generically for the rest of the mission -- the fort-approach trigger
-- (Distance(M.user, "nw_trigger"/"ne_trigger")), sniper retargeting (Strike()'s Valid(M.user) guard), the
-- cloak-zone check, and IsUser(howitzer_nw/ne) (clears the objective marker once the player reaches it).
-- Going permanently nil the moment the driver dismounts would silently break all of that. So the rule is
-- sticky by HUMAN, not by handle: whichever connected human first occupies apc[4] stays "the player" for
-- the rest of the mission, resolved to their CURRENT craft every frame (on foot after jumping out, or back
-- to apc[4] if they foolishly re-board it -- which still correctly re-triggers MS_WAITFORWRECKER's
-- re-entry fail, since their current handle becomes apc[4] again). Before anyone has boarded it, this
-- returns nil; Distance(_, M.user) already treats a nil "from"/"to" as infinite in the faithful body's own
-- Distance() helper, so an unboarded convoy fails open (no false triggers).
-- CRCoop.lua's own RefreshLocalHandle() reads the bare global GetPlayerHandle; the MissionEnv sandbox
-- above is what keeps that call seeing the true native instead of recursing into this shadow.
GetPlayerHandle = campaignRuntime and function()
    local coop = campaignRuntime.Coop
    if not coop.IsNetworkGame() then
        -- Exactly one human: still re-resolve to their CURRENT handle every frame once matched, not the
        -- stale apc[4] value, since they may now be on foot.
        if M.coopDriverFound then
            local h
            coop.ForEachPlayerHandle(function(local_h) h = local_h end)
            return h
        end
        local found
        coop.ForEachPlayerHandle(function(h) if h == M.apc[4] then found = h end end)
        if found then M.coopDriverFound = true end
        return found
    end
    if M.coopDriverId == nil then
        coop.ForEachPlayerHandle(function(h, id) if h == M.apc[4] then M.coopDriverId = id end end)
    end
    if M.coopDriverId == nil then return nil end
    local driver
    coop.ForEachPlayerHandle(function(h, id) if id == M.coopDriverId then driver = h end end)
    return driver
end or GetPlayerHandle
local function NearestHuman(from)
    local best, bestDistance
    campaignRuntime.Coop.ForEachPlayerHandle(function(h)
        local ok, distance = pcall(GetDistance, h, from)
        if ok and type(distance) == "number" and (bestDistance == nil or distance < bestDistance) then
            best, bestDistance = h, distance
        end
    end)
    return best
end
-- Strike() orders the snipers onto M.user. Before anyone has boarded APC #5, M.user is nil (no human is
-- "the player" yet); fall back to the nearest human so the snipers still react on the first frame, as the
-- single-player body always has exactly one player to target.
Attack = campaignRuntime and function(h, target, priority)
    if target == nil then target = NearestHuman(h) end
    if target == nil then return end
    return campaignRuntime.Attack(h, target, priority)
end or Attack
local eventFrame
BuildObject = campaignRuntime and function(odf, team, where, point)
    if team ~= 2 then
        if point ~= nil then return NativeBuildObject(odf, team, where, point) end
        return NativeBuildObject(odf, team, where)
    end
    if not SCALED_PATHS[where] then
        -- The convoy's APCs and apc_escort fighters: a direct, unscaled, immediately-real handle
        -- (SetName/Goto/Defend2/IsUser need it this frame, never a ticket). campaignRuntime.Spawn's own
        -- authority gate is bypassed by calling the native directly, so it is repeated here: every peer
        -- runs this same faithful Update(), and only the authority may actually build, or a network game
        -- would spawn five APCs per peer instead of one shared convoy.
        if not campaignRuntime.Coop.IsAuthority() then return nil end
        return NativeBuildObject(odf, DIRECT_ENEMY_TEAM, where)
    end
    local now = GetTime()
    if eventFrame ~= now then
        eventFrame = now
        campaignRuntime.BeginEvent()
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- CheckSpawns asks for the nearest unit on team 1 (the body's single-player team) to decide whether a
-- reinforcement wave should build; co-op must check every human team, not just the leader's.
GetNearestUnitOnTeam = campaignRuntime and function(path, team)
    if team ~= 1 then return NativeGetNearestUnitOnTeam(path, team) end
    local best, bestDistance
    campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam)
        local h = NativeGetNearestUnitOnTeam(path, humanTeam)
        if h ~= nil and h ~= 0 and IsValid(h) then
            local ok, distance = pcall(GetDistance, h, path)
            if ok and type(distance) == "number" and (bestDistance == nil or distance < bestDistance) then
                best, bestDistance = h, distance
            end
        end
    end)
    return best
end or GetNearestUnitOnTeam
-- The body's SetPilot(1, n) is the shared Chinese side: every human team gets the pilots. NativeSetPilot is
-- called directly throughout (never the reassigned global below) so the fan-out cannot recurse into itself.
local NativeSetPilot = SetPilot
function SetPilot(team, count)
    if not campaignRuntime then return NativeSetPilot(team, count) end
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) NativeSetPilot(humanTeam, count) end)
        return
    end
    if team == 2 then team = 5 end
    return NativeSetPilot(team, count)
end
SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever.
local nativeAudioDone = IsAudioMessageDone
function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
SetName = campaignRuntime and campaignRuntime.SetObjectiveName or SetName -- stock SetName alias of SetObjectiveName
SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
SetObjectiveOff = campaignRuntime and campaignRuntime.SetObjectiveOff or SetObjectiveOff
-- Camera calls gain the runtime's one-shot-at-a-time safety net; CameraCancelled is already unskippable in
-- a network game generically (CRCCARuntime.lua), so cut_1 and cut_bang need no mission-specific ETA/skip
-- handling: both already end on the body's own fixed stateTimer, never on camera arrival.
CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
CameraPath = campaignRuntime and campaignRuntime.CameraPath or CameraPath
CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
-- coopWon/coopLost are CR-only bookkeeping (never read by the faithful body) backing wonFlags/endedFlags.
SucceedMission = campaignRuntime and function(...)
    M.coopWon = true
    return campaignRuntime.SucceedMission(...)
end or SucceedMission
FailMission = campaignRuntime and function(...)
    if not M.coopWon then M.coopLost = true end
    return campaignRuntime.FailMission(...)
end or FailMission
-- Cloak, the core-failure decloak and the jump-out disguise are local engine state each peer applies to
-- its own copy (Docs/CHMISN08_COOP.md): every cloak/decloak/perceived-team change is presented so every
-- peer's client reflects it, not just the authority that detected the trigger.
Cloak = campaignRuntime and function(h) return campaignRuntime.Present("CH8Cloak", h) end or Cloak
Decloak = campaignRuntime and function(h) return campaignRuntime.Present("CH8Decloak", h) end or Decloak
EnableCloaking = campaignRuntime and function(h, on) return campaignRuntime.Present("CH8EnableCloak", h, on) end or EnableCloaking
-- SetPerceivedTeam(2) is the infiltrator disguising as the convoy's own (enemy, team 5) side; unlike a
-- squad-wide disguise, this applies to one handle: whichever human was driving APC #5 when it fired.
SetPerceivedTeam = campaignRuntime and function(h, team)
    return campaignRuntime.Present("CH8Perceived", h, team == 2 and 5 or team)
end or SetPerceivedTeam
MakeExplosion = campaignRuntime and function(odf, where) return campaignRuntime.Present("CH8Boom", odf, where) end or MakeExplosion
-- CR co-op runtime <<
-- CR co-op fixes >>
-- The presentation-op bodies the config above queues by name. There is no cut gameplay worth restoring
-- (Docs/CHMISN08_COOP.md, "Restored content") and no co-op-specific stock-bug fix: the faithful body's own
-- "Source quirks kept" are already preserved in Scripts/ch08.lua, byte for byte, unmodified here.
local function IsValidHandle(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
function Restored.OpCloak(h)
    if IsValidHandle(h) then NativeCloak(h) end
end
function Restored.OpDecloak(h)
    if IsValidHandle(h) then NativeDecloak(h) end
end
function Restored.OpEnableCloak(h, on)
    if IsValidHandle(h) then NativeEnableCloaking(h, on) end
end
function Restored.OpPerceived(h, team)
    if IsValidHandle(h) then NativeSetPerceivedTeam(h, team) end
end
function Restored.OpBoom(odf, where)
    if type(where) == "string" or IsValidHandle(where) then NativeMakeExplosion(odf, where) end
end
-- CR co-op fixes <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Alive(h)
    -- PORT ADAPTATION: native handles of removed/dead objects are harmless
    -- integers; Lua handles must be validated before every query.
    return Valid(h) and IsAlive(h)
end
local function Distance(from, to)
    -- PORT FIX: a missing/deleted handle must not become a zero-distance
    -- trigger or select a path overload. Infinity keeps every map radius intact.
    if not Valid(from) or (type(to) ~= "string" and not Valid(to)) then
        return math.huge
    end
    return GetDistance(from, to)
end
local function Health(h)
    if not Valid(h) then return 0 end
    return GetHealth(h)
end
local function IsUser(h)
    return h ~= nil and h == M.user
end
local function Done(message)
    -- Native zero audio IDs mean there is no message to wait for.
    return message == nil or IsAudioMessageDone(message)
end
local function Strike(h)
    if Valid(h) and Valid(M.user) then Attack(h, M.user) end
end
local function Remove(h)
    if Valid(h) then RemoveObject(h) end
end
local function Perceived(team)
    if Valid(M.user) then SetPerceivedTeam(M.user, team) end
end
local function Explode(odf, where)
    -- API ADAPTATION: native MakeExplosion(location, effect) is reversed in
    -- Lua, which takes (odf, location). Handle locations must still be live.
    if type(where) == "string" or Valid(where) then MakeExplosion(odf, where) end
end
local function GotoPath(h, path)
    if Valid(h) then Goto(h, path) end
end
local function Wave(odf, path, count)
    for _ = 1, count do
        GotoPath(BuildObject(odf, 2, path), path)
    end
end

local function ResetObjectives()
    ClearObjectives()
    local s = M.missionState
    -- Cut GREEN variants (missionState == MS_DISPLAYOBJ1/DISPLAYOBJ6/DISPODJ5/
    -- DISPOBJ7/DISPOBJ2) and the whole ch08003.otf objective: source archive.
    if s >= MS_WAITFORSCAP and s < MS_WAITSTARTSOUND4 then
        AddObjective("ch08001.otf", "white")
    end
    if s >= MS_WAITSTARTSOUND4 and s < MS_DISPLAYOBJ1 then
        AddObjective("ch08006.otf", "white")
    end
    if s >= MS_DISPLAYOBJ1 and s < MS_DISPODJ5 then
        AddObjective("ch08005.otf", "white")
    end
    if s >= MS_DISPODJ5 and s < MS_DISPOBJ7 then
        AddObjective("ch08007.otf", "white")
    end
    if s >= MS_DISPOBJ7 and s < MS_DISPOBJ2 then
        AddObjective("ch08002.otf", "white")
    end
    if s >= MS_WRECKER106 then
        AddObjective("ch08004.otf", "green")
    elseif s >= MS_DISPOBJ2 then
        AddObjective("ch08004.otf", "white")
    end
end

local function CheckAPCs()
    local apc = M.apc
    if not Alive(apc[4]) and Health(apc[4]) <= 0 then
        M.missionState = MS_END
        FailMission(GetTime() + 2.0, "ch08lsed.des")
        return true
    end

    if Distance(apc[3], "break_point") < 50 then
        M.apcInLine = 2
    end

    if not Alive(apc[4]) and M.apcInLine == 0 then
        M.apcInLine = GetTime() + 25
    elseif M.apcInLine > 2 and M.apcInLine < GetTime() then
        if Distance(apc[4], apc[3]) > 100 then
            AudioMessage("ch08005.wav")
            M.missionState = MS_END
            FailMission(GetTime() + 20.0, "ch08lseb.des")
            return true
        end
        M.apcInLine = 1
    elseif M.apcInLine == 1 then
        if Distance(apc[4], apc[3]) > 100 then
            AudioMessage("ch08005.wav")
            M.missionState = MS_END
            FailMission(GetTime() + 20.0, "ch08lsee.des")
            return true
        end
    end

    for i = 0, 3 do
        if not Alive(apc[i]) then
            M.missionState = MS_END
            FailMission(GetTime() + 2.0, "ch08lsed.des")
            return true
        end
    end
    return false
end

-- The convoy-break test repeated verbatim in WAITSTARTSOUND4, WAITFORSOUND4
-- and TRIGGER1 (WAITFORSCAP uses a different, simpler test, inlined there).
local function ConvoyBroken()
    local apc = M.apc
    return (Distance(apc[3], "apc_fail") < 50
            and (not IsUser(apc[4]) or Distance(apc[3], M.user) > 75))
        or (Distance(apc[4], "trigger_1") < 30 and Distance(apc[3], "apc_fail") > 300)
end

local function FailConvoy()
    AudioMessage("ch08005.wav")
    M.missionState = MS_END
    FailMission(GetTime() + 20.0, "ch08lsec.des")
end

local function CheckSpawns()
    local function near(path)
        local temp = GetNearestUnitOnTeam(path, 1)
        return Valid(temp) and Distance(temp, path) < 100
    end

    if not M.spawn_1 then
        if near("spawn_1") then
            M.spawn_1 = true
            Wave("svfigh", "wave_1", 3)
        end
    end

    if not M.spawn_2 then
        if near("spawn_2") then
            M.spawn_2 = true
            Wave("svfigh", "wave_2", 3)
            Wave("svtank", "wave_2", 5)
        end
    end

    if not M.spawn_2 then
        if near("spawn_2a") then
            M.spawn_2 = true
            Wave("svfigh", "wave_2", 3)
            Wave("svtank", "wave_2", 5)
        end
    end

    if not M.spawn_3 then
        if near("spawn_3") then
            M.spawn_3 = true
            Wave("svfigh", "wave_3", 3)
            Wave("svtank", "wave_3", 5)
        end
    end

    if not M.spawn_3 then
        if near("spawn_3a") then
            M.spawn_3 = true
            Wave("svfigh", "wave_3", 3)
            Wave("svtank", "wave_3", 5)
        end
    end

    if not M.spawn_4 then
        if near("spawn_4") then
            M.spawn_4 = true
            Wave("svwalk", "wave_4", 3)
        end
    end

    if not M.spawn_5 then
        if near("spawn_5") then
            M.spawn_5 = true
            Wave("svfigh", "wave_5", 3)
            Wave("svtank", "wave_5", 5)
        end
    end

    if not M.spawn_6 then
        if near("spawn_6") then
            M.spawn_6 = true
            Wave("svfigh", "wave_6", 3)
            Wave("svtank", "wave_6", 5)
        end
    end
end

function Start()
    M = NewState()
    M.west_1_1 = GetHandle("west_1_1")
    M.west_1_2 = GetHandle("west_1_2")
    M.west_1_3 = GetHandle("west_1_3")
    M.west_1_4 = GetHandle("west_1_4")
    M.east_1_1 = GetHandle("east_1_1")
    M.east_1_2 = GetHandle("east_1_2")
    M.east_1_3 = GetHandle("east_1_3")
    M.east_1_4 = GetHandle("east_1_4")
    M.nav = GetHandle("nav")
    if Valid(M.nav) then SetName(M.nav, "Base") end
    M.howitzer_nw = GetHandle("howitzer_nw")
    M.howitzer_ne = GetHandle("howitzer_ne")
    M.west_power = GetHandle("west_power")
    M.east_power = GetHandle("east_power")
    M.east_bolt = GetHandle("east_bolt")
    M.west_bolt = GetHandle("west_bolt")
    M.walker_1 = GetHandle("walker_1")
    for i = 0, 5 do M.magpull[i] = GetHandle("magpull_" .. (i + 1)) end
    for i = 0, 3 do
        M.west_mag[i] = GetHandle("west_mag_" .. (i + 1))
        M.east_mag[i] = GetHandle("east_mag_" .. (i + 1))
    end
    for i = 0, 25 do M.snipers[i] = GetHandle("sniper_" .. (i + 1)) end
    M.west_comm = GetHandle("west_comm")
    M.east_comm = GetHandle("east_comm")
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if M.missionState < MS_END and M.missionState > MS_BANGCAMERA then
        if not Alive(M.recycler) and not Alive(M.factory) then
            FailMission(GetTime() + 2.0, "ch08lsea.des")
            M.missionState = MS_END
        end
    end

    if M.missionState == MS_STARTUP or M.olduser ~= M.user then
        for i = 0, 25 do
            Strike(M.snipers[i])
        end
    end

    if M.missionState >= MS_SPAWNAPC1 and M.missionState <= MS_WAITFORSCAP
        and M.soundHandle ~= nil and IsAudioMessageDone(M.soundHandle) then
        M.soundHandle = nil
        local temp = BuildObject("apcamr", 1, "apc_nav")
        if Valid(temp) then
            SetName(temp, "APC Convoy")
            SetUserTarget(temp)
        end
    end

    if M.userCloakState == 0 then
        if Distance(M.user, "east_cloak") < 200 or Distance(M.user, "west_cloak") < 200 then
            if Valid(M.user) and IsCloaked(M.user) then
                M.coreFailSound = AudioMessage("ch04002.wav")
                Decloak(M.user)
            end
            M.userCloakState = 1
            if Valid(M.user) then EnableCloaking(M.user, false) end
        end
    else
        if M.coreFailSound ~= nil then
            if IsAudioMessageDone(M.coreFailSound) then
                M.coreFailSound = nil
            end
        elseif Valid(M.user) and IsCloaked(M.user) then
            M.coreFailSound = AudioMessage("ch04002.wav")
            Decloak(M.user)
        end
    end

    local s = M.missionState
    if s == MS_STARTUP then
        M.olduser = M.user

        SetAIP("chmisn08.aip")
        SetScrap(1, 0)
        SetPilot(1, 10)
        SetScrap(2, 0)

        AudioMessage("ch08001.wav")

        M.missionState = MS_WAITFORTRIGGER

        if Valid(M.west_1_1) then Cloak(M.west_1_1) end
        if Valid(M.west_1_2) then Cloak(M.west_1_2) end
        if Valid(M.west_1_3) then Cloak(M.west_1_3) end
        if Valid(M.west_1_4) then Cloak(M.west_1_4) end
        if Valid(M.east_1_1) then Cloak(M.east_1_1) end
        if Valid(M.east_1_2) then Cloak(M.east_1_2) end
        if Valid(M.east_1_3) then Cloak(M.east_1_3) end
        if Valid(M.east_1_4) then Cloak(M.east_1_4) end

        CameraReady()

    elseif s == MS_WAITFORCLOAK then
        -- Empty in source and never entered.

    elseif s == MS_WAITFORTRIGGER then
        if Valid(M.west_1_1) then CameraPath("cut_1", 2000, 0, M.west_1_1) end

        if Distance(M.west_1_1, "cut_trigger") < 50 or Distance(M.east_1_1, "cut_trigger") < 50 then
            M.missionState = MS_CAMERATRIGGER
            M.stateTimer = GetTime() + 22
        end

    elseif s == MS_CAMERATRIGGER then
        if Valid(M.west_1_1) then CameraPath("cut_1", 2000, 0, M.west_1_1) end

        if M.stateTimer ~= 0 and M.stateTimer < GetTime() then
            CameraFinish()
            M.missionState = MS_SPAWNAPC1
            M.stateTimer = GetTime() + 30
            AudioMessage("ch08002.wav")

            Remove(M.west_1_1)
            Remove(M.west_1_2)
            Remove(M.west_1_3)
            Remove(M.west_1_4)
            Remove(M.east_1_1)
            Remove(M.east_1_2)
            Remove(M.east_1_3)
            Remove(M.east_1_4)
            Remove(M.walker_1)
        end

    elseif s == MS_SPAWNAPC1 then
        if M.stateTimer < GetTime() then
            M.soundHandle = AudioMessage("ch08003.wav")

            M.apc[0] = BuildObject("svapc", 2, "apc_spawn")
            if Valid(M.apc[0]) then
                SetName(M.apc[0], "apc_1")
                Goto(M.apc[0], "apc_path")
            end

            local temp = BuildObject("svfigh", 2, "apc_escort")
            if Valid(temp) and Valid(M.apc[0]) then Defend2(temp, M.apc[0]) end

            temp = BuildObject("svfigh", 2, "apc_escort")
            if Valid(temp) and Valid(M.apc[0]) then Defend2(temp, M.apc[0]) end

            M.missionState = MS_SPAWNAPC2
            ResetObjectives()
            M.stateTimer = GetTime() + 5
        end

    elseif s == MS_SPAWNAPC2 or s == MS_SPAWNAPC3 or s == MS_SPAWNAPC4 then
        if M.stateTimer < GetTime() then
            local n = s - MS_SPAWNAPC2 + 1 -- apc[1], apc[2], apc[3]
            M.apc[n] = BuildObject("svapc", 2, "apc_spawn")
            if Valid(M.apc[n]) then
                SetName(M.apc[n], "apc_" .. (n + 1))
                Goto(M.apc[n], "apc_path")
            end

            M.missionState = s + 1
            ResetObjectives()
            M.stateTimer = GetTime() + 5
        end

    elseif s == MS_SPAWNAPC5 then
        if M.stateTimer < GetTime() then
            M.apc[4] = BuildObject("svapc", 2, "apc_spawn")
            if Valid(M.apc[4]) then
                SetName(M.apc[4], "apc_5")
                Goto(M.apc[4], "apc_path")
            end

            M.missionState = MS_WAITFORSCAP
            ResetObjectives()

            -- Cut: SetUserTarget(apc[4]);
            M.startwalker = false
        end

    elseif s == MS_WAITFORSCAP then
        if CheckAPCs() then
            -- native break
        else
            if IsUser(M.apc[4]) and Distance(M.apc[4], M.nav) <= 30 then
                M.stateTimer = GetTime() + 5
                M.missionState = MS_WAITSTARTSOUND4
                ResetObjectives()
            end
            -- #if 0 walker_1 "walker_path" start (startwalker): source archive.
            if Distance(M.apc[3], "apc_fail") < 30
                or (Distance(M.apc[4], "trigger_1") < 30 and Distance(M.apc[3], "apc_fail") > 300) then
                FailConvoy()
            end
        end

    elseif s == MS_WAITSTARTSOUND4 then
        if not CheckAPCs() then
            -- #if 0 walker_1 "walker_path" start (startwalker): source archive.
            if ConvoyBroken() then
                FailConvoy()
            elseif M.stateTimer < GetTime() then
                SetScrap(1, 100)
                M.soundHandle = AudioMessage("ch08004.wav")
                M.missionState = MS_DISPLAYOBJ6
                ResetObjectives()
                M.missionState = MS_WAITFORSOUND4

                if Valid(M.apc[3]) then SetObjectiveOn(M.apc[3]) end
                M.apc3objectiveon = true
            end
        end

    elseif s == MS_WAITFORSOUND4 then
        if not CheckAPCs() then
            -- #if 0 walker_1 "walker_path" start (startwalker): source archive.
            if M.apc3objectiveon and Distance(M.apc[3], M.user) < 100 then
                M.apc3objectiveon = false
                if Valid(M.apc[3]) then SetObjectiveOff(M.apc[3]) end
            end

            if ConvoyBroken() then
                FailConvoy()
            elseif Done(M.soundHandle) then
                -- Cut recycler/factory/armory military_spawn block: source archive.
                M.missionState = MS_DISPLAYOBJ1
                ResetObjectives()
                M.missionState = MS_TRIGGER1
            end
        end

    elseif s == MS_TRIGGER1 then
        if not CheckAPCs() then
            if M.apc3objectiveon and Distance(M.apc[3], M.user) < 100 then
                M.apc3objectiveon = false
                if Valid(M.apc[3]) then SetObjectiveOff(M.apc[3]) end
            end

            if ConvoyBroken() then
                FailConvoy()
            elseif IsUser(M.apc[4]) and Distance(M.user, "trigger_1") < 30 then
                AudioMessage("ch08006.wav")
                M.missionState = MS_WAITFORJUMPOUT
                M.stateTimer = GetTime() + 20
            end
        end

    elseif s == MS_WAITFORJUMPOUT then
        if M.stateTimer < GetTime() then
            M.missionState = MS_END
            FailMission(GetTime() + 2.0, "ch08lseg.des")
        elseif not IsUser(M.apc[4]) then
            -- Cut: Goto(walker_1, "walker_return");
            Perceived(2)

            M.missionState = MS_WAITFORWRECKER
            M.stateTimer = GetTime() + 20
            -- Cut: Goto(walker_1, "walker_return");
        end

    elseif s == MS_WAITFORWRECKER then
        if IsUser(M.apc[4]) then
            M.missionState = MS_END
            FailMission(GetTime() + 2.0, "ch08lseg.des")
        elseif M.stateTimer < GetTime() then
            CameraReady()
            M.missionState = MS_BANGCAMERA
            M.stateTimer = GetTime() + 5
        end

    elseif s == MS_BANGCAMERA then
        if Valid(M.apc[4]) then CameraPath("cut_bang", 2000, 0, M.apc[4]) end

        local cameraFinishedRet = CameraCancelled()
        if M.stateTimer < GetTime() or cameraFinishedRet then
            -- PORT FIX: a destroyed apc[4] has no explosion location; skip it.
            -- API ADAPTATION: native chooses xpltrsr when (useD3D & 4) else
            -- xpltrss. The legacy renderer flag is unavailable in Lua; Redux
            -- uses the D3D effect. xpltrss is kept in the source archive.
            Explode("xpltrsr", M.apc[4])

            Explode("xpltrsd", "wrecker_1")
            Perceived(1)

            -- remove mag pull's
            for i = 0, 5 do
                Remove(M.magpull[i])
            end

            M.recycler = BuildObject("cvrecy", 1, "military_spawn")
            GotoPath(M.recycler, "military_path")
            M.factory = BuildObject("cvmuf", 1, "military_spawn")
            GotoPath(M.factory, "military_path")
            GotoPath(BuildObject("cvslf", 1, "military_spawn"), "military_path")
            SetScrap(1, GetMaxScrap(1))

            if cameraFinishedRet then
                CameraFinish()
                M.missionState = MS_DISPODJ5
                ResetObjectives()
                M.missionState = MS_TRIGGERNWNE

                M.stateTimer = GetTime() + (5 * 60)
            else
                M.stateTimer = GetTime() + 5
                M.missionState = MS_BANGCAMERA2
            end
        end

    elseif s == MS_BANGCAMERA2 then
        if Valid(M.apc[4]) then CameraPath("cut_bang", 2000, 0, M.apc[4]) end

        if M.stateTimer < GetTime() or CameraCancelled() then
            CameraFinish()
            M.missionState = MS_DISPODJ5
            ResetObjectives()
            M.missionState = MS_TRIGGERNWNE

            M.stateTimer = GetTime() + (5 * 60)
        end

    elseif s == MS_TRIGGERNWNE then
        if M.stateTimer ~= 0 and M.stateTimer < GetTime() then
            M.stateTimer = 0

            SetScrap(2, 100)

            -- Cut: six svscav on team 2 sent to Hunt from path "scavs".
        end

        local target, triggered
        if Distance(M.user, "nw_trigger") <= 60 then
            target, triggered = M.howitzer_nw, true
        elseif Distance(M.user, "ne_trigger") <= 60 then
            target, triggered = M.howitzer_ne, true
        end
        if triggered then
            AudioMessage("ch08007.wav")
            AudioMessage("ch08008.wav")

            if Valid(M.howitzer_nw) then SetObjectiveOn(M.howitzer_nw) end
            if Valid(M.howitzer_ne) then SetObjectiveOn(M.howitzer_ne) end
            M.howitzerobjectiveon = true
            if Valid(M.west_power) then SetObjectiveOn(M.west_power) end
            if Valid(M.east_power) then SetObjectiveOn(M.east_power) end
            if Valid(M.west_comm) then SetObjectiveOn(M.west_comm) end
            if Valid(M.east_comm) then SetObjectiveOn(M.east_comm) end

            M.missionState = MS_DISPOBJ7
            ResetObjectives()
            M.missionState = MS_DESTROYPOWERS

            if Valid(target) then SetUserTarget(target) end
        end

    elseif s == MS_DESTROYPOWERS then
        local anyDead = M.west_powerDead or M.east_powerDead or M.west_commDead or M.east_commDead
        if anyDead and GetCockpitTimer() < 1 then
            FailMission(GetTime() + 2.0, "ch08lsef.des")
            M.missionState = MS_END
        else
            if M.stateTimer ~= 0 and M.stateTimer < GetTime() then
                M.stateTimer = 0

                SetScrap(2, 50)
            end

            if M.howitzerobjectiveon and (IsUser(M.howitzer_nw) or IsUser(M.howitzer_ne)) then
                M.howitzerobjectiveon = false
                if Valid(M.howitzer_nw) then SetObjectiveOff(M.howitzer_nw) end
                if Valid(M.howitzer_ne) then SetObjectiveOff(M.howitzer_ne) end
            end

            if not M.west_powerDead and not Alive(M.west_power) then
                M.west_powerDead = true

                if not M.east_powerDead and not M.west_commDead and not M.east_commDead then
                    StartCockpitTimer(60 * 4.5)
                end

                -- remove west_mag units...
                for i = 0, 3 do
                    Remove(M.west_mag[i])
                end
                Remove(M.west_bolt)
            end

            if not M.west_commDead and not Alive(M.west_comm) then
                M.west_commDead = true

                if not M.east_powerDead and not M.west_powerDead and not M.east_commDead then
                    StartCockpitTimer(60 * 4.5)
                end
            end

            if not M.east_powerDead and not Alive(M.east_power) then
                M.east_powerDead = true

                if not M.west_powerDead and not M.east_commDead and not M.west_commDead then
                    StartCockpitTimer(60 * 4.5)
                end

                -- remove east_mag units...
                for i = 0, 3 do
                    Remove(M.east_mag[i])
                end
                -- SOURCE BUG KEPT: the east branch removes west_bolt again
                -- (east_bolt is never removed). Not corrected: faithful port.
                Remove(M.west_bolt)
            end

            if not M.east_commDead and not Alive(M.east_comm) then
                M.east_commDead = true

                if not M.east_powerDead and not M.west_powerDead and not M.west_commDead then
                    StartCockpitTimer(60 * 4.5)
                end
            end

            if M.west_powerDead and M.east_powerDead and M.west_commDead and M.east_commDead then
                HideCockpitTimer()
                M.missionState = MS_DISPOBJ2
                ResetObjectives()
                M.missionState = MS_WRECKER10
                M.stateTimer = GetTime() + 40
                -- Cut: soundHandle = AudioMessage("ch08008.wav") and the
                -- MS_WAITFORSOUND8 hand-off: source archive.
            end
        end

    elseif s == MS_WAITFORSOUND8 then
        -- Unreachable in source (only entered by the cut block above).
        if Done(M.soundHandle) then
            M.missionState = MS_DESTROYTOWERS
            StartCockpitTimer(60 + 40)
        end

    elseif s == MS_DESTROYTOWERS then
        -- Unreachable in source (only entered via MS_WAITFORSOUND8).
        if GetCockpitTimer() < 1 then
            FailMission(GetTime() + 2.0, "ch08lsef.des")
            M.missionState = MS_END
        elseif not Alive(M.west_comm) and not Alive(M.east_comm) then
            HideCockpitTimer()
            M.missionState = MS_WRECKER10
            ResetObjectives()
            M.stateTimer = GetTime() + 10
        end

    elseif s == MS_WRECKER10 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_1")
            Explode("xpltrsd", "day_1a")
            M.stateTimer = GetTime() + 12
            M.missionState = MS_WRECKER22
        end

    elseif s == MS_WRECKER22 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_2")
            Explode("xpltrsd", "day_2a")
            M.stateTimer = GetTime() + 11
            M.missionState = MS_WRECKER33
        end

    elseif s == MS_WRECKER33 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_3")
            M.stateTimer = GetTime() + 9
            M.missionState = MS_WRECKER42
        end

    elseif s == MS_WRECKER42 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_4")
            Explode("xpltrsd", "day_4a")
            M.stateTimer = GetTime() + 13
            M.missionState = MS_WRECKER55
        end

    elseif s == MS_WRECKER55 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_5")
            Explode("xpltrsd", "day_5a")
            M.stateTimer = GetTime() + 15
            M.missionState = MS_WRECKER70
        end

    elseif s == MS_WRECKER70 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_6")
            M.stateTimer = GetTime() + 15
            M.missionState = MS_WRECKER85
        end

    elseif s == MS_WRECKER85 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_7")
            Explode("xpltrsd", "day_7a")
            M.stateTimer = GetTime() + 7
            M.missionState = MS_WRECKER92
        end

    elseif s == MS_WRECKER92 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_8")
            Explode("xpltrsd", "day_8a")
            M.stateTimer = GetTime() + 8
            M.missionState = MS_WRECKER100
        end

    elseif s == MS_WRECKER100 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_9")
            Explode("xpltrsd", "day_9a")
            M.stateTimer = GetTime() + 6
            M.missionState = MS_WRECKER106
        end

    elseif s == MS_WRECKER106 then
        if M.stateTimer < GetTime() then
            Explode("xpltrsd", "day_10")
            AudioMessage("ch08009.wav")
            M.missionState = MS_END

            ResetObjectives()
            SucceedMission(GetTime() + 10.0, "ch08win.des")
            -- Native comment: "play avi..." (no call exists).
        end
    end

    CheckSpawns()

    M.olduser = M.user
end

function Save()
    return M
end
function Load(state)
    -- LuaMission serializes tables and engine handles; do not rerun Start or
    -- replay spawns/cameras/audio on load. Zero-based arrays remain intact.
    M = state
end
-- CR co-op callbacks >>
-- The body is never edited: the runtime's per-frame calls wrap its callbacks here.
local BodyStart, BodyAddObject, BodyUpdate, BodySave, BodyLoad = Start, AddObject, Update, Save, Load
-- Restore the real environment now that the faithful functions above are safely captured by value: every
-- entry point below must land in the real global table so the host engine's lua_getglobal finds it, exactly
-- like every other mission's Start/Update/Save/Load (see the "CR co-op runtime" comment above for why).
setfenv(1, RealEnv)
function Start()
    BodyStart()
    if campaignRuntime then campaignRuntime.Start() end
end
function AddObject(h)
    BodyAddObject(h)
    if campaignRuntime then return campaignRuntime.AddObject(h) end
end
function Update(dt)
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
    BodyUpdate(dt)
    if campaignRuntime then campaignRuntime.AfterUpdate() end
end
function Save()
    if campaignRuntime then campaignRuntime.Save() end
    return BodySave()
end
function Load(state)
    BodyLoad(state)
    if campaignRuntime then
        campaignRuntime.Load()
        -- ResetObjectives is the faithful body's own rebuild; a load never replays spawns, cameras or
        -- audio (Docs/CH08_LUA_PORT.md), so the objective panel must be rebuilt from missionState alone.
        ResetObjectives()
    end
end
function CreatePlayer(id, name, team) if campaignRuntime then return campaignRuntime.CreatePlayer(id, name, team) end end
function AddPlayer(id, name, team) if campaignRuntime then return campaignRuntime.AddPlayer(id, name, team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from, kind, ...) if campaignRuntime then return campaignRuntime.Receive(from, kind, ...) end end
-- CR co-op callbacks <<
