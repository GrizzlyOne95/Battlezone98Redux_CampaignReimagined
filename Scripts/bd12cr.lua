-- BlackDog12Mission.cpp: stock BZR 2.1+ / Lua 5.1 port.
-- Source blob: 584450878d2ed983c75195f10d8ccaeb6abcaedc.
-- Complete source, all comments and native serialization scaffolding:
-- References/BlackDog12Source/BlackDog12Mission.cpp.
-- No project helper / EXU / OpenShim dependency. Attach to the original bd12 map.
-- Zero-based arrays, strict timers, command priorities and Execute order kept.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN12_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn12CoopSourceParity.py).
-- CR co-op layer <<

local NEVER = 999999.9
-- low health warnings (source: shield warnings; also used for power units)
local warnings = {[0] = "bd12005.wav", "bd12006.wav", "bd12007.wav", "bd12008.wav"}
local desporSpawnSpots = {[0] = "despor_1", "despor_2", "despor_3", "despor_4"}

local function NewState()
    local s = {
        -- record whether the init code has been done
        startDone = false,
        -- objectives complete?
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused in source
        -- cameras
        cameraReady = {[0] = false, false},
        cameraComplete = {[0] = false, false}, -- second camera unused
        -- sounds
        camera1SoundPlayed = false, portalDeadSoundPlayed = false,
        -- delays initialized
        delaysInitialized = false,
        -- health low warnings? / despor units
        healthLow = {}, desporSpawned = {},
        -- have we lost?
        lost = false, won = false,
        delays = {}, camera1SoundDelay = NEVER, scrapDelay = NEVER,
        portalOnTime = NEVER, portalOffTime = NEVER,
        shields = {}, power = {}, goal = {},
        -- Native null handles/audio IDs are nil: user, recycler, portal,
        -- winSound, introSound, portalDeadSound.
    }
    for i = 0, 7 do s.healthLow[i] = false end
    for i = 0, 3 do s.desporSpawned[i] = false end
    for i = 0, 9 do s.delays[i] = NEVER end
    return s
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN12_COOP.md lists every wrapped call and restoration.
-- Each flag switches one restoration off (Docs/BDMISN12_COOP.md, "Restored content").
local RESTORED_VOICE_LINES = true
-- Off since the TRO 1.3 timing: the escorts now arrive while the portal is open (778-794 s), so no pulse is needed.
local RESTORED_PORTAL_PULSE = false
local Restored
-- Every Chinese combat craft of the four waves and the counterattack becomes a concealed, head-count-scaled ticket.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true, cvhtnk = true, cvhraz = true, cvwalk = true }
-- The geyser under each Chinese goal building (index = goal_N - 1; the vents the generated sites carry).
local GOAL_VENTS = { [0] = "eggeizr15_geyser", [1] = "eggeizr14_geyser", [2] = "eggeizr13_geyser" }
-- The vents next to the Black Dog base answer the loss of a shield or power generator pair.
local BASE_VENTS = { [0] = "eggeizr11_geyser", "eggeizr10_geyser", "eggeizr11_geyser", "eggeizr10_geyser" }
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn12", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "portal" }, -- the shared Black Dog base is the portal compound
    scaledOdfs = SCALED_ODFS,
    -- A staging point with a human within 460 m (despor_3 sits 420 m from the start) comes from the next hidden
    -- Chinese approach instead, farthest from the base first.
    fallbackEntries = { "attack_1", "attack_6", "attack_4", "attack_2", "attack_7", "attack_8" },
    liveCap = 24, -- wave 4 alone is fifteen units, with the counterattacks on top
    scrapPerGuest = 10,
    failDes = "bd12lsea.des", -- the shipped loss debrief, also used for out of lives
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- The portal's activation is a local effect of the object: every peer applies it to its own copy.
    presentationOps = { BD12Portal = function(mode) Restored.OpPortal(mode) end },
    -- Ganymede: CREuropaWeather over the generated BD12 sites (six geyser vents, three under the Chinese goals).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD12",
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
            local function fired(i) return state.delaysInitialized and state.delays[i] >= 999999 end
            -- The first Chinese raid breaks the silence: the quiet moon begins to stir.
            if (not beats.stirring) and fired(0) then
                beats.stirring = true
                ganymede.SetTargetLevel(2)
            end
            -- The second raid, with its heavy tank: the ice shell flexes.
            if (not beats.second) and fired(1) then
                beats.second = true
                ganymede.SetTargetLevel(3)
                ganymede.Quake(0.35, 3.0)
            end
            -- The bombers: a vent next to the base answers.
            if (not beats.third) and fired(2) then
                beats.third = true
                ganymede.Quake(0.3, 2.5)
                plume("eggeizr10_geyser")
            end
            -- The five walkers: the worst of the sky, Jupiter's radiation surging over the column.
            if (not beats.walkers) and fired(3) then
                beats.walkers = true
                ganymede.SetTargetLevel(4)
                ganymede.Quake(0.5, 3.5)
                ganymede.Surge(5.0, 0.9)
            end
            -- A shield or power generator falls and the counterattack tanks come: a vent opens under the base.
            for i = 0, 3 do
                if (not beats["despor" .. i]) and state.desporSpawned and state.desporSpawned[i] then
                    beats["despor" .. i] = true
                    ganymede.Quake(0.3, 2.5)
                    plume(BASE_VENTS[i])
                end
            end
            -- The portal opens ("strong electromagnetic pulses"): a surge and a quake.
            if (not beats.portal) and state.delaysInitialized and state.portalOnTime >= 999999 then
                beats.portal = true
                ganymede.Surge(6.0, 0.8)
                ganymede.Quake(0.35, 3.0)
            end
            -- Each Chinese goal that falls opens the geyser beneath it.
            for i, label in pairs(GOAL_VENTS) do
                local goal = state.goal and state.goal[i]
                if (not beats["goal" .. i]) and goal ~= nil and not IsValid(goal) then
                    beats["goal" .. i] = true
                    ganymede.Quake(0.4, 3.0)
                    plume(label)
                end
            end
            -- The base is saved and the sky eases for the debrief.
            if (not beats.easing) and state.won then
                beats.easing = true
                ganymede.SetTargetLevel(2)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
        update = function(R, _, authority) if Restored then Restored.Update(R, authority) end end,
    },
})
local NativeBuildObject, NativeSetCloaked = BuildObject, SetCloaked
local NativePortalOut, NativeActivatePortal, NativeDeactivatePortal = PortalOut, ActivatePortal, DeactivatePortal
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
-- A line whose audio handle is absent (nil or 0) counts as finished, so no gate can wait on it for ever.
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
-- Opening film. A shot starts with the host's skip latch cleared. The runtime stops driving a shot the host
-- skipped (it releases only the host's own camera), so in a network game that shot would never arrive and the
-- opening would never end for anyone: a skip raised after the shot began ends the shared opening instead.
local CameraReady = campaignRuntime and function()
    campaignRuntime.Native.CameraCancelled(true)
    return campaignRuntime.CameraReady()
end or CameraReady
local CameraPath = campaignRuntime and function(path, height, speed, target)
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if not arrived and campaignRuntime.Coop.IsNetworkGame() and campaignRuntime.Native.CameraCancelled() then return true end
    return arrived
end or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool).
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
    end
    return SetPilot(team, count)
end or SetPilot
-- Every Chinese combat craft is a ticket, and a new scripted group (a new frame or a new entry path) is a new
-- scaling event: the first unit of each group is mirrored by min(floor(humans / 2), 2) extras with its orders.
-- The scrap (team 0) is built straight through the runtime.
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
-- The raiders are cloaked: a unit that is still a ticket is cloaked when the real unit is built (Restored.Built).
local SetCloaked = campaignRuntime and function(h)
    if type(h) == "number" and h < 0 then
        if Restored then Restored.DeferCloak(-h) end
        return
    end
    return NativeSetCloaked(h)
end or SetCloaked
-- The portal is engine state each peer applies to its own copy of the map object.
local PortalOut = campaignRuntime and function() return campaignRuntime.Present("BD12Portal", 1) end or PortalOut
local ActivatePortal = campaignRuntime and function() return campaignRuntime.Present("BD12Portal", 2) end or ActivatePortal
local DeactivatePortal = campaignRuntime and function() return campaignRuntime.Present("BD12Portal", 0) end or DeactivatePortal
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Health(h)
    -- PORT FIX: deleted/missing objects must count as zero health without
    -- passing nil/stale handles to Lua API calls. This retains native death
    -- checks, warnings and victory/failure triggers for destroyed objects.
    if not Valid(h) then return 0 end
    return GetHealth(h)
end
local function CloakUnit(h)
    -- PORT FIX: failed builds cannot receive Lua commands. Successful builds
    -- keep the exact source cloak calls, targets and priority-1 commands.
    if Valid(h) then SetCloaked(h) end
end
local function AttackUnit(h, target, priority)
    if Valid(h) and Valid(target) then Attack(h, target, priority) end
end
local function DefendUnit(h, target, priority)
    if Valid(h) and Valid(target) then Defend2(h, target, priority) end
end
local function GotoUnit(h, path, priority)
    if Valid(h) then Goto(h, path, priority) end
end
local function BuildAtPortal(odf, team, portal)
    if Valid(portal) then return BuildObjectAtPortal(odf, team, portal) end
end
local function ActivateOutwardPortal()
    if Valid(M.portal) then
        -- Native activatePortal(portal, false): outward activation.
        PortalOut(M.portal)
        ActivatePortal(M.portal)
    end
end
local function ClosePortal()
    if Valid(M.portal) then DeactivatePortal(M.portal) end
end
local function AudioDone(message)
    -- PORT FIX: AudioMessage may return nil if playback fails. Treat that as
    -- completed to avoid an unwinnable/stalled ending or an invalid API call.
    -- Successful audio still gates the same +1 victory / +2 failure delay.
    return message == nil or IsAudioMessageDone(message)
end

-- CR restored content >>
-- The co-op fixes that need state, the weather sensor binding, the portal pulse and the unused voice line
-- (Docs/BDMISN12_COOP.md lists each). The restorations are gated by RESTORED_VOICE_LINES / RESTORED_PORTAL_PULSE.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function NearestHuman(unit)
        local best, bestDistance
        runtime.Coop.ForEachPlayerHandle(function(human)
            if Valid(human) then
                local distance = GetDistance(human, unit)
                if bestDistance == nil or distance < bestDistance then best, bestDistance = human, distance end
            end
        end)
        return best
    end
    -- The body cloaks every raider right after building it; for a ticket the cloak waits for the real unit
    -- (and for the extras that mirror it).
    function Restored.DeferCloak(id)
        local r = RState()
        r.cloak = r.cloak or {}
        r.cloak[id] = true
    end
    function Restored.Built(h, request, id)
        local r = RState()
        local key = (request and request.primary) or id
        if r.cloak and r.cloak[key] then NativeSetCloaked(h) end
    end
    -- Every peer: apply a portal mode to its own copy of the map object (0 closed, 1 outward, 2 activated).
    function Restored.OpPortal(mode)
        local portal = GetHandle("portal")
        if portal == nil or not IsValid(portal) then return end
        if mode == 1 then NativePortalOut(portal)
        elseif mode == 2 then NativeActivatePortal(portal)
        else NativeDeactivatePortal(portal) end
    end
    -- The objective list as the body publishes it, rebuilt from the mission state.
    local function ResetObjectives()
        ClearObjectives()
        if M.objective1Complete then
            AddObjective("bd12001.otf", "green")
            AddObjective("bd12002.otf", "white")
        else
            AddObjective("bd12001.otf", "white")
        end
    end
    local sensorsBound = false
    function Restored.OnLoad()
        sensorsBound = false
        RState().afterLoad = true
    end
    -- A load cannot resume a camera (the shots are gone): a film that was running opens its camera again; the
    -- body keeps calling its CameraPath every frame and ends the film itself. The runtime's Load resets the
    -- presentation, so the objectives are published again once the opening is over.
    function Restored.AfterLoad()
        if M.cameraReady[0] and not M.cameraComplete[0] then CameraReady() end
        if M.cameraComplete[0] then ResetObjectives() end
    end
    -- Every peer, every frame. The weather director's sensor modifier follows the director once both exist.
    function Restored.Update(R)
        if not sensorsBound and R.Weather and R.Weather.module.Initialized then
            sensorsBound = true
            pcall(function() require("Environment").BindWeatherSensors("Ganymede", R.Weather.module) end)
        end
    end
    -- Stock bug: the raiders are ordered once, against a shield, a generator or the portal. If that target is
    -- already gone when they are built (or dies before they arrive) the order is dropped and they stand where they
    -- were built. A scaled unit with no command attacks the nearest human instead, checked every 20 s.
    function Restored.Retarget(r)
        if type(GetCurrentCommand) ~= "function" or M.won or M.lost then return end
        local now = GetTime()
        if now < (r.retargetAt or 0) then return end
        r.retargetAt = now + 20
        local none = AiCommand and AiCommand.NONE or 0
        for _, h in ipairs(runtime.State().live) do
            if Valid(h) and IsAlive(h) and GetCurrentCommand(h) == none then
                local human = NearestHuman(h)
                if human ~= nil then Attack(h, human, 1) end
            end
        end
    end
    -- Unused voice line bd12002 ("Oh yeah, back home to roost. Now where're those commie bastards?"): the
    -- Sergeant's answer to the briefing, once the player has control of the base.
    function Restored.RoostLine(r)
        if not RESTORED_VOICE_LINES or r.roost or not M.cameraComplete[0] or M.won or M.lost then return end
        r.roost = true
        AudioMessage("bd12002.wav")
    end
    -- Stock timing: the escorts arrive at 546 s and 552 s while the portal is shut (it opens at 778 s). The
    -- portal pulses open two seconds before the first escort and the body's own close at 554 s ends the window.
    function Restored.PortalPulse(r)
        if not RESTORED_PORTAL_PULSE or r.pulsed or not M.delaysInitialized then return end
        if r.pulseAt == nil then
            if M.delays[5] >= 900000 then r.pulsed = true; return end -- the escorts are already through
            r.pulseAt = M.delays[5] - 2.0
        end
        if GetTime() >= r.pulseAt then
            r.pulsed = true
            PortalOut(M.portal)
            ActivatePortal(M.portal)
        end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad() end
        Restored.Retarget(r)
        Restored.RoostLine(r)
        Restored.PortalPulse(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn12] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    -- units (native Setup)
    M.portal = GetHandle("portal")
    for i = 0, 3 do
        M.shields[i] = GetHandle("shield_" .. (i + 1))
        M.power[i] = GetHandle("power_" .. (i + 1))
        M.goal[i] = GetHandle("goal_" .. (i + 1))
    end
end
function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<

    M.user = GetPlayerHandle() --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 50)
        SetScrap(2, 10)
        SetPilot(1, 10)

        -- don't do this part after the first shot
        M.startDone = true
    end

    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            M.cameraReady[0] = true
            CameraReady()
            M.camera1SoundDelay = GetTime() + 3.0
        end

        -- PORT FIX: finish a shot whose subject was deleted/missing via the
        -- same arrival branch; a valid portal keeps the original camera path.
        local arrived = not Valid(M.portal)
        if not arrived then arrived = CameraPath("camera_start", 300, 2000, M.portal) end

        if M.camera1SoundDelay < GetTime() then
            M.camera1SoundDelay = 999999.9
            M.camera1SoundPlayed = true
            M.introSound = AudioMessage("bd12001.wav")
        end

        if CameraCancelled() then
            arrived = true
            if M.introSound ~= nil then
                StopAudioMessage(M.introSound)
            end
        end

        if arrived then
            CameraFinish()
            M.cameraComplete[0] = true

            -- show objectives
            ClearObjectives()
            AddObjective("bd12001.otf", "white")
        end
    end

    -- objects spawned
    if not M.delaysInitialized then
        M.delaysInitialized = true

        M.delays[0] = GetTime() + 120.0 -- 2 minutes
        M.delays[1] = GetTime() + 240.0 -- 4 minutes
        M.delays[2] = GetTime() + 360.0 -- 6 minutes
        M.delays[3] = GetTime() + 480.0 -- 8 minutes
        -- TRO 1.3: recycler at 780 s with the portal open from 778 s, escorts at 786/792 s, portal
        -- closed at 794 s and the objective advance at 795 s (FUN_005aa100). The later C++ source
        -- had 546/552/555 s, which put the escorts through a closed portal.
        M.delays[4] = GetTime() + 13 * 60.0 -- 13 minutes
        M.portalOnTime = M.delays[4] - 2.0
        M.delays[5] = GetTime() + 786.0
        M.delays[6] = GetTime() + 792.0
        M.portalOffTime = M.delays[6] + 2.0
        M.delays[7] = GetTime() + 795.0

        M.scrapDelay = 60.0
    end

    -- delay 1
    if M.delays[0] < GetTime() then
        M.delays[0] = 999999.9

        -- 3 fighters
        local a1 = BuildObject("cvfigh", 2, "attack_1")
        CloakUnit(a1)
        AttackUnit(a1, M.power[0], 1)
        local a2 = BuildObject("cvfigh", 2, "attack_1")
        CloakUnit(a2)
        AttackUnit(a2, M.power[0], 1)
        local a3 = BuildObject("cvfigh", 2, "attack_1")
        CloakUnit(a3)
        AttackUnit(a3, M.power[0], 1)

        -- 2 defenders
        local d1 = BuildObject("cvtnk", 2, "defend_1")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvtnk", 2, "defend_1")
        CloakUnit(d2)
        DefendUnit(d2, a2, 1)
    end

    -- delay 2
    if M.delays[1] < GetTime() then
        M.delays[1] = 999999.9

        -- 3 fighters
        local a1 = BuildObject("cvfigh", 2, "attack_2")
        CloakUnit(a1)
        AttackUnit(a1, M.power[1], 1)
        local a2 = BuildObject("cvfigh", 2, "attack_2")
        CloakUnit(a2)
        AttackUnit(a2, M.power[1], 1)
        local a3 = BuildObject("cvfigh", 2, "attack_2")
        CloakUnit(a3)
        AttackUnit(a3, M.power[1], 1)

        -- 1 heavy tank
        local a4 = BuildObject("cvhtnk", 2, "attack_2")
        CloakUnit(a4)
        AttackUnit(a4, M.power[1], 1)

        -- defenders
        local d1 = BuildObject("cvfigh", 2, "defend_2")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvfigh", 2, "defend_2")
        CloakUnit(d2)
        DefendUnit(d2, a2, 1)
        local d3 = BuildObject("cvfigh", 2, "defend_2")
        CloakUnit(d3)
        DefendUnit(d3, a3, 1)
        local d4 = BuildObject("cvhtnk", 2, "defend_2")
        CloakUnit(d4)
        DefendUnit(d4, a4, 1)
    end

    -- delay 3
    if M.delays[2] < GetTime() then
        M.delays[2] = 999999.9

        -- 2 bombers
        local a1 = BuildObject("cvhraz", 2, "attack_3")
        CloakUnit(a1)
        AttackUnit(a1, M.power[2], 1)
        local a2 = BuildObject("cvhraz", 2, "attack_3")
        CloakUnit(a2)
        AttackUnit(a2, M.power[2], 1)

        -- 2 fighters
        local a3 = BuildObject("cvfigh", 2, "attack_3")
        CloakUnit(a3)
        AttackUnit(a3, M.power[2], 1)
        local a4 = BuildObject("cvfigh", 2, "attack_3")
        CloakUnit(a4)
        AttackUnit(a4, M.power[2], 1)

        -- defenders
        local d1 = BuildObject("cvtnk", 2, "defend_3")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvtnk", 2, "defend_3")
        CloakUnit(d2)
        DefendUnit(d2, a2, 1)
        local d3 = BuildObject("cvfigh", 2, "defend_3")
        CloakUnit(d3)
        DefendUnit(d3, a3, 1)
        local d4 = BuildObject("cvfigh", 2, "defend_3")
        CloakUnit(d4)
        DefendUnit(d4, a4, 1)
    end

    -- delay 4
    if M.delays[3] < GetTime() then
        M.delays[3] = 999999.9

        -- attacker 1
        local a1 = BuildObject("cvwalk", 2, "attack_4")
        AttackUnit(a1, M.shields[0], 1)
        -- and it's defence
        local d1 = BuildObject("cvltnk", 2, "defend_4")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvltnk", 2, "defend_4")
        CloakUnit(d2)
        DefendUnit(d2, a1, 1)

        -- attacker 2
        local a2 = BuildObject("cvwalk", 2, "attack_5")
        AttackUnit(a2, M.shields[1], 1)
        -- and it's defence
        local d3 = BuildObject("cvltnk", 2, "defend_5")
        CloakUnit(d3)
        DefendUnit(d3, a2, 1)
        local d4 = BuildObject("cvltnk", 2, "defend_5")
        CloakUnit(d4)
        DefendUnit(d4, a2, 1)

        -- attacker 3
        local a3 = BuildObject("cvwalk", 2, "attack_6")
        AttackUnit(a3, M.shields[2], 1)
        -- and it's defence
        local d5 = BuildObject("cvtnk", 2, "defend_6")
        CloakUnit(d5)
        DefendUnit(d5, a3, 1)
        local d6 = BuildObject("cvtnk", 2, "defend_6")
        CloakUnit(d6)
        DefendUnit(d6, a3, 1)

        -- attacker 4
        local a4 = BuildObject("cvwalk", 2, "attack_7")
        AttackUnit(a4, M.shields[3], 1)
        -- and it's defence
        local d7 = BuildObject("cvtnk", 2, "defend_7")
        CloakUnit(d7)
        DefendUnit(d7, a4, 1)
        local d8 = BuildObject("cvtnk", 2, "defend_7")
        CloakUnit(d8)
        DefendUnit(d8, a4, 1)

        -- attacker 5
        local a5 = BuildObject("cvwalk", 2, "attack_8")
        AttackUnit(a5, M.portal, 1)
        -- and it's defence
        local d9 = BuildObject("cvhtnk", 2, "defend_8")
        CloakUnit(d9)
        DefendUnit(d9, a5, 1)
        local d10 = BuildObject("cvhtnk", 2, "defend_8")
        CloakUnit(d10)
        DefendUnit(d10, a5, 1)
    end

    -- turn on/off the portal
    if M.portalOnTime < GetTime() then
        M.portalOnTime = 999999.9
        ActivateOutwardPortal()
    end

    if M.portalOffTime < GetTime() then
        M.portalOffTime = 999999.9
        ClosePortal()
    end

    -- delay 5
    if M.delays[4] < GetTime() then
        M.delays[4] = 999999.9

        M.recycler = BuildAtPortal("bvrecyd", 1, M.portal)
        GotoUnit(M.recycler, "follow", 1)
    end

    -- delay 6
    if M.delays[5] < GetTime() then
        M.delays[5] = 999999.9

        local h
        h = BuildAtPortal("bvtank", 1, M.portal)
        GotoUnit(h, "follow", 1)
        h = BuildAtPortal("bvtank", 1, M.portal)
        GotoUnit(h, "follow", 1)
    end

    -- delay 7
    if M.delays[6] < GetTime() then
        M.delays[6] = 999999.9

        local h = BuildAtPortal("bvfigh", 1, M.portal)
        GotoUnit(h, "follow", 1)
    end

    -- delay 8
    if M.delays[7] < GetTime() then
        M.delays[7] = 999999.9

        ClearObjectives()
        AddObjective("bd12001.otf", "green")
        AddObjective("bd12002.otf", "white")
        M.objective1Complete = true
    end

    -- check the goals
    if M.objective1Complete and not M.objective2Complete then
        M.objective2Complete = true
        for i = 0, 3 do
            if Health(M.goal[i]) > 0.0 then
                M.objective2Complete = false
                break
            end
        end

        if M.objective2Complete then
            -- start the sound
            M.winSound = AudioMessage("bd12003.wav")
        end
    end

    if M.objective2Complete and not M.won and not M.lost then
        if AudioDone(M.winSound) then
            M.won = true
            SucceedMission(GetTime() + 1.0, "bd12win.des")
        end
    end

    -- TRO 1.3 spawns no scrap here (scrapDelay is set but never read in FUN_005aa100), so the
    -- later source's six npscr1 pickups per minute are gone.

    -- low health warnings?
    for i = 0, 3 do
        -- check the power units
        if not M.healthLow[i] and Health(M.power[i]) < 0.25 then
            M.healthLow[i] = true
            AudioMessage(warnings[i])
        end

        -- check the shield units
        if not M.healthLow[4+i] and Health(M.shields[i]) < 0.25 then
            M.healthLow[4+i] = true
            AudioMessage(warnings[i])
        end
    end

    -- shields or power dead?
    for i = 0, 3 do
        if not M.desporSpawned[i] then
            if Health(M.power[i]) <= 0.0 or Health(M.shields[i]) <= 0.0 then
                M.desporSpawned[i] = true
                local h
                h = BuildObject("cvltnk", 2, desporSpawnSpots[i])
                CloakUnit(h)
                AttackUnit(h, M.portal, 1)
                h = BuildObject("cvltnk", 2, desporSpawnSpots[i])
                CloakUnit(h)
                AttackUnit(h, M.portal, 1)
            end
        end
    end

    -- portal dead?
    if Health(M.portal) <= 0.0 and not M.portalDeadSoundPlayed then
        M.portalDeadSoundPlayed = true
        M.portalDeadSound = AudioMessage("bd12004.wav")
    end

    if M.portalDeadSoundPlayed and not M.lost and not M.won then
        if AudioDone(M.portalDeadSound) then
            M.lost = true
            FailMission(GetTime() + 2.0, "bd12lsea.des")
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
    -- LuaMission restores tables and remaps handles/messages; do not rerun
    -- Setup or reset timers, cameras, warnings, spawns or outcome latches.
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
