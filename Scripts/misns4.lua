-- Faithful stock misns4 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns4Mission.cpp
-- Source blob: efc5de9d0b4cd4fcfd0165c04319725417f87ae7.
-- All disabled mission code is retained inline. The complete native source,
-- including declarations/serialization and all comments, is archived in
-- References/Misns4Source/. No campaign helpers, EXU, or OpenShim required.

local function NewState()
    -- Native Load initializes all members before Setup, including unused ones.
    local state = {
        counter = false, first = false, first_bridge = false, warning = false,
        bridge_clear = false, won = false, lost = false, start_done = false,
        north_bridge = false, convoy_alive = {}, safe = {}, convoy_handle = {},
        wakeup_time = 99999.0, convoy_time = 99999.0, attack_time = 99999.0,
        raider_time = 99999.0, army_time = 99999.0, counter_time = 99999.0,
        convoy_total = 5, convoy_count = 0, convoy_dead = 0, win_count = 0,
    }
    -- Preserve native zero-based arrays and all ten serialized slots.
    -- Handles start nil: cam1, t1/2, b1/2, h1/2, counter1/2/3/4.
    for count = 0, 9 do
        state.convoy_alive[count] = count < state.convoy_total
        state.safe[count] = false
    end
    return state
end

-- Initialize before map AddObject callbacks; Start must not erase map haulers.
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function Distance(h, path)
    -- PORT FIX: the native arrival check calls GetDistance on NULL/dead haulers.
    -- Only a living object can arrive. Guard the Lua overload against invalid
    -- handles; valid living-object distances and all thresholds are unchanged.
    if not Alive(h) then return math.huge end
    return GetDistance(h, path)
end

function Start()
    -- NewState replaces native Load/Setup. Execute startup stays in Update.
end

function AddObject(h)
    if not Valid(h) or GetTeamNum(h) ~= 1 or not IsOdf(h, "svhaul") then return end
    -- PORT FIX: deduplicate callbacks and bound the native ten-slot array.
    -- BuildObject registration below also works with deferred AddObject hosts;
    -- repeated callbacks cannot count a hauler twice or shorten the five-spawn
    -- schedule. Normal native one-callback registration is unchanged.
    for count = 0, M.convoy_count - 1 do
        if M.convoy_handle[count] == h then return end
    end
    if M.convoy_count < 10 then
        M.convoy_handle[M.convoy_count] = h
        M.convoy_count = M.convoy_count + 1
    end
    Goto(h, "escort")
end

function Update(dt)
    local player = GetPlayerHandle()
    --[[
        Notes
        'escort' is the path you need to escort
        things down
        'spawn1' is where they start
        'spawn2' is where enemy artillery starts
        'spawn3' is where enemy tanks, etc. start
    ]]
    if not M.start_done then
        M.start_done = true
        M.convoy_time = GetTime() + 420.0
        M.wakeup_time = GetTime() + 30.0
        BuildObject("avartl", 2, "spawn2")
        M.cam1 = BuildObject("spcamr", 1, "camerapt")
        M.raider_time = GetTime() + 30.0
        M.army_time = GetTime() + 100.0
        AddScrap(1, 50)
        SetPilot(1, 30)
        SetPilot(2, 30)
        ClearObjectives()
        AddObjective("misns4.otf", "white")
        AudioMessage("misns401.wav")
        AudioMessage("misns410.wav")
        StartCockpitTimer(420, 300, 0)
        -- Stock Lua equivalent of GameObjectHandle::GetObj(cam1)->SetName.
        if Valid(M.cam1) then SetObjectiveName(M.cam1, "Bridge") end
        BuildObject("abtowe", 2, "tower1")
        BuildObject("abtowe", 2, "tower2")
        BuildObject("ablpow", 2, "power1")
        BuildObject("ablpow", 2, "power2")
        BuildObject("svcnst", 1, "svcnst")
    end
    if GetTime() > M.wakeup_time then
        local h = BuildObject("avfigh", 2, "spawn4")
        if Valid(h) then Goto(h, "wakeup") end -- a little reminder
        M.wakeup_time = 99999.0
    end
    if GetTime() > M.convoy_time then
        if not M.first then
            AudioMessage("misns402.wav")
            StopCockpitTimer()
            HideCockpitTimer()
            M.first = true
        end
        local hauler = BuildObject("svhaul", 1, "spawn1")
        if Valid(hauler) then
            AddObject(hauler) -- immediate registration; synchronous callback is deduplicated
            SetObjectiveOn(hauler)
        end
        if M.convoy_count < M.convoy_total then
            M.convoy_time = GetTime() + 45.0
        else
            M.convoy_time = 99999.0
        end
    end
    if GetTime() > M.raider_time then
        BuildObject("avfigh", 2, "spawn4")
        BuildObject("avfigh", 2, "spawn4")
        -- BuildObject("avltnk",2,"spawn4");
        M.raider_time = 99999.0
    end
    if GetTime() > M.army_time then
        M.t1 = BuildObject("avtank", 2, "sbridge")
        M.t2 = BuildObject("avtank", 2, "sbridge")
        M.b1 = BuildObject("avhraz", 2, "sbridge")
        -- b2=BuildObject("avhraz",2,"sbridge");
        M.army_time = 99999.0
    end
    --[[
        At some point later
        add more forces north
        of the bridge
        at spawn3
    ]]
    if not M.north_bridge and Distance(player, "sbridge") < 200.0 then
        M.north_bridge = true
        -- BuildObject("avtank",2,"spawn3");
        BuildObject("avltnk", 2, "spawn3")
        BuildObject("avturr", 2, "spawn3")
        BuildObject("avscav", 2, "spawn3")
        BuildObject("avrecy", 2, "spawn3")
        --[[
            Now load an AIP.
        ]]
    end
    -- Intentionally keep the source's lack of an army-spawn prerequisite:
    -- approaching the bridge before 100s can clear its currently absent guards.
    if not M.bridge_clear and M.north_bridge and
        not Alive(M.t1) and not Alive(M.t2) and not Alive(M.b1) then
        AudioMessage("misns405.wav") -- wrong message.. (source annotation)
        M.bridge_clear = true
        SetAIP("misns4.aip")
        M.counter_time = GetTime() + 150.0 -- counter attack in 2 1/2 minutes
    end
    if not M.warning and Distance(player, "warn1") < 200.0 then
        AudioMessage("misns409.wav")
        M.warning = true
    end
    -- Source index 2 is the third hauler. Keep its living requirement for BOTH
    -- triggers; do not substitute another hauler if this one is destroyed.
    if Alive(M.convoy_handle[2]) and not M.counter and
        (GetTime() > M.counter_time or Distance(M.convoy_handle[2], "warn1") < 200.0) then
        M.counter1 = BuildObject("avrckt", 2, "counter")
        M.counter2 = BuildObject("avrckt", 2, "counter")
        M.counter3 = BuildObject("avrckt", 2, "counter")
        M.counter4 = BuildObject("avrckt", 2, "counter")
        if Valid(M.counter1) then Goto(M.counter1, "sbridge") end
        if Valid(M.counter2) then Goto(M.counter2, "sbridge") end
        if Valid(M.counter3) then Goto(M.counter3, "sbridge") end
        if Valid(M.counter4) then Goto(M.counter4, "sbridge") end
        M.counter = true
        M.counter_time = 99999.0
    end
    for count = 0, M.convoy_total - 1 do
        local h = M.convoy_handle[count]
        if h ~= nil and h ~= 0 then
            if not Alive(h) and M.convoy_alive[count] then
                --[[
                    Another one bites the dust
                    AudioMessage("transport dead..")
                ]]
                AudioMessage("misns403.wav")
                M.convoy_alive[count] = false
                M.convoy_dead = M.convoy_dead + 1
                -- C++ integer division: 5/3 is 1, so the second loss fails.
                if M.convoy_dead > math.floor(M.convoy_total / 3) and not M.lost then
                    --[[
                        That's it
                        AudioMessage()
                    ]]
                    -- PORT FIX: latch the existing but unused lost flag. Later
                    -- casualties must not reschedule the original 15s defeat.
                    -- The second-loss trigger, debrief, and delay are unchanged.
                    M.lost = true
                    FailMission(GetTime() + 15.0, "misns4l1.des")
                    --[[
                        Cineractive
                        on neareset guy to
                        the dying guy
                    ]]
                end
            end
        end
        if Distance(h, "goal") < 100.0 and not M.safe[count] then
            M.safe[count] = true
            M.win_count = M.win_count + 1
        end
    end
    -- PORT FIX: equality can skip success if the fourth and fifth arrivals
    -- occur together (3 -> 5 in one Update). >= preserves four-of-five success.
    -- A latched defeat cannot be overwritten by stale arrival state. Ordinary
    -- successful runs still schedule the source's ten-second success delay.
    if M.win_count >= M.convoy_total - 1 and not M.won and not M.lost then
        SucceedMission(GetTime() + 10.0, "misns4w1.des")
        M.won = true
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores the serialized table and its engine handles; do not
    -- run Setup again, replay spawns, reset deadlines, or recount loaded units.
    M = state
end
