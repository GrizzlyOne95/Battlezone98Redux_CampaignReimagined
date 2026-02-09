-- tran04.lua
-- Ported from Tran04Mission.cpp
-- Training Mission 4: Advanced Command (Factory, Camera, Wingman)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- Libraries
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"}) 
local exu = require("exu")
local DiffUtils = require("DiffUtils")
local Subtitles = require("ScriptSubtitles")

-- Mission State
local found1 = false -- Factory
local found2 = false -- Wingman
local start_done = false
local message1 = false
local message2 = false
local message3 = false
local message4 = false
local message5 = false
local message6 = false
local message7 = false
local message8 = false
local message9 = false
local message10 = false
local message11 = false
local message12 = false
local message13 = false
local message14 = false
local message15 = false
local message16 = false -- Fail/Win flag
local press7 = false
local attacked = false

local repeat_time = 0.0
local camera_delay = 99999.0

-- Handles
local player = nil
local target1 = nil
local target2 = nil
local recycler = nil
local muf = nil -- Factory
local camera = nil
local wing = nil -- Wingman

function Save()
    return found1, found2, start_done, message1, message2, message3, message4,
           message5, message6, message7, message8, message9, message10,
           message11, message12, message13, message14, message15, message16,
           press7, attacked,
           repeat_time, camera_delay,
           player, target1, target2, recycler, muf, camera, wing
end

function Load(...)
    local arg = {...}
    if #arg > 0 then
        found1, found2, start_done, message1, message2, message3, message4,
        message5, message6, message7, message8, message9, message10,
        message11, message12, message13, message14, message15, message16,
        press7, attacked,
        repeat_time, camera_delay,
        player, target1, target2, recycler, muf, camera, wing = unpack(arg)
    end
end

function Start()
    Subtitles.Initialize("durations.csv")
    DiffUtils.SetupTeams(1, 2, 0)
    
    target1 = GetHandle("avturr12_turrettank")
    target2 = GetHandle("avturr-1_turrettank")
    recycler = GetHandle("avrecy-1_recycler")
    camera = GetHandle("apcamr-1_camerapod")
    player = GetHandle("player-1_hover")
    
    camera_delay = 99999.0
    
    -- QOL Improvements
    if exu then
        if exu.EnableShotConvergence then exu.EnableShotConvergence() end
        if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end
    end
end

function AddObject(h)
    local odf = GetOdf(h)
    if odf then 
        odf = string.lower(odf) 
        odf = string.gsub(odf, "%z", "") -- Null strip
    end
    
    if GetTeamNum(h) == 1 and odf then
        if string.find(odf, "avmuf") then
            found1 = true
            muf = h
        elseif string.find(odf, "avfigh") then
            found2 = true
            wing = h
        end
    end
end

function Update()
    Subtitles.Update()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    if not start_done then
        -- Handles Safety
        target1 = target1 or GetHandle("avturr12_turrettank")
        target2 = target2 or GetHandle("avturr-1_turrettank")
        recycler = recycler or GetHandle("avrecy-1_recycler")
        camera = camera or GetHandle("apcamr-1_camerapod")
        player = player or GetHandle("player-1_hover")
        
        SetScrap(1, 30)
        Subtitles.Play("tran0401.wav")
        Subtitles.Play("tran0402.wav")
        Subtitles.Play("tran0424.wav") -- Select Recycler
        
        ClearObjectives()
        AddObjective("tran0401.otf", "white")
        
        start_done = true
        
        -- Dynamic Difficulty: Buff Targets on Hard+
        local diff = DiffUtils.Get().index
        if diff >= 3 then -- Hard or Very Hard
            if IsAlive(target1) then AddHealth(target1, 1000) end
            if IsAlive(target2) then AddHealth(target2, 1000) end
        end
    end
    
    if not message1 and IsAlive(recycler) and IsSelected(recycler) then
        Subtitles.Play("tran0425.wav") -- "Good"
        message1 = true
    end
    
    if message1 and not message2 and IsAlive(recycler) then
        if IsDeployed(recycler) then
            Subtitles.Play("tran0424.wav") -- Select Recycler again (if deselected?) 
            -- or maybe "Ready to build"
            message2 = true
        end
    end
    
    -- RESTORED FACTORY LOGIC START
    if message2 and IsAlive(recycler) and IsSelected(recycler) and not press7 then
        -- Restore cut content: Prompt to build factory
        Subtitles.Play("tran0403.wav") -- "Press 7..."
        press7 = true
        -- message6 = true -- In C++ this skipped the factory logic. We DON'T set message6 yet.
    end
    
    if message2 and not message3 and press7 then
        local money = GetScrap(1)
        if money < 30 and found1 then
            -- Initial check: Player spent money and we found a factory
            muf = muf or GetHandle("avmuf") -- Fallback if AddObject missed it
            if IsAlive(muf) then
                Subtitles.Play("tran0404.wav")
                Subtitles.Play("tran0405.wav")
                message3 = true
            else
                -- Built wrong thing? 
                -- FailMission(GetTime() + 10.0, "tran04l1.des")
                -- We'll just wait.
            end
        end
    end
    
    if message3 and not message4 and IsAlive(muf) and IsSelected(muf) then
        Subtitles.Play("tran0423.wav")
        message4 = true
    end
    
    if message4 and not message5 and IsAlive(muf) then
        if IsDeployed(muf) then
            -- Subtitles.Play("tran0405.wav") -- repeated in C++?
            message5 = true
        end
    end
    
    if message5 and not message6 and IsSelected(muf) then
        Subtitles.Play("tran0406.wav") -- "Now selects..."
        message6 = true
    end
    -- RESTORED FACTORY LOGIC END
    
    if message6 and not message7 and IsAlive(recycler) and not IsSelected(recycler) then
        -- C++ Logic: (!IsSelected(recycler)) was a check for "was muf selected" context switch?
        -- Logic seems to be: Move on to Camera Training
        Subtitles.Play("tran0407.wav") -- "Find Camera Pod"
        camera_delay = GetTime() + 5.0
        message7 = true
    end
    
    if message7 and not message8 and GetTime() > camera_delay then
        Subtitles.Play("tran0408.wav") -- "Select Camera Pod"
        camera_delay = 99999.0
    end
    
    if message7 and not message8 and GetUserTarget() == camera then
        Subtitles.Play("tran0409.wav") -- "Good"
        message8 = true
        camera_delay = GetTime() + 3.0
    end
    
    if message8 and not message9 and GetTime() > camera_delay and found2 then
        Subtitles.Play("tran0410.wav") -- "Build a scout" (Wait, found2 is scout)
        -- Actually "tran0410" might be "Select the scout".
        message9 = true
        camera_delay = 99999.0
    end
    
    if message8 and not IsAlive(wing) and not message16 and not found2 then
        -- If died before we even selected it?
        -- Actually C++: Fail if !IsAlive(wing).
        -- We won't fail instantly if not built yet.
        -- But once found2 is true, wing should be set.
    end
    
    if message9 and not message10 and IsAlive(wing) and IsSelected(wing) then
        Subtitles.Play("tran0411.wav") -- "Send to attack"
        message10 = true
    end
    
    if message10 and not message11 and IsAlive(wing) and not IsSelected(wing) and camera_delay == 99999.0 then
        -- Deselected wingman logic?
        camera_delay = GetTime() + 10.0
    end
    
    if message10 and not message11 and GetTime() > camera_delay then
        Subtitles.Play("tran0412.wav") -- Reminder
        camera_delay = 99999.0
    end
    
    if message10 and not attacked and IsAlive(wing) then
        -- C++: GetLastEnemyShot() > 0.
        -- Lua: HasLastEnemyShot? No.
        -- We'll check if wingman has a command "attack"
        if GetCurrentCommand(wing) == 3 then -- CMD_ATTACK? No standard definition.
            -- Proxy: IsFiring? Or just ignore confirmation.
            -- Let's just assume if command is attack.
            -- Native `GetCurrentCommand` returns int.
            -- We'll use Subtitles.Play("tran0413") "Good attack"
        end
        -- Simpler: Check if target1 health drops?
        if GetHealth(target1) < GetMaxHealth(target1) then
            Subtitles.Play("tran0413.wav")
            attacked = true
        end
    end
    
    if not IsAlive(target1) and not message12 then
        Subtitles.Play("tran0415.wav") -- "Target 1 destroyed"
        if IsAlive(target2) then
            SetObjectiveOn(target2)
            SetObjectiveName(target2, "Drone 2")
        end
        message12 = true
    end
    
    if message12 and GetDistance(player, target2) < 300.0 and not message13 then
        Subtitles.Play("tran0416.wav")
        message13 = true
        Subtitles.Play("tran0418.wav")
        -- message13 = true (Double set in C++)
    end
    
    if message13 and GetUserTarget() == target2 and not message14 then
        Subtitles.Play("tran0410.wav") -- "Select it"?
        message14 = true
    end
    
    if message14 and not message15 and IsAlive(wing) and IsSelected(wing) then
         Subtitles.Play("tran0420.wav")
         message15 = true
    end
    
    if message6 and not IsAlive(target1) and not IsAlive(target2) and not message16 then
        Subtitles.Play("tran0421.wav")
        SucceedMission(GetTime() + 10.0, "tran04w1.des")
        message16 = true
    end
    
    if not message16 and ( (not message6 and not IsAlive(recycler)) or (not IsAlive(target1) and not IsAlive(target2) and not message6) ) then
        -- If destroyed targets before instructions?
        -- Actually check fail condition: Logic says if not message6 (tutorial not done) and targets dead -> fail.
        -- Also check recycler death.
        -- FailMission(GetTime() + 5.0, "tran04l1.des")
        -- message16 = true
    end
end
