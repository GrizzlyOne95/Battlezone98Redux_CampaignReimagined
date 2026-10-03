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

function Start()
    -- Keep unused members and all six native miner slots available for cut content.
    -- In particular, Load's 99999 defaults for check1..4 are NOT zero: the
    -- source never arms these four proximity waves during an ordinary mission.
    M = NewState()
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

function Update(timestep)
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
end

function Save()
    return M
end

function Load(state)
    -- LuaMission serializes handles/messages in the state table. Native
    -- PostLoad/ConvertHandle and the union-array serializers are unnecessary.
    -- Do not call Start or re-register miners: this preserves next_target,
    -- timers, the pending audio message, and the selected mission outcome.
    M = state
end
