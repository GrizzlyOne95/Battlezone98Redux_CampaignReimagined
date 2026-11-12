-- BlackDog15Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source blob: 7a7d7d440cbc1ec875abf02a97683349820d1814.
-- Complete original (including every comment, cut statement and native save code):
-- References/BlackDog15Source/BlackDog15Mission.cpp.
-- Single-player mission; no campaign helpers, EXU or OpenShim are required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN15_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn15CoopSourceParity.py).
-- CR co-op layer <<

local DISABLED_TIME = 999999.9
-- //#define DO_EXPLOSION
-- Native #ifdef DO_EXPLOSION skips the battle for finale testing. Keep disabled.
local DO_EXPLOSION = false
-- Native useD3D & 4 selects xpltrso, otherwise xpltrsp. Stock Lua does not
-- expose useD3D; Redux uses hardware rendering, so retain the hardware effect.
-- The original software-renderer alternative is preserved: "xpltrsp".
local EXPLOSION_ODF = "xpltrso"

local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused source flags, retained for cut content
        doingCamera = false, doingExplosion = false, doingCountdown = false,
        sound10Played = false, allUnitsSpawned = false, wonLost = false,
        sound2Time = DISABLED_TIME, sound3Time = DISABLED_TIME,
        sound4Time = DISABLED_TIME, sound5Time = DISABLED_TIME,
        sound6Time = DISABLED_TIME, sound8Time = DISABLED_TIME,
        sound9Time = DISABLED_TIME, sound12Time = DISABLED_TIME,
        eastWaveTime = DISABLED_TIME,
        user = nil, lastUser = nil,
        intro1 = nil, -- GetHandle("chin_fighter_intro1");
        intro2 = nil, -- GetHandle("chin_fighter_intro2");
        units = {}, numUnits = 0,
        sound1 = nil, sound2 = nil, sound3 = nil, sound4 = nil,
        sound7 = nil, sound11 = nil, sound12 = nil,
        finaleTarget = nil, -- stock camera adapter, not one of the enemy units
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN15_COOP.md lists every wrapped call and restoration.
-- RESTORED_COUNTDOWN_LINES switches the two unused countdown voice lines off (bd15008, bd15009);
-- RESTORED_SAFE_DISTANCE the cut "minimum safe distance" check (bd15013 and the green escape objective).
local RESTORED_COUNTDOWN_LINES = true
local RESTORED_SAFE_DISTANCE = true
-- The victory is held back this long so the restored meltdown line (5.4 s) is not cut off by the debrief.
local VICTORY_HOLD = 2.0
local Restored
-- Every Chinese craft of the six waves becomes a concealed, head-count-scaled ticket.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true, cvapc = true, cvhtnk = true, cvhraz = true,
    cvhaul = true }
local NativeColorFade, NativeMakeExplosion, NativeGetCockpitTimer = ColorFade, MakeExplosion, GetCockpitTimer
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn15", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "bvslfd0_armory" }, -- the shared Black Dog base is the authored armory
    scaledOdfs = SCALED_ODFS,
    -- A wave whose spawn has a human within 460 m comes from the next hidden Chinese approach instead.
    fallbackEntries = { "spawn_east_wave", "spawn_north_wave", "spawn_west_wave", "spawn_south_wave" },
    liveCap = 30, -- the east waves, the north squad and the last run overlap
    scrapPerGuest = 10,
    failDes = "bd15lose.des", -- out of lives: the lost-transport debrief
    wonFlags = { "doingExplosion" },
    endedFlags = { "doingExplosion", "wonLost" },
    -- The flash and the blast of the transport are local effects of every peer.
    presentationOps = {
        ColorFade = function(...) if NativeColorFade then NativeColorFade(...) end end,
        BD15Boom = function(odf, where) if Restored then Restored.Boom(odf, where) end end,
    },
    -- Ganymede: CREuropaWeather over the generated BD15 sites (six geyser vents around the launch site).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD15", glassFrost = 0.15,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        startLevel = 1, targetLevel = 1,
        beats = function(ganymede, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local function plume(label)
                for index, site in ipairs(ganymede.GetVentSites()) do
                    if site.label == label then return ganymede.TriggerPlume(index) end
                end
            end
            local sent = state.numUnits or 0
            -- The lone west fighter: the quiet moon begins to stir.
            if (not beats.scout) and sent >= 1 then
                beats.scout = true
                ganymede.SetTargetLevel(2)
            end
            -- The southern column: the vent under its road opens.
            if (not beats.south) and sent >= 7 then
                beats.south = true
                plume("eggeizr10_geyser")
            end
            -- The squad in the north: the ice shell flexes and the northern vent answers.
            if (not beats.north) and sent >= 14 then
                beats.north = true
                ganymede.SetTargetLevel(3)
                ganymede.Quake(0.35, 3.0)
                plume("eggeizr15_geyser")
            end
            -- The dozen tanks in the east: another vent, and the sky darkens.
            if (not beats.east) and sent >= 20 then
                beats.east = true
                ganymede.SetTargetLevel(4)
                plume("eggeizr18_geyser")
            end
            if (not beats.east2) and sent >= 26 then
                beats.east2 = true
                ganymede.Surge(4.0, 0.7)
            end
            -- The survivors make their run: the western vents open together.
            if (not beats.run) and state.allUnitsSpawned then
                beats.run = true
                ganymede.Quake(0.5, 3.5)
                plume("eggeizr14_geyser")
                plume("eggeizr17_geyser")
            end
            -- The transport lifts off: the worst of the sky.
            if (not beats.breach) and state.wonLost then
                beats.breach = true
                ganymede.SetTargetLevel(5)
                ganymede.Quake(0.7, 4.0)
                ganymede.Surge(6.0, 0.9)
            end
            -- The last attacker is down and the orbital strike is called: Jupiter surges over the field.
            if (not beats.clear) and state.objective1Complete then
                beats.clear = true
                ganymede.SetTargetLevel(3)
                ganymede.Surge(5.0, 0.9)
            end
            -- The countdown: the sky builds with the clock.
            if (not beats.countdown) and state.doingCountdown then
                beats.countdown = true
                ganymede.SetTargetLevel(5)
                ganymede.Quake(0.35, 3.0)
            end
            -- The core melts: a quake, a surge and the vents round the launch site.
            if (not beats.blast) and state.doingExplosion then
                beats.blast = true
                ganymede.Quake(0.9, 5.0)
                ganymede.Surge(8.0, 1.0)
                plume("eggeizr10_geyser")
                plume("eggeizr15_geyser")
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
        update = function(R) if Restored then Restored.Update(R) end end,
    },
})
-- The body's "player" (M.user) is the runtime's nearest-human token: a valid object while any human lives, and its
-- distance is that of the nearest human.
local PLAYERS = campaignRuntime and campaignRuntime.PLAYERS
local IsValid = campaignRuntime and function(h)
    if h == PLAYERS then return true end
    return campaignRuntime.IsValid(h)
end or IsValid
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local GetDistance = campaignRuntime and campaignRuntime.WrapDistance(campaignRuntime.GetDistance) or GetDistance
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever. The body keeps a
-- line only when its handle is neither nil nor 0, so a failed AudioMessage returns a placeholder it accepts.
local ABSENT_AUDIO = "crcca_absent_audio"
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 or message == ABSENT_AUDIO then return true end
    return nativeAudioDone(message)
end
local AudioMessage = campaignRuntime and function(file)
    local handle = campaignRuntime.AudioMessage(file)
    if handle == nil or handle == 0 then return ABSENT_AUDIO end
    return handle
end or AudioMessage
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraPath = campaignRuntime and campaignRuntime.CameraPath or CameraPath
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SucceedMission = campaignRuntime and function(when, description)
    if RESTORED_COUNTDOWN_LINES then when = when + VICTORY_HOLD end
    return campaignRuntime.SucceedMission(when, description)
end or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The escape countdown is presentation: every peer shows the host's timer. The engine cannot keep the clock (the
-- map runs MultSTMission, which restarts the cockpit timer upward every frame), so the host counts the 30 s itself.
local StartCockpitTimer = campaignRuntime and function(seconds, warn, alert)
    Restored.TimerStart(seconds)
    return campaignRuntime.Present("StartCockpitTimer", seconds, warn, alert)
end or StartCockpitTimer
local HideCockpitTimer = campaignRuntime and function()
    Restored.TimerHide()
    return campaignRuntime.Present("HideCockpitTimer")
end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
-- The white flash and the blast particles are local effects: the host makes its own (with the damage), every guest
-- its own.
local ColorFade = campaignRuntime and function(...) return campaignRuntime.Present("ColorFade", ...) end or ColorFade
local MakeExplosion = campaignRuntime and function(odf, where)
    NativeMakeExplosion(odf, where)
    if campaignRuntime.Coop.IsNetworkGame() then return campaignRuntime.Present("BD15Boom", odf, where) end
end or MakeExplosion
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool).
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
    end
    return SetPilot(team, count)
end or SetPilot
-- Every attacker is a ticket, and a new scripted wave (a new frame or a new spawn path) is a new scaling event: the
-- first unit of each wave is mirrored by min(floor(humans / 2), 2) extras with its orders. The hidden finale
-- camera target (apcamr) is not scaled and is built directly.
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
-- A marker on a unit that is still a ticket waits for the real unit (Restored.Built).
local SetObjectiveOn = campaignRuntime and function(h)
    if type(h) == "number" and h < 0 then
        if Restored then Restored.DeferMark(-h) end
        return
    end
    return campaignRuntime.SetObjectiveOn(h)
end or SetObjectiveOn
-- CR co-op runtime <<

function Start()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    -- Setup defaults are established above; first Update runs SOE #1.
end
function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end
function Save() return M end
function Load(state)
    -- LuaMission restores saved handles/audio IDs; do not replay Setup.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end

local function HasMessage(id) return id ~= nil and id ~= 0 end
local function Alive(h) return h ~= nil and h ~= 0 and IsAlive(h) end
local function Spawn(odf, direction)
    local h = BuildObject(odf, 2, "spawn_" .. direction .. "_wave")
    -- Native units[numUnits++] becomes a 1-based table plus an explicit count.
    -- Count even a failed spawn; the completion scan treats missing handles dead.
    M.numUnits = M.numUnits + 1
    M.units[M.numUnits] = h
    if h ~= nil and h ~= 0 and IsValid(h) then
        Goto(h, "path_" .. direction .. "_wave")
        SetObjectiveOn(h)
    end
end
local function Wave(direction, odfs)
    for i = 1, #odfs do Spawn(odfs[i], direction) end
end

local function FinaleCamera()
    -- Native CameraPathPath("camera_finale", 2400, 0, "spawn_explosion1")
    -- has no stock Lua binding; CameraPath requires an object handle. Use a
    -- hidden, neutral nav camera at the same path point as a stationary target.
    -- It is excluded from units, receives no marker/orders, and is made durable
    -- so the explosion cannot remove the camera target. No wave/escape gate
    -- depends on it. Runtime QA must verify camera alignment and hidden radar.
    if M.finaleTarget == nil or M.finaleTarget == 0 or not IsValid(M.finaleTarget) then
        M.finaleTarget = BuildObject("bpcamr", 0, "spawn_explosion1")
        if M.finaleTarget ~= nil and M.finaleTarget ~= 0
            and IsValid(M.finaleTarget) then
            SetMaxHealth(M.finaleTarget, 1000000000)
            SetCurHealth(M.finaleTarget, 1000000000)
            Hide(M.finaleTarget)
        end
    end
    if M.finaleTarget ~= nil and M.finaleTarget ~= 0
        and IsValid(M.finaleTarget) then
        CameraPath("camera_finale", 2400, 0, M.finaleTarget)
    end
end

-- CR restored content >>
-- The co-op fixes that need state and the cut countdown content (Docs/BDMISN15_COOP.md lists each restoration with
-- the source block it comes from; each is behind a RESTORED_* flag at the top of the runtime region).
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- ---------------------------------------------------------------- markers
    function Restored.DeferMark(id)
        local r = RState()
        r.marks = r.marks or {}
        r.marks[id] = true
    end
    -- A built ticket (a wave unit, or one of the extras that mirror it) takes the marker its primary asked for.
    function Restored.Built(h, request, id)
        local r = RState()
        local key = (request and request.primary) or id
        if r.marks and r.marks[key] then runtime.SetObjectiveOn(h) end
    end
    -- ---------------------------------------------------------------- the host-counted escape timer
    function Restored.TimerStart(seconds)
        local r = RState()
        r.timerEnd, r.timerDone = GetTime() + seconds, nil
    end
    function Restored.TimerHide()
        local r = RState()
        if r.timerEnd ~= nil then r.timerDone = true end
        r.timerEnd = nil
    end
    -- Once the countdown has run out the timer reads zero; before it the body does not read the clock.
    function Restored.TimerLeft()
        local r = RState()
        if r.timerEnd ~= nil then return math.max(0, r.timerEnd - GetTime()) end
        if r.timerDone then return 0 end
        return NativeGetCockpitTimer()
    end
    -- ---------------------------------------------------------------- the blast on a guest
    function Restored.Boom(odf, where)
        if runtime.Coop.IsAuthority() then return end -- the host made its own
        NativeMakeExplosion(odf, where)
    end
    -- ---------------------------------------------------------------- weather and loads
    local sensorsBound = false
    function Restored.OnLoad()
        sensorsBound = false
        RState().afterLoad = true
    end
    -- Every peer, every frame. The weather director's sensor modifier follows the director once both exist.
    function Restored.Update(R)
        if not sensorsBound and R.Weather and R.Weather.module.Initialized then
            sensorsBound = true
            pcall(function() require("Environment").BindWeatherSensors("Ganymede", R.Weather.module) end)
        end
    end
    -- ---------------------------------------------------------------- the objective list
    -- The body publishes the list at two events only; it is rebuilt here from the saved state (the escape entry
    -- turns green when the cut safe-distance check passes).
    local function Publish()
        ClearObjectives()
        if M.objective1Complete then
            AddObjective("bd15001.otf", "green")
            AddObjective("bd15002.otf", (RESTORED_SAFE_DISTANCE and M.objective2Complete) and "green" or "white")
        else
            AddObjective("bd15001.otf", "white")
        end
    end
    -- A load cannot resume a camera, and the runtime's Load resets the presentation: the objective list, the unit
    -- markers, the running countdown and the finale camera come back from the saved state.
    function Restored.AfterLoad(r)
        Publish()
        local seen = {}
        local function Mark(h)
            if h ~= nil and not seen[h] and not (type(h) == "number" and h < 0) and Alive(h) then
                seen[h] = true
                runtime.SetObjectiveOn(h)
            end
        end
        for _, h in ipairs(runtime.State().live) do Mark(h) end
        for i = 1, M.numUnits do Mark(M.units[i]) end
        if M.doingCountdown and r.timerEnd ~= nil then
            local remaining = r.timerEnd - GetTime()
            if remaining > 0 then runtime.Present("StartCockpitTimer", remaining, 10, 5) end
        end
        if M.doingCamera then CameraReady() end
    end
    -- ---------------------------------------------------------------- breach and victory gates for the extras
    -- The body scans only the units it built itself; the extras that mirror a wave walk the same road and breach the
    -- launch site just as well.
    function Restored.ExtraBreach()
        if M.wonLost or M.doingExplosion then return end
        for _, h in ipairs(runtime.State().live) do
            if Alive(h) and GetDistance(h, "chin_launch") < 100.0 then
                M.sound11 = AudioMessage("bd15011.wav")
                M.wonLost = true
                return
            end
        end
    end
    -- The enemies the body does not track: the extras that mirror each wave and the requests still waiting for a
    -- hidden spawn. The body's "everything beaten" test must wait for them too.
    function Restored.EnemiesLeft()
        local s = runtime.State()
        for _, h in ipairs(s.live) do
            if Alive(h) then return true end
        end
        return next(s.arrivals) ~= nil
    end
    -- ---------------------------------------------------------------- restored voice lines
    -- Unused bd15008 ("30 seconds to core meltdown.") opens the countdown; unused bd15009 ("Core meltdown in
    -- progress. Thank you, and enjoy your day.") is the cut sound8 beat of the blast.
    function Restored.CountdownLines(r)
        if not RESTORED_COUNTDOWN_LINES then return end
        if M.doingCountdown and not r.thirty then
            r.thirty = true
            AudioMessage("bd15008.wav")
        end
        if M.doingExplosion and not r.meltdown then
            r.meltdown = true
            AudioMessage("bd15009.wav")
        end
    end
    -- Cut: `float dist = GetDistance(user, "spawn_explosion1"); //if (dist > 800.0f) { //sound9 = AudioMessage("bd15013.wav");`
    -- Evaluated where the source evaluates it, at the finale camera: when every human is farther than 800 m the unused
    -- bd15013 ("Minimum safe distance reached.") plays and the escape objective turns green.
    function Restored.SafeDistance(r)
        if not RESTORED_SAFE_DISTANCE or r.safeChecked or not M.doingCamera then return end
        r.safeChecked = true
        if GetDistance(M.user, "spawn_explosion1") > 800.0 then
            AudioMessage("bd15013.wav")
            M.objective2Complete = true
            Publish()
        end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad(r) end
        Restored.ExtraBreach()
        Restored.SafeDistance(r)
        Restored.CountdownLines(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn15] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    assert(M.numUnits < 100, "BlackDog15 numUnits >= 100")
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()
    -- SOE #1
    if not M.startDone then
        SetScrap(1, 50)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        ClearObjectives()
        AddObjective("bd15001.otf", "white")
        M.sound1 = AudioMessage("bd15001.wav")
        if DO_EXPLOSION then M.sound7 = AudioMessage("bd15007.wav") end
    end

    if not DO_EXPLOSION then -- native #ifndef DO_EXPLOSION
        -- SOE #1
        if HasMessage(M.sound1) and IsAudioMessageDone(M.sound1) then
            M.sound1 = nil
            M.sound2Time = now + 20.0
        end
        if not M.sound10Played and M.user ~= nil and M.user ~= 0
            and IsValid(M.user) and GetDistance(M.user, "chin_launch") < 300.0 then
            M.sound10Played = true
            AudioMessage("bd15010.wav")
        end
        -- SOE #2
        if M.sound2Time < now then
            M.sound2Time = DISABLED_TIME
            M.sound2 = AudioMessage("bd15002.wav")
            Wave("west", {"cvfigh"})
        end
        if HasMessage(M.sound2) and IsAudioMessageDone(M.sound2) then
            M.sound2 = nil
            M.sound3Time = now + 40.0
        end
        -- SOE #3
        if M.sound3Time < now then
            M.sound3Time = DISABLED_TIME
            M.sound3 = AudioMessage("bd15003.wav")
            Wave("south", {"cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvtnk", "cvapc"})
        end
        if HasMessage(M.sound3) and IsAudioMessageDone(M.sound3) then
            M.sound3 = nil
            M.sound4Time = now + 120.0
        end
        -- SOE #4
        if M.sound4Time < now then
            M.sound4Time = DISABLED_TIME
            M.sound4 = AudioMessage("bd15004.wav")
            Wave("north", {"cvapc", "cvapc", "cvapc", "cvhtnk", "cvtnk", "cvtnk", "cvtnk"})
        end
        if HasMessage(M.sound4) and IsAudioMessageDone(M.sound4) then
            M.sound4 = nil
            M.sound5Time = now + 180.0
        end
        -- SOE #5
        if M.sound5Time < now then
            M.sound5Time = DISABLED_TIME
            AudioMessage("bd15005.wav")
            Wave("east", {"cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvltnk", "cvltnk"})
            M.eastWaveTime = now + 60.0
        end
        if M.eastWaveTime < now then
            M.eastWaveTime = DISABLED_TIME
            Wave("east", {"cvltnk", "cvltnk", "cvhraz", "cvhraz", "cvfigh", "cvfigh"})
            M.sound6Time = now + 180.0
        end
        -- SOE #6
        if M.sound6Time < now then
            M.sound6Time = DISABLED_TIME
            AudioMessage("bd15006.wav")
            Spawn("cvhtnk", "south")
            Wave("north", {"cvfigh", "cvfigh"})
            Wave("west", {"cvapc", "cvapc", "cvhaul"})
            M.allUnitsSpawned = true
        end
        -- SOE #7
        for i = 1, M.numUnits do
            if M.wonLost then break end
            -- PORT FIX: destroyed/absent handles must not trigger a launch-site
            -- breach from stale positions or an invalid distance result. Only
            -- living attackers can breach; all living-unit timing is unchanged.
            if Alive(M.units[i]) and GetDistance(M.units[i], "chin_launch") < 100.0 then
                M.sound11 = AudioMessage("bd15011.wav")
                M.wonLost = true
                break
            end
        end
        if HasMessage(M.sound11) and IsAudioMessageDone(M.sound11) then
            M.sound11 = nil
            M.sound12Time = now + 5.0
        end
        if M.sound12Time < now then
            M.sound12Time = DISABLED_TIME
            M.sound12 = AudioMessage("bd15012.wav")
        end
        if HasMessage(M.sound12) and IsAudioMessageDone(M.sound12) then
            M.sound12 = nil
            FailMission(now, "bd15lose.des")
        end
        -- SOE #8
        -- PORT FIX: native completion lacks !wonLost. Killing the last enemy
        -- after a breach can queue both victory and defeat. A latched breach
        -- now keeps the loss sequence exclusive; an unbreached defence follows
        -- exactly the same all-units-dead gate and escape countdown as before.
        if M.allUnitsSpawned and not M.objective1Complete and not M.wonLost then
            M.objective1Complete = true
            for i = 1, M.numUnits do
                if Alive(M.units[i]) then
                    M.objective1Complete = false
                    break
                end
            end
-- CR co-op gate >>
            if campaignRuntime and M.objective1Complete and Restored.EnemiesLeft() then M.objective1Complete = false end
-- CR co-op gate <<
            if M.objective1Complete then
                M.sound7 = AudioMessage("bd15007.wav")
                ClearObjectives()
                AddObjective("bd15001.otf", "green")
                AddObjective("bd15002.otf", "white")
            end
        end
    end

    if HasMessage(M.sound7) and IsAudioMessageDone(M.sound7) then
        M.sound7 = nil
        M.doingCountdown = true
        StartCockpitTimer(30, 10, 5)
        --explTime = GetTime() + 32.0f;
        --cameraTime = GetTime() + 30.0f;
        --sound8Time = GetTime() + 32.0f;
    end
    -- SOE #9
    if M.doingCountdown and GetCockpitTimer() <= 0 and not M.doingExplosion then
        -- hopefully, if the player get's caught in the explosion,
        -- this success won't happen
        HideCockpitTimer()
        SucceedMission(now + 5.0, "bd15win.des")
        M.doingExplosion = true
        ColorFade(1.0, 0.5, 255, 255, 255)
        -- Lua MakeExplosion takes ODF first, unlike the native call.
        MakeExplosion(EXPLOSION_ODF, "spawn_explosion1")
    end
    if M.doingCountdown and GetCockpitTimer() <= 2 and not M.doingCamera then
        -- float dist = GetDistance(user, "spawn_explosion1"); (unused)
        --if (dist > 800.0f)
        --sound9 = AudioMessage("bd15013.wav");
        -- focus on the explosion
        CameraReady()
        M.doingCamera = true
    end
    -- PORT FIX: native submits its camera only once. Stock cinematic controls
    -- need updates every frame, also after Load. Reissue the stationary view
    -- without resetting CameraReady, moving its start time, or adding a skip.
    -- Source never calls CameraFinish; keep the view until mission transition.
    if M.doingCamera then FinaleCamera() end
-- CR restored content >>
    if campaignRuntime then Restored.Run() end
-- CR restored content <<
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.AfterUpdate() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
function AddObject(h) if campaignRuntime then return campaignRuntime.AddObject(h) end end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
do
    local faithfulSave = Save
    function Save()
        if campaignRuntime then campaignRuntime.Save() end
        return faithfulSave()
    end
end
-- CR co-op callbacks <<
