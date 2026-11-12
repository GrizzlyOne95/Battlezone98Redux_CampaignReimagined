-- Faithful Chinese02Mission port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Chinese02Mission.cpp
-- Source blob: a73b6107b9e22c7073d36f9e102322c360c511ca.
-- Full source (including declarations, serialization and cut content):
-- References/Chinese02Source/Chinese02Mission.cpp.
-- Stock BZR 2.1 APIs only; no EXU/OpenShim/campaign helper dependency.
-- Arrays deliberately retain C++ zero-based indexes. Do not use # on them.
-- Event order, strict timer comparisons, wave composition and AI priorities
-- match the source. Unused objective flags, camera slot 1, factory handle and
-- apcArrived flags are retained for reconstructing cut content.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/CHMISN02_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Chmisn02CoopSourceParity.py).
-- CR co-op layer <<

local DISABLED_TIME = 999999.9
local function NewState()
    -- Native Load initializes all storage before Setup, including won/lost
    -- and the unused factory. Lua represents NULL handles/messages as nil.
    return {
        won = false, lost = false,
        cameraReady = {}, cameraComplete = {}, apcArrived = {},
        attack3 = {}, attack5 = {}, apc = {},
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/CHMISN02_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/CHMISN02_COOP.md, "Restored content").
local RESTORED_WALKER_AMBUSH = true -- the #if 0 ambush at walker_attack_1
local RESTORED_WALKER_RAZORS = true -- the commented-out heavy razors at walker_attack_3
local RESTORED_ATTACK_9_PATH = true -- the authored but never used attack_9_path
local RESTORED_VOICE_LINES = true -- ch03007 (convoy lost) and ch04005 (defector lost): shipped, never played
local Restored = { builtAt = {} }
local ENEMY_TEAM = 5 -- the body says team 2; team 2 is a human slot in co-op
-- Every Soviet combat craft the script builds (the body builds them all on team 2) becomes a concealed,
-- head-count-scaled ticket. The convoy (team 1), its escorts and the defecting walker (team 0) are built straight.
local SCALED_ODFS = { svfigh = true, svtank = true, svwalk = true, svhraz = true, svartl = true, svltnk = true,
    svrckt = true }
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "ch02cr", leaderTeam = 1, enemyTeam = ENEMY_TEAM, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- respawn at the shared Chinese base
    scaledOdfs = SCALED_ODFS,
    -- The raids leave from the valley around the base and hanger_attack_5/6 sit 320-340 m from the hangar: 300 m
    -- keeps units from popping into a human's face without holding the whole siege back. A watched spawn comes
    -- from the next hidden approach instead.
    safeRadius = 300,
    fallbackEntries = { "attack_8", "hanger_attack_3", "attack_10", "attack_7", "attack_6", "attack_9",
        "hanger_attack_4", "convoy_attack_10" },
    liveCap = 36, -- the post-attack_5 raid alone is twenty units, plus the extras of each event
    scrapPerGuest = 10,
    failDes = "ch02lsea.des", -- out of lives: the hangar-lost debrief
    wonFlags = { "won" }, -- a convoy has reached the hangar: a late out-of-lives failure is ignored
    endedFlags = { "lost", "won" }, -- the result is decided: nothing more is built
    orders = { "Goto", "Attack", "Hunt" }, -- replayed on the real unit when a ticket is built
    -- Ganymede: CREuropaWeather over the generated CH02 sites (seven geyser vents, the first beside the armoury).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesCH02", glassFrost = 0.15, startLevel = 1, targetLevel = 1,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local NEVER = 999999
            local function plume(index)
                if #europa.GetVentSites() >= index then europa.TriggerPlume(index) end
            end
            -- The timers read "never" before they are armed and after they fire: latch them while armed.
            if state.sound2Time < NEVER then beats.warnArmed = true end
            if state.attack5DestroyedSpawnTime < NEVER then beats.raidArmed = true end
            if state.walkerTime < NEVER then beats.walkerArmed = true end
            -- "Incoming CCA forces": the quiet moon begins to stir.
            if (not beats.warn) and beats.warnArmed and state.sound2Time >= NEVER then
                beats.warn = true
                europa.SetTargetLevel(2)
            end
            -- The first Soviet column is broken: the ice shell flexes.
            if (not beats.column) and state.attack3Destroyed then
                beats.column = true
                europa.Quake(0.3, 2.5)
            end
            -- The big raid leaves attack_6 and attack_7: a vent blows at the base and the ground shakes.
            if (not beats.raid) and beats.raidArmed and state.attack5DestroyedSpawnTime >= NEVER then
                beats.raid = true
                europa.SetTargetLevel(3)
                plume(1)
                europa.Quake(0.35, 3.0)
                europa.Surge(6.0, 0.8)
            end
            -- The defecting walker comes in under fire.
            if (not beats.walker) and beats.walkerArmed and state.walkerTime >= NEVER then
                beats.walker = true
                europa.Quake(0.3, 2.5)
                plume(5)
            end
            -- General Fu's convoy rolls: the worst of the sky, Jupiter's radiation surging.
            if (not beats.convoy) and state.apcSpawned then
                beats.convoy = true
                europa.SetTargetLevel(4)
                europa.Quake(0.5, 3.5)
                europa.Surge(5.0, 0.9)
            end
            -- The convoy is hit: the ground answers.
            if (not beats.hit) and state.apcDamaged then
                beats.hit = true
                europa.Quake(0.4, 3.0)
                plume(2)
            end
            -- The convoy reaches the hangar: everything calms while the debrief plays.
            if (not beats.calm) and state.won then
                beats.calm = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
            -- The hangar, the convoy or the defector is lost: a last surge over the base.
            if (not beats.lost) and state.lost and not state.won then
                beats.lost = true
                europa.Surge(6.0, 0.8)
                europa.Quake(0.35, 3.0)
            end
        end },
    hooks = {
        load = function() Restored.OnLoad() end,
    },
    -- Cloaking is local engine state: it is switched off on every peer through the stream.
    presentationOps = {
        CH2Cloak = function(on) Restored.OpCloak(on) end,
    },
})
local NativeBuildObject, NativeAudioDone, NativeEnableAllCloaking = BuildObject, IsAudioMessageDone, EnableAllCloaking
function Restored.OpCloak(on) NativeEnableAllCloaking(on == 1) end
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Hunt = campaignRuntime and campaignRuntime.Hunt or Hunt
local ClearObjectives = campaignRuntime and function()
    Restored.Objectives(nil)
    return campaignRuntime.ClearObjectives()
end or ClearObjectives
local AddObjective = campaignRuntime and function(text, color)
    Restored.Objectives(text, color)
    return campaignRuntime.AddObjective(text, color)
end or AddObjective
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
-- SetName is not replicated; the runtime names the object on every peer (a stock alias of SetObjectiveName).
local SetName = campaignRuntime and function(h, name) return campaignRuntime.SetObjectiveName(h, name) end or SetName
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
-- The defector walker's loss ends the mission without a word in the source: the restored reproach plays first
-- and the debrief waits for it (RESTORED_VOICE_LINES, Docs/CHMISN02_COOP.md).
local FailMission = campaignRuntime and function(when, description)
    if RESTORED_VOICE_LINES and description == "ch02lsec.des" then
        Restored.DefectorLost()
        when = when + 7.0
    end
    return campaignRuntime.FailMission(when, description)
end or FailMission
-- The runtime hands out a handle (or 0) for every line; a line whose audio handle is absent counts as finished,
-- so no gate can wait on it for ever.
local AudioMessage = campaignRuntime and function(file) return campaignRuntime.AudioMessage(file) or 0 end or AudioMessage
local StopAudioMessage = campaignRuntime and function(message)
    if message == nil or message == 0 then return end
    return campaignRuntime.StopAudioMessage(message)
end or StopAudioMessage
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    if campaignRuntime and Restored.LineBusy(message) then return false end
    return NativeAudioDone(message)
end
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
-- The cockpit countdown is presentation: every peer shows the host's timer.
local StartCockpitTimer = campaignRuntime and function(seconds, ...)
    return campaignRuntime.Present("StartCockpitTimer", seconds, ...)
end or StartCockpitTimer
-- The body's team 1 is the one shared Chinese side: its 10 pilots go to every human team (each human respawns
-- from its own pool).
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
    end
    return SetPilot(team, count)
end or SetPilot
-- Each scripted group (a new frame or a new entry path) is a new scaling event: the first unit of the group is
-- mirrored by min(floor(humans / 2), 2) extras with its orders. The convoy (team 1) and the defecting walker
-- (team 0) are built straight through.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where)
    local h
    if team == 2 then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
        h = campaignRuntime.Spawn(odf, team, where)
    else
        h = NativeBuildObject(odf, team, where)
    end
    if h ~= nil then Restored.builtAt[h] = where end
    return h
end or BuildObject
-- Goto: the attack_9 column takes its authored route (RESTORED_ATTACK_9_PATH). The body's last-resort target
-- (the "player" token, when no base building is left) cannot be reached: a dead hangar is a loss and ends the spawns.
local Goto = campaignRuntime and function(h, target, priority)
    if RESTORED_ATTACK_9_PATH and Restored.builtAt[h] == "attack_9" and campaignRuntime.PathExists("attack_9_path") then
        target = "attack_9_path"
    end
    return campaignRuntime.Goto(h, target, priority)
end or Goto
-- A save during a shot cannot resume it (the cameras are gone): the first CameraPath after the load reports arrival.
-- The body ends the opening on CameraPath's return, and a skip releases only the skipper's own native camera (the
-- runtime then stops calling the native path, so the host would never "arrive"): in a network game the shot also
-- ends at its flight time plus a margin. CAMERA_ETA is path length / (speed / 100) in seconds (the contract test
-- recomputes it from the map).
local CAMERA_ETA = { camera_start = 16.6 }
local shotPath, shotStart
local CameraPath = campaignRuntime and function(path, height, speed, target)
    if Restored.SkipCamera() then shotPath = nil; return true end
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if arrived then shotPath = nil; return arrived end
    if CAMERA_ETA[path] and campaignRuntime.Coop.IsNetworkGame() then
        local now = GetTime()
        if shotPath ~= path then shotPath, shotStart = path, now end
        if now - shotStart > CAMERA_ETA[path] * 1.25 + 3 then shotPath = nil; return true end
    end
    return arrived
end or CameraPath
local EnableAllCloaking = campaignRuntime and function(on)
    return campaignRuntime.Present("CH2Cloak", on and 1 or 0)
end or EnableAllCloaking
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function Health(h)
    -- PORT FIX: native null/deleted handles have zero health. Avoid Lua
    -- overload errors on nil; living-object health and loss timing are intact.
    if not Valid(h) then return 0.0 end
    return GetHealth(h)
end

local function Distance(h, target, point)
    -- PORT FIX: missing objects cannot satisfy a proximity trigger. Avoid
    -- invalid Lua distance overloads without altering valid-object distances.
    if not Valid(h) or (type(target) ~= "string" and not Valid(target)) then
        return math.huge
    end
    if point ~= nil then return GetDistance(h, target, point) end
    return GetDistance(h, target)
end

local function ConvoyNear(target, radius)
    -- PORT FIX: the source queries every APC handle, including wrecks. Only
    -- a live APC can trigger an ambush or arrive at the hangar. Living convoy
    -- trigger radii, order and one-APC victory rule are unchanged.
    for i = 0, 2 do
        if Health(M.apc[i]) > 0.0 and Distance(M.apc[i], target) < radius then
            return true
        end
    end
    return false
end

local function AtEndOfPath(h, path)
    -- PORT ADAPTATION: native isAtEndOfPath is not a stock Lua global. Use
    -- stock zero-based path queries, explicitly checking the LAST waypoint.
    -- Its implementation/radius is absent from the supplied source. 25 m is
    -- an explicit provisional tolerance; validate against the original map.
    -- TRO 1.3: 2D (x,z) distance to the last waypoint < 12 m (FUN_005b0460).
    local count = GetPathPointCount(path)
    if Health(h) <= 0.0 or count <= 0 then return false end
    local p, e = GetPosition(h), GetPosition(path, count - 1)
    local dx, dz = p.x - e.x, p.z - e.z
    return math.sqrt(dx * dx + dz * dz) < 12.0
end

local function getLiveApc()
    local candidates = {}
    for i = 0, 2 do
        if Health(M.apc[i]) > 0.0 then
            candidates[#candidates + 1] = M.apc[i]
        end
    end
    if #candidates == 0 then return nil end
    -- Uniform live-target selection replaces native rand() % numApc.
    return candidates[math.random(1, #candidates)]
end

local function getBase()
    local candidates = {}
    -- Preserve native candidate order and independent choice per attacker.
    for _, key in ipairs({ "hangar", "recycler", "armoury", "commTower" }) do
        if Health(M[key]) > 0.0 then candidates[#candidates + 1] = M[key] end
    end
    if #candidates == 0 then return M.user end
    return candidates[math.random(1, #candidates)]
end

local function GotoLiveApc(h)
    local target = getLiveApc()
    -- PORT FIX: native getLiveApc can return NULL after the convoy dies.
    -- Keep the scheduled spawn, but skip a Lua Goto with no destination.
    -- Every attack with a surviving APC retains its original order/priority.
    if target ~= nil then Goto(h, target, 1) end
end
-- CR co-op fixes >>
-- The co-op state: the objective list the runtime's Load drops, the load fix for the opening shot, and the cut
-- content (Docs/CHMISN02_COOP.md lists each). Every restoration is gated by a RESTORED_* flag and by the map
-- carrying the path.
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- The objective list as the body published it, so a load can publish it again.
    function Restored.Objectives(text, color)
        local r = RState()
        if text == nil then r.objectives = {}; return end
        r.objectives = r.objectives or {}
        r.objectives[#r.objectives + 1] = { text, color }
    end
    function Restored.OnLoad()
        RState().skipCamera = (M.cameraReady[0] == true and not M.cameraComplete[0]) or nil
        RState().afterLoad = true
    end
    function Restored.SkipCamera()
        local r = RState()
        if r.skipCamera then r.skipCamera = nil; return true end
        return false
    end
    -- The runtime's Load resets the presentation (objective list, markers): they come back from the saved state.
    function Restored.AfterLoad()
        runtime.ClearObjectives()
        for _, entry in ipairs(RState().objectives or {}) do runtime.AddObjective(entry[1], entry[2]) end
        if Valid(M.walker) then runtime.SetObjectiveOn(M.walker) end
        if Valid(M.convoyIntercept) then runtime.SetObjectiveName(M.convoyIntercept, "Convoy Intercept") end
    end
    -- ch03007 follows ch02006 when two convoy APCs are lost: the body only waits for its own line.
    function Restored.LineBusy(message)
        local r = RState()
        if r.convoyLine == nil or r.convoyLine == 0 or message ~= M.lose2Sound then return false end
        return not NativeAudioDone(r.convoyLine)
    end
    function Restored.DefectorLost()
        local r = RState()
        if r.defectorLine then return end
        r.defectorLine = true
        AudioMessage("ch04005.wav")
    end
    local function Raider(odf, where, target)
        local h = BuildObject(odf, 2, where)
        Attack(h, target, 1)
    end
    -- Runs after the body's Update, authority only.
    function Restored.Step()
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad() end
        -- Cut: the `#if 0` ambush as the walker passes walker_attack_1 (300 m): two Soviet fighters.
        if RESTORED_WALKER_AMBUSH and Valid(M.walker) and not M.walkerAttack1
            and runtime.PathExists("walker_attack_1") and Distance(M.walker, "walker_attack_1") < 300 then
            M.walkerAttack1 = true
            Raider("svfigh", "walker_attack_1", M.walker)
            Raider("svfigh", "walker_attack_1", M.walker)
        end
        -- Cut: the two heavy razors commented out of the walker_attack_3 ambush (the body's four tanks are built).
        if RESTORED_WALKER_RAZORS and M.walkerAttack3 and not r.razors then
            r.razors = true
            if Valid(M.walker) and runtime.PathExists("walker_attack_3") then
                Raider("svhraz", "walker_attack_3", M.walker)
                Raider("svhraz", "walker_attack_3", M.walker)
            end
        end
        -- Unused shipped line ch03007 closes the convoy-lost reproach.
        if RESTORED_VOICE_LINES and M.lose2Sound ~= nil and not r.convoyLine then
            r.convoyLine = AudioMessage("ch03007.wav")
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[ch02cr] restored content failed: " .. tostring(err))
        end
    end
end
-- CR co-op fixes <<

function Start()
    M = NewState()
    M.startDone = false
    M.objective1Complete = false
    M.objective2Complete = false
    M.cameraArrived = false
    M.attack3Destroyed = false
    M.attack5Destroyed = false
    M.apcSpawned = false
    M.apcDamaged = false
    M.apcArrived[0] = false
    M.apcArrived[1] = false
    M.apcArrived[2] = false
    M.apcTrigger1 = false
    M.apcTrigger2 = false
    M.apcAtHangar = false
    M.walkerAttack1 = false
    M.walkerAttack2 = false
    M.walkerAttack3 = false
    -- cameras
    for i = 0, 1 do
        M.cameraReady[i] = false
        M.cameraComplete[i] = false
    end
    -- units
    M.user = nil
    M.recycler = GetHandle("recycler")
    M.hangar = GetHandle("hanger")
    M.commTower = GetHandle("comm_tower")
    M.armoury = GetHandle("armory")
    M.attack3[0] = GetHandle("attack_3_1")
    M.attack3[1] = GetHandle("attack_3_2")
    M.attack3[2] = GetHandle("attack_3_3")
    M.attack3[3] = GetHandle("attack_3_4")
    M.attack3[4] = GetHandle("attack_3_5")
    M.attack5[0] = GetHandle("attack_5_1")
    M.attack5[1] = GetHandle("attack_5_2")
    M.attack5[2] = GetHandle("attack_5_3")
    M.attack5[3] = GetHandle("attack_5_4")
    M.attack5[4] = GetHandle("attack_5_5")
    M.apc[0] = nil
    M.apc[1] = nil
    M.apc[2] = nil
    M.walker = nil
    -- navs
    M.convoyIntercept = nil
    -- sounds
    M.openingSound = nil
    M.lose1Sound = nil
    M.lose2Sound = nil
    M.winSound = nil
    -- times
    M.openingSoundTime = DISABLED_TIME
    M.cameraPauseTime = DISABLED_TIME
    M.sound2Time = DISABLED_TIME
    M.attack5DestroyedSpawnTime = DISABLED_TIME
    M.attack8Time = DISABLED_TIME
    M.convoyTime = DISABLED_TIME
    M.convoyAttack1Time = DISABLED_TIME
    M.walkerTime = DISABLED_TIME
    M.hangarAttack5Time = DISABLED_TIME
    M.hangarAttack6Time = DISABLED_TIME
    M.annoyTime = DISABLED_TIME
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.user = GetPlayerHandle()
    -- assigns the player a handle every frame
    if not M.startDone then
        SetScrap(1, 30)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        -- disable all cloaking for this mission
        EnableAllCloaking(false)
        M.openingSoundTime = GetTime() + 1.0
    end
    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            M.cameraReady[0] = true
            CameraReady()
        end
        local complete = false
        if not M.cameraArrived then
            M.cameraArrived = CameraPath("camera_start", 800, 2000, M.hangar)
            if M.cameraArrived then
                M.cameraPauseTime = GetTime() + 2.0
            end
        elseif M.cameraPauseTime < GetTime() then
            complete = true
        end
        if CameraCancelled() then
            complete = true
            -- PORT FIX: cancellation can precede the first audio message.
            -- Skip stopping a nil message; cinematic timing is unchanged.
            if M.openingSound ~= nil then StopAudioMessage(M.openingSound) end
        end
        if complete then
            CameraFinish()
            M.cameraComplete[0] = true
            ClearObjectives()
            AddObjective("ch02001.otf", "white")
            M.sound2Time = GetTime() + 60.0
            M.annoyTime = GetTime() + 120.0
            M.openingSoundTime = DISABLED_TIME
        end
    end
    if M.annoyTime < GetTime() then
        M.annoyTime = GetTime() + 120.0
        local h
        h = BuildObject("svltnk", 2, "annoy_1")
        Hunt(h, 1)
        h = BuildObject("svltnk", 2, "annoy_1")
        Hunt(h, 1)
        h = BuildObject("svfigh", 2, "annoy_1")
        Hunt(h, 1)
        h = BuildObject("svfigh", 2, "annoy_1")
        Hunt(h, 1)
    end
    if M.openingSoundTime < GetTime() then
        M.openingSoundTime = DISABLED_TIME
        M.openingSound = AudioMessage("ch02001.wav")
    end
    if M.openingSound ~= nil and IsAudioMessageDone(M.openingSound) then
        M.openingSound = nil
    end
    if M.sound2Time < GetTime() then
        M.sound2Time = DISABLED_TIME
        AudioMessage("ch02002.wav")
    end
    -- are our important units destroyed?
    if Health(M.hangar) <= 0.0 and not M.lost and not M.won then
        M.lost = true
        M.lose1Sound = AudioMessage("ch02006.wav")
    end
    if M.lose1Sound ~= nil and IsAudioMessageDone(M.lose1Sound) then
        M.lose1Sound = nil
        FailMission(GetTime() + 1.0, "ch02lsea.des")
    end
    -- have we lost 2 or more APCs?
    if M.apcSpawned and not M.lost and not M.won then
        local apcDead = 0
        for i = 0, 2 do
            if Health(M.apc[i]) <= 0.0 and not M.apcArrived[i] then
                apcDead = apcDead + 1
            end
        end
        if apcDead >= 2 then
            M.lost = true
            M.lose2Sound = AudioMessage("ch02006.wav")
        end
    end
    if M.lose2Sound ~= nil and IsAudioMessageDone(M.lose2Sound) then
        M.lose2Sound = nil
        FailMission(GetTime() + 1.0, "ch02lseb.des")
    end
    -- attack_3 destroyed?
    if not M.attack3Destroyed then
        M.attack3Destroyed = true
        for i = 0, 4 do
            if Alive(M.attack3[i]) then
                M.attack3Destroyed = false
                break
            end
        end
        if M.attack3Destroyed then
            local h = BuildObject("svartl", 2, "hanger_attack_2")
            Attack(h, M.hangar, 1)
        end
    end
    -- attack_5 destroyed?
    if not M.attack5Destroyed then
        M.attack5Destroyed = true
        for i = 0, 4 do
            if Alive(M.attack5[i]) then
                M.attack5Destroyed = false
                break
            end
        end
        if M.attack5Destroyed then
            M.attack5DestroyedSpawnTime = GetTime() + 60.0
        end
    end
    if M.attack5DestroyedSpawnTime < GetTime() then
        M.attack5DestroyedSpawnTime = DISABLED_TIME
        local h
        -- spawn at attack_6
        h = BuildObject("svfigh", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svfigh", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svfigh", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svtank", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svtank", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svtank", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svwalk", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svwalk", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        h = BuildObject("svwalk", 2, "attack_6")
        Goto(h, "attack_6_path", 1)
        -- spawn at attack_7
        h = BuildObject("svfigh", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svfigh", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svfigh", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svtank", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svtank", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svtank", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_7")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_7")
        Goto(h, getBase(), 1)
        -- spawn at hanger_attack_3
        h = BuildObject("svhraz", 2, "hanger_attack_3")
        Attack(h, M.hangar, 1)
        h = BuildObject("svhraz", 2, "hanger_attack_3")
        Attack(h, M.hangar, 1)
        -- setup for walker spawn time
        M.walkerTime = GetTime() + 240.0
    end
    if M.walkerTime < GetTime() then
        M.walkerTime = DISABLED_TIME
        M.walker = BuildObject("svwalk", 0, "walker_spawn")
        SetObjectiveOn(M.walker)
        SetPerceivedTeam(M.walker, 1)
        Retreat(M.walker, "walker_path")
        AudioMessage("ch02007.wav")
        -- AudioMessage("ch02008.wav")
        -- setup for hangar attack
        M.hangarAttack5Time = GetTime() + 10.0
        -- set up for attack_8
        M.attack8Time = GetTime() + 300.0
        -- objectives
        ClearObjectives()
        AddObjective("ch02001.otf", "white")
        AddObjective("ch02003.otf", "white")
    end
    --[=[ Cut content: source #if 0, translated to Lua but disabled.
    if M.walker ~= nil and not M.walkerAttack1
        and Distance(M.walker, "walker_attack_1") < 300 then
        M.walkerAttack1 = true
        local h
        h = BuildObject("svfigh", 2, "walker_attack_1")
        Attack(h, M.walker, 1)
        h = BuildObject("svfigh", 2, "walker_attack_1")
        Attack(h, M.walker, 1)
    end
    ]=]
    if M.walker ~= nil and not M.walkerAttack2 and Distance(M.walker, "walker_attack_2") < 200 then
        M.walkerAttack2 = true
        local h
        h = BuildObject("svfigh", 2, "walker_attack_2")
        Attack(h, M.walker, 1)
        h = BuildObject("svfigh", 2, "walker_attack_2")
        Attack(h, M.walker, 1)
        h = BuildObject("svltnk", 2, "walker_attack_2")
        Attack(h, M.walker, 1)
        h = BuildObject("svltnk", 2, "walker_attack_2")
        Attack(h, M.walker, 1)
        h = BuildObject("svtank", 2, "walker_attack_2")
        Attack(h, M.walker, 1)
        h = BuildObject("svtank", 2, "walker_attack_2")
        Attack(h, M.walker, 1)
    end
    if M.walker ~= nil and not M.walkerAttack3 and Distance(M.walker, "walker_attack_3") < 200 then
        M.walkerAttack3 = true
        local h
        -- h = BuildObject("svhraz", 2, "walker_attack_3")
        -- Attack(h, M.walker, 1)
        -- h = BuildObject("svhraz", 2, "walker_attack_3")
        -- Attack(h, M.walker, 1)
        h = BuildObject("svltnk", 2, "walker_attack_3")
        Attack(h, M.walker, 1)
        h = BuildObject("svltnk", 2, "walker_attack_3")
        Attack(h, M.walker, 1)
        h = BuildObject("svtank", 2, "walker_attack_3")
        Attack(h, M.walker, 1)
        h = BuildObject("svtank", 2, "walker_attack_3")
        Attack(h, M.walker, 1)
    end
    if M.walker ~= nil and Health(M.walker) <= 0.0 and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime(), "ch02lsec.des")
    end
    if M.walker ~= nil and AtEndOfPath(M.walker, "walker_path") then
        SetTeamNum(M.walker, 1)
        -- Native Recycle is issued through the stock generic command API.
        SetCommand(M.walker, AiCommand.RECYCLE, 1)
        M.walker = nil
        AudioMessage("ch02008.wav")
        -- TRO 1.3: arrival turns ch02003 green and lists ch02002 once the convoy exists (FUN_005b0460)
        M.objective2Complete = true
        ClearObjectives()
        AddObjective("ch02001.otf", "white")
        AddObjective("ch02003.otf", "green")
        if M.apcSpawned then AddObjective("ch02002.otf", "white") end
    end
    if M.hangarAttack5Time < GetTime() then
        M.hangarAttack5Time = DISABLED_TIME
        local h = BuildObject("svartl", 2, "hanger_attack_5")
        Attack(h, M.hangar, 1)
    end
    if M.attack8Time < GetTime() then
        M.attack8Time = DISABLED_TIME
        local h
        h = BuildObject("svtank", 2, "attack_8")
        Goto(h, getBase(), 1)
        h = BuildObject("svtank", 2, "attack_8")
        Goto(h, getBase(), 1)
        h = BuildObject("svtank", 2, "attack_8")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_8")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_8")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_8")
        Goto(h, getBase(), 1)
        h = BuildObject("svwalk", 2, "attack_8")
        Goto(h, getBase(), 1)
        M.convoyTime = GetTime() + 270.0
    end
    -- spawn the convoy
    if M.convoyTime < GetTime() then
        M.convoyTime = DISABLED_TIME
        AudioMessage("ch02003.wav")
        -- TRO 1.3: the convoy objective is listed as soon as the convoy spawns (FUN_005b0460)
        ClearObjectives()
        AddObjective("ch02001.otf", "white")
        AddObjective("ch02003.otf", M.objective2Complete and "green" or "white")
        AddObjective("ch02002.otf", "white")
        -- spawn the APCs
        M.apcSpawned = true
        M.apc[0] = BuildObject("cvapcb", 1, "convoy_units")
        Goto(M.apc[0], "convoy_path")
        M.apc[1] = BuildObject("cvapcb", 1, "convoy_units")
        Goto(M.apc[1], "convoy_path")
        M.apc[2] = BuildObject("cvapcb", 1, "convoy_units")
        Goto(M.apc[2], "convoy_path")
        -- spawn the scouts
        local h
        h = BuildObject("cvfighc", 1, "convoy_defend")
        Defend2(h, M.apc[0], 1)
        h = BuildObject("cvfighc", 1, "convoy_defend")
        Defend2(h, M.apc[0], 1)
        h = BuildObject("cvfighc", 1, "convoy_defend")
        Defend2(h, M.apc[1], 1)
        h = BuildObject("cvfighc", 1, "convoy_defend")
        Defend2(h, M.apc[1], 1)
        h = BuildObject("cvfighc", 1, "convoy_defend")
        Defend2(h, M.apc[2], 1)
        h = BuildObject("cvfighc", 1, "convoy_defend")
        Defend2(h, M.apc[2], 1)
        M.convoyAttack1Time = GetTime() + 60.0
        M.hangarAttack6Time = GetTime() + 5 * 60.0
    end
    if M.hangarAttack6Time < GetTime() then
        M.hangarAttack6Time = DISABLED_TIME
        for i = 0, 1 do
            local h = BuildObject("svartl", 2, "hanger_attack_6")
            Attack(h, M.hangar, 1)
        end
    end
    if M.convoyAttack1Time < GetTime() then
        M.convoyAttack1Time = DISABLED_TIME
        local h
        -- spawn convoy_attack_1
        h = BuildObject("svfigh", 2, "convoy_attack_1")
        GotoLiveApc(h)
        h = BuildObject("svfigh", 2, "convoy_attack_1")
        GotoLiveApc(h)
        h = BuildObject("svfigh", 2, "convoy_attack_1")
        GotoLiveApc(h)
        h = BuildObject("svfigh", 2, "convoy_attack_1")
        GotoLiveApc(h)
        -- convoy_attack_2
        h = BuildObject("svartl", 2, "convoy_attack_2")
        GotoLiveApc(h)
        -- convoy_attack_3
        h = BuildObject("svartl", 2, "convoy_attack_3")
        GotoLiveApc(h)
        -- convoy_attack_4
        h = BuildObject("svartl", 2, "convoy_attack_4")
        GotoLiveApc(h)
        -- convoy_attack_5
        h = BuildObject("svartl", 2, "convoy_attack_5")
        GotoLiveApc(h)
        -- convoy_attack_6
        h = BuildObject("svartl", 2, "convoy_attack_6")
        GotoLiveApc(h)
        -- convoy_attack_7
        h = BuildObject("svartl", 2, "convoy_attack_7")
        GotoLiveApc(h)
        -- convoy_attack_8
        h = BuildObject("svartl", 2, "convoy_attack_8")
        GotoLiveApc(h)
        -- convoy_attack_9
        h = BuildObject("svartl", 2, "convoy_attack_9")
        GotoLiveApc(h)
    end
    if M.apcSpawned and not M.apcDamaged then
        -- check the health
        for i = 0, 2 do
            if Health(M.apc[i]) < 1.0 then
                M.apcDamaged = true
                break
            end
        end
        if M.apcDamaged then
            AudioMessage("ch02004.wav")
            M.convoyIntercept = BuildObject("cpcamr", 1, "nav_convoy")
            SetName(M.convoyIntercept, "Convoy Intercept")
            ClearObjectives()
            AddObjective("ch02001.otf", "white")
            if not M.objective2Complete then AddObjective("ch02003.otf", "white") end
            AddObjective("ch02002.otf", "white")
        end
    end
    if M.apcSpawned and not M.apcTrigger1 then
        -- if any of the APCs are within 30 units of trigger_point_1
        -- then do this stuff
        if ConvoyNear("trigger_point_1", 30.0) then
            M.apcTrigger1 = true
            local h
            h = BuildObject("svfigh", 2, "convoy_attack_10")
            GotoLiveApc(h)
            h = BuildObject("svfigh", 2, "convoy_attack_10")
            GotoLiveApc(h)
            h = BuildObject("svfigh", 2, "convoy_attack_10")
            GotoLiveApc(h)
            h = BuildObject("svfigh", 2, "convoy_attack_10")
            GotoLiveApc(h)
            h = BuildObject("svfigh", 2, "convoy_attack_10")
            GotoLiveApc(h)
            h = BuildObject("svfigh", 2, "convoy_attack_10")
            GotoLiveApc(h)
            h = BuildObject("svhraz", 2, "hanger_attack_3")
            Attack(h, M.hangar, 1)
            h = BuildObject("svhraz", 2, "hanger_attack_3")
            Attack(h, M.hangar, 1)
            h = BuildObject("svhraz", 2, "hanger_attack_3")
            Attack(h, M.hangar, 1)
        end
    end
    if M.apcSpawned and not M.apcTrigger2 then
        -- if any of the APCs are within 40 units of trigger_point_2
        -- then do this stuff
        if ConvoyNear("trigger_point_2", 40.0) then
            M.apcTrigger2 = true
            local h
            -- attack_9
            h = BuildObject("svtank", 2, "attack_9")
            Goto(h, getBase(), 1)
            h = BuildObject("svtank", 2, "attack_9")
            Goto(h, getBase(), 1)
            h = BuildObject("svtank", 2, "attack_9")
            Goto(h, getBase(), 1)
            h = BuildObject("svtank", 2, "attack_9")
            Goto(h, getBase(), 1)
            h = BuildObject("svltnk", 2, "attack_9")
            Goto(h, getBase(), 1)
            h = BuildObject("svltnk", 2, "attack_9")
            Goto(h, getBase(), 1)
            -- attack_10
            h = BuildObject("svtank", 2, "attack_10")
            Goto(h, getBase(), 1)
            h = BuildObject("svtank", 2, "attack_10")
            Goto(h, getBase(), 1)
            h = BuildObject("svltnk", 2, "attack_10")
            Goto(h, getBase(), 1)
            h = BuildObject("svltnk", 2, "attack_10")
            Goto(h, getBase(), 1)
            h = BuildObject("svrckt", 2, "attack_10")
            Goto(h, getBase(), 1)
            h = BuildObject("svrckt", 2, "attack_10")
            Goto(h, getBase(), 1)
            -- hanger_attack_4
            h = BuildObject("svhraz", 2, "hanger_attack_4")
            Attack(h, M.hangar, 1)
            h = BuildObject("svhraz", 2, "hanger_attack_4")
            Attack(h, M.hangar, 1)
            h = BuildObject("svhraz", 2, "hanger_attack_4")
            Attack(h, M.hangar, 1)
        end
    end
    -- PORT FIX: loss checks run earlier in this Update. Do not schedule success
    -- after a hangar/APC/walker defeat (or schedule victory more than once).
    -- Successful live-convoy arrivals still use the original <30 m trigger,
    -- 30-second cockpit display, audio, and audio-completion +1 s success delay.
    if M.apcSpawned and not M.apcAtHangar and not M.lost and not M.won then
        -- if any of the APCs are within 30 units of the hangar
        -- then do this stuff
        if ConvoyNear(M.hangar, 30.0) then
            M.apcAtHangar = true
            StartCockpitTimer(30)
            M.won = true
            M.winSound = AudioMessage("ch02005.wav")
        end
    end
    if M.winSound ~= nil and not M.lost and IsAudioMessageDone(M.winSound) then
        M.winSound = nil
        SucceedMission(GetTime() + 1.0, "ch02win.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores tables, handles and audio messages. Do not rerun
    -- Setup or convert handles manually: that would reset live mission state.
    M = state
end
-- CR co-op callbacks >>
-- The runtime's per-frame calls wrap the body's callbacks, and the engine's player callbacks.
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
    if campaignRuntime then Restored.builtAt = {} end
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
