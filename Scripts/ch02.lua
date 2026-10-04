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
    -- This approximates native arrival; it is not a recovered native radius.
    local count = GetPathPointCount(path)
    return Health(h) > 0.0 and count > 0 and Distance(h, path, count - 1) < 25.0
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
