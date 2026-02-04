-- tran05.lua
-- Converted from Tran05Mission.cpp

-- Compatibility for 1.5 vs Redux naming
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")

-- Global Variables (State)
local camera1 = false
local camera2 = false
local camera3 = false
local found = false
local found2 = false
local start_done = false
local patrol1 = false
local message1 = false
local message2 = false
local message3 = false
local message4 = false
local message5 = false
local mission_won = false
local mission_lost = false

local wave_timer = 0.0
local last_wave_time = 99999.0
local cam_time = 0.0
local NextSecond = 99999.0

local bscav = nil
local bscout = nil
local scav2 = nil
local audmsg = nil

-- Handles that are looked up
local dummy = nil
local lander = nil
local bhandle = nil
local bhome = nil
local recycler = nil
local bgoal = nil
local bhandle2 = nil

-- Save function: Returns values to be saved
function Save()
    return camera1, camera2, camera3, found, found2, start_done, patrol1,
           message1, message2, message3, message4, message5, mission_won, mission_lost,
           wave_timer, last_wave_time, cam_time, NextSecond,
           bscav, bscout, scav2, audmsg,
           dummy, lander, bhandle, bhome, recycler, bgoal, bhandle2
end

-- Load function: Restores values from save
function Load(...)
    local arg = {...}
    if #arg > 0 then
        camera1, camera2, camera3, found, found2, start_done, patrol1,
        message1, message2, message3, message4, message5, mission_won, mission_lost,
        wave_timer, last_wave_time, cam_time, NextSecond,
        bscav, bscout, scav2, audmsg,
        dummy, lander, bhandle, bhome, recycler, bgoal, bhandle2 = unpack(arg)
    end
end

-- AddObject function: Called when a game object is added
function AddObject(h)
    local team = GetTeamNum(h)
    local odf = GetOdf(h)

    -- Apply turbo to new enemy units on Very Hard difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team == 1 then
            exu.SetUnitTurbo(h, true)
        elseif team ~= 0 then
            local diff = (exu.GetDifficulty and exu.GetDifficulty()) or 2
            if diff > 3 then
                exu.SetUnitTurbo(h, true)
            end
        end
    end

    if team == 1 and odf == "avscav" and bscav == nil then
        found = true
        bscav = h
        SetCritical(bscav, true)
        SetObjectiveOn(bscav)
    end

    if team == 2 and odf == "svfigh" then
        if not found2 then
            found2 = true
            bscout = h
            Goto(bscout, "patrol1")
            SetObjectiveOn(bscout)
        else
            if IsAlive(bscav) and IsAlive(bgoal) and GetDistance(bscav, bgoal) < 200.0 then
                Attack(h, bscav)
            else
                Goto(h, "patrol2")
            end
        end
    end
end

-- Update function: Called every frame
function Update()
    local player = GetPlayerHandle()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    if not start_done then
        if exu then
            local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
            print("EXU Version: " .. tostring(ver))
            local diff = (exu.GetDifficulty and exu.GetDifficulty()) or 2
            print("Difficulty: " .. tostring(diff))

            if diff >= 3 then
                AddObjective("hard_diff", "red", 8.0, "High Difficulty: Enemy presence intensified.")
            elseif diff <= 1 then
                AddObjective("easy_diff", "green", 8.0, "Low Difficulty: Enemy presence reduced.")
            end

            -- Apply turbo to existing units
            if exu.SetUnitTurbo then
                for h in AllCraft() do
                    if GetTeamNum(h) == 1 then
                        exu.SetUnitTurbo(h, true)
                    elseif GetTeamNum(h) ~= 0 and diff > 3 then
                        exu.SetUnitTurbo(h, true)
                    end
                end
            end

            if exu.EnableShotConvergence then exu.EnableShotConvergence() end
            if exu.SetSmartCursorRange then exu.SetSmartCursorRange(500) end -- Extended targeting range
            if exu.EnableOrdnanceTweak then exu.EnableOrdnanceTweak(1.0) end -- Projectiles inherit velocity
            if exu.SetSelectNone then exu.SetSelectNone(false) end -- Modern selection (don't deselect on move)
        end

        SetPilot(1, 2)
        SetScrap(1, 5)
        SetAIP("misn02.aip")
        
        dummy = GetHandle("fake_player")
        lander = GetHandle("avland0_wingman")
        bhandle = GetHandle("sscr_171_scrap")
        bhome = GetHandle("abcomm1_i76building")
        recycler = GetHandle("avrecy-1_recycler")
        bgoal = GetHandle("apscrap-1_camerapod")
        bhandle2 = GetHandle("sscr_176_scrap")
        
        SetUserTarget(bgoal)
        SetObjectiveName(bgoal, "Scrap Field Alpha")
        start_done = true
        camera1 = true
        cam_time = GetTime() + 30.0
        CameraReady()
        --audmsg = AudioMessage("misn0230.wav")
        audmsg = AudioMessage("misn0201.wav")
    end

    -- Camera Logic
    if camera1 then
        if CameraPath("fixcam", 1200, 250, lander) or CameraCancelled() or IsAudioMessageDone(audmsg) then
            camera1 = false
            cam_time = GetTime() + 10.0
            camera2 = true
        end
    end

    if camera2 then
        camera2 = false
        camera3 = true
        if IsAlive(dummy) then
            Goto(dummy, "player_path")
        end
        cam_time = GetTime() + 25.0
    end

    if camera3 then
        if CameraPath("zoomcam", 1200, 800, dummy) or IsAudioMessageDone(audmsg) or CameraCancelled() then
            camera3 = false
            cam_time = 99999.0
            CameraFinish()
            if IsAlive(dummy) then RemoveObject(dummy) end
            SetPosition(player, "playermove")
            StopAudioMessage(audmsg)
            audmsg = nil
            AudioMessage("misn0224.wav")
            wave_timer = GetTime() + 30.0
            AddObjective("misn02b1.otf", "white")
        end
    end

    -- Patrol 1 Logic
    if not patrol1 and found and IsAlive(bhandle) and IsAlive(bscav) and GetDistance(bhandle, bscav) < 75.0 then
        BuildObject("svfigh", 2, "spawn1")

        if exu and exu.GetDifficulty and exu.GetDifficulty() >= 3 then
            BuildObject("svfigh", 2, "spawn1")
        end

        AudioMessage("misn0233.wav")
        message1 = true
        patrol1 = true
        
        if not message4 and found2 then
            message4 = true
        end
    end

    if not message4 and found2 then
        message4 = true
    end

    -- Wave Logic
    if message4 and not message5 and IsAlive(bscav) and IsAlive(bhandle2) and GetDistance(bscav, bhandle2) < 200.0 then
        BuildObject("svfigh", 2, "spawn2")
        message5 = true
        wave_timer = GetTime() + 30.0
    end

    if message5 and not message3 and GetTime() > wave_timer then
        BuildObject("svfigh", 2, "spawn2")
        
        local delay = 45.0
        if exu then
            local diff = exu.GetDifficulty()
            if diff <= 1 then delay = 60.0
            elseif diff >= 3 then delay = 30.0 end
        end
        wave_timer = GetTime() + delay
    end

    -- Retreat Logic
    if message1 and message5 and not message2 and IsAlive(bscav) and GetLastEnemyShot(bscav) > 0 then
        Follow(bscav, bhome)
        ClearObjectives()
        AddObjective("misn02b2.otf", "white")
        AudioMessage("misn0225.wav")
        local bbase = GetHandle("apbase-1_camerapod")
        SetUserTarget(bbase)
        message2 = true
    end

    -- Loss Condition
    if bscav ~= nil and not mission_lost then
        if not IsAlive(player) or not IsAlive(bscav) or (message3 and not IsAlive(scav2)) or not IsAlive(bhome) or not IsAlive(recycler) then
            ClearObjectives()
            AddObjective("misn02b4.otf", "red")
            audmsg = AudioMessage("misn0227.wav")
            mission_lost = true
        end
    end

    if mission_lost and IsAudioMessageDone(audmsg) then
        FailMission(GetTime(), "misn02l1.des")
    end

    -- Rescue Logic
    if IsAlive(player) and message1 and message4 and IsAlive(bhome) and IsAlive(bscav) and GetDistance(bhome, bscav) < 300.0 and not message3 then
        Follow(bscav, bhome)
        wave_timer = GetTime() + 45.0
        scav2 = BuildObject("avscav", 1, "spawn3")
        SetCritical(scav2, true)
        Retreat(scav2, "retreat")
        SetObjectiveOn(scav2)
        SetObjectiveOff(bscav)
        AudioMessage("misn0228.wav")
        last_wave_time = GetTime() + 10.0
        NextSecond = GetTime() + 1.0
        message3 = true
    end

    -- Health Regen
    if IsAlive(bscav) and message3 and GetTime() > NextSecond then
        AddHealth(bscav, 200.0)
        NextSecond = GetTime() + 1.0
    end

    -- Final Wave
    if last_wave_time < GetTime() then
        local sid = BuildObject("svfigh", 2, "spawn4")
        if IsAlive(scav2) then
            Attack(sid, scav2)
        end

        if exu and exu.GetDifficulty() >= 3 then
            local sid2 = BuildObject("svfigh", 2, "spawn4")
            if IsAlive(scav2) then
                Attack(sid2, scav2)
            end
        end
        last_wave_time = 99999.0
    end

    -- Win Condition
    if message3 and not mission_won and IsAlive(bhome) and IsAlive(scav2) and GetDistance(bhome, scav2) < 200.0 then
        ClearObjectives()
        SetObjectiveOff(scav2)
        if IsAlive(bscav) then SetObjectiveOff(bscav) end
        AddObjective("misn02b3.otf", "green")
        if IsAlive(bscav) then AddHealth(bscav, 1000.0) end
        if IsAlive(scav2) then AddHealth(scav2, 1000.0) end
        audmsg = AudioMessage("misn0234.wav")
        mission_won = true
    end

    if mission_won and IsAudioMessageDone(audmsg) then
        SucceedMission(GetTime(), "misn02w1.des")
    end
end
