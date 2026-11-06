-- BlackDog06Mission, stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/blackdog06mission.cpp
-- Git blob: 4103fbfa8032b89fc3592c46f2366e4f0f115839.
-- Exact source including ALL comments/cut code and native save scaffolding:
-- References/BlackDog06Source/blackdog06mission.cpp. No helper dependencies.

-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN06_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn06CoopSourceParity.py).
-- CR co-op layer <<
local MS_STARTUP, MS_STARTCAMERA, MS_WAITING1 = 0, 1, 2
local MS_WAITFORSOUND2, MS_WAITING2, MS_FAKEATTACKCAMERA = 3, 4, 5
local MS_WAITFORALL2BDESTDEAD, MS_WAITFORREDDEVIL = 6, 7
local MS_WAITFORBADGUY, MS_WAITFORBADGUY1DIE = 8, 9
local MS_WAITFORBADGUY2, MS_WAITFORBADGUY2DIE = 10, 11
local MS_WAITFORSOUND3, MS_WAITFOROBJECTIVE2, MS_WAITFORRECYCLER = 12, 13, 14
local MS_WAITFORBADGUY3, MS_WAITFORAPC, MS_ENDCUTSCENE = 15, 16, 17
local MS_WAITING3, MS_WAITAPCFINISHED, MS_WAITAPCOUT = 18, 19, 20
-- Cut states remain named for reconstruction; their handlers stay disabled.
local MS_WAITFORSOUND8, MS_WAITING4, MS_RECYCLERDEAD, MS_ATTACKTOEARLY = 21, 22, 23, 24

local function NewState()
    return {
        lost = false, portalours = false, recyclerDropped = false,
        randomAttack = true, -- unused in the active native mission
        stateTimer = 99999, stateTimer2 = 99999,
        stateTimer3 = 0, stateTimer4 = 0, missionState = MS_STARTUP,
        -- Native null handles/messages are nil, not Lua's truthy numeric zero.
        -- Keep zero-based arrays so source indices can be compared directly.
        bdtank = {}, silo_attack = {}, h2bdest = {}, portalattack = {},
        randomattack = {}, badguy = {},
        portalWaveActive = false, portalWaveSpawned = false, apcEntered = false,
        apcEntryAudioPending = false,
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN06_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/BDMISN06_COOP.md, "Restored content").
local RESTORED_VICTORY_LINES = true -- the cut bd06008 / bd06005 victory narration
local RESTORED_COCKPIT_TIMER = true -- the cut 11-minute cockpit timer
local Restored
-- Every Chinese combat craft the body sends becomes a concealed, head-count-scaled ticket (the body's team 2 is
-- the co-op enemy 5). Portal waves are built by BuildObjectAtPortal: that unit stays the native portal build and
-- only its co-op extras are tickets (see Restored.PortalExtras).
local SCALED_ODFS = { cvfigh = true, cvtnk = true, cvrckt = true, cvartl = true }
local NativeBuildObjectAtPortal, NativePortalOut, NativeActivatePortal, NativeDeactivatePortal =
    BuildObjectAtPortal, PortalOut, ActivatePortal, DeactivatePortal
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn06", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "backup_1" }, -- the Black Dog start: no base exists until the recycler deploys late
    scaledOdfs = SCALED_ODFS,
    -- A group whose entry has a human within 460 m comes from the next hidden Chinese approach instead.
    fallbackEntries = { "attack_always", "dummy_1", "attack_1", "attack_2", "attack_3" },
    liveCap = 24, -- hunters every 110 s, the counter-attacks, the portal waves and the closing fighters overlap
    scrapPerGuest = 10,
    -- Out of lives: bd06lsea ("... as you pilot your new Scavenger"); the game ships no bd06lose.
    failDes = "bd06lsea.des",
    wonFlags = { "crWon" },
    endedFlags = { "lost", "crWon" },
    orders = { "Goto", "Attack", "Hunt" }, -- the orders the body gives to units that may still be tickets
    -- The portal's direction and pulse are local effects of the object: every peer applies them to its own copy.
    presentationOps = {
        BD6PortalOut = function() Restored.OpPortal(NativePortalOut) end,
        BD6PortalOn = function() Restored.OpPortal(NativeActivatePortal) end,
        BD6PortalOff = function() Restored.OpPortal(NativeDeactivatePortal) end,
    },
    -- Ganymede: CREuropaWeather over the generated BD06 sites (four geyser vents; three sit in the Chinese base).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD06",
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        startLevel = 1, targetLevel = 1,
        beats = function(ganymede, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local mission = state.missionState or 0
            local function raise(level)
                if ganymede.GetTargetLevel() < level then ganymede.SetTargetLevel(level) end
            end
            local function plume(label)
                for index, site in ipairs(ganymede.GetVentSites()) do
                    if site.label == label then return ganymede.TriggerPlume(index) end
                end
            end
            -- "Delta Three is Go": the diversion draws the fighters off and the quiet moon begins to stir.
            if (not beats.diversion) and mission >= MS_WAITFORSOUND2 then
                beats.diversion = true
                raise(2)
                ganymede.Quake(0.3, 3.0)
            end
            -- The Chinese base is down: the ice shell it stood on cracks and a vent opens in its ruins.
            if (not beats.base) and mission >= MS_WAITFORREDDEVIL then
                beats.base = true
                raise(3)
                ganymede.Quake(0.4, 3.0)
                plume("eggeizr143_geyser")
            end
            -- The first counter-attack: another vent answers.
            if (not beats.counter) and mission >= MS_WAITFORBADGUY1DIE then
                beats.counter = true
                plume("eggeizr142_geyser")
            end
            -- The heavy counter-attack is beaten: Jupiter's radiation surges over the column.
            if (not beats.heavy) and mission >= MS_WAITFORSOUND3 then
                beats.heavy = true
                raise(3)
                ganymede.Surge(5.0, 0.8)
            end
            -- The recycler deploys and the last raid comes in: the worst of the sky.
            if (not beats.recycler) and mission >= MS_WAITFORBADGUY3 then
                beats.recycler = true
                raise(4)
                ganymede.Quake(0.35, 3.0)
                plume("eggeizr144_geyser")
            end
            -- The APC is in the portal and the reprogramming starts: a quake and a surge ("strong pulses").
            if (not beats.portal) and state.portalours then
                beats.portal = true
                raise(4)
                ganymede.Quake(0.5, 3.5)
                ganymede.Surge(6.0, 0.9)
            end
            -- Victory: the sky eases for the debrief. A loss leaves the ice restless.
            if (not beats.easing) and state.crWon then
                beats.easing = true
                ganymede.ReleaseForcedLevel()
                ganymede.SetTargetLevel(2)
            end
            if (not beats.lost) and state.lost and not state.crWon then
                beats.lost = true
                raise(4)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
        update = function(R, _, authority) if Restored then Restored.Update(R, authority) end end,
    },
})
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Hunt = campaignRuntime and campaignRuntime.Hunt or Hunt
-- The body's "player" (M.user) is the runtime's nearest-human token: an order aimed at it goes to the human nearest
-- to the unit that obeys it (a unit that is still a waiting ticket remembers it: Restored.Built).
local Attack = campaignRuntime and function(h, target, ...) return Restored.Attack(h, target, ...) end or Attack
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- A line with no audio handle counts as finished (nil -> 0, which the body's gates read as done and as "played"),
-- so no gate can wait on it for ever or replay it every frame.
local AudioMessage = campaignRuntime and function(file)
    return campaignRuntime.AudioMessage(file) or 0
end or AudioMessage
local nativeAudioDone = IsAudioMessageDone
local IsAudioMessageDone = campaignRuntime and function(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end or IsAudioMessageDone
-- A skip pressed before this shot opened must not end it: the cancel flag is cleared as the shot opens.
local CameraReady = campaignRuntime and function()
    campaignRuntime.CameraReady()
    pcall(campaignRuntime.Native.CameraCancelled, true)
end or CameraReady
-- The opening ends when the shot arrives or is cancelled. The runtime stops driving a shot the host skipped (it
-- releases only the host's own camera) and CameraCancelled is false in a network game, so in a network game that
-- shot would never arrive and the opening, and everything behind it, would stall: a host skip ends the shared shot.
local CameraPath = campaignRuntime and function(path, height, speed, target)
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if not arrived and campaignRuntime.Coop.IsNetworkGame() and campaignRuntime.Native.CameraCancelled() then return true end
    return arrived
end or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
-- The result: victory is latched first (a late out-of-lives failure is then ignored) and may be delayed by the
-- restored closing narration. The game ships no bd06lsed.des (Docs/BDMISN06_COOP.md): the out-of-time loss uses
-- bd06lsea, the shipped debrief about the time lost before the next attempt on the gateway.
local SucceedMission = campaignRuntime and function(when, description)
    return Restored.Succeed(when, description)
end or SucceedMission
local FailMission = campaignRuntime and function(when, description)
    if description == "bd06lsed.des" then description = "bd06lsea.des" end
    return campaignRuntime.FailMission(when, description)
end or FailMission
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
-- One scaling event per frame and entry path: the first unit of each scripted group is mirrored by
-- min(floor(humans / 2), 2) extras with its orders.
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
local portalFrame
local BuildObjectAtPortal = campaignRuntime and function(odf, team, portal)
    local h = NativeBuildObjectAtPortal(odf, team == 2 and 5 or team, portal)
    local now = GetTime()
    if portalFrame ~= now then
        portalFrame = now
        Restored.PortalExtras(odf)
    end
    return h
end or BuildObjectAtPortal
-- Portal direction and pulse: every peer applies them to its own copy of the portal.
local PortalOut = campaignRuntime and function() return campaignRuntime.Present("BD6PortalOut") end or PortalOut
local ActivatePortal = campaignRuntime and function() return campaignRuntime.Present("BD6PortalOn") end or ActivatePortal
local DeactivatePortal = campaignRuntime and function() return campaignRuntime.Present("BD6PortalOff") end or DeactivatePortal
-- CR co-op runtime <<

local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end
local function AudioDone(h)
    -- PORT FIX: a failed/missing audio file must not block its completion gate.
    -- Existing messages still finish at the original gate; no timer is added.
    return h == nil or h == 0 or IsAudioMessageDone(h)
end
local function Order(command, h, target)
    -- PORT FIX: deleted objects/failed spawns cannot receive handle commands.
    -- Every successful spawn retains the source's default priority (1).
    if Valid(h) then
        if target == nil then
            if command == Hunt then command(h) end
        elseif type(target) == "string" or Valid(target) then
            command(h, target)
        end
    end
end
local function Spawn(odf, team, path, command, target)
    local h = BuildObject(odf, team, path)
    Order(command, h, target)
    return h
end
local function resetObjectives()
    ClearObjectives()
    if M.missionState >= MS_WAITFORSOUND3 then
        AddObjective("bd06001.otf", "green")
    elseif M.missionState >= MS_WAITING1 then
        AddObjective("bd06001.otf", "white")
    end
    if M.portalours then
        AddObjective("bd06002.otf", "green")
    elseif M.missionState >= MS_WAITFORRECYCLER then
        AddObjective("bd06002.otf", "white")
    end
end

-- CR restored content >>
-- The co-op fixes that need state, the cut content restored from the native source and the weather sensor
-- binding (Docs/BDMISN06_COOP.md lists each). Each restoration is gated by a RESTORED_* flag.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local sensorsBound, winLine = false, nil -- per peer, not saved
    -- A load cannot resume a camera (the shots are gone): the states that hold one open it again; the body keeps
    -- calling its CameraPath every frame and ends the film itself.
    local FILM_STATES = { [MS_STARTCAMERA] = true, [MS_FAKEATTACKCAMERA] = true, [MS_ENDCUTSCENE] = true }
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function NearestHuman(unit)
        local best, bestDistance
        runtime.Coop.ForEachPlayerHandle(function(human)
            if Alive(human) then
                local distance = GetDistance(human, unit)
                if bestDistance == nil or distance < bestDistance then best, bestDistance = human, distance end
            end
        end)
        return best
    end

    -- ---------------------------------------------------------------- the player
    -- Attack(unit, M.user): a real unit gets the nearest human now; a waiting ticket remembers the order (the
    -- runtime drops one whose target is the token) and is ordered when it is built (Restored.Built).
    function Restored.Attack(h, target, ...)
        if target ~= runtime.PLAYERS then return runtime.Attack(h, target, ...) end
        if type(h) == "number" and h < 0 then
            local s = RState()
            s.orders = s.orders or {}
            s.orders[tostring(-h)] = true
            return
        end
        if Alive(h) then
            local human = NearestHuman(h)
            if human ~= nil then return runtime.Attack(h, human, ...) end
        end
    end
    function Restored.Built(h, request, id)
        local r = RState()
        local key = tostring((request and request.primary) or id)
        if r.orders and r.orders[key] then
            r.chasers = r.chasers or {}
            r.chasers[#r.chasers + 1] = h
            local human = NearestHuman(h)
            if human ~= nil then runtime.Attack(h, human) end
        end
    end
    -- Stock bug (a human can die and respawn here, the DLL's single player could not): a counter-attack unit
    -- whose human target is gone sits idle and the body's "both tanks dead" gates then never open. Idle chasers
    -- attack the nearest human again, checked every 10 s.
    function Restored.Retarget(r)
        if not r.chasers or M.lost then return end
        local now = GetTime()
        if now < (r.retargetAt or 0) then return end
        r.retargetAt = now + 10
        local keep = {}
        for _, h in ipairs(r.chasers) do
            if Alive(h) then
                keep[#keep + 1] = h
                if GetCurrentCommand(h) == AiCommand.NONE then
                    local human = NearestHuman(h)
                    if human ~= nil then runtime.Attack(h, human) end
                end
            end
        end
        r.chasers = keep
    end

    -- ---------------------------------------------------------------- the portal
    function Restored.OpPortal(native)
        local portal = GetHandle("portal")
        if portal ~= nil and IsValid(portal) then native(portal) end
    end
    -- Co-op: the portal wave's first unit is mirrored by the event's extras. They are concealed tickets at the
    -- authored portal exit (the ticket of the native build itself is cancelled), ordered like the wave.
    function Restored.PortalExtras(odf)
        if runtime.HumanCount() < 2 or not runtime.PathExists("portal_spawn") then return end
        runtime.BeginEvent()
        local ticket = runtime.Spawn(odf, 5, "portal_spawn")
        if type(ticket) ~= "number" or ticket >= 0 then return end
        runtime.Goto(ticket, "camera_go")
        runtime.State().arrivals[-ticket] = nil
    end

    -- ---------------------------------------------------------------- results
    -- Cut: `soundhandle = AudioMessage("bd06008.wav"); missionState = MS_WAITFORSOUND8;` then, when it is done,
    -- `MS_WAITING4` waits 5 s, plays "bd06005.wav" and calls SucceedMission(GetTime() + 10.0f, "bd06wina.des").
    -- The body's own SucceedMission call (the APC has left through the portal) starts that sequence.
    function Restored.Succeed(when, description)
        M.crWon = true
        if not RESTORED_VICTORY_LINES then return runtime.SucceedMission(when, description) end
        RState().win = { des = description, stage = 1 }
    end
    local function WinLines()
        local w = RState().win
        if not w or w.done then return end
        local now = GetTime()
        if w.stage == 1 then
            if not w.played then
                w.played = true
                winLine = AudioMessage("bd06008.wav")
            end
            if IsAudioMessageDone(winLine) then w.stage, w.at = 2, now + 5 end
        elseif now >= w.at then
            w.done = true
            AudioMessage("bd06005.wav")
            runtime.SucceedMission(now + 10, w.des)
        end
    end

    -- ---------------------------------------------------------------- the 11-minute cockpit timer
    -- Cut: `// StartCockpitTimer(11 * 60);` when the opening ends, `// HideCockpitTimer();` once the Chinese base is
    -- down. The body's own deadline (stateTimer2) is unchanged; this only shows it, on every peer.
    local function CockpitTimer(r)
        local timed = RESTORED_COCKPIT_TIMER and not M.lost
            and M.missionState >= MS_WAITING1 and M.missionState <= MS_WAITFORALL2BDESTDEAD
        if timed and not r.timer then
            local left = M.stateTimer2 - GetTime()
            if left > 0 then
                r.timer = true
                runtime.Present("StartCockpitTimer", left)
            end
        elseif r.timer and not timed then
            r.timer = false
            runtime.Present("HideCockpitTimer")
        end
    end

    -- ---------------------------------------------------------------- loads and per-frame hooks
    function Restored.OnLoad()
        sensorsBound, winLine = false, nil
        local r = RState()
        r.afterLoad, r.timer = true, false -- the timer is shown again with what is left
    end
    -- Every peer, every frame. The weather director's sensor modifier follows the director once both exist; the
    -- authority plays the restored closing narration (the body has stopped by then: it set lost).
    function Restored.Update(R, authority)
        if not sensorsBound and R.Weather and R.Weather.module.Initialized then
            sensorsBound = true
            pcall(function() require("Environment").BindWeatherSensors("Ganymede", R.Weather.module) end)
        end
        if authority then WinLines() end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        local r = RState()
        if r.afterLoad then
            r.afterLoad = nil
            if FILM_STATES[M.missionState] and not M.lost then CameraReady() end
            -- The runtime's Load resets the presentation: republish the objectives once the opening is over.
            -- (The cockpit timer restarts through r.timer; the body names and marks nothing else.)
            if M.missionState > MS_STARTCAMERA and not M.lost then resetObjectives() end
        end
        Restored.Retarget(r)
        CockpitTimer(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn06] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
    -- Cut setup: portalAttackStage = 0; portalAttackNum = 0;
    M.portal = GetHandle("portal")
    for i = 0, 9 do
        M.silo_attack[i] = GetHandle("silo_attack" .. (i + 1))
        M.bdtank[i] = GetHandle("bdtank_" .. (i + 1))
    end
    local labels = {"2bdest_1", "2bdest_2", "2bdest_3", "2bdest_7", "2bdest_9", "2bdest_10"}
    for i = 0, 5 do M.h2bdest[i] = GetHandle(labels[i + 1]) end
end
function AddObject(h)
    -- Native AddObject(Handle) is empty; no extra construction trigger.
end
function Save() return M end
function Load(state)
    -- LuaMission serializes/remaps state and object handles. Do not rerun Setup.
    if state ~= nil then M = state end
end

local function FakeAttackCamera()
    -- PORT FIX: if the subject was destroyed, finish the existing shot instead
    -- of calling CameraPath with a deleted handle. Intact-map timing is kept.
    local arrived = not Valid(M.silo_attack[3])
    if not arrived then arrived = CameraPath("camera_go", 2000, 2000, M.silo_attack[3]) end
    if arrived or CameraCancelled() or M.stateTimer < GetTime() then
        for i = 0, 9 do
            if Valid(M.silo_attack[i]) then RemoveObject(M.silo_attack[i]) end
        end
        CameraFinish()
        M.missionState = MS_WAITFORALL2BDESTDEAD
    end
end

local function PortalWaves()
    if M.stateTimer4 ~= 0 and M.stateTimer4 < GetTime() then
        local diff = GetTime() - M.stateTimer4
        -- ADAPTATION: native portalOut(h, strength) has no stock Lua strength
        -- overload. Set outward direction and activate for the same two-second
        -- window. Unit appearance is still delayed until diff >= 1 second.
        if not M.portalWaveActive then
            PortalOut(M.portal)
            ActivatePortal(M.portal)
            M.portalWaveActive = true
        end
        if diff >= 1 then
            for i = 0, 1 do
                if M.portalattack[i] == nil then
                    -- TRO 1.3: roll is uniform in [-1,1), so about 66.5% cvfigh, 16.5% cvtnk, 17% cvrckt
                    local r, odf = math.random() * 2 - 1, "cvrckt"
                    if r < 0.33 then odf = "cvfigh"
                    elseif r < 0.66 then odf = "cvtnk" end
                    M.portalattack[i] = BuildObjectAtPortal(odf, 2, M.portal)
                    Order(Goto, M.portalattack[i], "camera_go")
                end
            end
        end
        -- PORT FIX: native resets stateTimer4 inside the two-unit loop, so
        -- iteration 1 can compute a negative diff and an out-of-range strength.
        -- Reset once AFTER both slots have been processed. Keep the two units,
        -- >=2-second close, and original next-wave delay of 80 seconds.
        -- Native gives a late first spawn one Update before resetting; keep it.
        if diff >= 2 and M.portalWaveSpawned then
            DeactivatePortal(M.portal)
            M.portalWaveActive, M.portalWaveSpawned = false, false
            M.stateTimer4 = GetTime() + 80
            M.portalattack[0], M.portalattack[1] = nil, nil
        elseif diff >= 1 then
            M.portalWaveSpawned = true
        end
    end
end

local function APCEntry()
    -- PORT FIX: the native entry/removal/audio block lived only in the camera
    -- state. Early camera arrival could skip it forever and reuse the old
    -- 11-minute timer for the return APC. Continue that SAME entry sequence
    -- after the camera exits; normal cinematics keep all original timings.
    if not M.apcEntered and Valid(M.apchandle)
        and GetCurrentCommand(M.apchandle) == AiCommand.NONE then
        RemoveObject(M.apchandle)
        M.apchandle = nil
        M.apcEntered = true
        M.soundhandle = AudioMessage("bd06009.wav")
        M.apcEntryAudioPending = true
        M.stateTimer2 = GetTime() + 60
    end
    if M.apcEntryAudioPending and AudioDone(M.soundhandle) then
        M.soundhandle, M.apcEntryAudioPending = nil, false
        for i = 0, 6 do Spawn("cvtnk", 2, "dummy_1", Goto, "dummy_1_path") end
        if M.missionState == MS_ENDCUTSCENE then M.stateTimer = GetTime() + 3 end
    end
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    if M.lost then return end

    if not M.portalours and M.recycler ~= nil then
        -- Count ALL bvapc objects, as the native cfg comparison does. Do not
        -- impose an invented team filter. AllObjects is stock (not the broken
        -- ObjectiveObjects iterator). Player-built APCs must also be detected.
        local apclist = 0
        for apc in AllObjects() do
            if Valid(apc) and IsOdf(apc, "bvapc") then
                if GetDistance(apc, "apc_in") < 100 then
                    Order(Goto, apc, "apc_in")
                    M.apchandle, M.portalours, M.soundhandle = apc, true, nil
                    resetObjectives() -- deliberately before changing state
                    for i = 0, 2 do Spawn("cvartl", 2, "portal_attack_1", Attack, M.portal) end
                    M.missionState, M.stateTimer = MS_ENDCUTSCENE, 0
                    CameraReady()
                    break
                end
                apclist = apclist + 1
            end
        end
        if not M.portalours and apclist == 0 and not Alive(M.recycler)
            and M.missionState ~= MS_RECYCLERDEAD then
            -- PORT FIX: restarting bd06006 every frame prevents it finishing.
            -- Enter loss state once, preserving the audio-then-failure flow.
            M.missionState = MS_RECYCLERDEAD
            M.soundhandle = AudioMessage("bd06006.wav")
        end
    end

    if not Alive(M.portal) then
        FailMission(GetTime() + 2, "bd06lseb.des")
        M.lost = true
        -- PORT FIX: stop this Update as well, preventing simultaneous success
        -- or portal spawns on a destroyed portal. This retains the source loss.
        return
    end

    PortalWaves()
    if M.stateTimer3 ~= 0 and M.stateTimer3 < GetTime() then
        for i = 0, 4 do
            -- TRO 1.3: roll is uniform in [-1,1), so about 75% cvfigh, 25% cvtnk
            local odf = math.random() * 2 - 1 < 0.5 and "cvfigh" or "cvtnk"
            M.randomattack[i] = Spawn(odf, 2, "attack_always", Hunt)
        end
        M.stateTimer3 = GetTime() + 60 + 50
    end
    if M.portalours and M.missionState >= MS_ENDCUTSCENE
        and M.missionState <= MS_WAITAPCFINISHED then APCEntry() end

    if M.missionState == MS_STARTUP then
        SetScrap(1, 75)
        SetPilot(1, 10)
        resetObjectives()
        M.missionState, M.stateTimer, M.soundhandle = MS_STARTCAMERA, GetTime() + 2, nil
        CameraReady()
        -- Source's commented-out break intentionally falls through this frame.
        -- // break;
    end
    if M.missionState == MS_STARTCAMERA then
        local arrived = CameraPath("camera_start", 1000, 2500, M.portal)
        if arrived or CameraCancelled() then
            CameraFinish()
            M.missionState = MS_WAITING1
            resetObjectives()
            M.stateTimer = GetTime() + 20
            -- // resetObjectives();
            M.stateTimer2 = GetTime() + (11 * 60)
            -- // StartCockpitTimer(11 * 60);
        end
        if M.stateTimer < GetTime() and M.soundhandle == nil then
            M.soundhandle = AudioMessage("bd06001.wav")
            --[==[ Cut source:
            else if (IsAudioMessageDone(soundhandle))
            {
                missionState = MS_WAITING1;
            }
            ]==]
        end
    elseif M.missionState == MS_WAITING1 then
        if M.stateTimer < GetTime() then
            M.soundhandle = AudioMessage("bd06002.wav")
            for i = 0, 9 do Order(Goto, M.silo_attack[i], "fake_attack") end
            M.missionState = MS_WAITFORSOUND2
        else
            for i = 0, 9 do
                --[==[ Cut source (friendly damage check remains disabled):
                if(i < 5)
                {
                    o = GameObjectHandle::GetObj(bdtank[i]);
                    if(o->GetCurHealth() != o->GetMaxHealth())
                    {
                        missionState = MS_ATTACKTOEARLY;
                        soundhandle = AudioMessage("bd06007.wav");
                    }
                }
                ]==]
                -- PORT FIX: native dereferences a null object if a silo unit
                -- was killed. Treat destruction as damage, the same loss gate.
                if not Valid(M.silo_attack[i])
                    or GetCurHealth(M.silo_attack[i]) ~= GetMaxHealth(M.silo_attack[i]) then
                    M.missionState = MS_ATTACKTOEARLY
                    M.soundhandle = AudioMessage("bd06007.wav")
                    break -- one loss message, even when several are damaged
                end
            end
        end
    elseif M.missionState == MS_WAITFORSOUND2 then
        if AudioDone(M.soundhandle) then
            M.missionState, M.stateTimer = MS_WAITING2, GetTime() + 3
        end
    elseif M.missionState == MS_WAITING2 then
        if M.stateTimer < GetTime() then
            M.missionState, M.stateTimer = MS_FAKEATTACKCAMERA, GetTime() + 5
            CameraReady()
            FakeAttackCamera() -- source switch fallthrough, same Update
        end
    elseif M.missionState == MS_FAKEATTACKCAMERA then
        FakeAttackCamera()
    elseif M.missionState == MS_WAITFORALL2BDESTDEAD then
        -- out of time? Cut: if(GetCockpitTimer() < 1)
        if M.stateTimer2 < GetTime() then
            FailMission(GetTime() + 2, "bd06lsed.des")
            M.lost = true
        else
            local allDead = true
            for i = 0, 5 do if Alive(M.h2bdest[i]) then allDead = false; break end end
            if allDead then
                M.missionState = MS_WAITFORREDDEVIL
                resetObjectives()
                M.stateTimer = GetTime() + (60 * 1.5)
                M.stateTimer3, M.stateTimer4 = GetTime() + 60 + 50, GetTime() + 80
                M.portalattack[0], M.portalattack[1] = nil, nil
                M.soundhandle, M.recyclerDropped = nil, false
                -- // HideCockpitTimer();
            end
        end
    elseif M.missionState == MS_WAITFORREDDEVIL then
        if M.stateTimer < GetTime() then
            local maxgoodguysdead = 0
            -- PORT FIX: native `i < 10 || maxgoodguysdead == 5` reads beyond
            -- bdtank[9] when exactly five died. Bound the ten actual slots.
            -- Do NOT invent a five-unit cap: retain one replacement per dead
            -- tank (0..10), the same spawn point/path and 90-second timing.
            for i = 0, 9 do if not Alive(M.bdtank[i]) then maxgoodguysdead = maxgoodguysdead + 1 end end
            for i = 0, maxgoodguysdead - 1 do Spawn("bvrdeva", 1, "backup_1", Goto, "backup_path") end
            M.stateTimer, M.missionState = GetTime() + 60 + 30, MS_WAITFORBADGUY
        end
    elseif M.missionState == MS_WAITFORBADGUY then
        if M.stateTimer < GetTime() then
            for i = 0, 1 do M.badguy[i] = Spawn("cvtnk", 2, "attack_1", Attack, M.user) end
            M.missionState = MS_WAITFORBADGUY1DIE
        end
    elseif M.missionState == MS_WAITFORBADGUY1DIE then
        -- Preserve the source's FIRST-tank-only gate (not both tanks).
        if not Alive(M.badguy[0]) then
            M.stateTimer, M.missionState = GetTime() + (60 * 3), MS_WAITFORBADGUY2
        end
    elseif M.missionState == MS_WAITFORBADGUY2 then
        if M.stateTimer < GetTime() then
            for i = 0, 2 do M.badguy[i] = Spawn("cvtnk", 2, "attack_2", Attack, M.user) end
            M.missionState = MS_WAITFORBADGUY2DIE
        end
    elseif M.missionState == MS_WAITFORBADGUY2DIE then
        if not Alive(M.badguy[0]) and not Alive(M.badguy[1]) and not Alive(M.badguy[2]) then
            M.missionState = MS_WAITFORSOUND3
            resetObjectives()
            M.soundhandle = AudioMessage("bd06003.wav")
        end
    elseif M.missionState == MS_WAITFORSOUND3 then
        if AudioDone(M.soundhandle) then
            M.recycler = Spawn("bvrecy", 1, "recycler_spawn", Goto, "recycler_path")
            for i = 0, 1 do Spawn("bvrdeva", 1, "recycler_spawn", Follow, M.recycler) end
            M.stateTimer, M.missionState = GetTime() + 30, MS_WAITFOROBJECTIVE2
        end
    elseif M.missionState == MS_WAITFOROBJECTIVE2 then
        if M.stateTimer < GetTime() then
            M.missionState = MS_WAITFORRECYCLER
            resetObjectives()
        end
    elseif M.missionState == MS_WAITFORRECYCLER then
        if Valid(M.recycler) and GetCurrentCommand(M.recycler) == AiCommand.NONE then
            Deploy(M.recycler) -- stock equivalent of Recycler::Deploy()
            AudioMessage("bd06004.wav")
            M.missionState, M.stateTimer = MS_WAITFORBADGUY3, GetTime() + 60
        end
    elseif M.missionState == MS_WAITFORBADGUY3 then
        -- Preserve the native next-Update spawn: its +60 timer is NOT checked.
        for i = 0, 4 do Spawn("cvtnk", 2, "attack_3", Hunt) end
        M.missionState = MS_WAITFORAPC
    elseif M.missionState == MS_WAITFORAPC then
        -- APC proximity is checked before the state machine, as in Execute.
    elseif M.missionState == MS_ENDCUTSCENE then
        -- PORT FIX: source removes apchandle then uses that null camera target.
        -- The portal is the stationary subject once the APC has entered it;
        -- the camera path, height, speed and original finish gates are retained.
        local target = Valid(M.apchandle) and M.apchandle or M.portal
        local arrived = CameraPath("camera_end_scene", 2000, 0, target)
        if arrived or (M.stateTimer ~= 0 and (CameraCancelled() or M.stateTimer < GetTime())) then
            CameraFinish()
            M.missionState, M.stateTimer = MS_WAITING3, GetTime() + 5
        end
    elseif M.missionState == MS_WAITING3 then
        if M.stateTimer < GetTime() then
            for i = 0, 6 do Spawn("cvfigh", 2, "portal_attack_2", Attack, M.portal) end
            M.missionState = MS_WAITAPCFINISHED
        end
    elseif M.missionState == MS_WAITAPCFINISHED then
        if M.apcEntered and M.stateTimer2 < GetTime() then
            M.apchandle = Spawn("bvapc", 1, "portal", Goto, "apc_out")
            M.missionState = MS_WAITAPCOUT
        end
    elseif M.missionState == MS_WAITAPCOUT then
        -- PORT FIX: a null/destroyed exit APC must not masquerade as CMD_NONE
        -- and grant victory. No new loss condition is invented by this guard.
        if Valid(M.apchandle) and GetCurrentCommand(M.apchandle) == AiCommand.NONE then
            SucceedMission(GetTime() + 10, "bd06wina.des")
            M.lost = true
        end
        --[==[ Cut source: alternate audio-driven victory (still disabled).
                soundhandle = AudioMessage("bd06008.wav");
                missionState = MS_WAITFORSOUND8;
            }
            break;

        case MS_WAITFORSOUND8:
            if(IsAudioMessageDone(soundhandle))
            {
                missionState = MS_WAITING4;
                stateTimer = GetTime() + 5;
            }
            break;

        case MS_WAITING4:
            if(stateTimer < GetTime())
            {
                AudioMessage("bd06005.wav");
                SucceedMission(GetTime() + 10.0f, "bd06wina.des");
                lost = TRUE;
            }
            break;
        ]==]
    elseif M.missionState == MS_RECYCLERDEAD then
        if AudioDone(M.soundhandle) then
            FailMission(GetTime() + 2, "bd06lsec.des")
            M.lost = true
        end
    elseif M.missionState == MS_ATTACKTOEARLY then
        if AudioDone(M.soundhandle) then
            FailMission(GetTime() + 2, "bd06lsea.des")
            M.lost = true
        end
    end
end

-- Cut declarations: number of fighters attacking through the portal (2-5)
-- // portalAttackNum,
-- portal attack stage
-- // portalAttackStage,
-- CR co-op callbacks >>
-- The body is never edited: the runtime's per-frame calls wrap its callbacks here.
local BodyStart, BodyAddObject, BodyUpdate, BodySave, BodyLoad = Start, AddObject, Update, Save, Load
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
    if campaignRuntime then
        Restored.Run()
        campaignRuntime.AfterUpdate()
    end
end
function Save()
    if campaignRuntime then campaignRuntime.Save() end
    return BodySave()
end
function Load(state)
    BodyLoad(state)
    if campaignRuntime then campaignRuntime.Load() end
end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
