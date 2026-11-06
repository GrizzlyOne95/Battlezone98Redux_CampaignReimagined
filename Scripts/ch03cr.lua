-- Chinese03Mission.cpp -> stock BZR 2.1 / Lua 5.1.
-- Source blob: 41b44bf53de2ce74a49bca874aaa440bb2fcfc9c.
-- Complete native source (including declarations, serialization and every
-- comment) is preserved in References/Chinese03Source/Chinese03Mission.cpp.
-- Requires the original map labels/paths, ODFs, audio, OTFs and debriefs.
-- This file does not change the map's mission-class configuration.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/CHMISN03_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Chmisn03CoopSourceParity.py).
-- CR co-op layer <<

-- Keep native zero-based indices, including the random general APC index.
local sounds = {[0] = "ch03003.wav", "ch03004.wav", "ch03005.wav"}
local back = {[0] = "east_back", "north_back", "west_back"}
local closeTo = {[0] = "east_exit", "north_exit", "west_exit"}
local explosionSpot = {
    [0] = "east_exit", "east_exit", "east_exit", "east_exit", "east_exit",
    "north_exit", "north_exit", "north_exit", "north_exit", "north_exit",
    "west_exit", "west_exit", "west_exit", "west_exit", "west_exit",
}
local spawns = {[0] = "apc_east", "apc_east", "apc_north", "apc_north", "apc_west", "apc_west"}
local apcFollow = {[0] = "east_path", "east_path", "north_path", "north_path", "west_path", "west_path"}
local defends = {[0] = "east_defend", "east_defend", "north_defend", "north_defend", "west_defend", "west_defend"}
local NEVER = 999999.9

local function NewState()
    local s = {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused in source
        cameraReady = {[0] = false, false},
        cameraComplete = {[0] = false, false}, -- unused cameras
        inHowitzer = {}, howitzerReady = {}, turnedAround = {},
        trigger1Done = false, won = false, lost = false,
        howitzers = {}, apc = {}, explosionTime = {},
        openingSoundTime = NEVER, apcSpawnTime = NEVER,
        factorySpawnTime = NEVER, generalSpawnTime = NEVER,
        generalApc = -1,
        -- user, lastUser, general, factory, armoury and audio start nil.
        -- openingSound, lose1Sound, lose2Sound, winSound (unused), sound9.
    }
    for i = 0, 5 do
        s.inHowitzer[i], s.howitzerReady[i] = false, false
    end
    -- SOURCE BUG FIX: Setup writes six entries into turnedAround[3], corrupting
    -- following flags. Initialize only the three routes. All intended route
    -- flags still start false; no mission event or timing is changed.
    for i = 0, 2 do s.turnedAround[i] = false end
    for i = 0, 14 do s.explosionTime[i] = NEVER end
    return s
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/CHMISN03_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut block off (Docs/CHMISN03_COOP.md, "Restored content").
local RESTORED_TIMEOUT_LINE = true
local RESTORED_ESCAPE_FAIL = true
local RESTORED_FACTORY_SCAVENGERS = true
local Restored
-- The Soviet escorts and the ambush are concealed, head-count-scaled tickets. The six APCs themselves are built
-- directly: the body keeps their handles from the first frame (turn-around, general, base_fail).
local SCALED_ODFS = { svtank = true, svhraz = true, svfigh = true }
local NativeMakeExplosion, NativeGetCockpitTimer = MakeExplosion, GetCockpitTimer
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "ch03cr", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "won_mission" }, -- respawn at the starting base
    scaledOdfs = SCALED_ODFS,
    -- The authored ambush (apc_attack, factory_attack) sits 300-360 m from the trigger the general's driver walks
    -- into; the runtime default 460 m would always divert it.
    safeRadius = 250,
    -- A spawn with a human close by comes from the next hidden approach: the map edge exits, then the Soviet base.
    fallbackEntries = { "east_fail", "north_fail", "west_fail", "north_defend", "east_defend", "west_defend" },
    liveCap = 40, -- six escort groups (24 + their extras) and the ambush (15 + extras) can overlap
    scrapPerGuest = 10,
    failDes = "ch03lsea.des", -- out of lives
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    orders = { "Attack", "Defend2" },
    -- The gas explosions are a local effect: every peer makes its own.
    presentationOps = {
        CH03Boom = function(odf, where) if Restored then Restored.Boom(odf, where) end end,
    },
    -- Ganymede: the icy moon of bdmisn01, with the four geysers of the starting base (Docs/CHMISN03_COOP.md).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesCH03", startLevel = 1, targetLevel = 1,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local ready, turned = 0, false
            for i = 0, 5 do if state.howitzerReady and state.howitzerReady[i] then ready = ready + 1 end end
            for i = 0, 2 do if state.turnedAround and state.turnedAround[i] then turned = true end end
            -- The guns wake one by one: the vapour stirs.
            if (not beats.stir) and ready >= 3 then
                beats.stir = true
                europa.SetTargetLevel(2)
            end
            -- All six ready: the convoys leave the Soviet base, the vent beside the start blows, the ground shakes.
            if (not beats.convoy) and state.objective1Complete then
                beats.convoy = true
                europa.SetTargetLevel(3)
                if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end
                europa.Quake(0.3, 3.0)
            end
            -- The first bombardment: the Jovian surge.
            if (not beats.guns) and turned then
                beats.guns = true
                europa.SetTargetLevel(4)
                europa.Surge(6.0, 0.8)
            end
            -- The General is in hand: the sky eases while the escort drives.
            if (not beats.rescue) and state.objective2Complete then
                beats.rescue = true
                europa.SetTargetLevel(3)
            end
            -- The ambush closes in: a second vent and the heaviest rung.
            if (not beats.ambush) and state.trigger1Done then
                beats.ambush = true
                europa.SetTargetLevel(4)
                if #europa.GetVentSites() > 1 then europa.TriggerPlume(2) end
                europa.Quake(0.35, 3.0)
            end
            -- The result: everything calms for the debrief.
            if (not beats.calm) and (state.won or state.lost) then
                beats.calm = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
        end },
    hooks = { load = function() if Restored then Restored.OnLoad() end end },
})
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- The player is the token; the seat of each howitzer is resolved per howitzer (Restored.Seat).
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever: a failed
-- AudioMessage returns 0 (the body's `~= nil` gates then see an already finished line).
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
local AudioMessage = campaignRuntime and function(file)
    local handle = campaignRuntime.AudioMessage(file)
    if handle == nil then return 0 end
    return handle
end or AudioMessage
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SetObjectiveOff = campaignRuntime and campaignRuntime.SetObjectiveOff or SetObjectiveOff
-- The nav beacon's handle is remembered so a load can name it again.
local SetObjectiveName = campaignRuntime and function(h, name)
    if Restored then Restored.Named(h, name) end
    return campaignRuntime.SetObjectiveName(h, name)
end or SetObjectiveName
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
-- The rearming timer loss has no voice in the source; the unused rebuke ch03007 slots in before the debrief.
local FailMission = campaignRuntime and function(when, description)
    if Restored and Restored.HoldFail(description) then return end
    return campaignRuntime.FailMission(when, description)
end or FailMission
-- The engine cannot keep the 13 minute clock (the map runs MultSTMission, which restarts the cockpit timer upward
-- every frame), so the host counts it itself and every peer shows the host's timer.
local StartCockpitTimer = campaignRuntime and function(seconds, warn, alert)
    Restored.TimerStart(seconds, warn, alert)
    return campaignRuntime.Present("StartCockpitTimer", seconds, warn, alert)
end or StartCockpitTimer
local StopCockpitTimer = campaignRuntime and function()
    Restored.TimerHide()
    return campaignRuntime.Present("StopCockpitTimer")
end or StopCockpitTimer
local HideCockpitTimer = campaignRuntime and function()
    Restored.TimerHide()
    return campaignRuntime.Present("HideCockpitTimer")
end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
-- The gas explosions are a local effect: the host makes its own and the guests theirs. A path travels by name.
local MakeExplosion = campaignRuntime and function(odf, where)
    NativeMakeExplosion(odf, where)
    if campaignRuntime.Coop.IsNetworkGame() then return campaignRuntime.Present("CH03Boom", odf, where) end
end or MakeExplosion
-- The Soviets are team 2 in the DLL and team 5 here (the howitzers are perceived as theirs).
local SetPerceivedTeam = campaignRuntime and function(h, team)
    if team == 2 then team = 5 end
    return SetPerceivedTeam(h, team)
end or SetPerceivedTeam
-- The body's team 1 is the one shared Chinese side: its 10 pilots go to every human team (each human respawns
-- from its own pool); the Soviets are team 2 in the DLL and team 5 here.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
-- "The General's APC is ours": the body asks for team 1 only; humans are teams 1-4, so any human team is team 1.
local GetTeamNum = campaignRuntime and function(h)
    local team = GetTeamNum(h)
    if team >= 1 and team <= 4 then return 1 end
    return team
end or GetTeamNum
-- Every Soviet escort and raider is a ticket. A new scripted spawn (a new frame or a new entry path) is a new
-- scaling event: the first unit of each is mirrored by min(floor(humans / 2), 2) extras with its orders.
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
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Health(h)
    -- Native missing-object health is zero; preserve destruction losses.
    if not Valid(h) then return 0 end
    return GetHealth(h)
end
local function Distance(h, path)
    -- PORT FIX: absent/dead APCs must not turn a route around or reach a base.
    -- Live objects retain the original paths, strict radii and event order.
    if not Valid(h) or Health(h) <= 0 then return math.huge end
    return GetDistance(h, path)
end
local function AttackIfValid(h, target)
    -- A destroyed attacker/target has no executable command in the native
    -- mission. Avoid invalid Lua handles without redirecting surviving units.
    if Valid(h) and Valid(target) then Attack(h, target, 1) end
end
local function GotoIfValid(h, path)
    if Valid(h) then Goto(h, path, 1) end
end
-- CR restored content >>
-- The co-op fixes that need state and the cut content (Docs/CHMISN03_COOP.md lists each; every restoration is
-- behind a RESTORED_* flag at the top of the runtime region and gated on what the shipped map carries).
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    -- The end of each APC route is the map-edge point the source never uses (east_fail, north_fail, west_fail).
    local ESCAPE = {[0] = "east_fail", "north_fail", "west_fail"}
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- ---------------------------------------------------------------- the seat of each howitzer
    -- The DLL's single player is replaced by "is a human in this howitzer": Scan reads who sits where once per
    -- frame and Seat(i) puts the answer into the body's M.user / M.lastUser, so its unchanged comparisons
    -- (`M.user == howitzer`) hold for any human on any team.
    function Restored.Scan()
        local r = RState()
        r.prev = r.occ or {}
        local occ = {}
        for i = 0, 5 do
            local h = M.howitzers[i]
            occ[i] = false
            if Valid(h) then
                occ[i] = runtime.Coop.AnyPlayerSatisfies(function(p) return p == h end)
            end
        end
        r.occ = occ
    end
    function Restored.Seat(i)
        local r = RState()
        local h = M.howitzers[i]
        M.user = (r.occ and r.occ[i]) and h or runtime.PLAYERS
        M.lastUser = (r.prev and r.prev[i]) and h or runtime.PLAYERS
    end
    -- ---------------------------------------------------------------- local effects and the timer
    function Restored.Boom(odf, where)
        if runtime.Coop.IsAuthority() then return end -- the host made its own
        NativeMakeExplosion(odf, where)
    end
    function Restored.Named(h, name)
        if name == "CCA Base" then RState().base = h end
    end
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
    function Restored.OnLoad() RState().afterLoad = true end
    -- A load resets the presentation: the objective list, the markers, the timer and the beacon name are shown
    -- again from the state the mission saved.
    function Restored.AfterLoad(r)
        runtime.ClearObjectives()
        if M.objective2Complete then
            runtime.AddObjective("ch03001.otf", "green")
            runtime.AddObjective("ch03002.otf", "green")
            runtime.AddObjective("ch03003.otf", "white")
        elseif M.objective1Complete then
            runtime.AddObjective("ch03001.otf", "green")
            runtime.AddObjective("ch03002.otf", "white")
        else
            runtime.AddObjective("ch03001.otf", "white")
            for i = 0, 5 do
                local h = M.howitzers[i]
                if Valid(h) and not M.howitzerReady[i] then runtime.SetObjectiveOn(h) end
            end
            if r.timerEnd then
                runtime.Present("StartCockpitTimer", math.max(1, r.timerEnd - GetTime()), r.timerWarn or 30, r.timerAlert or 10)
            end
        end
        if Valid(r.base) then runtime.SetObjectiveName(r.base, "CCA Base") end
    end
    -- ---------------------------------------------------------------- restored content
    -- Unused voice line ch03007 ("This is unthinkable! Your feeble ineptitude sickens me, Major"): the body fails the
    -- rearming timeout in silence. The line plays first; the failure (ch03lsea.des) follows when it has finished.
    function Restored.HoldFail(description)
        if not RESTORED_TIMEOUT_LINE or description ~= "ch03lsea.des" then return false end
        local r = RState()
        if r.timeoutLine ~= nil then return true end
        r.timeoutLine, r.timeoutDes = AudioMessage("ch03007.wav"), description
        return true
    end
    -- Unused map paths east_fail / north_fail / west_fail (the end of each APC route, at the map edge) and unused
    -- debrief ch03lseb.des ("The General has been taken to the launch facility!"): the General's APC, still Soviet,
    -- reaching the end of its route has escaped. The routes turn around at the exits, so this is a backstop.
    function Restored.Escape(r)
        if not RESTORED_ESCAPE_FAIL or M.lost or M.won or M.generalApc == -1 then return end
        local general = M.general
        if not Valid(general) or Health(general) <= 0 or GetTeamNum(general) == 1 then return end
        if Distance(general, ESCAPE[math.floor(M.generalApc / 2)]) < 75.0 then
            M.lost = true
            r.escapeLine, r.escapeDes = AudioMessage("ch03007.wav"), "ch03lseb.des"
        end
    end
    -- Cut: the four `cvscav` scavengers (commented out in the source) that came with the factory and the armory.
    function Restored.Scavengers(r)
        if not RESTORED_FACTORY_SCAVENGERS or r.scavengers or M.factory == nil then return end
        r.scavengers = true
        for _ = 1, 4 do
            local h = BuildObject("cvscav", 1, "factory")
            if Valid(h) then Goto(h, "factory_path", 1) end
        end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad(r) end
        Restored.Scavengers(r)
        Restored.Escape(r)
        for _, key in ipairs({ "timeout", "escape" }) do
            if r[key .. "Line"] ~= nil and IsAudioMessageDone(r[key .. "Line"]) then
                local description = r[key .. "Des"]
                r[key .. "Line"], r[key .. "Des"] = nil, nil
                runtime.FailMission(GetTime() + 1.0, description)
            end
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[chmisn03] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<

local function RestoreHowitzerAI(i)
-- CR co-op user >>
    if campaignRuntime then Restored.Seat(i) end
-- CR co-op user <<
    local h = M.howitzers[i]
    if M.howitzerReady[i] and M.inHowitzer[i] and M.user ~= h and Valid(h) and Health(h) > 0 then
        -- PORT ADAPTATION: Lua cannot access GetAIProcess, curPilot or
        -- AiProcess::Attach. Reset the default pilot class and issue a stock
        -- Stop command once after leaving an unpiloted repaired howitzer.
        -- Engine AI attachment/empty-craft behavior must be checked in-game;
        -- this is a stock API substitute, not a claim of native equivalence.
        -- Original engine-only block, including the cut pilot assignment:
        --[[
        GameObject *obj = GameObjectHandle::GetObj(howitzers[i]);
        _ASSERTMSG0(obj != NULL, "NULL Howitzer");
        if (obj->GetAIProcess() == NULL)
        {
            obj->curPilot = 0;//*(PrjID*)"cspilo\0";
            AiProcess::Attach(this, obj);
        }
        SetPerceivedTeam(howitzers[i], 2);
        ]]
        if not M.howitzerAiRestored[i] then
            if not IsAliveAndPilot(h) then
                SetPilotClass(h, nil)
                Stop(h, 0)
                -- If the player leaves after this route's attack trigger,
                -- restore the already-issued order instead of cancelling it.
                if M.turnedAround[math.floor(i / 2)] then
                    AttackIfValid(h, M.apc[i])
                end
            end
            M.howitzerAiRestored[i] = true
        end
        SetPerceivedTeam(h, 2)
    end
end

function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    M.howitzerAiRestored = {}
    for i = 0, 5 do M.howitzers[i] = GetHandle("howitzer_" .. (i + 1)) end
end

function AddObject(h)
    -- Source AddObject(Handle h) is empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
-- CR co-op user >>
    if campaignRuntime then Restored.Scan() end
-- CR co-op user <<

    if not M.startDone then
        SetPilot(1, 10)
        SetScrap(1, 0)
        -- don't do this part after the first shot
        M.startDone = true
        M.openingSoundTime = GetTime() + 1.0
        ClearObjectives()
        AddObjective("ch03001.otf", "white")
        for i = 0, 5 do
            if Valid(M.howitzers[i]) then
                SetObjectiveOn(M.howitzers[i])
                SetPerceivedTeam(M.howitzers[i], 2)
            end
        end
        StartCockpitTimer(780, 30, 10)
        M.factorySpawnTime = GetTime() + 480.0
    end

    if M.openingSoundTime < GetTime() then
        M.openingSoundTime = NEVER
        M.openingSound = AudioMessage("ch03001.wav")
    end
    if M.openingSound ~= nil and IsAudioMessageDone(M.openingSound) then
        M.openingSound = nil
    end

    if not M.objective1Complete and GetCockpitTimer() <= 0 and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime() + 1.0, "ch03lsea.des")
    end

    -- SOURCE BUG FIX: the native AI-restoration branch runs only while repair
    -- objective 1 is incomplete. The final repaired howitzer can be left after
    -- that phase ends and never receive AI. Keep the same exit/ready conditions
    -- active after completion, without delaying APC spawns or changing repair
    -- thresholds. Also reset the one-shot adapter if the player boards again.
    for i = 0, 5 do
-- CR co-op user >>
    if campaignRuntime then Restored.Seat(i) end
-- CR co-op user <<
        if Valid(M.howitzers[i]) and M.user == M.howitzers[i] and M.lastUser ~= M.user then
            M.howitzerAiRestored[i] = false
        end
        RestoreHowitzerAI(i)
    end

    if not M.objective1Complete then
        M.objective1Complete = true
        for i = 0, 5 do
-- CR co-op user >>
    if campaignRuntime then Restored.Seat(i) end
-- CR co-op user <<
            local h = M.howitzers[i]
            if Valid(h) and M.user == h and not M.inHowitzer[i] then
                M.inHowitzer[i] = true
                AudioMessage("ch03002.wav")
            end
            if not M.howitzerReady[i] then
                -- test to see if ready: absolute health/ammo, strictly > 400.
                if Valid(h) and GetCurHealth(h) > 400 and GetCurAmmo(h) > 400 then
                    M.howitzerReady[i] = true
                end
                if M.howitzerReady[i] then
                    SetObjectiveOff(h)
                else
                    M.objective1Complete = false
                end
            else -- /* if (howitzerReady[i]) */ handled by RestoreHowitzerAI
                -- Native pilot/AI block is retained above verbatim.
            end
        end
        if M.objective1Complete then
            StopCockpitTimer()
            HideCockpitTimer()
            ClearObjectives()
            AddObjective("ch03001.otf", "green")
            AddObjective("ch03002.otf", "white")
            M.apcSpawnTime = GetTime()
            local h = BuildObject("apcamr", 1, "nav_base")
            SetObjectiveName(h, "CCA Base") -- stock SetName alias
        end
    end

    if M.apcSpawnTime < GetTime() then
        M.apcSpawnTime = NEVER
        -- spawn the apcs; source rand() % 6 selects one of six slots.
        M.generalApc = math.random(0, 5)
        M.generalSpawnTime = GetTime()
        for i = 0, 5 do
            M.apc[i] = BuildObject(M.generalApc == i and "svapcq" or "svapcr", 2, spawns[i])
            SetPerceivedTeam(M.apc[i], 1)
            Goto(M.apc[i], apcFollow[i], 1)
            local h = BuildObject("svtank", 2, defends[i])
            Defend2(h, M.apc[i], 1)
            h = BuildObject("svtank", 2, defends[i])
            Defend2(h, M.apc[i], 1)
            h = BuildObject("svhraz", 2, defends[i])
            Defend2(h, M.apc[i], 1)
            h = BuildObject("svfigh", 2, defends[i])
            Defend2(h, M.apc[i], 1)
        end
        M.general = M.apc[M.generalApc]
        -- _DEBUGMSG1("General APC spawned at %s", spawns[generalApc]);
    end

    if M.factorySpawnTime < GetTime() then
        M.factorySpawnTime = NEVER
        -- spawn the factory
        M.factory = BuildObject("cvmufa", 1, "factory")
        Goto(M.factory, "factory_path", 1)
        AddScrap(1, 100)
        M.armoury = BuildObject("cvslfa", 1, "factory")
        Goto(M.armoury, "factory_path", 1)
        --Handle h;
        --h = BuildObject("cvscav", 1, "factory");
        --Goto(h, "factory_path", 1);
        --h = BuildObject("cvscav", 1, "factory");
        --Goto(h, "factory_path", 1);
        --h = BuildObject("cvscav", 1, "factory");
        --Goto(h, "factory_path", 1);
        --h = BuildObject("cvscav", 1, "factory");
        --Goto(h, "factory_path", 1);
        AddScrap(1, 100) -- both source grants are intentional
    end
    if M.factory ~= nil and Health(M.factory) <= 0 and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime() + 1.0, "ch03lsee.des")
    end

    if M.objective1Complete and not M.objective2Complete then
        for i = 0, 2 do
            if not M.turnedAround[i] then
                if Distance(M.apc[2*i], closeTo[i]) < 40.0 or Distance(M.apc[2*i+1], closeTo[i]) < 40.0 then
                    M.turnedAround[i] = true
                    AudioMessage(sounds[i])
                    GotoIfValid(M.apc[2*i], back[i])
                    GotoIfValid(M.apc[2*i+1], back[i])
                    -- get the howies to attack
                    AttackIfValid(M.howitzers[2*i], M.apc[2*i])
                    AttackIfValid(M.howitzers[2*i+1], M.apc[2*i+1])
                    -- start the explosions: first one is due this frame.
                    for j = 0, 4 do M.explosionTime[5*i+j] = GetTime() + 5*j end
                end
            end
        end
    end
    for i = 0, 14 do
        if M.explosionTime[i] <= GetTime() then
            M.explosionTime[i] = NEVER
            -- PORT ADAPTATION: Lua MakeExplosion takes ODF first, location second.
            MakeExplosion("xgasxpl", explosionSpot[i])
        end
    end

    -- general apc destroyed?
    if M.general ~= nil and Health(M.general) <= 0 and not M.lost and not M.won then
        M.lost = true
        M.lose1Sound = AudioMessage("ch03008.wav")
    end
    if M.lose1Sound ~= nil and IsAudioMessageDone(M.lose1Sound) then
        -- SOURCE BUG FIX: clear completed loss messages so FailMission is not
        -- rescheduled every frame. First call keeps the original audio +1 s.
        M.lose1Sound = nil
        FailMission(GetTime() + 1.0, "ch03lsec.des")
    end
    -- Unused lose2Sound branch is retained for reconstruction.
    if M.lose2Sound ~= nil and IsAudioMessageDone(M.lose2Sound) then
        M.lose2Sound = nil -- same one-shot scheduling fix
        FailMission(GetTime() + 1.0, "ch03lsed.des")
    end
    -- SOURCE BUG FIX: add !won to match all other terminal-loss guards. A
    -- successful delivery cannot be replaced by escape during its +1 s delay.
    -- Before victory, the original 120 s grace period and 50 m radius remain.
    if M.general ~= nil and M.generalSpawnTime + 120.0 < GetTime()
        and Distance(M.general, "base_fail") < 50.0 and not M.lost and not M.won then
        M.lost = true
        M.sound9 = AudioMessage("ch03009.wav")
    end
    if M.sound9 ~= nil and IsAudioMessageDone(M.sound9) then
        M.sound9 = nil
        FailMission(GetTime() + 1.0, "ch03lsed.des")
    end

    if not M.objective2Complete and M.generalApc ~= -1 and Valid(M.general)
        and GetTeamNum(M.general) == 1 then
        M.objective2Complete = true
        AudioMessage("ch03006.wav")
        ClearObjectives()
        AddObjective("ch03001.otf", "green")
        AddObjective("ch03002.otf", "green")
        AddObjective("ch03003.otf", "white")
    end
    if M.objective2Complete and not M.trigger1Done and Distance(M.general, "trigger_1") < 30.0 then
        M.trigger1Done = true
        for i = 0, 5 do
            local h = BuildObject("svfigh", 2, "apc_attack")
            AttackIfValid(h, M.general)
        end
        for i = 0, 3 do
            local h = BuildObject("svfigh", 2, "apc_attack_2")
            AttackIfValid(h, M.general)
        end
        local h = BuildObject("svtank", 2, "factory_attack")
        AttackIfValid(h, M.factory)
        h = BuildObject("svtank", 2, "factory_attack")
        AttackIfValid(h, M.factory)
        h = BuildObject("svtank", 2, "factory_attack")
        AttackIfValid(h, M.factory)
        h = BuildObject("svfigh", 2, "factory_attack")
        AttackIfValid(h, M.factory)
        h = BuildObject("svfigh", 2, "factory_attack")
        AttackIfValid(h, M.factory)
    end
    if M.objective2Complete and not M.won and Distance(M.general, "won_mission") < 30.0 and not M.lost then
        M.won = true
        SucceedMission(GetTime() + 1.0, "ch03win.des")
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
    -- LuaMission serializes table primitives, engine handles and audio messages.
    -- Do not rerun Setup/Start or reset timers, random choice, resources/spawns.
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
