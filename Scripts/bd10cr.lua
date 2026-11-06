-- Faithful BlackDog10Mission port for stock BZR / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog10Mission.cpp
-- Source blob: a1b4f90298b15f8c622f920e90ab5603c672b72e.
-- Full native source, including declarations, comments and serialization:
-- References/BlackDog10Source/BlackDog10Mission.cpp.
-- No EXU/OpenShim or campaign helper is required. C++ array indexes are
-- translated to Lua's 1-based indexes; commands, timings and order are retained.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN10_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Elysium weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn10CoopSourceParity.py).
-- CR co-op layer <<

local DISABLED_TIME = 999999.9
local defences = { "defend_a", "defend_b", "defend_c", "defend_d" }
local defenceUnits = {
    { "cvtnk", "cvtnk", "cvltnk", "cvltnk", "cvfigh", "cvfigh" },
    { "cvfigh", "cvfigh", "cvfigh", "cvwalk", "cvhtnk", "cvtnk" },
    { "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", "cvwalk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk", "cvtnk", "cvtnk", "cvwalk" },
}
local patrols = { "patrol_a", "patrol_b", "patrol_c", "patrol_d" }
local patrolUnits = {
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
}

local function NewState()
    -- Native Load initializes all members, including Setup's untouched flags.
    -- Handles and audio messages use nil instead of native NULL/0.
    return {
        startDone = false, objective1Complete = false,
        cameraReady = { false, false, false },
        cameraComplete = { false, false, false }, arrived = false,
        apcSpawned = false, recyclerSpawned = false,
        defencesSpawned = { false, false, false, false },
        patrolsSpawned = { false, false, false, false },
        lost = false, won = false, -- unused in source; no new defeat/win gates
        navDelay = DISABLED_TIME, apcDelay = DISABLED_TIME,
        apcCameraTimeout = DISABLED_TIME, cameraTime = DISABLED_TIME,
        destroy = {},
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN10_COOP.md lists every wrapped call and restoration.
-- RESTORED_FACTORY_OBJECTIVES switches the unused "Factory 1..6" objectives and target markers off.
local RESTORED_FACTORY_OBJECTIVES = true
local Restored
-- Every Chinese combat craft of the eight ambushes becomes a concealed, head-count-scaled ticket.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true, cvwalk = true, cvhtnk = true }
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn10", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "backup" }, -- no base exists: respawn at the Black Dog drop zone
    scaledOdfs = SCALED_ODFS,
    -- The ambush fires at 400 m, so the concealment radius is smaller than the runtime default (460 m): an
    -- ambush whose spot has a human within 350 m waits (saved in M.crcca) until it is clear.
    safeRadius = 350,
    liveCap = 20, -- up to eight ambushes of five to eight hunters, plus two extras per ambush
    scrapPerGuest = 10,
    -- No failDes: the game ships no bd10 loss debrief (only out of lives fails, the mission has no loss of its own).
    wonFlags = { "crFinale" },
    endedFlags = { "crFinale" },
    orders = { "Hunt" }, -- the only order the body gives to units that may still be tickets
    -- Elysium: the Venus engine in its Earth-like storm dress (Docs/BDMISN10_COOP.md, "Weather: Elysium").
    weather = { module = "CRElysiumWeather", sites = "CRElysiumSitesBD10", startLevel = 1, targetLevel = 2,
        beats = function(elysium, state, s)
            local beats = s.elysiumBeats
            if beats == nil then beats = { sprung = {}, down = {}, pos = {} }; s.elysiumBeats = beats end
            local function strikeAt(pos)
                if pos then elysium.TriggerStrike({ x = pos.x, y = pos.y, z = pos.z }) end
            end
            local function strikePath(path)
                local ok, pos = pcall(GetPosition, path)
                if ok then strikeAt(pos) end
            end
            -- Every ambush that springs arrives under a strike on its spot.
            local sprung = 0
            for i = 1, 4 do
                if state.defencesSpawned[i] then
                    sprung = sprung + 1
                    if not beats.sprung["d" .. i] then beats.sprung["d" .. i] = true; strikePath(defences[i]) end
                end
                if state.patrolsSpawned[i] then
                    sprung = sprung + 1
                    if not beats.sprung["p" .. i] then beats.sprung["p" .. i] = true; strikePath(patrols[i]) end
                end
            end
            -- Each of the six key buildings goes down under a strike on its ruins.
            local down = 0
            for i = 1, 6 do
                local h = state.destroy[i]
                if h ~= nil and h ~= 0 and IsValid(h) and GetHealth(h) > 0.0 then
                    local p = GetPosition(h)
                    beats.pos[i] = { x = p.x, y = p.y, z = p.z }
                elseif beats.pos[i] and not beats.down[i] then
                    beats.down[i] = true
                    strikeAt(beats.pos[i])
                end
                if beats.down[i] then down = down + 1 end
            end
            -- The Chinese move on the drop zone and take the Recycler: lightning over the Black Dog landing.
            if state.apcSpawned and not beats.apc then beats.apc = true; strikePath("recycler") end
            if state.recyclerSpawned and not beats.recycler then beats.recycler = true; strikePath("recycler") end
            local want = 2
            if sprung >= 1 then want = 3 end
            if sprung >= 4 or down >= 3 then want = 4 end
            if state.apcSpawned then want = 5 end
            -- "Pull back": the storm eases for the debrief.
            if state.crFinale then want = 4 end
            if beats.level ~= want then
                beats.level = want
                elysium.SetTargetLevel(want)
            end
        end },
    hooks = {
        load = function() if Restored then Restored.OnLoad() end end,
    },
})
local NativeGetNearestUnitOnTeam = GetNearestUnitOnTeam
local Hunt = campaignRuntime and campaignRuntime.Hunt or Hunt
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local StopAudioMessage = campaignRuntime and function(message)
    if message == nil or message == 0 then return end
    return campaignRuntime.StopAudioMessage(message)
end or StopAudioMessage
-- A failed AudioMessage yields 0, never nil: the body's gate (`navSound ~= nil and done`) must still open.
local AudioMessage = campaignRuntime and function(file)
    return campaignRuntime.AudioMessage(file) or 0
end or AudioMessage
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever.
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
-- A cancel counts as a host skip only when it was raised after the shot began.
local shotStale = false
local CameraReady = campaignRuntime and function()
    shotStale = campaignRuntime.Native.CameraCancelled() and true or false
    return campaignRuntime.CameraReady()
end or CameraReady
-- The opening ends when the shot arrives. The runtime stops driving a shot the host skipped (it releases only the
-- host's own camera), so in a network game that shot would never arrive and the intro behind it would stall for
-- everyone: a host skip ends the shot instead.
local CameraPath = campaignRuntime and function(path, height, speed, target)
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if not arrived and not shotStale and campaignRuntime.Coop.IsNetworkGame()
        and campaignRuntime.Native.CameraCancelled() then return true end
    return arrived
end or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool).
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
    end
    return SetPilot(team, count)
end or SetPilot
-- The ambushers are tickets, and a new scripted ambush (a new frame or a new spot) is a new scaling event: the
-- first unit of each ambush is mirrored by min(floor(humans / 2), 2) extras with its orders.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where)
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- "The closest Black Dog unit": the body asks for team 1 only; humans are teams 1-4, so ask all four.
local GetNearestUnitOnTeam = campaignRuntime and function(where, point, team)
    if team ~= 1 then return NativeGetNearestUnitOnTeam(where, point, team) end
    local best, bestDistance
    for humanTeam = 1, 4 do
        local h = NativeGetNearestUnitOnTeam(where, point, humanTeam)
        if h ~= nil and h ~= 0 and IsValid(h) then
            local distance = GetDistance(h, where)
            if bestDistance == nil or distance < bestDistance then best, bestDistance = h, distance end
        end
    end
    return best
end or GetNearestUnitOnTeam
-- CR co-op runtime <<
-- CR restored content >>
-- The co-op fixes that need state and the unused "Factory 1..6" objectives (Docs/BDMISN10_COOP.md lists each).
-- The objectives are gated by RESTORED_FACTORY_OBJECTIVES.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local FACTORY_OTFS = { "bd10002.otf", "bd10003.otf", "bd10004.otf", "bd10005.otf", "bd10006.otf", "bd10007.otf" }
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
    -- The body's own test of a target: missing, deleted or zero health counts as destroyed.
    local function TargetDown(i)
        local h = M.destroy[i]
        return not (Valid(h) and GetHealth(h) > 0.0)
    end
    local function Publish()
        ClearObjectives()
        AddObjective("bd10001.otf", (RESTORED_FACTORY_OBJECTIVES and M.objective1Complete) and "green" or "white")
        if RESTORED_FACTORY_OBJECTIVES then
            for i = 1, 6 do AddObjective(FACTORY_OTFS[i], TargetDown(i) and "green" or "white") end
        end
    end
    local function Mark()
        for i = 1, 6 do
            if not TargetDown(i) then runtime.SetObjectiveOn(M.destroy[i]) end
        end
    end
    function Restored.OnLoad()
        RState().afterLoad = true
    end
    -- A load cannot resume a camera (the shots are gone): a shot that was running opens its camera again and
    -- the body ends it itself. The runtime's Load resets the presentation: objectives and markers come back.
    function Restored.AfterLoad(r)
        for i = 1, 3 do
            if M.cameraReady[i] and not M.cameraComplete[i] then CameraReady() end
        end
        r.sig, r.marked = nil, nil
        if not RESTORED_FACTORY_OBJECTIVES then Publish() end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad(r) end
        -- The finale has begun: a late out-of-lives failure is ignored and nothing more is built.
        if M.cameraComplete[3] then M.crFinale = true end
        if not RESTORED_FACTORY_OBJECTIVES then return end
        if not r.marked then r.marked = true; Mark() end
        local sig = M.objective1Complete and "1" or "0"
        for i = 1, 6 do sig = sig .. (TargetDown(i) and "1" or "0") end
        if r.sig ~= sig then
            r.sig = sig
            Publish()
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn10] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<

function Start()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    -- setup handles; one-shot resources/objectives still run in first Update.
    for i = 1, 6 do
        M.destroy[i] = GetHandle("destroy_" .. i)
    end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

local function checkAmbush(distance, spawn_spot, spawned, units)
    -- if we're already spawned, then leave
    if spawned then return true end
    -- Path overload: path, point, team (same order as the native call).
    local h = GetNearestUnitOnTeam(spawn_spot, 0, 1)
    if h == nil or h == 0 then return false end
    -- is the closest unit close enough?
    if GetDistance(h, spawn_spot, 0) < distance then
        -- yep, spawn the units (the native NULL terminator becomes table end).
        for i = 1, #units do
            local unit = BuildObject(units[i], 2, spawn_spot)
            Hunt(unit)
        end
        return true
    end
    return false
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    if not M.startDone then
        SetScrap(1, 100) -- we start with 100 scrap
        SetScrap(2, 0) -- enemy starts with 0 scrap
        SetPilot(1, 10)
        -- setup the initial objectives
        ClearObjectives()
        AddObjective("bd10001.otf", "white")
        -- don't do this part after the first shot
        M.startDone = true
    end

    -- should we spawn the defences?
    for i = 1, 4 do
        M.defencesSpawned[i] = checkAmbush(400.0, defences[i],
            M.defencesSpawned[i], defenceUnits[i])
    end
    -- how about the patrols?
    for i = 1, 4 do
        M.patrolsSpawned[i] = checkAmbush(400.0, patrols[i],
            M.patrolsSpawned[i], patrolUnits[i])
    end

    if not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.introSound = AudioMessage("bd10001.wav")
            M.cameraReady[1] = true
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("camera_start", 3000, 2000, M.destroy[4])
        end
        if M.arrived and IsAudioMessageDone(M.introSound)
            and M.cameraTime == DISABLED_TIME then
            M.cameraTime = GetTime() + 2.0
        end
        if M.cameraTime < GetTime() then seqDone = true end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.introSound)
        end
        if seqDone then
            CameraFinish()
            M.cameraComplete[1] = true
        end
    end

    if not M.objective1Complete then
        -- have we killed all the "destroy" units? assume we have
        M.objective1Complete = true
        for i = 1, 6 do
            local h = M.destroy[i]
            -- PORT FIX: Lua NULL is nil, not a native null Handle. Avoid passing
            -- missing/deleted objects to the health overload. They count as
            -- zero health as in native code; surviving targets still block
            -- completion, so valid-map gameplay and the six-target gate match.
            if h ~= nil and h ~= 0 and IsValid(h) and GetHealth(h) > 0.0 then
                -- nope, not yet
                M.objective1Complete = false
                break
            end
        end
        if M.objective1Complete then M.navDelay = GetTime() + 10.0 end
    end

    if M.objective1Complete and M.navDelay < GetTime() then
        M.navDelay = DISABLED_TIME
        -- spawn the nav beacon
        BuildObject("apcamr", 1, "navcam_end")
        -- start the sound
        M.navSound = AudioMessage("bd10002.wav")
    end
    if M.objective1Complete and M.navSound ~= nil
        and IsAudioMessageDone(M.navSound) then
        M.navSound = nil
        M.apcDelay = GetTime() + 5.0
    end
    if M.objective1Complete and M.apcDelay < GetTime() then
        M.apcDelay = DISABLED_TIME
        -- spawn the APC
        M.apcSpawned = true
        M.apc = BuildObject("bvapc", 1, "apc")
        Goto(M.apc, "apc_path", 1)
        -- spawn the portal
        BuildObject("cbport", 0, "portal")
    end

    if M.apcSpawned and not M.cameraComplete[2] then
        if not M.cameraReady[2] then
            -- get the camera ready
            CameraReady()
            M.cameraReady[2] = true
            M.apcCameraTimeout = GetTime() + 7.0
        end
        CameraPath("camera_apc", 30, 200, M.apc)
        if M.apcCameraTimeout < GetTime() or CameraCancelled() then
            CameraFinish()
            M.cameraComplete[2] = true
            M.apcCameraTimeout = DISABLED_TIME
        end
    end

    if M.cameraComplete[2] and not M.recyclerSpawned then
        M.recyclerSpawned = true
        M.recycler = BuildObject("bvrecy", 1, "recycler")
        Goto(M.recycler, "recycler_path", 1)
        for i = 1, 6 do
            local h = BuildObject("cvtnka", 1, "capture")
            SetIndependence(h, 0)
            Follow(h, M.recycler, 1)
        end
    end

    if M.recyclerSpawned and not M.cameraComplete[3] then
        if not M.cameraReady[3] then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.winSound = AudioMessage("bd10003.wav")
            M.cameraReady[3] = true
            M.arrived = false
            M.cameraTime = GetTime() + 10.0
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("camera_end", 30, 200, M.recycler)
        end
        if IsAudioMessageDone(M.winSound) and M.cameraTime < GetTime() then
            seqDone = true
        end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.winSound)
        end
        if seqDone then
            --CameraFinish();
            -- Source intentionally leaves the final camera active until the
            -- one-second victory transition; preserve this cut/disabled line.
            M.cameraComplete[3] = true
            SucceedMission(GetTime() + 1.0, "bd10win.des")
        end
    end
-- CR restored content >>
    if campaignRuntime then Restored.Run() end
-- CR restored content <<
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.AfterUpdate() end
-- CR co-op callback <<
end

function Save()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Save() end
-- CR co-op callback <<
    return M
end

function Load(state)
    -- LuaMission serializes tables and engine handles/audio messages. Native
    -- PostLoad/ConvertHandle has no Lua equivalent to call. Do not rerun Setup,
    -- replay audio, reset timers or spawn already-created waves after loading.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
function AddObject(h) if campaignRuntime then return campaignRuntime.AddObject(h) end end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
