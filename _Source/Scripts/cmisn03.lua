-- cmisn03.lua (Converted from Chinese03Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CRA, aiCore.Factions.CCA, 2)
end

-- Variables
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local in_howitzer = {false, false, false, false, false, false}
local howitzer_ready = {false, false, false, false, false, false}
local turned_around = {false, false, false}
local trigger1_done = false
local won = false
local lost = false

-- Timers
local opening_sound_time = 99999.0
local apc_spawn_time = 99999.0
local factory_spawn_time = 99999.0
local general_spawn_time = 99999.0
local explosion_times = {} -- 1 to 15
for i=1,15 do table.insert(explosion_times, 99999.0) end

-- Handles
local user, last_user
local howitzers = {} -- 1-6
local apc = {} -- 1-6
local general
local factory, armoury
local opening_sound, lose1_sound, lose2_sound, win_sound, sound9
local general_apc_idx = -1

-- Data Arrays from C++
local sounds = {"ch03003.wav", "ch03004.wav", "ch03005.wav"}
local back_paths = {"east_back", "north_back", "west_back"}
local close_to = {"east_exit", "north_exit", "west_exit"}
local explosion_spots = {
    "east_exit", "east_exit", "east_exit", "east_exit", "east_exit",
    "north_exit", "north_exit", "north_exit", "north_exit", "north_exit",
    "west_exit", "west_exit", "west_exit", "west_exit", "west_exit"
}
local spawns = {"apc_east", "apc_east", "apc_north", "apc_north", "apc_west", "apc_west"}
local apc_follow_paths = {"east_path", "east_path", "north_path", "north_path", "west_path", "west_path"}
local defend_spawn_spots = {"east_defend", "east_defend", "north_defend", "north_defend", "west_defend", "west_defend"}

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
    end
end

function DeleteObject(h)
end

function Update()
    last_user = user
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetPilot(1, DiffUtils.ScaleRes(10))
        SetScrap(1, DiffUtils.ScaleRes(0))
        
        for i=1,6 do howitzers[i] = GetHandle("howitzer_1") end -- wait, C++ says 1..6
        for i=1,6 do howitzers[i] = GetHandle("howitzer_"..i) end
        
        for i=1,6 do
            if howitzers[i] then
                SetObjectiveOn(howitzers[i])
                SetPerceivedTeam(howitzers[i], 2)
            end
        end
        
        StartCockpitTimer(DiffUtils.ScaleTimer(780), 30, 10)
        factory_spawn_time = GetTime() + 480.0
        opening_sound_time = GetTime() + 1.0
        
        ClearObjectives()
        AddObjective("ch03001.otf", "white")
        
        start_done = true
    end
    
    if won or lost then return end
    
    -- Sound Intro
    if GetTime() > opening_sound_time then
        opening_sound_time = 99999.0
        opening_sound = AudioMessage("ch03001.wav")
    end
    
    -- Phase 1 logic: Howitzer Repair
    if not objective1_complete then
        if GetCockpitTimer() <= 0 and not lost then
            lost = true
            FailMission(GetTime() + 1.0, "ch03lsea.des")
            return
        end
        
        objective1_complete = true
        for i=1,6 do
            local h = howitzers[i]
            if h then
                if user == h and not in_howitzer[i] then
                    in_howitzer[i] = true
                    AudioMessage("ch03002.wav")
                end
                
                if not howitzer_ready[i] then
                    if GetCurHealth(h) > 400 and GetCurAmmo(h) > 400 then
                        howitzer_ready[i] = true
                        SetObjectiveOff(h)
                    else
                        objective1_complete = false
                    end
                else
                    -- Attachment logic: if player leaves a ready howitzer, give it an AI pilot
                    if user ~= h and in_howitzer[i] then
                        SetTeamNum(h, 1) -- Ensure on player team
                        -- SetPerceivedTeam(h, 2) -- C++ does this to avoid friendly fire or similar? 
                        -- Actually C++ line 456 does: SetPerceivedTeam(howitzers[i], 2);
                        SetPerceivedTeam(h, 2)
                        -- In Lua BZ98, units with no pilot don't do anything. 
                        -- To simulate "attaching" an AI process, we might need to ensure it has a pilot.
                        -- SetPilotClass(h, "cspilo") -- if needed
                    end
                end
            end
        end
        
        if objective1_complete then
            StopCockpitTimer()
            HideCockpitTimer()
            ClearObjectives()
            AddObjective("ch03001.otf", "green")
            AddObjective("ch03002.otf", "white")
            apc_spawn_time = GetTime()
            local nav = BuildObject("apcamr", 1, "nav_base")
            SetName(nav, "CCA Base")
        end
    end
    
    -- Phase 2: Convoy Ambush
    if GetTime() > apc_spawn_time then
        apc_spawn_time = 99999.0
        general_apc_idx = math.random(1, 6)
        general_spawn_time = GetTime()
        for i=1,6 do
            local odf = (general_apc_idx == i) and "svapcq" or "svapcr"
            apc[i] = BuildObject(odf, 2, spawns[i])
            SetPerceivedTeam(apc[i], 1)
            Goto(apc[i], apc_follow_paths[i], 1)
            
            -- Defenses
            local function Sp(odf, n) for j=1, DiffUtils.ScaleEnemy(n) do local h = BuildObject(odf, 2, defend_spawn_spots[i]); Defend2(h, apc[i], 1) end end
            Sp("svtank", 2); Sp("svhraz", 1); Sp("svfigh", 1)
        end
        general = apc[general_apc_idx]
    end
    
    -- Groups turn around logic
    if objective1_complete and not objective2_complete then
        for i=1,3 do
            if not turned_around[i] then
                if GetDistance(apc[2*i-1], close_to[i]) < 40.0 or
                   GetDistance(apc[2*i], close_to[i]) < 40.0 then
                    turned_around[i] = true
                    AudioMessage(sounds[i])
                    
                    Goto(apc[2*i-1], back_paths[i], 1)
                    Goto(apc[2*i], back_paths[i], 1)
                    
                    -- Howitzers attack!
                    if howitzers[2*i-1] then Attack(howitzers[2*i-1], apc[2*i-1], 1) end
                    if howitzers[2*i] then Attack(howitzers[2*i], apc[2*i], 1) end
                    
                    -- Start explosion sequence for this path
                    explosion_times[5*i-4] = GetTime()
                    explosion_times[5*i-3] = GetTime() + 5
                    explosion_times[5*i-2] = GetTime() + 10
                    explosion_times[5*i-1] = GetTime() + 15
                    explosion_times[5*i] = GetTime() + 20
                end
            end
        end
    end
    
    -- Explosions
    for i=1,15 do
        if GetTime() > explosion_times[i] then
            explosion_times[i] = 99999.0
            MakeExplosion("xgasxpl", explosion_spots[i])
        end
    end
    
    -- Phase 3 Captured logic
    if not objective2_complete and general and GetTeamNum(general) == 1 then
        objective2_complete = true
        AudioMessage("ch03006.wav")
        ClearObjectives()
        AddObjective("ch03001.otf", "green")
        AddObjective("ch03002.otf", "green")
        AddObjective("ch03003.otf", "white")
        SetObjectiveOn(general)
    end
    
    -- Escort Ambushes
    if objective2_complete and not trigger1_done and GetDistance(general, "trigger_1") < 30.0 then
        trigger1_done = true
        for i=1, DiffUtils.ScaleEnemy(6) do local h = BuildObject("svfigh", 2, "apc_attack"); Attack(h, general, 1) end
        for i=1, DiffUtils.ScaleEnemy(4) do local h = BuildObject("svfigh", 2, "apc_attack_2"); Attack(h, general, 1) end
        
        if factory and IsAlive(factory) then
            for i=1, DiffUtils.ScaleEnemy(3) do local h = BuildObject("svtank", 2, "factory_attack"); Attack(h, factory, 1) end
            for i=1, DiffUtils.ScaleEnemy(2) do local h = BuildObject("svfigh", 2, "factory_attack"); Attack(h, factory, 1) end
        end
    end
    
    -- Factory Spawn
    if GetTime() > factory_spawn_time then
        factory_spawn_time = 99999.0
        factory = BuildObject("cvmufa", 1, "factory")
        Goto(factory, "factory_path", 1)
        AddScrap(1, 100)
        armoury = BuildObject("cvslfa", 1, "factory")
        Goto(armoury, "factory_path", 1)
    end
    
    -- Failure: General APC Escapes
    if general and IsAlive(general) and GetTeamNum(general) == 2 then
        if (general_spawn_time + 120.0) < GetTime() and GetDistance(general, "base_fail") < 50.0 and not lost then
            lost = true
            sound9 = AudioMessage("ch03009.wav")
        end
    end
    
    if sound9 and IsAudioMessageDone(sound9) then
        sound9 = nil
        FailMission(GetTime() + 1.0, "ch03lsed.des")
    end
    
    -- Failure: Assets Dead
    if general and not IsAlive(general) and not won and not lost then
        lost = true
        lose1_sound = AudioMessage("ch03008.wav")
    end
    if lose1_sound and IsAudioMessageDone(lose1_sound) then
        lose1_sound = nil
        FailMission(GetTime() + 1.0, "ch03lsec.des")
    end
    
    if factory and not IsAlive(factory) and not won and not lost then
        lost = true
        FailMission(GetTime() + 1.0, "ch03lsee.des")
    end
    
    -- Win
    if objective2_complete and not won and not lost then
        if GetDistance(general, "won_mission") < 30.0 then
            won = true
            SucceedMission(GetTime() + 1.0, "ch03win.des")
        end
    end
end
