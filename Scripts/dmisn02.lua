-- dmisn02.lua (Converted from evolvemission.cpp)

-- Compatibility and Library Setup
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})
local exu = require("exu")
local bzfile = require("bzfile")
local DiffUtils = require("DiffUtils")

-- Data Structures
local attackRounds = {
    { wait = 5.0,  invehicleWait = false, numunits = 3, spawnPrefix = "pilot_%d",  attacker = "cspilo" },
    { wait = 0.0,  invehicleWait = false, numunits = 3, spawnPrefix = "sold_%d",   attacker = "cssolda" },
    { wait = 0.0,  invehicleWait = false, numunits = 3, spawnPrefix = "sniper_%d", attacker = "cssold" },
    { wait = 30.0, invehicleWait = true,  numunits = 3, spawnPrefix = "spawn_%d",  attacker = "cvfigh" },
    { wait = 10.0, invehicleWait = false, numunits = 3, spawnPrefix = "spawn_%d",  attacker = "cvltnk" },
    { wait = 10.0, invehicleWait = false, numunits = 3, spawnPrefix = "spawn_%d",  attacker = "cvtnk" },
    { wait = 10.0, invehicleWait = false, numunits = 3, spawnPrefix = "spawn_%d",  attacker = "cvhraz" },
    { wait = 10.0, invehicleWait = false, numunits = 3, spawnPrefix = "spawn_%d",  attacker = "cvwalk" },
    { wait = 10.0, invehicleWait = false, numunits = 3, spawnPrefix = "spawn_%d",  attacker = "cvhtnk" }
}

local spawnitems = {
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "repair",   item = "aprepaa" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "ammo",     item = "apammoa" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apmini_1", item = "apmini" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apmini_2", item = "apmini" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apstab_1", item = "apstab" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apstab_2", item = "apstab" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apsstb_1", item = "apsstb" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apsstb_2", item = "apsstb" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apflsh_1", item = "apflsh" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "apflsh_2", item = "apflsh" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "aptagg_1", item = "apbolt" },
    { wait = 30.0, initround = 1, attackplayer = false, spawnpoint = "aptagg_2", item = "apbolt" },
    -- C++ initround 4 becomes round 5 in this one-based Lua table.
    { wait = 30.0, initround = 5, attackplayer = true,  spawnpoint = "cover_1",  item = "csuserb" },
    { wait = 30.0, initround = 5, attackplayer = true,  spawnpoint = "cover_2",  item = "csuserb" },
    { wait = 30.0, initround = 5, attackplayer = true,  spawnpoint = "cover_3",  item = "csuserb" },
    { wait = 30.0, initround = 5, attackplayer = true,  spawnpoint = "cover_4",  item = "csuserb" }
}

-- Variables
local startup = true
local lost = false
local score = 0
local round = 1
local maxroundattackers = 1
local invehicle = false
local bestscore = 0
local orgbestscore = 0
local orgbesttime = 0
local dead_timer = 0
local state_timer = 0
local item_timers = {} -- [idx] = time
local item_handles = {} -- [idx] = handle
local current_attackers = {} -- list of active attacker handles
local old_user

-- Helpers
local function LoadBestScore()
    -- GetWorkingDirectory() has no trailing separator, so the separator has to
    -- be supplied here. Without it the path became "...\Battlezone 98
    -- Reduxemission.bst", which lands outside the game folder and bzfile
    -- refuses it -- the best score never loaded or saved.
    local filePath = bzfile.GetWorkingDirectory() .. "\\emission.bst"
    local f = bzfile.Open(filePath, "r")
    if f then
        local dump = f:Dump()
        if dump and #dump >= 8 then
            -- Binary unpack if possible, otherwise assume text or corrupt
            if string.unpack then
                bestscore, orgbesttime = string.unpack("ii", dump)
            else
               -- Fallback to text if binary is unsupported
               for s, t in dump:gmatch("(%d+) (%d+)") do
                   bestscore = tonumber(s)
                   orgbesttime = tonumber(t)
               end
            end
        end
        f:Close()
    end
    orgbestscore = bestscore
end

local function SaveBestScore(newScore, newTime)
    -- GetWorkingDirectory() has no trailing separator, so the separator has to
    -- be supplied here. Without it the path became "...\Battlezone 98
    -- Reduxemission.bst", which lands outside the game folder and bzfile
    -- refuses it -- the best score never loaded or saved.
    local filePath = bzfile.GetWorkingDirectory() .. "\\emission.bst"
    local f = bzfile.Open(filePath, "w", "trunc")
    if f then
        if string.pack then
            f:Write(string.pack("ii", newScore, newTime))
        else
            f:Write(newScore .. " " .. newTime)
        end
        f:Close()
    end
end

local function CreateAttackerRound()
    local r = attackRounds[round]
    local roundmax = r.onlyone and 1 or maxroundattackers
    local user = GetPlayerHandle()

    for i=1, r.numunits do
        local spn = string.format(r.spawnPrefix, i)
        for j=1, roundmax do
            local h = BuildObject(r.attacker, 2, spn)
            if h then
                table.insert(current_attackers, h)
                Attack(h, user)
            end
        end
    end

    -- "nowait" logic in C++ loop
    if r.nowait and round < #attackRounds then
        round = round + 1
        CreateAttackerRound()
    end
end

-- Preserve native mission state across save/load.
function Save()
    return {
        attackRounds = attackRounds,
        spawnitems = spawnitems,
        startup = startup,
        lost = lost,
        score = score,
        round = round,
        maxroundattackers = maxroundattackers,
        invehicle = invehicle,
        bestscore = bestscore,
        orgbestscore = orgbestscore,
        orgbesttime = orgbesttime,
        dead_timer = dead_timer,
        state_timer = state_timer,
        item_timers = item_timers,
        item_handles = item_handles,
        current_attackers = current_attackers,
        old_user = old_user,
    }
end

function Load(state)
    if not state then return end
    attackRounds = state.attackRounds
    spawnitems = state.spawnitems
    startup = state.startup
    lost = state.lost
    score = state.score
    round = state.round
    maxroundattackers = state.maxroundattackers
    invehicle = state.invehicle
    bestscore = state.bestscore
    orgbestscore = state.orgbestscore
    orgbesttime = state.orgbesttime
    dead_timer = state.dead_timer
    state_timer = state.state_timer
    item_timers = state.item_timers
    item_handles = state.item_handles
    current_attackers = state.current_attackers
    old_user = state.old_user
end
function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    LoadBestScore()
    startup = true
    lost = false
    score = 0
    round = 1
    maxroundattackers = 1
end

function Update()
    local user = GetPlayerHandle()

    -- Death and Scoring Persistence
    if not lost and not IsAlive(user) then
        if dead_timer > 0 then
            if GetTime() > dead_timer then
                local currenttime = GetCockpitTimer()
                local bestmin, bestsec = math.floor(orgbesttime / 60), orgbesttime % 60
                local curmin, cursec = math.floor(currenttime / 60), currenttime % 60

                local values = {score, curmin, cursec, orgbestscore, bestmin, bestsec}

                if score > orgbestscore or (score == orgbestscore and currenttime < orgbesttime) then
                    SaveBestScore(score, currenttime)
                    SucceedMission(GetTime() + 2.0, "sammywin.des", unpack(values))
                else
                    SucceedMission(GetTime() + 2.0, "sammylse.des", unpack(values))
                end
                lost = true
                return
            end
        else
            dead_timer = GetTime() + 2.0
        end
    elseif lost then
        return
    else
        dead_timer = 0
    end

    if startup then
        SetScrap(1, 0); SetPilot(1, 10); SetMaxScrap(1, bestscore)
        StartCockpitTimerUp(0)
        score = 0; startup = false; invehicle = false; round = 1
        old_user = user
        state_timer = 0; maxroundattackers = 1

        for i, item_def in ipairs(spawnitems) do
            item_handles[i] = nil
            item_timers[i] = (item_def.initround <= round) and 1 or 0
        end
        CreateAttackerRound()
        return
    end

    -- FSM State Logic
    if state_timer > 0 then
        if state_timer == 1 then -- invehicleWait
            if invehicle then state_timer = GetTime() + (attackRounds[round] and attackRounds[round].wait or 0) end
        elseif GetTime() > state_timer then
            CreateAttackerRound()
            state_timer = 0
        end
    else
        -- Check Wave Progress
        local alldead = true
        local i = 1
        while i <= #current_attackers do
            local h = current_attackers[i]
            if not IsAlive(h) then
                RemoveObject(h); table.remove(current_attackers, i)
                score = score + 1
                if score > bestscore then bestscore = score; SetMaxScrap(1, bestscore) end
                SetScrap(1, score)
            else
                alldead = false; i = i + 1
            end
        end

        -- Check Item Attacker score increment
        for i, item_def in ipairs(spawnitems) do
            if item_def.attackplayer and item_handles[i] and not IsAlive(item_handles[i]) then
                RemoveObject(item_handles[i]); item_handles[i] = nil
                score = score + 1
                if score > bestscore then bestscore = score; SetMaxScrap(1, bestscore) end
                SetScrap(1, score)
            end
        end

        if alldead then
            round = round + 1
            if round > #attackRounds then
                round = 4 -- RESTARTROUND (index 4 in 1-based Lua)
                if maxroundattackers < 20 then maxroundattackers = maxroundattackers + 1 end
            end

            local r = attackRounds[round]
            if r.invehicleWait then state_timer = 1
            elseif r.wait > 0 then state_timer = GetTime() + r.wait
            else CreateAttackerRound() end
        end
    end

    -- Timed Item Respawning
    for i, item_def in ipairs(spawnitems) do
        if item_timers[i] == 0 then
            if not item_handles[i] or not IsAlive(item_handles[i]) then
                if item_def.initround <= round then
                    item_def.initround = 0 -- Once triggered, always respawn
                    item_timers[i] = GetTime() + item_def.wait
                end
            end
        elseif item_timers[i] > 1 and GetTime() > item_timers[i] then
            item_timers[i] = 0
            local team = item_def.attackplayer and 2 or 1
            item_handles[i] = BuildObject(item_def.item, team, item_def.spawnpoint)
            if item_def.attackplayer and item_handles[i] then Attack(item_handles[i], user) end
        end
    end

    -- Source repeatedly removes npscr debris so the arena remains uncluttered.
    for h in AllObjects() do
        local odf = GetOdf(h)
        if odf and odf:sub(1, 5):lower() == "npscr" then RemoveObject(h) end
    end

    -- A player-handle change signals entering/changing craft. Retarget active
    -- attackers and hostile cover pilots exactly as the source does.
    if user and user ~= old_user then
        for _, h in ipairs(current_attackers) do
            if IsAlive(h) then Attack(h, user) end
        end
        for i, item_def in ipairs(spawnitems) do
            if item_def.attackplayer and item_handles[i] and IsAlive(item_handles[i]) then
                Attack(item_handles[i], user)
            end
        end
        old_user = user
        invehicle = true
    end
end

