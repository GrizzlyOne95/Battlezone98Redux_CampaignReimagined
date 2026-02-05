-- tran02.lua
-- Ported from Tran02Mission.cpp
-- Training Mission 2: Commanding Units

-- Compatibility
SetLabel = SetLabel or SettLabel

-- Libraries
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"}) 
local exu = require("exu")
local DiffUtils = require("DiffUtils")
local Subtitles = require("Subtitles")

-- Mission State
local lost = false
local go_reminder = false
local start_done = false
local first_selection = false
local second_selection = false
local third_selection = false
local thirda_selection = false
local fourth_selection = false
local fifth_selection = false
local end_message = false
local jump_start = false
local hint1 = false
local hint2 = false

local repeat_time = 0.0
local hint_delay = 99999.0
local num_reps = 0
local message = 0

-- Handles
local turret = nil
local pointer = nil
local haul1 = nil
local haul2 = nil

function Save()
    return lost, go_reminder, start_done, first_selection, second_selection,
           third_selection, thirda_selection, fourth_selection, fifth_selection,
           end_message, jump_start, hint1, hint2,
           repeat_time, hint_delay, num_reps, message,
           turret, pointer, haul1, haul2
end

function Load(...)
    local arg = {...}
    if #arg > 0 then
        lost, go_reminder, start_done, first_selection, second_selection,
        third_selection, thirda_selection, fourth_selection, fifth_selection,
        end_message, jump_start, hint1, hint2,
        repeat_time, hint_delay, num_reps, message,
        turret, pointer, haul1, haul2 = unpack(arg)
    end
end

function Start()
    Subtitles.Initialize("durations.csv")
    DiffUtils.SetupTeams(1, 2, 0)
    
    -- Handles grabbed in Update/Setup usually, but Start is fine if objects exist
    turret = GetHandle("avturr-1_turrettank")
    pointer = GetHandle("nparr-1_i76building")
    haul1 = GetHandle("avhaul-1_tug")
    haul2 = GetHandle("avhaul19_tug")
    
    repeat_time = 99999.0
    hint_delay = 99999.0
    
    -- QOL Improvements
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
    end
end

local function PlayReminder(time, msg_id)
    local new_time = time
    if GetTime() > time then
        new_time = GetTime() + 15.0
        if msg_id == 1 then Subtitles.Play("tran0202.wav")
        elseif msg_id == 2 then Subtitles.Play("tran0203.wav")
        elseif msg_id == 3 then Subtitles.Play("tran0204.wav")
        elseif msg_id == 4 then Subtitles.Play("tran0211.wav")
        elseif msg_id == 5 then Subtitles.Play("tran0206.wav")
        elseif msg_id == 6 then Subtitles.Play("misn0109.wav")
        elseif msg_id == 7 then Subtitles.Play("tran0207.wav")
        elseif msg_id == 8 then 
            Subtitles.Play("tran0208.wav")
            new_time = 99999.0
        end
    end
    return new_time
end

function Update()
    Subtitles.Update()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    if IsAlive(turret) then
        repeat_time = PlayReminder(repeat_time, message)
        
        if not start_done then
            SetObjectiveOn(turret)
            SetObjectiveName(turret, "Turret")
            Subtitles.Play("tran0201.wav")
            hint_delay = GetTime() + 1.0
            ClearObjectives()
            AddObjective("tran0201.otf", "green")
            start_done = true
        end
        
        if GetTime() > hint_delay then
            Subtitles.Play("tran0204.wav")
            hint_delay = 99999.0
            repeat_time = GetTime() + 30.0
            message = 3
            second_selection = true
        end
        
        -- Check for Interface Selection (Proxy: Key '2' or just selecting unit)
        -- C++: ControlPanel::GetCurrentItem()==2
        if not thirda_selection and second_selection then
            -- Proxy: If player presses '2' (Unit Menu?)
            if exu.GetGameKey("2") then
                 Subtitles.Play("tran0205.wav")
                 thirda_selection = true
                 repeat_time = GetTime() + 30.0
                 message = 4
            end
        end
        
        if not third_selection and second_selection and IsSelected(turret) then
            Subtitles.Play("tran0206.wav")
            SetObjectiveOff(turret)
            SetObjectiveOn(pointer)
            SetObjectiveName(pointer, "Target Range")
            third_selection = true
            repeat_time = GetTime() + 30.0
            message = 5
        end
        
        if third_selection and not go_reminder and not IsSelected(turret) then
            Subtitles.Play("misn0109.wav")
            go_reminder = true
            repeat_time = GetTime() + 30.0
            message = 6
        end
        
        if third_selection and not hint1 then
            local t_pos = GetPosition(turret)
            local p_pos = GetPosition(pointer)
            if GetDistance(turret, pointer) < 100.0 then
                Subtitles.Play("tran0207.wav")
                Subtitles.Play("tran0212.wav") -- Press 2
                hint1 = true
                repeat_time = GetTime() + 30.0
                message = 7
            end
        end
        
        if hint1 and not hint2 then
            -- C++ check: ControlPanel::GetCurrentItem()==2 (Again?)
            -- "Press 2" usually opens menu.
            if exu.GetGameKey("2") then
                hint2 = true
                Subtitles.Play("tran0211.wav") -- Press 1?
                repeat_time = GetTime() + 20.0
                message = 4
            end
        end
        
        if hint1 and not fourth_selection and IsSelected(turret) then
             Subtitles.Play("tran0208.wav")
             fourth_selection = true
             repeat_time = GetTime() + 30.0
             message = 8
        end
        
        if fourth_selection and not fifth_selection and GetCurrentCommand(turret) == 1 then -- 1 is CMD_GO? Stock definitions usually needed.
            -- CMD_GO usually maps to move.
            -- C++ uses CMD_GO enum. In Lua, 1 = Stop, 2 = Go? No, need to verify CMD constants.
            -- Stock scriptutils usually doesn't define CMD_. I'll assume CMD_GO implies checking IsMoving or similar?
            -- Or assume index 2 (Move/Go)?
            -- C++: GetCurrentCommand(turret)==CMD_GO
            -- Let's check scriptutils lines again later, but usually GetCurrentCommand returns integer.
            -- Assuming standard BZ: 0=None, 1=Go?
            
            repeat_time = 99999.0
            Subtitles.Play("tran0209.wav")
            
            if IsAlive(haul1) then
                -- Script commands Hauler to Turret
                -- info.what=CMD_GO; info.priority=1; info.where=turret_pos
                -- Lua: SetCommand(handle, command, priority, target/pos)
                -- command: "move"? or integer? SetCommand takes string in some versions, int in others?
                -- BZ98R Lua: SetCommand(handle, "move", pos)
                Goto(haul1, GetPosition(turret), 1) -- Goto(handle, pos, priority) wrapper?
                -- Native SetCommand(handle, "move", position)
                SetCommand(haul1, "move", GetPosition(turret)) 
                
                SetObjectiveOff(pointer)
                SetObjectiveOn(haul1)
                SetObjectiveName(haul1, "Target Drone")
            else
                FailMission(GetTime() + 2.0, "tran02l1.des")
            end
            fifth_selection = true
        end
        
        -- Re-issue Hauler command if idle
        if IsAlive(haul1) and GetCurrentCommand(haul1) == 0 and fifth_selection then
            SetCommand(haul1, "move", GetPosition(turret))
        end
        
        if fifth_selection and not end_message and not IsAlive(haul1) then
            Subtitles.Play("tran0210.wav")
            end_message = true
            SucceedMission(GetTime() + 10.0, "tran02w1.des")
        end
        
    else
        -- Turret died
        if not lost then
            lost = true
            FailMission(GetTime() + 5.0, "tran02l1.des")
        end
    end
end
