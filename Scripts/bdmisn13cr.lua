-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN13_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port, byte for byte (Tools/Test-Bdmisn13CoopSourceParity.py).
-- CR co-op layer <<
-- Faithful BlackDog13Mission port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog13Mission.cpp
-- Source blob: ac9bdec108f18a8d5ad933353ebd612fc156da34.
-- Complete source, including comments/declarations/native serialization:
-- References/BlackDog13Source/BlackDog13Mission.cpp.
-- No executable commented-out code occurs in this source revision.
-- No EXU/OpenShim or campaign helper is required; stock Redux 2.1+ is needed
-- for IsRecycledByTeam. C++ array indices below are translated to 1-based Lua.

local DISABLED_TIME = 999999.9
local waveUnits = {
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvltnk", "cvtnk" },
    { "cvrckt", "cvrckt", "cvltnk", "cvltnk", "cvtnk", "cvtnk" },
    { "cvhraz", "cvhraz", "cvhraz", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvhtnk", "cvhtnk" },
}
local defenderUnits = {
    { "cvfigh", "cvfigh", "cvltnk", "cvltnk" },
    { "cvltnk", "cvltnk", "cvltnk", "cvltnk" },
    { "cvfigh", "cvfigh", "cvrckt", "cvrckt" },
    { "cvtnk", "cvtnk", "cvltnk", "cvltnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh" },
    { "cvhtnk", "cvhtnk", "cvfigh", "cvfigh" },
}

local function NewState()
    -- Native Load initializes all members before Setup, including unused ones.
    -- Handles/audio messages use nil in place of native NULL; unused handles
    -- user and lastUser and sound1/3/4/5 are initially absent table entries.
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        cameraReady = { false, false }, cameraComplete = { false, false },
        defendersSpawned = { false, false, false, false, false, false },
        recycled = { false, false, false, false, false, false },
        silosRecycled = false, recycleChecked = false, sound2Played = false,
        arrived = false, lost = false, won = false,
        wave1Time = DISABLED_TIME, wave2Time = DISABLED_TIME,
        wave3Time = DISABLED_TIME, wave4Time = DISABLED_TIME,
        silos = {}, scrapValue = 0, lastScrapValue = 0,
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN13_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/BDMISN13_COOP.md, "Restored content").
local RESTORED_SILO_LOSS_VOICE = true -- the unused bd13006 reprimand when a silo is destroyed instead of recycled
local RESTORED_EARLY_STRIKE_VOICE = true -- the unused bd13007 warning when the Chinese base is hit before the silos
local Restored = {}
-- Every Chinese combat craft of the four waves and the six silo guards is a concealed, head-count-scaled ticket.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true, cvrckt = true, cvhraz = true, cvhtnk = true }
local sensorsBound = false
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn13", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared base is wherever the recycler is
    scaledOdfs = SCALED_ODFS,
    -- A wave or a guard whose authored entry has a human within 460 m comes from the next hidden approach instead.
    fallbackEntries = { "spawn_defend5", "spawn_defend2", "spawn_defend7", "spawn_defend8" },
    liveCap = 60, -- 24 guards stay out for the whole mission and four waves of 6-9 arrive on top of them
    scrapPerGuest = 10,
    -- No failDes: the game ships no bd13 generic loss debrief (the DLL names only its four causes).
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- Ganymede: CREuropaWeather over the generated BD13 sites (fifteen geysers: the Black Dog base, the Chinese base
    -- and the scrap fields between them).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD13", startLevel = 1, targetLevel = 1,
        -- Ganymede under Jupiter: the sun's real path, a short eclipse, Jupiter-shine at night.
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.europaBeats
            if beats == nil then beats = {}; s.europaBeats = beats end
            local function plume(label)
                for index, site in ipairs(europa.GetVentSites()) do
                    if site.label == label then return europa.TriggerPlume(index) end
                end
            end
            local function sent(wave) return state.startDone and state["wave" .. wave .. "Time"] >= 999999.0 end
            local seized = 0
            for i = 1, 6 do if state.recycled and state.recycled[i] then seized = seized + 1 end end
            -- The first silo is seized: the Chinese scrap flow is cut and the ice answers.
            if (not beats.first) and seized >= 1 then
                beats.first = true
                europa.Surge(3.0, 0.4)
            end
            -- Wave one (3:00) hits the Black Dog base: the moon stirs and a vent opens under the base.
            if (not beats.wave1) and sent(1) then
                beats.wave1 = true
                europa.SetTargetLevel(2)
                plume("eggeizr10_geyser")
            end
            -- Wave two (10:00): the ice shell flexes.
            if (not beats.wave2) and sent(2) then
                beats.wave2 = true
                europa.SetTargetLevel(3)
                europa.Quake(0.35, 3.0)
            end
            -- The heavy third wave (15:00): another vent under the base, Jupiter's radiation surges.
            if (not beats.wave3) and sent(3) then
                beats.wave3 = true
                europa.Surge(5.0, 0.7)
                plume("eggeizr11_geyser")
            end
            -- The last wave (30:00): the worst of the sky.
            if (not beats.wave4) and sent(4) then
                beats.wave4 = true
                europa.SetTargetLevel(4)
                europa.Quake(0.5, 3.5)
                europa.Surge(5.0, 0.9)
            end
            -- Every silo is in Black Dog hands ("take down that Recycler"): the Chinese base geysers vent.
            if (not beats.seized) and state.silosRecycled then
                beats.seized = true
                europa.Surge(6.0, 0.8)
                europa.Quake(0.35, 3.0)
                plume("eggeizr1146_geyser")
                plume("eggeizr1147_geyser")
                plume("eggeizr1148_geyser")
            end
            -- The deadline passes and the order to nuke Ganymede is given: the worst the sky can do.
            if (not beats.nuke) and state.lost and state.recycleChecked and not state.silosRecycled then
                beats.nuke = true
                europa.SetTargetLevel(4)
                europa.Quake(0.7, 5.0)
                europa.Surge(8.0, 1.0)
                for index = 1, #europa.GetVentSites() do europa.TriggerPlume(index) end
            end
            -- The Chinese recycler falls: calm for the debrief.
            if (not beats.easing) and state.won then
                beats.easing = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
        end },
    hooks = {
        start = function() sensorsBound = false end,
        -- The weather director slows radar and scrambles velocity jammers as it intensifies (every peer).
        update = function(runtime)
            if not sensorsBound and runtime.Weather then
                sensorsBound = true
                require("Environment").BindWeatherSensors("Ganymede", runtime.Weather.module)
            end
        end,
        load = function() if Restored.OnLoad then Restored.OnLoad() end end,
    },
})
local NativeIsRecycledByTeam, NativeIsAudioMessageDone, NativeGetCockpitTimer = IsRecycledByTeam, IsAudioMessageDone, GetCockpitTimer
local PLAYERS = campaignRuntime and campaignRuntime.PLAYERS
-- The body's "player" (M.user) is the runtime's nearest-human token; its only use is the distance to a silo.
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local GetDistance = campaignRuntime and campaignRuntime.WrapDistance(GetDistance) or GetDistance
local IsValid = campaignRuntime and function(h)
    if h == PLAYERS then return true end
    return campaignRuntime.IsValid(h)
end or IsValid
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool); the Chinese are team 2 in the DLL and team 5 here.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
-- Scaled spawns and their orders: the runtime keeps a ticket for each (Restored.Scale opens the scaling events).
local BuildObject = campaignRuntime and function(odf, team, where)
    Restored.Scale(where)
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
-- Any human team recycling a silo counts: the body asks team 1 only, which in co-op is just the host.
local IsRecycledByTeam = campaignRuntime and function(h, team)
    if team ~= 1 then return NativeIsRecycledByTeam(h, team) end
    local recycled = false
    campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam)
        if not recycled and NativeIsRecycledByTeam(h, humanTeam) then recycled = true end
    end)
    return recycled
end or IsRecycledByTeam
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever; the gates test
-- `sound ~= nil`, so a line that returns no handle becomes 0 (finished) rather than nil (never played).
local IsAudioMessageDone = campaignRuntime and function(message)
    if message == nil or message == 0 then return true end
    return NativeIsAudioMessageDone(message)
end or IsAudioMessageDone
local AudioMessage = campaignRuntime and function(file)
    local handle = campaignRuntime.AudioMessage(file)
    if handle == nil then return 0 end
    return handle
end or AudioMessage
local StopAudioMessage = campaignRuntime and function(message)
    if message == nil or message == 0 then return end
    return campaignRuntime.StopAudioMessage(message)
end or StopAudioMessage
-- The intro ends when its shot arrives. The runtime stops driving a shot the host skipped (it releases only the
-- host's own camera), so in a network game that shot would never arrive and the intro would hang for everyone: a
-- skip that rises after the shot began ends the shared shot (the briefing line still gates the end). A cancel
-- still latched when the shot begins is not a skip of this shot, so it is sampled when the shot opens.
local shotLatched = false
local CameraReady = campaignRuntime and function()
    shotLatched = campaignRuntime.Native.CameraCancelled() and true or false
    return campaignRuntime.CameraReady()
end or CameraReady
local CameraPath = campaignRuntime and function(path, height, speed, target)
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if arrived or not campaignRuntime.Coop.IsNetworkGame() then return arrived end
    if not campaignRuntime.Native.CameraCancelled() then
        shotLatched = false
    elseif not shotLatched then
        return true
    end
    return arrived
end or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
-- The cockpit countdown is presentation: every peer shows the host's timer. The engine cannot keep the clock (the
-- map runs MultSTMission, which restarts the cockpit timer upward every frame, so the 45 minutes never run out),
-- so the host counts them itself (saved with the mission state).
local StartCockpitTimer = campaignRuntime and function(seconds, warn, alert)
    Restored.TimerStart(seconds, warn, alert)
    return campaignRuntime.Present("StartCockpitTimer", seconds, warn, alert)
end or StartCockpitTimer
local HideCockpitTimer = campaignRuntime and function()
    Restored.TimerHide()
    return campaignRuntime.Present("HideCockpitTimer")
end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
-- The two losses the DLL leaves silent (silos destroyed, Chinese base hit first) play their unused voice line
-- before the debrief; every other debrief is untouched.
local FailMission = campaignRuntime and function(when, description)
    if Restored.FailLine(description) then return end
    return campaignRuntime.FailMission(when, description)
end or FailMission
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Health(h)
    -- PORT FIX: native absent-object health is zero. Guard nil/deleted handles
    -- before Lua's health overload, preserving every native zero-health gate.
    -- Living-object values and mission ordering are unchanged.
    if not Valid(h) then return 0.0 end
    return GetHealth(h)
end

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/BDMISN13_COOP.md quotes the cut block), plus the
-- co-op fixes that need state. Each restoration is gated by a RESTORED_* flag.
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function Done(sound)
        return sound == nil or sound == 0 or IsAudioMessageDone(sound)
    end

    -- ---------------------------------------------------------------- scaling events
    -- The runtime mirrors the first scaled unit of an event with min(floor(humans / 2), 2) extras. A wave is one
    -- event (all its units are built in one frame from one path); the six guard groups are built in one frame too,
    -- four units each, so every fourth guard build opens the next group's event.
    local waveEvent, guards = false, 0
    function Restored.NewFrame() waveEvent, guards = false, 0 end
    function Restored.Scale(where)
        if where == "spawn_attack_waves" then
            if not waveEvent then
                waveEvent = true
                runtime.BeginEvent()
            end
        elseif where == "spawn_defend1" or where == "spawn_defend6" then
            if guards % 4 == 0 then runtime.BeginEvent() end
            guards = guards + 1
        end
    end

    -- ---------------------------------------------------------------- the 45 minutes
    function Restored.TimerStart(seconds, warn, alert)
        local r = RState()
        r.timerEnd, r.timerWarn, r.timerAlert = GetTime() + seconds, warn, alert
    end
    function Restored.TimerHide() RState().timerEnd = nil end
    function Restored.TimerLeft()
        local finish = RState().timerEnd
        if finish ~= nil then return math.max(0, finish - GetTime()) end
        return NativeGetCockpitTimer()
    end

    -- ---------------------------------------------------------------- loads
    -- A load cannot resume a cinematic (the camera is gone): the intro that was running is ended, as the body would
    -- on arrival; its objective is published by AfterLoad.
    function Restored.OnLoad()
        if not runtime.Coop.IsAuthority() then return end
        RState().afterLoad = true
        if M.cameraReady[1] and not M.cameraComplete[1] then
            M.sound1 = nil
            M.arrived = true
            M.cameraComplete[1] = true
        end
    end
    -- The runtime's Load resets the presentation (objective list, nav names, timer) and the body publishes them only
    -- when a stage begins. Republish what the current stage shows, with the body's own names and colours.
    function Restored.AfterLoad(r)
        for i = 1, 6 do
            local h = GetHandle("nav_chin_silo" .. i)
            if Valid(h) then SetObjectiveName(h, "Scrap Field") end
        end
        ClearObjectives()
        if M.silosRecycled and M.sound2Played then
            AddObjective("bd13001.otf", "green")
            AddObjective("bd13002.otf", "white")
        else
            AddObjective("bd13001.otf", "white")
        end
        if r.timerEnd ~= nil then
            local remaining = r.timerEnd - GetTime()
            if remaining > 0 then
                runtime.Present("StartCockpitTimer", remaining, r.timerWarn or 30, r.timerAlert or 10)
            end
        end
    end

    -- ---------------------------------------------------------------- unused voice lines
    -- Cut: no line of the DLL plays bd13006 or bd13007. The two losses that have a debrief but no voice are the ones
    -- they were recorded for: a destroyed silo (bd13lsec: "recycle the Chinese silos, not destroy them") and a hit on
    -- the Chinese base before the silos are held (bd13lsed: "you attacked the Chinese base before dealing with the
    -- silos"). The line plays first and the debrief follows it, like the DLL's other three losses.
    local FAIL_LINES = {
        ["bd13lsec.des"] = { "bd13006.wav", RESTORED_SILO_LOSS_VOICE },
        ["bd13lsed.des"] = { "bd13007.wav", RESTORED_EARLY_STRIKE_VOICE },
    }
    -- True when the failure is held back for its line (the body's repeated calls for the same loss are swallowed).
    function Restored.FailLine(description)
        local entry = FAIL_LINES[description]
        if entry == nil or not entry[2] or M.won then return false end
        local r = RState()
        if r.failLine == nil then
            r.failLine = { description = description, sound = AudioMessage(entry[1]) }
        end
        return true
    end
    function Restored.FailStep(r)
        local pending = r.failLine
        if pending ~= nil and Done(pending.sound) then
            r.failLine = nil
            runtime.FailMission(GetTime() + 1.0, pending.description)
        end
    end

    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad and M.cameraComplete[1] then r.afterLoad = nil; Restored.AfterLoad(r) end
        Restored.FailStep(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn13] restored content failed: " .. tostring(err))
        end
    end
    function Restored.BeforeRun() Restored.NewFrame() end
end
-- CR restored content <<
function Start()
    assert(type(IsRecycledByTeam) == "function",
        "bdmisn13 requires stock Redux 2.1+ IsRecycledByTeam")
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    -- units
    M.recycler = GetHandle("recycler")
    M.chinRecycler = GetHandle("chin_recycler")
    for i = 1, 6 do M.silos[i] = GetHandle("chin_silo" .. i) end
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
    if campaignRuntime then Restored.BeforeRun() end
-- CR co-op callback <<
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 30)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        M.wave1Time = GetTime() + 3 * 60.0
        M.wave2Time = GetTime() + 10 * 60.0
        M.wave3Time = GetTime() + 15 * 60.0
        M.wave4Time = GetTime() + 30 * 60.0
        StartCockpitTimer(45 * 60, 30, 10)
        -- label the navs
        for i = 1, 6 do
            local h = GetHandle("nav_chin_silo" .. i)
            if Valid(h) then SetObjectiveName(h, "Scrap Field") end
        end
    end

    M.lastScrapValue = M.scrapValue
    M.scrapValue = GetScrap(1)

    if not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            CameraReady()
            M.cameraReady[1] = true
            M.sound1 = AudioMessage("bd13001.wav")
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("camera_intro", 500, 1500, M.silos[6])
        end
        if M.arrived and IsAudioMessageDone(M.sound1) then seqDone = true end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.sound1)
        end
        if seqDone then
            M.cameraComplete[1] = true
            CameraFinish()
            ClearObjectives()
            AddObjective("bd13001.otf", "white")
        end
    end

    for wave = 1, 4 do
        local key = "wave" .. wave .. "Time"
        if M[key] < GetTime() then
            M[key] = DISABLED_TIME
            for i = 1, #waveUnits[wave] do
                local h = BuildObject(waveUnits[wave][i], 2, "spawn_attack_waves")
                Goto(h, M.recycler, 1)
            end
        end
    end

    for i = 1, 6 do
        -- Source: !defendersSpawned[i] && GetDistance(user, silos[i]).
        -- C++ converts zero to false; Lua treats zero as true, so compare
        -- explicitly. No threshold was supplied: retain every nonzero distance,
        -- including the source's immediate spawns on a normal map start.
        -- Missing handles skip distance binding; valid-map behavior is unchanged.
        if not M.defendersSpawned[i] and Valid(M.user) and Valid(M.silos[i])
            and GetDistance(M.user, M.silos[i]) ~= 0 then
            M.defendersSpawned[i] = true
            for unit = 1, 4 do
                -- All six groups really use spawn_defend1 and spawn_defend6.
                local path = unit <= 2 and "spawn_defend1" or "spawn_defend6"
                local h = BuildObject(defenderUnits[i][unit], 2, path)
                Defend2(h, M.silos[i])
            end
        end
    end

    -- Keep deadline check before this frame's silo checks, as in native code.
    if not M.recycleChecked and GetCockpitTimer() <= 0.0 and not M.lost and not M.won then
        M.recycleChecked = true
        if M.silosRecycled then
            HideCockpitTimer()
        else
            M.lost = true
            M.sound5 = AudioMessage("bd13005.wav")
        end
    end
    if M.sound5 ~= nil and IsAudioMessageDone(M.sound5) then
        M.sound5 = nil
        FailMission(GetTime() + 1.0, "bd13lsea.des")
    end

    if not M.silosRecycled and not M.lost and not M.won then
        -- check to see if any silos are gone this frame
        -- Native unused local: int numSilosGone = 0;
        for i = 1, 6 do
            -- The native continue becomes this guard (Lua 5.1 has no continue).
            if not M.recycled[i] and Health(M.silos[i]) <= 0.0 then
                -- find all the construction rigs in the world
                -- did any of them just recycle this silo?
                -- Stock IsRecycledByTeam is the capitalized Lua counterpart;
                -- do not gate on IsValid: the query must accept the dead handle.
                local h = M.silos[i]
                local r = h ~= nil and h ~= 0 and IsRecycledByTeam(h, 1)
                if r then
                    M.recycled[i] = true
                else
                    M.lost = true
                    FailMission(GetTime() + 1.0, "bd13lsec.des")
                end
            end
        end
        -- check to see if they're all recycled
        M.silosRecycled = true
        for i = 1, 6 do
            if not M.recycled[i] then M.silosRecycled = false end
        end
    end

    if M.silosRecycled and not M.sound2Played then
        HideCockpitTimer()
        M.recycleChecked = true
        M.sound2Played = true
        AudioMessage("bd13002.wav")
        ClearObjectives()
        AddObjective("bd13001.otf", "green")
        AddObjective("bd13002.otf", "white")
    end

    -- has the player lost his recycler?
    if Health(M.recycler) <= 0.0 and not M.lost and not M.won then
        M.lost = true
        M.sound4 = AudioMessage("bd13004.wav")
    end
    if M.sound4 ~= nil and IsAudioMessageDone(M.sound4) then
        M.sound4 = nil
        FailMission(GetTime() + 1.0, "bd13lseb.des")
    end
    -- has the chinese recycler taken any damage?
    if Health(M.chinRecycler) < 1.0 and not M.silosRecycled and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime() + 1.0, "bd13lsed.des")
    end
    if Health(M.chinRecycler) <= 0.0 and M.silosRecycled and not M.won and not M.lost then
        M.won = true
        M.sound3 = AudioMessage("bd13003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        SucceedMission(GetTime() + 1.0, "bd13win.des")
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
    -- LuaMission restores serialized tables and engine handles/audio userdata.
    -- Do not rerun Setup or replay resources, waves, timer, or intro on resume.
    -- Native PostLoad's ConvertHandle is handled by the LuaMission serializer.
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
