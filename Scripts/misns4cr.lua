-- Faithful stock misns4 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns4Mission.cpp
-- Source blob: efc5de9d0b4cd4fcfd0165c04319725417f87ae7.
-- All disabled mission code is retained inline. The complete native source,
-- including declarations/serialization and all comments, is archived in
-- References/Misns4Source/. No campaign helpers, EXU, or OpenShim required.

-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/MISNS4_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Io weather); outside it this file is
-- the faithful port below, byte for byte (Tools/Test-Misns4CoopSourceParity.py).
-- CR co-op layer <<
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
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/MISNS4_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/MISNS4_COOP.md, "Restored content").
local RESTORED_RAIDER_LTNK, RESTORED_BRIDGE_HRAZ, RESTORED_NORTH_TANK = true, true, true
local SCRAP_PER_GUEST = 10
local Restored = {}
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "misns4", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "svrecy0_recycler" },
    scrapPerGuest = SCRAP_PER_GUEST,
    -- Every enemy unit the body builds (raiders, bridge guard, north force, counterattack rockets) is a scaled
    -- ticket: concealed from the humans, mirrored by extras, orders replayed. Towers, power plants, the
    -- howitzer and all Soviet-side builds (pod, constructor, haulers) are built straight away.
    scaledOdfs = { avfigh = true, avtank = true, avltnk = true, avrckt = true, avturr = true, avscav = true,
        avrecy = true },
    fallbackEntries = { "spawn4", "spawn3", "counter" },
    failDes = "misns4l1.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    weather = { module = "CRIoWeather", sites = "CRIoSitesS4", startLevel = 1, targetLevel = 1,
        ops = { "IoState", "IoErupt", "IoQuake" },
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -75 } },
        beats = function(io, state, s)
            local beats = s.ioBeats
            if beats == nil then beats = {}; s.ioBeats = beats end
            local function once(name, condition, fn)
                if (not beats[name]) and condition then
                    beats[name] = true
                    pcall(fn)
                end
            end
            local function erupt(power)
                local sites = io.GetVentSites and io.GetVentSites() or nil
                local count = sites and #sites or 0
                if count > 0 then
                    beats.erupts = (beats.erupts or 0) + 1
                    io.TriggerEruption(1 + beats.erupts % count, power)
                end
            end
            -- The convoy rolls in under a restless sky; the bridge fight and the rocket counterattack raise it,
            -- a lost transport makes a vent erupt, defeat is paroxysm, and a clean win eases it.
            once("convoy", state.first, function() io.SetTargetLevel(2) end)
            once("bridge", state.north_bridge, function() io.SetTargetLevel(3) end)
            once("secure", state.bridge_clear, function() io.Quake(0.3, 5) end)
            once("counter", state.counter, function()
                io.SetTargetLevel(4)
                io.Quake(0.5, 6)
                erupt(1.3)
            end)
            once("loss1", (state.convoy_dead or 0) >= 1, function() erupt(1.5) end)
            once("lost", state.lost, function() io.ForceLevel(5, 60.0, 5.0) end)
            once("won", state.won, function() io.SetTargetLevel(2) end)
        end },
    hooks = {
        -- The Io sensors feed Environment's sky/ambient reads on every peer, once the director is running.
        update = function(runtime)
            if not Restored.sensorsBound and runtime.Weather then
                Restored.sensorsBound = true
                local ok, Environment = pcall(require, "Environment")
                if ok and type(Environment) == "table" and Environment.BindWeatherSensors then
                    pcall(Environment.BindWeatherSensors, "Io", runtime.Weather.module)
                end
            end
        end,
        load = function() Restored.sensorsBound = false end,
    },
})
local BuildObject = campaignRuntime and campaignRuntime.Spawn or BuildObject
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local GetDistance = campaignRuntime and campaignRuntime.GetDistance or GetDistance
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
-- Stock bug: misns4.aip asks the American base for Soviet svturr turrets it cannot build; crns4.aip is the same plan with avturr.
local CR_AIP = { ["misns4.aip"] = "crns4.aip" }
local stockSetAIP = SetAIP
SetAIP = function(name, team) return stockSetAIP(CR_AIP[name] or name, team) end
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The cockpit countdown is presentation: every peer shows the leader's timer (and loses it together).
local StartCockpitTimer = campaignRuntime and function(...) return campaignRuntime.Present("StartCockpitTimer", ...) end or StartCockpitTimer
local StopCockpitTimer = campaignRuntime and function() return campaignRuntime.Present("StopCockpitTimer") end or StopCockpitTimer
local HideCockpitTimer = campaignRuntime and function() return campaignRuntime.Present("HideCockpitTimer") end or HideCockpitTimer
-- Team 2 is the enemy in the DLL and a guest's team here: team 2 -> 5. Team 1 is the one shared Soviet side:
-- its pilots go to every human team (each human respawns from its own pool) and its starting scrap grows per guest.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
local AddScrap = campaignRuntime and function(team, amount)
    if team == 1 then return AddScrap(1, amount + SCRAP_PER_GUEST * (campaignRuntime.HumanCount() - 1)) end
    if team == 2 then team = 5 end
    return AddScrap(team, amount)
end or AddScrap
-- CR co-op runtime <<

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

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/MISNS4_COOP.md quotes each cut block). Each has a
-- RESTORED_* flag and is built only when the map carries its path; units go through the scaled spawn layer.
if campaignRuntime then
    -- The body's approach triggers ask for the PLAYERS token: answer with the nearest human.
    Distance = campaignRuntime.WrapDistance(Distance)
    local function Mine()
        local s = campaignRuntime.State()
        s.r = s.r or {}
        return s.r
    end
    function Restored.Step()
        if not M.start_done then return end
        local r = Mine()
        -- Cut: `// BuildObject("avltnk",2,"spawn4");` after the two raiders.
        if RESTORED_RAIDER_LTNK and not r.ltnk and M.raider_time >= 99999.0 then
            r.ltnk = true
            if campaignRuntime.PathExists("spawn4") then BuildObject("avltnk", 2, "spawn4") end
        end
        -- Cut: `// b2=BuildObject("avhraz",2,"sbridge");` after the bridge guard.
        if RESTORED_BRIDGE_HRAZ and not r.hraz and M.army_time >= 99999.0 then
            r.hraz = true
            if campaignRuntime.PathExists("sbridge") then M.b2 = BuildObject("avhraz", 2, "sbridge") end
        end
        -- Cut: `// BuildObject("avtank",2,"spawn3");` ahead of the north force.
        if RESTORED_NORTH_TANK and not r.north and M.north_bridge then
            r.north = true
            if campaignRuntime.PathExists("spawn3") then BuildObject("avtank", 2, "spawn3") end
        end
    end
end
-- CR restored content <<
function Start()
    -- NewState replaces native Load/Setup. Execute startup stays in Update.
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
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
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
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
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
        BuildObject("avfigh", 2, "spawn4")
        BuildObject("avfigh", 2, "spawn4")
        -- BuildObject("avltnk",2,"spawn4");
        M.raider_time = 99999.0
    end
    if GetTime() > M.army_time then
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
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
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
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
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
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
-- CR restored content >>
    if campaignRuntime then Restored.Step() end
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
    -- LuaMission restores the serialized table and its engine handles; do not
    -- run Setup again, replay spawns, reset deadlines, or recount loaded units.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
-- The body's AddObject registers convoy haulers and orders them down the escort path. The runtime also needs the
-- engine callback; only the authority runs the body half (guests never order anything).
local bodyAddObject = AddObject
function AddObject(h)
    if not campaignRuntime then return bodyAddObject(h) end
    campaignRuntime.AddObject(h)
    local known, authority = pcall(campaignRuntime.Coop.IsAuthority)
    if known and authority then
        local ok, err = pcall(bodyAddObject, h)
        if not ok then print("[misns4] AddObject failed: " .. tostring(err)) end
    end
end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
