-- Faithful stock misns3 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns3Mission.cpp
-- Source blob: 2805325b14fcd9273f0bd03eb36f0be17b755527.
-- Complete original comments, declarations, and native serialization are kept
-- byte-for-byte in References/Misns3Source/. No campaign helpers are required.
--[[
	Misns3Mission
]]

local function NewState()
    -- Native Load initializes all members before Setup (including unused ones).
    -- bools
    local state = {
        economy1 = false, economy2 = false, economy3 = false, economy4 = false,
        unit1spawned = false, unit2spawned = false, unit3spawned = false,
        newobjective = false, unit4spawned = false, bdspawned2 = false,
        missionstart = false, missionwon = false, missionfail = false,
        bdspawned = false, recyclerdestroyed = false,
        warn1 = false, warn2 = false, plea1 = false, plea2 = false, plea3 = false,
        mark1 = false, play = false,
        minefield1 = false, minefield2 = false, minefield3 = false,
        patrolspawned = false,
        -- floats
        withdraw = 99999.0, help1 = 9999999.0, help2 = 9999999.0, help3 = 9999999.0,
        -- integers
        audmsg = 0,
        -- PORT FIX: native Setup converts enormous float literals to int,
        -- exceeding the integer range. Use representable Lua numbers instead.
        -- First Execute overwrites these before any test, so deadlines and flow
        -- are unchanged. Preserve truncation of active integer timers below.
        Checkdist = 9999999999999.0, Checkdist2 = 999999999999999.0,
        Checkalive = 9999999999.0,
        -- handles
        bd1 = nil, bd2 = nil, bd3 = nil, bd4 = nil, bd5 = nil, bd6 = nil,
        bd7 = nil, bd8 = nil, bd9 = nil, bd10 = nil, bd11 = nil, bd12 = nil,
        bd50 = nil, bd60 = nil, bd70 = nil, bd80 = nil,
        bd51 = nil, bd52 = nil, bd61 = nil, bd62 = nil,
        bd71 = nil, bd72 = nil, bd81 = nil, bd82 = nil,
        avrec = nil, player = nil, bomb1 = nil, bomb2 = nil,
        bomb3 = nil, bomb4 = nil, pat1 = nil, pat2 = nil,
        Enemy1 = nil, Enemy2 = nil, cam1 = nil, cam2 = nil,
        aud1 = nil, aud2 = nil, aud50 = nil,
    }
    -- handles (native zero becomes Lua nil): bd1..bd12, bd50/60/70/80,
    -- bd51/52/61/62/71/72/81/82, avrec, player, bomb1..bomb4, pat1/2,
    -- Enemy1/2, cam1/2. Unused bd6..bd12 remain reserved for reconstruction.
    -- aud1, aud2, aud50 are native integer audio IDs; Lua uses message userdata.
    -- Keep these nil until AudioMessage returns a stock Lua message.
    --[[
	Here's where you
	set the values
	at the start.
    ]]
    return state
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Distance(from, to)
    -- PORT FIX: missing/deleted objects must not satisfy proximity tests or be
    -- passed to Lua's handle overloads. Valid objects and path distances retain
    -- every source threshold; this only rejects unusable operands.
    if not Valid(from) or (type(to) ~= "string" and not Valid(to)) then
        return math.huge
    end
    return GetDistance(from, to)
end

local function SafeAttack(h, target)
    -- PORT FIX: failed spawns/deleted patrols cannot receive valid orders.
    -- Guard these calls; surviving units keep the source's orders and timing.
    if Valid(h) and Valid(target) then Attack(h, target) end
end

local function SpawnDefenders()
    M.bd1 = BuildObject("avtank", 2, "bdspawn1")
    M.bd2 = BuildObject("avtank", 2, "bdspawn1")
    M.bd3 = BuildObject("avtank", 2, "bdspawn1")
    M.bd4 = BuildObject("avfigh", 2, "bdspawn1")
    M.bd5 = BuildObject("avfigh", 2, "bdspawn1")
end

local function SpawnEscorts(leader, odf1, odf2)
    local first = BuildObject(odf1, 2, leader)
    local second = BuildObject(odf2, 2, leader)
    if Valid(first) then Follow(first, leader) end
    if Valid(second) then Follow(second, leader) end
    return first, second
end

local function ShowObjectives()
    ClearObjectives()
    if M.recyclerdestroyed then
        AddObjective("misns302.otf", "white")
        AddObjective("misns301.otf", "green")
    else
        AddObjective("misns301.otf", "white")
    end
    if M.missionwon then
        -- PORT FIX: source never requests a refresh when missionwon is set,
        -- leaving the return objective white. Replace its existing slot with
        -- green instead of appending a duplicate. Presentation only: success
        -- still requires returning home and finishing misns303.wav.
        UpdateObjective("misns302.otf", "green")
    end
    M.newobjective = false
end

function Start()
    -- State implements native Load/Setup; Execute starts on the first Update.
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
    --[[
		Here is where you
		put what happens
		every frame.
    ]]
    if not M.missionstart then
        AudioMessage("misns301.wav")
        M.newobjective = true
        M.missionstart = true
        M.avrec = GetHandle("avrecy1_recycler")
        M.player = GetPlayerHandle()
        M.withdraw = GetTime() + 600.0
        M.help1 = GetTime() + 120.0
        M.help2 = GetTime() + 280.0
        M.help3 = GetTime() + 380.0
        M.Checkdist = math.floor(GetTime() + 5.0)
        M.Checkdist2 = math.floor(GetTime() + 5.0)
        M.Checkalive = math.floor(GetTime() + 15.0)
        M.bomb1 = GetHandle("bomb1")
        M.bomb2 = GetHandle("bomb2")
        M.bomb3 = GetHandle("bomb3")
        M.bomb4 = GetHandle("bomb4")
        M.cam1 = GetHandle("basenav")
        M.cam2 = GetHandle("avrecy")
        -- PORT FIX: source dereferences both navigation objects unconditionally.
        -- A missing marker is skipped; naming surviving markers changes no flow.
        -- SetObjectiveName is stock Lua's alias of native SetName.
        if Valid(M.cam1) then SetObjectiveName(M.cam1, "Home Base") end
        if Valid(M.cam2) then SetObjectiveName(M.cam2, "Black Dog Outpost") end
    end
    M.player = GetPlayerHandle()

    if M.newobjective then ShowObjectives() end
    if M.help1 < GetTime() and not M.plea1 and not M.recyclerdestroyed then
        AudioMessage("misns307.wav")
        M.plea1 = true
    end
    if M.help2 < GetTime() and not M.plea2 and not M.recyclerdestroyed then
        AudioMessage("misns308.wav")
        M.plea2 = true
    end
    if M.help3 < GetTime() and not M.plea3 and not M.recyclerdestroyed then
        AudioMessage("misns309.wav")
        M.plea3 = true
    end

    if IsAlive(M.avrec) and Distance(M.player, "bdspawntrig") < 200.0 and not M.bdspawned then
        SpawnDefenders()
        SafeAttack(M.bd1, M.player)
        SafeAttack(M.bd2, M.player)
        SafeAttack(M.bd3, M.player)
        SafeAttack(M.bd4, M.player)
        SafeAttack(M.bd5, M.player)
        M.bdspawned = true
        AudioMessage("misns310.wav")
    end

    -- PORT FIX: source calls IsAlive(bd1) five times and discards every result.
    -- Preserve the exact statements as comments; removing pure queries cannot
    -- change gameplay. Do not "fix" them into a new condition or retarget rule.
    -- if (bdspawned == true) {
    --     IsAlive(bd1);
    --     IsAlive(bd1);
    --     IsAlive(bd1);
    --     IsAlive(bd1);
    --     IsAlive(bd1);
    -- }

    if M.bdspawned and M.Checkalive < GetTime() then
        if IsAlive(M.bd1) then SafeAttack(M.bd1, M.player) end
        if IsAlive(M.bd2) then SafeAttack(M.bd2, M.player) end
        if IsAlive(M.bd3) then SafeAttack(M.bd3, M.player) end
        if IsAlive(M.bd4) then SafeAttack(M.bd4, M.player) end
        if IsAlive(M.bd5) then SafeAttack(M.bd5, M.player) end
        if not IsAlive(M.bd1) and not IsAlive(M.bd2) and not IsAlive(M.bd3)
            and not IsAlive(M.bd4) and not IsAlive(M.bd5) then
            SpawnDefenders()
            -- Source deliberately issues no Attack until the next 8-second poll.
        end
        M.Checkalive = math.floor(GetTime() + 8.0)
    end

    if not IsAlive(M.avrec) and not M.recyclerdestroyed then
        AudioMessage("misns302.wav")
        if not M.bdspawned2 then
            M.bd50 = BuildObject("avtank", 2, "bdspawn1")
            M.bd60 = BuildObject("avfigh", 2, "bdspawn1")
            M.bd70 = BuildObject("avfigh", 2, "bdspawn1")
            M.bd80 = BuildObject("avtank", 2, "bdspawn1")
            if Valid(M.bd50) then Goto(M.bd50, "bdpath1") end
            if Valid(M.bd60) then Goto(M.bd60, "bdpath2") end
            if Valid(M.bd70) then Goto(M.bd70, "bdpath3") end
            if Valid(M.bd80) then Goto(M.bd80, "bdpath4") end
            M.bdspawned2 = true
            M.bdspawned = false
        end
        M.economy1, M.economy2, M.economy3, M.economy4 = true, true, true, true
        M.recyclerdestroyed = true
        M.newobjective = true
    end

    if M.economy1 and Distance(M.player, M.bd50) < 410.0 and not M.unit1spawned then
        M.bd51, M.bd52 = SpawnEscorts(M.bd50, "avtank", "avtank")
        M.unit1spawned = true
    end
    if M.economy2 and Distance(M.player, M.bd60) < 410.0 and not M.unit2spawned then
        M.bd61, M.bd62 = SpawnEscorts(M.bd60, "avfigh", "avfigh")
        M.unit2spawned = true
    end
    if M.economy3 and Distance(M.player, M.bd70) < 410.0 and not M.unit3spawned then
        M.bd71, M.bd72 = SpawnEscorts(M.bd70, "avfigh", "avtank")
        M.unit3spawned = true
    end
    if M.economy4 and Distance(M.player, M.bd80) < 410.0 and not M.unit4spawned then
        M.bd81, M.bd82 = SpawnEscorts(M.bd80, "avtank", "avtank")
        M.unit4spawned = true
    end

    if Distance(M.player, "homesweethome") < 200.0 and not M.missionwon and M.recyclerdestroyed then
        M.aud50 = AudioMessage("misns303.wav")
        M.missionwon = true
        M.newobjective = true -- PORT FIX: request the presentation-only refresh.
    end
    if M.missionwon and IsAudioMessageDone(M.aud50) then
        SucceedMission(GetTime() + 0.0, "misns3w1.des")
    end
    if M.withdraw < GetTime() and not M.recyclerdestroyed and not M.missionfail then
        M.aud2 = AudioMessage("misns304.wav")
        M.missionfail = true
    end
    if M.missionfail and IsAudioMessageDone(M.aud2) then
        FailMission(GetTime(), "misns3l1.des")
    end
    if Distance(M.player, "don'tgohere") < 50.0 and not M.warn1 and not M.recyclerdestroyed then
        AudioMessage("misns305.wav")
        M.warn1 = true
    end
    if Distance(M.player, "iwarnedyou") < 50.0 and not M.warn2 and not M.recyclerdestroyed then
        M.aud1 = AudioMessage("misns306.wav")
        M.warn2 = true
    end
    if M.warn2 and IsAudioMessageDone(M.aud1) then
        FailMission(GetTime(), "misns3l2.des")
    end

    if not M.patrolspawned then
        if not M.bdspawned and IsAlive(M.avrec) then
            if M.Checkdist < GetTime() then
                if Distance(M.bomb1, "patroltrig1") < 100.0 or Distance(M.bomb2, "patroltrig1") < 100.0
                    or Distance(M.bomb3, "patroltrig1") < 100.0 or Distance(M.bomb4, "patroltrig1") < 100.0
                    or Distance(M.player, "patroltrig1") < 100.0 then
                    M.pat1 = BuildObject("bvraz", 2, "patrolspawn1")
                    M.pat2 = BuildObject("bvraz", 2, "patrolspawn1")
                    AudioMessage("misns219.wav")
                    if Valid(M.pat1) then Goto(M.pat1, "patrolpath1") end
                    if Valid(M.pat2) then Goto(M.pat2, "patrolpath1") end
                    if Valid(M.pat1) then SetIndependence(M.pat1, 0) end
                    if Valid(M.pat2) then SetIndependence(M.pat2, 0) end
                    M.patrolspawned = true
                end
                -- Preserve independent tests: source can spawn both patrols on
                -- one poll when different craft cross the two triggers together.
                if Distance(M.bomb1, "patroltrig2") < 100.0 or Distance(M.bomb2, "patroltrig2") < 100.0
                    or Distance(M.bomb3, "patroltrig2") < 100.0 or Distance(M.bomb4, "patroltrig2") < 100.0
                    or Distance(M.player, "patroltrig2") < 100.0 then
                    M.pat1 = BuildObject("bvraz", 2, "patrolspawn2")
                    M.pat2 = BuildObject("bvraz", 2, "patrolspawn2")
                    AudioMessage("misns219.wav")
                    if Valid(M.pat1) then Goto(M.pat1, "patrolpath2") end
                    if Valid(M.pat2) then Goto(M.pat2, "patrolpath2") end
                    if Valid(M.pat1) then SetIndependence(M.pat1, 0) end
                    if Valid(M.pat2) then SetIndependence(M.pat2, 0) end
                    M.patrolspawned = true
                end
                M.Checkdist = math.floor(GetTime() + 3.0)
            end
        end
    end

    if not M.mark1 and M.patrolspawned and not M.bdspawned then
        -- PORT FIX: don't query a destroyed patrol or attack a nil nearest enemy.
        -- The original 180m detection and both independent target tests remain.
        M.Enemy1 = nil
        M.Enemy2 = nil
        if Valid(M.pat1) then M.Enemy1 = GetNearestEnemy(M.pat1) end
        if Valid(M.pat2) then M.Enemy2 = GetNearestEnemy(M.pat2) end
        if M.Checkdist2 < GetTime() then
            if Distance(M.pat1, M.Enemy1) < 180.0 then
                M.bdspawned = true
                SafeAttack(M.pat1, M.Enemy1)
                SafeAttack(M.pat2, M.Enemy1)
                M.play = true
            end
            if Distance(M.pat2, M.Enemy2) < 180.0 then
                M.bdspawned = true
                SafeAttack(M.pat2, M.Enemy2)
                SafeAttack(M.pat1, M.Enemy2)
                M.play = true
            end
            M.Checkdist2 = math.floor(GetTime() + 3.0)
            if M.play and not M.mark1 then
                AudioMessage("misns220.wav")
                M.mark1 = true
            end
        end
    end

    if not M.minefield1 and (Distance(M.player, "minetrig1") < 200.0 or Distance(M.player, "minetrig1b") < 200.0) then
        for index = 1, 11 do BuildObject("proxmine", 2, "path_" .. index) end
        M.minefield1 = true
    end
    if not M.minefield2 and (Distance(M.player, "minetrig2") < 200.0 or Distance(M.player, "minetrig2b") < 200.0) then
        for index = 12, 22 do BuildObject("proxmine", 2, "path_" .. index) end
        M.minefield2 = true
    end
    if not M.minefield3 and (Distance(M.player, "minetrig3") < 200.0 or Distance(M.player, "minetrig3b") < 200.0) then
        for index = 23, 34 do BuildObject("proxmine", 2, "path_" .. index) end
        M.minefield3 = true
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission serializes tables and restores handles/message userdata.
    -- Native PostLoad/ConvertHandle is replaced by the host; never replay Setup.
    M = state
end
