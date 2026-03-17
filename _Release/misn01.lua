-- misn01.lua
-- Ported from Misn01Mission.cpp
-- Training Mission 1

-- Compatibility
SetLabel = SetLabel or SetLabel

-- Libraries
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"}) -- Adjust ID as needed
local exu = require("exu")
local DiffUtils = require("DiffUtils")
local Subtitles = require("ScriptSubtitles")

-- Mission State
local start_done = false
local hop_in = false
local first_objective = false -- Unused in C++?
local second_objective = false -- Unused in C++?
local third_objecitve = false -- Unused in C++?
local combat_start = false
local combat_start2 = false
local start_path1 = false
local start_path2 = false
local start_path3 = false
local start_path4 = false
local hint1 = false
local hint2 = false
local done_message = false
local jump_start = false
local lost = false

local repeat_time = 0.0
local forgiveness = 40.0
local jump_done = 0.0
local num_reps = 0
local max_reps = 4 -- Default
local on_point = 0

-- Handles
local get_in_me = nil
local target = nil
local target2 = nil
local aud = nil -- Audio handle

-- Save/Load
function Save()
    return start_done, hop_in, combat_start, combat_start2,
           start_path1, start_path2, start_path3, start_path4,
           hint1, hint2, done_message, jump_start, lost,
           repeat_time, forgiveness, jump_done, num_reps, on_point,
           get_in_me, target, target2, aud
end

function Load(...)
    local arg = {...}
    if #arg > 0 then
        start_done, hop_in, combat_start, combat_start2,
        start_path1, start_path2, start_path3, start_path4,
        hint1, hint2, done_message, jump_start, lost,
        repeat_time, forgiveness, jump_done, num_reps, on_point,
        get_in_me, target, target2, aud = unpack(arg)
    end
end

function Start()
    -- Initialize Subtitles with duration file if available
    Subtitles.Initialize("durations.csv")
    
    -- Setup teams
    DiffUtils.SetupTeams(1, 2, 0) 
    
    -- QOL Improvements
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
    end
    
    -- Dynamic Difficulty
    local diff_idx = DiffUtils.Get().index -- 0 to 4
    -- Forgiveness: E(60), N(50), H(40), VH(30)
    forgiveness = 60.0 - (diff_idx * 7.5) 
    if forgiveness < 30.0 then forgiveness = 30.0 end
    
    -- Max Reps: E(8), N(5), H(3), VH(2)
    -- Default was 4 in C++ (actually test was >4, so 5 fails)
    local max_reps_table = {8, 6, 5, 3, 2}
    max_reps = max_reps_table[diff_idx + 1] or 4
end

function Update()
    Subtitles.Update()

    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    local player = GetPlayerHandle()
    local player_pos = GetPosition(player)
    
    if not start_done then
        start_done = true
        
        get_in_me = GetHandle("avfigh0_wingman")
        aud = Subtitles.Play("misn0101.wav")
        target = GetHandle("svturr0_turrettank")
        target2 = GetHandle("svturr1_turrettank")
        
        repeat_time = GetTime() + 30.0
        ClearObjectives()
        AddObjective("misn0101.otf", "white")
        AddObjective("misn0103.otf", "white")
        num_reps = 0
    end
    
    -- Repeated Opening Msg
    if not start_path1 and GetTime() > repeat_time then
        repeat_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn0101.otf", "green")
        num_reps = num_reps + 1
        -- C++ had this commented out: aud=AudioMessage("misn0101.wav");
    end
    
    -- Path 1 Start Logic
    if not start_path1 then
        local p1_start = GetPosition("path_1", 0) -- Point 0
        local dist = GetDistance(player, "path_1", 0)
        
        if dist < forgiveness then
            -- Started
            if player ~= get_in_me and not hop_in then
                hop_in = true
                if aud then StopAudioMessage(aud) end
                aud = Subtitles.Play("misn0122.wav")
            else
                ClearObjectives()
                AddObjective("misn0101.otf", "green")
                AddObjective("misn0103.otf", "white")
            end
            
            StartCockpitTimerUp(0, 300, 240)
            repeat_time = 0.0
            num_reps = 0
            start_path1 = true
            on_point = 0 -- Lua 0-indexed or 1-indexed for points? 
                         -- GetPosition(path, point) uses 0-based index in C++ usually.
                         -- In BZ Redux Lua, GetPosition(path, point) point is 0-indexed usually?
                         -- Let's assume 0-indexed consistent with C++ source.
        end
    end
    
    -- Path 1 Following
    if start_path1 and not start_path2 and player == get_in_me then
        -- Check distance to current point
        -- In C++: p1->points[on_point]
        local current_pt_dist = GetDistance(player, "path_1", on_point)
        
        if current_pt_dist > forgiveness and GetTime() > repeat_time then
            Subtitles.Play("misn0103.wav")
            
            if not IsAlive(target) and not IsAlive(target2) and not lost then
                lost = true
                FailMission(GetTime() + 5.0, "misn01l1.des")
            end
            repeat_time = GetTime() + 15.0
            num_reps = num_reps + 1
        end
        
        -- Check if closer to next point
        -- C++: p1->points[on_point+1]
        -- Note: We need to know max points to avoid error? 
        -- GetPosition returns nil if point invalid?
        local next_pt_dist = GetDistance(player, "path_1", on_point + 1)
        
        if next_pt_dist < current_pt_dist then
            on_point = on_point + 1
            
            -- Check if end of path. 
            -- Instead of checking pointCount (hard to get in Lua without iterating),
            -- checking if next+1 exists or if we reached a known count?
            -- C++ logic: on_point == p1->pointCount-1.
            -- This implies on_point is now the LAST index.
            -- Let's check if there is a point after this one.
            if GetPosition("path_1", on_point + 1) == nil then
               start_path2 = true
               on_point = 0 
            end
        end
    end
    
    -- Path 2 Following
    if start_path2 and not start_path3 then
        local current_pt_dist = GetDistance(player, "path_2", on_point)
        
        if current_pt_dist > forgiveness and GetTime() > repeat_time then
            Subtitles.Play("misn0103.wav")
             if not IsAlive(target) and not IsAlive(target2) and not lost then
                lost = true
                FailMission(GetTime() + 5.0, "misn01l1.des")
            end
            repeat_time = GetTime() + 15.0
            num_reps = num_reps + 1
        end
        
        local next_pt_dist = GetDistance(player, "path_2", on_point + 1)
        if next_pt_dist < current_pt_dist then
            on_point = on_point + 1
            if GetPosition("path_2", on_point + 1) == nil then
                start_path3 = true
                Subtitles.Play("misn0104.wav")
                on_point = 0
            end
        end
    end
    
    -- Path 3 Following
    if start_path3 and not jump_start then
       local current_pt_dist = GetDistance(player, "path_3", on_point)
        
        if current_pt_dist > forgiveness and GetTime() > repeat_time then
            Subtitles.Play("misn0103.wav")
             if not IsAlive(target) and not IsAlive(target2) and not lost then
                lost = true
                FailMission(GetTime() + 5.0, "misn01l1.des")
            end
            repeat_time = GetTime() + 15.0
            num_reps = num_reps + 1
        end
        
        local next_pt_dist = GetDistance(player, "path_3", on_point + 1)
        if next_pt_dist < current_pt_dist then
            on_point = on_point + 1
            if GetPosition("path_3", on_point + 1) == nil then
                jump_start = true
                jump_done = GetTime() + 8.0
            end
        end 
    end
    
    -- Jump Logic
    if jump_start and not hint1 and GetTime() > jump_done then
        repeat_time = GetTime() + 45.0
        Subtitles.Play("misn0105.wav")
        forgiveness = forgiveness * 1.5 -- Increased for jumps
        Subtitles.Play("misn0107.wav")
        hint1 = true
    end
    
    -- Path 4 Start
    if not start_path4 and hint1 then -- Logic inferred: assumes transition to path 4 check after hint1?
                                   -- C++ code specifically checks `if (!start_path4)` separately. 
                                   -- But it relies on `p4` being checked.
                                   -- If we are at this stage, we should be looking for p4 start interactions.
        local dist = GetDistance(player, "path_5", 0) -- C++ uses "path_5" for p4 variable
        if dist < forgiveness then
            repeat_time = 0.0
            num_reps = 0
            start_path4 = true
            on_point = 0
            
            -- "Rude" check
            if player ~= get_in_me then
                Subtitles.Play("misn0122.wav")
            end
        end
    end
    
    -- Path 4 Following
    if start_path4 and not combat_start then
       local current_pt_dist = GetDistance(player, "path_5", on_point)
        
        if current_pt_dist > forgiveness and GetTime() > repeat_time then
            Subtitles.Play("misn0108.wav")
            repeat_time = GetTime() + 15.0
            num_reps = num_reps + 1
        end
        
        local next_pt_dist = GetDistance(player, "path_5", on_point + 1)
        if next_pt_dist < current_pt_dist then
            on_point = on_point + 1
            if GetPosition("path_5", on_point + 1) == nil then
                StopCockpitTimer()
                combat_start = true
                if IsAlive(target) then
                    SetObjectiveOn(target)
                    SetObjectiveName(target, "Combat Training")
                end
                Subtitles.Play("misn0109.wav")
            end
        end 
    end
    
    -- Combat Logic
    if combat_start and not hint2 and IsAlive(target) then
        -- C++: Dist3D_Squared(first->GetPosition(), player->GetPosition()) < 100.0f * 100.0f
        -- "first" is target (svturr0)
        local dist = GetDistance(target, player)
        if dist < 100.0 then
            HideCockpitTimer()
            Subtitles.Play("misn0111.wav")
            hint2 = true
        end
    end
    
    if not combat_start2 and not IsAlive(target) and IsAlive(target2) then
        SetObjectiveOn(target2)
        SetObjectiveName(target2, "Combat Training 2")
        Subtitles.Play("misn0113.wav")
        combat_start2 = true
    end
    
    -- Win Condition
    if not done_message and not IsAlive(target) and not IsAlive(target2) then
        Subtitles.Play("misn0121.wav")
        done_message = true
        SucceedMission(GetTime() + 10.0, "misn01w1.des")
    end
    
    -- Loss Condition (Too many reps)
    if num_reps > max_reps and not lost then
        repeat_time = 99999.0
        ClearObjectives()
        AddObjective("misn0102.otf", "red")
        Subtitles.Play("misn0123.wav")
        FailMission(GetTime() + 10.0, "misn01l1.des")
        num_reps = 0 -- prevent re-trigger?
        lost = true
    end
end

