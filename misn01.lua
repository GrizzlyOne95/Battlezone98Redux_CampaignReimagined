-- misn01mission.lua
-- Converted from misn01mission.cpp

-- Compatibility for 1.5 vs Redux naming
SetLabel = SetLabel or SettLabel

-- Global Variables (State)
local start_done = false
local hop_in = false
local first_objective = false
local second_objective = false
local third_objecitve = false
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

local get_in_me = nil
local target = nil
local target2 = nil

local aud = nil
local num_reps = 0
local on_point = 0

-- Path names (Constants)
local p1 = "path_1"
local p2 = "path_2"
local p3 = "path_3"
local p4 = "path_5"

-- Save function: Returns values to be saved
function Save()
    return start_done, hop_in, first_objective, second_objective, third_objecitve, 
           combat_start, combat_start2, start_path1, start_path2, start_path3, 
           start_path4, hint1, hint2, done_message, jump_start, lost,
           repeat_time, forgiveness, jump_done,
           get_in_me, target, target2,
           aud, num_reps, on_point
end

-- Load function: Restores values from save
function Load(...)
    local arg = {...}
    if #arg > 0 then
        start_done, hop_in, first_objective, second_objective, third_objecitve, 
        combat_start, combat_start2, start_path1, start_path2, start_path3, 
        start_path4, hint1, hint2, done_message, jump_start, lost,
        repeat_time, forgiveness, jump_done,
        get_in_me, target, target2,
        aud, num_reps, on_point = unpack(arg)
    end
end

-- Start function: Called once when mission starts
function Start()
    -- Initialization logic is handled in Update to ensure handles are valid
end

-- Update function: Called every frame
function Update()
    local player = GetPlayerHandle()
    
    -- Initialization
    if not start_done then
        get_in_me = GetHandle("avfigh0_wingman")
        aud = AudioMessage("misn0101.wav")
        target = GetHandle("svturr0_turrettank")
        target2 = GetHandle("svturr1_turrettank")
        start_done = true
        repeat_time = GetTime() + 30.0
        ClearObjectives()
        AddObjective("misn0101.otf", "white")
        AddObjective("misn0103.otf", "white")
        num_reps = 0
    end

    -- Repeat instructions logic
    if not start_path1 and GetTime() > repeat_time then
        repeat_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn0101.otf", "green")
        -- aud = AudioMessage("misn0101.wav") -- Commented out in original CPP
        num_reps = num_reps + 1
    end

    -- Check start of Path 1
    if not start_path1 then
        -- how far are we from the start..
        local start_pos = GetPosition(p1, 0)
        if start_pos and GetDistance(player, start_pos) < forgiveness then
            -- we've started
            if player ~= get_in_me and not hop_in then
                hop_in = true
                if aud then StopAudioMessage(aud) end
                AudioMessage("misn0122.wav")
            else
                ClearObjectives()
                AddObjective("misn0101.otf", "green")
                AddObjective("misn0103.otf", "white")
            end
            StartCockpitTimerUp(0, 300, 240)
            repeat_time = 0.0
            num_reps = 0
            start_path1 = true
            on_point = 0
        end
    end

    -- Path 1 Logic
    if start_path1 and not start_path2 and player == get_in_me then
        -- are we out of range of current point?
        local current_pt = GetPosition(p1, on_point)
        if current_pt then
            local dist = GetDistance(player, current_pt)
            
            if dist > forgiveness and GetTime() > repeat_time then
                -- tell player to get back where he was before
                AudioMessage("misn0103.wav")
                if not IsAlive(target) and not IsAlive(target2) and not lost then
                    lost = true
                    FailMission(GetTime() + 5.0, "misn01l1.des")
                end
                repeat_time = GetTime() + 15.0
                num_reps = num_reps + 1
            end
            
            local next_pt = GetPosition(p1, on_point + 1)
            if next_pt then
                local dist2 = GetDistance(player, next_pt)
                if dist2 < dist then
                    -- time to switch where we are on the path
                    on_point = on_point + 1
                    -- Check if we reached the end (next point doesn't exist)
                    if not GetPosition(p1, on_point + 1) then
                        start_path2 = true
                        on_point = 0
                    end
                end
            end
        end
    end

    -- Path 2 Logic
    if start_path2 and not start_path3 then
        -- are we out of range of current point?
        local current_pt = GetPosition(p2, on_point)
        if current_pt then
            local dist = GetDistance(player, current_pt)
            
            if dist > forgiveness and GetTime() > repeat_time then
                -- tell player to get back where he was before
                AudioMessage("misn0103.wav")
                if not IsAlive(target) and not IsAlive(target2) and not lost then
                    lost = true
                    FailMission(GetTime() + 5.0, "misn01l1.des")
                end
                repeat_time = GetTime() + 15.0
                num_reps = num_reps + 1
            end
            
            local next_pt = GetPosition(p2, on_point + 1)
            if next_pt then
                local dist2 = GetDistance(player, next_pt)
                if dist2 < dist then
                    -- time to switch where we are on the path
                    on_point = on_point + 1
                    if not GetPosition(p2, on_point + 1) then
                        start_path3 = true
                        AudioMessage("misn0104.wav")
                        on_point = 0
                    end
                end
            end
        end
    end

    -- Path 3 Logic
    if start_path3 and not jump_start then
        -- are we out of range of current point?
        local current_pt = GetPosition(p3, on_point)
        if current_pt then
            local dist = GetDistance(player, current_pt)
            
            if dist > forgiveness and GetTime() > repeat_time then
                -- tell player to get back where he was before
                AudioMessage("misn0103.wav")
                if not IsAlive(target) and not IsAlive(target2) and not lost then
                    lost = true
                    FailMission(GetTime() + 5.0, "misn01l1.des")
                end
                repeat_time = GetTime() + 15.0
                num_reps = num_reps + 1
            end
            
            local next_pt = GetPosition(p3, on_point + 1)
            if next_pt then
                local dist2 = GetDistance(player, next_pt)
                if dist2 < dist then
                    -- time to switch where we are on the path
                    on_point = on_point + 1
                    if not GetPosition(p3, on_point + 1) then
                        jump_start = true
                        jump_done = GetTime() + 8.0
                    end
                end
            end
        end
    end

    -- Jump Hint
    if jump_start and not hint1 and GetTime() > jump_done then
        repeat_time = GetTime() + 45.0  -- grace period to continue
        AudioMessage("misn0105.wav")
        forgiveness = forgiveness * 1.5  -- for the jumps you'll need it
        AudioMessage("misn0107.wav")
        hint1 = true
    end

    -- Check start of Path 4 (p4)
    if not start_path4 then
        -- how far are we from the start..
        local start_pos = GetPosition(p4, 0)
        if start_pos and GetDistance(player, start_pos) < forgiveness then
            -- we've started
            repeat_time = 0.0
            num_reps = 0
            start_path4 = true
            on_point = 0
            -- In case the player is developmentally disabled.
            if player ~= get_in_me then
                AudioMessage("misn0122.wav")
            end
        end
    end

    -- Path 4 Logic
    if start_path4 and not combat_start then
        -- are we out of range of current point?
        local current_pt = GetPosition(p4, on_point)
        if current_pt then
            local dist = GetDistance(player, current_pt)
            
            if dist > forgiveness and GetTime() > repeat_time then
                -- tell player to get back where he was before
                AudioMessage("misn0108.wav")
                repeat_time = GetTime() + 15.0
                num_reps = num_reps + 1
            end
            
            local next_pt = GetPosition(p4, on_point + 1)
            if next_pt then
                local dist2 = GetDistance(player, next_pt)
                if dist2 < dist then
                    -- time to switch where we are on the path
                    on_point = on_point + 1
                    if not GetPosition(p4, on_point + 1) then
                        StopCockpitTimer()
                        combat_start = true
                        local second_obj = target -- Handle is safe to use
                        SetObjectiveOn(second_obj)
                        SetObjectiveName(second_obj, "Combat Training")
                        AudioMessage("misn0109.wav")
                    end
                end
            end
        end
    end

    -- Combat Hint
    if combat_start and not hint2 and IsAlive(target) then
        -- Dist3D_Squared < 100*100 is equivalent to Distance < 100
        if GetDistance(target, player) < 100.0 then
            HideCockpitTimer()
            AudioMessage("misn0111.wav")
            hint2 = true
        end
    end

    -- Combat Start 2
    if not combat_start2 and not IsAlive(target) and IsAlive(target2) then
        local second_obj = target2
        SetObjectiveOn(second_obj)
        SetObjectiveName(second_obj, "Combat Training 2")
        AudioMessage("misn0113.wav")
        combat_start2 = true
    end

    -- Win Condition
    if not done_message and not IsAlive(target) and not IsAlive(target2) then
        AudioMessage("misn0121.wav")
        done_message = true
        SucceedMission(GetTime() + 10.0, "misn01w1.des")
    end

    -- Fail Condition (Too many reps)
    if num_reps > 4 and not lost then
        repeat_time = 99999.0
        ClearObjectives()
        AddObjective("misn0102.otf", "red")
        AudioMessage("misn0123.wav")
        FailMission(GetTime() + 10.0, "misn01l1.des")
        num_reps = 0
        lost = true
    end
end
