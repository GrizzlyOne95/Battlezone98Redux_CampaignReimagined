-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/MISNS6_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, Titan weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Misns6CoopSourceParity.py).
-- CR co-op layer <<
-- Faithful Misns6Mission port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misns6Mission.cpp
-- Source blob: d00a5728a0a925755807683d6d09a234d3afe593.
-- Complete original C++/header (all comments and #if 0 code preserved):
-- References/Misns6Source/. Single-player; stock BZR API only.

local function NewState()
    return {
        won = false, lost = false, last_objective = false,
        start_done = false, won_message = false, lost_message = false,
        warning = false, base_suggestion = false, art_found = false,
        counter1 = false, counter2 = false, counter3 = false,
        counter4 = false, counter5 = false, counter_attack = false,
        check_time = 99999.0, check1 = 99999.0, check2 = 99999.0,
        check3 = 99999.0, check4 = 99999.0, aip_time = 99999.0,
        beacon = nil, goal = nil, art1 = nil, art2 = nil,
        tur1 = nil, tur2 = nil, tur3 = nil, tur4 = nil,
        far_silo = nil, recy = nil, miners = {},
        next_target = 0, audmsg = nil, success_scheduled = false,
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/MISNS6_COOP.md lists every wrapped call. No cut content is
-- restored in this mission (the doc quotes each cut block and why it stays cut); the one RESTORED_* flag below
-- covers a single unused shipped voice line.
local RESTORED_VOICE_LINES = true -- unused shipped line misns606 (Docs/MISNS6_COOP.md)
local Restored = {}
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "misns6", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "svrecy0_recycler" },
    -- The two Black Dog raiders and the silo counter-attack are the scaled spawns; the mines never are.
    scaledOdfs = { bvraz = true, bvltnk = true, bvtank = true, bvrckt = true },
    fallbackEntries = { "counter3", "counter4", "counter2", "counter5" },
    failDes = "misns6l1.des",
    wonFlags = { "won" },
    endedFlags = { "success_scheduled", "lost" },
    weather = { module = "CRTitanWeather", sites = "CRTitanSitesS6", startLevel = 1, targetLevel = 2,
        environment = { nativeBaseline = true }, ops = { "TitanState", "TitanRoll" },
        beats = function(titan, state, s)
            local beats = s.titanBeats
            if beats == nil then beats = {}; s.titanBeats = beats end
            if (not beats.minefield) and (state.warning or state.counter1) then
                beats.minefield = true
                titan.SetTargetLevel(3)
            end
            if (not beats.shroud) and (state.counter_attack or state.last_objective) then
                beats.shroud = true
                titan.SetTargetLevel(4)
            end
            if (not beats.easing) and state.won then
                beats.easing = true
                titan.SetTargetLevel(2)
            end
        end },
})
local BuildObject = campaignRuntime and campaignRuntime.Spawn or BuildObject
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend = campaignRuntime and campaignRuntime.Defend or Defend
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
-- The body's player handle is the runtime's PLAYERS token. These shadows give it the semantics the body needs:
-- valid, and a distance origin or target that means "the nearest human" (the body only ever asks nearest;
-- a human without a live ship is infinitely far). The body also uses the 3-argument path-point form.
local IsValid = IsValid
local GetDistance = GetDistance
local GetTeamNum = GetTeamNum
local IsAudioMessageDone = IsAudioMessageDone
if campaignRuntime then
    local PLAYERS = campaignRuntime.PLAYERS
    local ENEMY_TEAM, MAP_ENEMY_TEAM = 5, 2
    local nativeIsValid, nativeGetDistance = IsValid, GetDistance
    local nativeGetTeamNum, nativeAudioDone = GetTeamNum, IsAudioMessageDone
    local runtimeIsValid = campaignRuntime.IsValid
    IsValid = function(h)
        if h == PLAYERS then return true end
        return runtimeIsValid(h)
    end
    local function ForEachHuman(fn)
        pcall(campaignRuntime.Coop.ForEachPlayerHandle, function(h)
            if h ~= nil and h ~= 0 and nativeIsValid(h) then fn(h) end
        end)
    end
    local function Measure(h, target, point)
        if point ~= nil then return nativeGetDistance(h, target, point) end
        return nativeGetDistance(h, target)
    end
    local function HumanDistance(target, point)
        if target == nil or target == 0 then return math.huge end
        if type(target) ~= "string" and not nativeIsValid(target) then return math.huge end
        local best = math.huge
        ForEachHuman(function(h)
            local d = Measure(h, target, point)
            if d < best then best = d end
        end)
        return best
    end
    GetDistance = function(a, b, point)
        if a == PLAYERS then return HumanDistance(b, point) end
        if b == PLAYERS then return HumanDistance(a, point) end
        if (type(a) == "number" and a < 0) or (type(b) == "number" and b < 0) then return math.huge end
        return Measure(a, b, point)
    end
    -- The map enemy team 2 is team 5 here; the body's AddObject filter still says 2.
    GetTeamNum = function(h)
        local team = nativeGetTeamNum(h)
        if team == ENEMY_TEAM then return MAP_ENEMY_TEAM end
        return team
    end
    -- BUG FIX (CR layer): the victory wait read IsAudioMessageDone of a nil/absent message handle.
    IsAudioMessageDone = function(message)
        if message == nil or message == 0 then return true end
        return nativeAudioDone(message)
    end
    -- BUG FIX (CR layer): Attack(raider, GetPlayerHandle()) means "the human" in the body; with several humans
    -- the raiders hunt the human nearest their entry (the miner field's counter1 path), as a real handle.
    local runtimeAttack = Attack
    local function NearestHumanHandle(anchor)
        local best, bestD
        ForEachHuman(function(h)
            local d = 0
            local ok, measured = pcall(Measure, h, anchor)
            if ok and type(measured) == "number" then d = measured end
            if bestD == nil or d < bestD then best, bestD = h, d end
        end)
        return best
    end
    Attack = function(h, target)
        if target == PLAYERS then target = NearestHumanHandle("counter1") end
        if target == nil then return end
        return runtimeAttack(h, target)
    end
end
-- CR co-op runtime <<
local mine_paths = {"s1", "s2", "s3", "m1", "m2", "m3"}

local function Exists(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

-- Missing/removed handles cannot satisfy proximity checks. This prevents nil
-- from selecting an unintended API overload; present-object radii are unchanged.
local function Distance(from, to, point)
    if not Exists(from) then return math.huge end
    if type(to) ~= "string" and not Exists(to) then return math.huge end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

-- CR restored content >>
-- misns606 "We've cleared the artillery. Continue to push forward." once, when both howitzers the body holds
-- (art1, art2) have been seen alive and are now both gone. Not after the mission is won, lost or scheduled.
if campaignRuntime then
    function Restored.Voice()
        if not RESTORED_VOICE_LINES or not M.start_done then return end
        local s = campaignRuntime.State()
        s.r = s.r or {}
        local r = s.r
        if r.l606 then return end
        local a1, a2 = IsAlive(M.art1), IsAlive(M.art2)
        if a1 then r.art1Seen = true end
        if a2 then r.art2Seen = true end
        if r.art1Seen and r.art2Seen and not a1 and not a2 and not M.won and not M.lost and not M.success_scheduled then
            r.l606 = true
            AudioMessage("misns606.wav")
        end
    end
end
-- CR restored content <<
function Start()
    -- Keep unused members and all six native miner slots available for cut content.
    -- In particular, Load's 99999 defaults for check1..4 are NOT zero: the
    -- source never arms these four proximity waves during an ordinary mission.
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
end

function AddObject(h)
    if not Exists(h) or GetTeamNum(h) ~= 2
        or not (IsOdf(h, "avmine") or IsOdf(h, "avmine.odf")) then return end
    -- BuildObject may deliver AddObject synchronously or after the spawn returns.
    -- Idempotency allows the explicit startup registration below in either case.
    for i = 1, 6 do
        if M.miners[i] == h then return end
    end
    -- BUG FIX: native 'closest' was uninitialized if all distances >=99999.
    -- Start with slot 0 as a safe fallback; retain the source's 99999 cutoff,
    -- strict tie handling and intermediate Goto calls for normal map positions.
    local closest, min_dist = 0, 99999.0
    for i = 1, 3 do
        local temp = Distance(h, "m" .. i, 1)
        if temp < min_dist then
            closest, min_dist = i - 1, temp
            Goto(h, "s" .. i, 1)
        end
    end
    -- Native miners[0..5] becomes Lua miners[1..6]; next_target stays 0..5.
    M.miners[closest + 1] = h
    M.next_target = closest
end

-- Stock bug: misns6.aip asks the American base for Soviet svturr turrets it cannot build; crns6.aip is the same plan with avturr.
local SetAIP = (function()
    local stockSetAIP = SetAIP
    local AIP = { ["misns6.aip"] = "crns6.aip" }
    return function(name, ...) return stockSetAIP(AIP[name] or name, ...) end
end)()

function Update(timestep)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(timestep) then return end
-- CR co-op callback <<
    local player = GetPlayerHandle()
    if not M.start_done then
        M.next_target = 0
        -- BuildObject("svrecy",1,"spawn1"); -- source cut recycler spawn
        M.aip_time = GetTime() + 120.0
        for i = 1, 3 do
            local h = BuildObject("avmine", 2, "m" .. i)
            AddObject(h)
        end
        M.goal = GetHandle("abcafe8_i76building")
        M.art1 = GetHandle("avartl3_howitzer")
        M.art2 = GetHandle("avartl4_howitzer")
        M.tur1 = GetHandle("avturr0_turrettank")
        M.tur2 = GetHandle("avturr1_turrettank")
        M.tur3 = GetHandle("defender1")
        M.tur4 = GetHandle("defender2")
        M.recy = GetHandle("svrecy0_recycler")
        M.far_silo = GetHandle("absilo0_scrapsilo")
        for _, key in ipairs({"art1", "art2", "tur3", "tur4", "tur1", "tur2"}) do
            if Exists(M[key]) then Defend(M[key], 1) end
        end
        SetScrap(1, 20)
        M.check_time = GetTime() + 10.0
        AudioMessage("misns601.wav")
        ClearObjectives()
        AddObjective("misns601.otf", "white")
        AddObjective("misns602.otf", "white")
        M.start_done = true
    end
    if not M.warning and (Distance(player, "m1", 1) < 250
        or Distance(player, "m2", 1) < 250
        or Distance(player, "m3", 1) < 250) then
        AudioMessage("misns602.wav")
        M.warning = true
    end
    if GetTime() > M.aip_time then
        SetAIP("misns6.aip")
        M.aip_time = 99999.0
    end
    if GetTime() > M.check_time then
        for count = 1, 3 do
            -- if (what == CMD_NONE)
            --   Attack(friend1, enemy1);
            local h = M.miners[count]
            if IsAlive(h) then
                -- Stock GetLastEnemyShot exposes the native enemyShot timestamp.
                -- Keep >0 literally: friendly damage/health loss is not equivalent.
                if GetLastEnemyShot(h) > 0 and not M.counter1 then
                    M.counter1 = true
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
                    local a1 = BuildObject("bvraz", 2, "counter1")
                    local a2 = BuildObject("bvraz", 2, "counter2")
                    Attack(a1, player)
                    Attack(a2, player)
                end
                -- Native-only state inspection retained for reconstruction:
                --[=[
                #if 0
                    AiProcess *p=meObj->GetAIProcess();
                    bool test=((MineLayerProcess *) p)->laying;
                #else
                    UnitProcess *p = (UnitProcess *)meObj->GetAIProcess();
                    bool test = p->curState == UnitProcess::USTATE1;
                #endif
                ]=]
                -- BZR adaptation: Lua cannot read UnitProcess::curState. The
                -- stock Mine command remains AiCommand.LAY_MINES until completion
                -- (MineLayerProcess::DoUState1 clears it when the task finishes).
                -- Therefore NONE is the public idle test; do not use IsBusy,
                -- which reports producer activity rather than mine-laying state.
                -- An engine state with NONE while still in USTATE1 cannot be
                -- distinguished by stock Lua and requires in-game validation.
                local what = GetCurrentCommand(h)
                if what == AiCommand.NONE then
                    -- (meObj->((MineLayerProcess *) GetAIProcess())->laying))
                    -- ((MineLayerProcess *) aiProcess)->laying))
                    Mine(h, mine_paths[M.next_target + 1], 1)
                    M.next_target = M.next_target + 1
                    if M.next_target > 5 then M.next_target = 0 end
                end
            end
            -- Source assignment is inside the loop; all three miners are still
            -- checked during this pass, not just the first surviving one.
            M.check_time = GetTime() + 3.0
        end
    end
    -- Preserve the four repeated waves, their false (never set) counter flags,
    -- dormant initial timers, and the source's differing timer arithmetic.
    if not M.counter2 and GetTime() > M.check1 then
        if Distance(player, "counter2") < 400.0 then
            BuildObject("bvtank", 2, "counter2")
            BuildObject("bvtank", 2, "counter2")
            BuildObject("bvturr", 2, "counter2")
            M.check1 = M.check1 + 300.0
        else M.check1 = GetTime() + 3.0 end
    end
    if not M.counter3 and GetTime() > M.check2 then
        if Distance(player, "counter3") < 400.0 then
            BuildObject("bvtank", 2, "counter3")
            BuildObject("bvtank", 2, "counter3")
            BuildObject("bvturr", 2, "counter3")
            M.check2 = M.check2 + 300.0
        else M.check2 = GetTime() + 3.0 end
    end
    if not M.counter4 and GetTime() > M.check3 then
        if Distance(player, "counter4") < 200.0 then
            BuildObject("bvtank", 2, "counter4")
            BuildObject("bvtank", 2, "counter4")
            BuildObject("bvturr", 2, "counter4")
            M.check3 = GetTime() + 300.0
        else M.check3 = GetTime() + 3.0 end
    end
    if not M.counter5 and GetTime() > M.check4 then
        if Distance(player, "counter5") < 200.0 then
            BuildObject("bvtank", 2, "counter5")
            BuildObject("bvtank", 2, "counter5")
            BuildObject("bvturr", 2, "counter5")
            M.check4 = GetTime() + 300.0
        else M.check4 = GetTime() + 3.0 end
    end
    if not M.art_found and (Distance(player, M.art1) < 200.0
        or Distance(player, M.art2) < 200.0) then
        M.art_found = true
        AudioMessage("misns605.wav")
    end
    if not M.counter_attack and Distance(M.far_silo, player) < 400.0 then
-- CR co-op scaling >>
    if campaignRuntime then campaignRuntime.BeginEvent() end
-- CR co-op scaling <<
        for _, odf in ipairs({"bvltnk", "bvltnk", "bvtank", "bvtank", "bvrckt"}) do
            local temp = BuildObject(odf, 2, "counter_attack")
            Goto(temp, "counter_attack_path", 1)
        end
        AudioMessage("misns603.wav")
        M.counter_attack = true
    end
    --[[
        If the player
        is close to the last objective
        make it the
        objective.
    ]]
    if not M.last_objective and Distance(player, M.goal) < 300.0 then
        ClearObjectives()
        AddObjective("misns601.otf", "green")
        AddObjective("misns602.otf", "white")
        M.last_objective = true
        SetObjectiveOn(M.goal)
    end
    -- BUG FIX: the native success branch reset won=false after scheduling
    -- success. A dead goal then replayed misns609 every subsequent Execute,
    -- and a dead recycler could schedule failure in that same success frame.
    -- Latch won and success_scheduled instead; the goal trigger, victory audio
    -- wait, zero success delay, and victory precedence on simultaneous goal/
    -- recycler destruction stay intact. Once loss is scheduled it is likewise
    -- final, avoiding a later goal death replacing an already chosen outcome.
    if not M.won and not M.lost and not IsAlive(M.goal) then
        M.audmsg = AudioMessage("misns609.wav")
        M.won_message = true
        M.won = true
    end
    if M.won and not M.success_scheduled and IsAudioMessageDone(M.audmsg) then
        SucceedMission(GetTime() + 0.0, "misns6w1.des")
        M.success_scheduled = true
        -- won=false; -- original faulty reset retained, intentionally disabled
    end
    if not M.won and not M.lost and not IsAlive(M.recy) then
        M.lost = true
        FailMission(GetTime() + 2.0, "misns6l1.des")
    end
-- CR restored content >>
    if campaignRuntime then Restored.Voice() end
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
    -- LuaMission serializes handles/messages in the state table. Native
    -- PostLoad/ConvertHandle and the union-array serializers are unnecessary.
    -- Do not call Start or re-register miners: this preserves next_target,
    -- timers, the pending audio message, and the selected mission outcome.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
local bodyAddObject = AddObject
-- The body's AddObject drives the mine layers (Goto/miners); only the authority runs it.
function AddObject(h)
    if campaignRuntime then
        campaignRuntime.AddObject(h)
        local ok, authority = pcall(campaignRuntime.Coop.IsAuthority)
        if ok and not authority then return end
    end
    return bodyAddObject(h)
end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
