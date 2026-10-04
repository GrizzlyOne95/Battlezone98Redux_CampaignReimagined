-- Chinese03Mission.cpp -> stock BZR 2.1 / Lua 5.1.
-- Source blob: 41b44bf53de2ce74a49bca874aaa440bb2fcfc9c.
-- Complete native source (including declarations, serialization and every
-- comment) is preserved in References/Chinese03Source/Chinese03Mission.cpp.
-- Requires the original map labels/paths, ODFs, audio, OTFs and debriefs.
-- This file does not change the map's mission-class configuration.

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

local function RestoreHowitzerAI(i)
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
    M.howitzerAiRestored = {}
    for i = 0, 5 do M.howitzers[i] = GetHandle("howitzer_" .. (i + 1)) end
end

function AddObject(h)
    -- Source AddObject(Handle h) is empty.
end

function Update(dt)
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

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
        if Valid(M.howitzers[i]) and M.user == M.howitzers[i] and M.lastUser ~= M.user then
            M.howitzerAiRestored[i] = false
        end
        RestoreHowitzerAI(i)
    end

    if not M.objective1Complete then
        M.objective1Complete = true
        for i = 0, 5 do
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
end

function Save()
    return M
end
function Load(state)
    -- LuaMission serializes table primitives, engine handles and audio messages.
    -- Do not rerun Setup/Start or reset timers, random choice, resources/spawns.
    M = state
end
