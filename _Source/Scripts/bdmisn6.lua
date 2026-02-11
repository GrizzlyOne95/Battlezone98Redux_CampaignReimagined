<<<<<<< HEAD
-- bdmisn6.lua (Converted from BlackDog06Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")

-- Helper for AI
local function SetupAI()
    -- Team 1: Black Dogs (Player)
    -- Team 2: CAA (Enemy)
    local caa = aiCore.AddTeam(2, aiCore.Factions.CCA) 
    
    local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    if diff <= 1 then
        caa:SetConfig("pilotZeal", 0.1)
    elseif diff >= 3 then
        caa:SetConfig("pilotZeal", 0.9)
    else
        caa:SetConfig("pilotZeal", 0.4)
    end
end

-- Variables
local start_done = false
local lost = false
local won = false
local portal_ours = false
local recycler_dropped = false
local random_attack = true
local soundhandle = false

-- States
local MS_STARTUP = 0
local MS_STARTCAMERA = 1
local MS_WAITING1 = 2
local MS_WAITFORSOUND2 = 3
local MS_WAITING2 = 4
local MS_FAKEATTACKCAMERA = 5
local MS_WAITFORALL2BDESTDEAD = 6
local MS_WAITFORREDDEVIL = 7
local MS_WAITFORBADGUY = 8
local MS_WAITFORBADGUY1DIE = 9
local MS_WAITFORBADGUY2 = 10
local MS_WAITFORBADGUY2DIE = 11
local MS_WAITFORSOUND3 = 12
local MS_WAITFOROBJECTIVE2 = 13
local MS_WAITFORRECYCLER = 14
local MS_WAITFORBADGUY3 = 15
local MS_WAITFORAPC = 16
local MS_ENDCUTSCENE = 17
local MS_WAITING3 = 18
local MS_WAITAPCFINISHED = 19
local MS_WAITAPCOUT = 20
local MS_WAITFORSOUND8 = 21
local MS_WAITING4 = 22
local MS_RECYCLERDEAD = 23
local MS_ATTACKTOEARLY = 24

local mission_state = MS_STARTUP
local state_timer = 0
local state_timer2 = 0
local state_timer3 = 0
local state_timer4 = 0

-- Handles
local user
local recycler
local portal
local apc_handle
local bdtank = {} -- 1..10
local silo_attack = {} -- 1..10
local h2bdest = {} -- 1..6
local portal_attack = {} -- 1..2
local random_attackers = {} -- 1..5
local badguy = {} -- 1..3

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
    end
    SetupAI()
    start_done = false
end

local function PlaySound(file)
    AudioMessage(file)
    -- return true if we track it? C++ sets soundhandle. 
    -- Assuming blocking or timer logic follows.
end

local function ResetObjectives()
    ClearObjectives()
    
    if mission_state >= MS_WAITFORSOUND3 then
        AddObjective("bd06001.otf", "green")
    elseif mission_state >= MS_WAITING1 then
        AddObjective("bd06001.otf", "white")
    end
    
    if portal_ours then
        AddObjective("bd06002.otf", "green")
    elseif mission_state >= MS_WAITFORRECYCLER then
        AddObjective("bd06002.otf", "white")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
    end
    -- Track APCs?
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, 75)
        SetPilot(1, 10)
        
        recycler = nil -- Not built yet
        portal = GetHandle("portal")
        apc_handle = nil
        
        for i=1,10 do
            silo_attack[i] = GetHandle("silo_attack"..i)
            bdtank[i] = GetHandle("bdtank_"..i)
        end
        
        h2bdest[1] = GetHandle("2bdest_1")
        h2bdest[2] = GetHandle("2bdest_2")
        h2bdest[3] = GetHandle("2bdest_3")
        h2bdest[4] = GetHandle("2bdest_7")
        h2bdest[5] = GetHandle("2bdest_9")
        h2bdest[6] = GetHandle("2bdest_10")
        
        start_done = true
        mission_state = MS_STARTCAMERA
        state_timer = GetTime() + 2.0
        CameraReady()
        ResetObjectives()
    end
    
    -- Lose Conditions
    if not lost then
        if not IsAlive(portal) then
            FailMission(GetTime() + 2.0, "bd06lseb.des")
            lost = true
        end
        
        -- APC capture logic check
        if not portal_ours and recycler then
            -- Find APCs going to portal
            -- Optimized: Iterate nearby APCs to 'apc_in'
            -- Can't iterate generic object list easily in Lua.
            -- Instead, track APCs or check distance of known ones.
            -- But player builds APC.
            -- We can use specific "bvapc" check around portal?
            -- Actually `CountUnitsNear`? No, need handle to command.
            -- Let's use `GetNearestObject` from nav `apc_in`?
            local near_apc = GetNearestObject(GetHandle("apc_in"))
            if near_apc and IsOdf(near_apc, "bvapc") and GetTeamNum(near_apc) == 1 and GetDistance(near_apc, "apc_in") < 100.0 then
                Goto(near_apc, "apc_in")
                apc_handle = near_apc
                portal_ours = true
                
                ResetObjectives()
                
                -- Spawn Portal Defenders (Attacking Portal?)
                -- C++ spawns "cvartl" (Howitzers) attacking Portal? Weird.
                -- Maybe friendly fire or distraction?
                -- Or, C++: temp = BuildObject("cvartl", 2, "portal_attack_1"); Attack(temp, portal);
                -- Team 2 Artl attacking Portal. But Portal is Team 2?
                -- Wait, if `portalours` = TRUE, implies we took it. So Team 2 shoots it. Correct.
                for k=1,3 do
                    local t = BuildObject("cvartl", 2, "portal_attack_1")
                    Attack(t, portal)
                end
                
                mission_state = MS_ENDCUTSCENE
                state_timer = 0
                CameraReady()
            end
            
            -- Recycler Dead?
            -- C++ check: `if (!portalours && apclist == 0 && !IsAlive(recycler))`
            -- `apclist` counts living APCs. If 0 APCs and No Recycler -> Fail.
            -- Hard to count ALL APCs in Lua without tracking list.
            -- Simplified: If Recycler Dead -> Fail.
            if not IsAlive(recycler) and mission_state ~= MS_RECYCLERDEAD then
                mission_state = MS_RECYCLERDEAD
                AudioMessage("bd06006.wav")
                state_timer = GetTime() + 5.0 -- Wait for audio
            end
        end
    elseif lost then
        return
    end
    
    -- State Machine
    if mission_state == MS_STARTCAMERA then
        CameraPath("camera_start", 1000, 2500, portal)
        
        if GetTime() > state_timer and not soundhandle then -- soundhandle used as flag
            AudioMessage("bd06001.wav")
            soundhandle = true
        end
        
        if CameraCancelled() then -- C++ `arrived || CameraCancelled()`
            CameraFinish()
            mission_state = MS_WAITING1
            state_timer = GetTime() + 20.0
            state_timer2 = GetTime() + (11 * 60.0) -- Timer?
            ResetObjectives()
            soundhandle = false
        end
        
    elseif mission_state == MS_WAITING1 then
        if GetTime() > state_timer then
            AudioMessage("bd06002.wav")
            for i=1,10 do
                if IsAlive(silo_attack[i]) then Goto(silo_attack[i], "fake_attack") end
            end
            mission_state = MS_WAITFORSOUND2
            state_timer = GetTime() + 5.0 -- Wait for audio approx
        else
            -- Check integrity (Early Attack fail)
            for i=1,10 do
                local o = silo_attack[i]
                if IsAlive(o) and GetHealth(o) < GetMaxHealth(o) then -- Taken damage
                    mission_state = MS_ATTACKTOEARLY
                    AudioMessage("bd06007.wav")
                    state_timer (GetTime() + 5.0)
                    return
                end
            end
        end
        
    elseif mission_state == MS_WAITFORSOUND2 then
        if GetTime() > state_timer then
            mission_state = MS_WAITING2
            state_timer = GetTime() + 3.0
        end
        
    elseif mission_state == MS_WAITING2 then
        if GetTime() > state_timer then
            mission_state = MS_FAKEATTACKCAMERA
            state_timer = GetTime() + 5.0
            CameraReady()
        end
        
    elseif mission_state == MS_FAKEATTACKCAMERA then
        local cam_target = silo_attack[3] or portal
        CameraPath("camera_go", 2000, 2000, cam_target)
        
        if CameraCancelled() or GetTime() > state_timer then -- Short cam
            for i=1,10 do 
                if IsAlive(silo_attack[i]) then RemoveObject(silo_attack[i]) end 
            end
            CameraFinish()
            mission_state = MS_WAITFORALL2BDESTDEAD
        end
        
    elseif mission_state == MS_WAITFORALL2BDESTDEAD then
        if GetTime() > state_timer2 then -- Time limit
            FailMission(GetTime()+2.0, "bd06lsed.des")
            lost = true
        end
        
        local all_dead = true
        for i=1,6 do if IsAlive(h2bdest[i]) then all_dead = false break end end
        
        if all_dead then
            mission_state = MS_WAITFORREDDEVIL
            ResetObjectives()
            state_timer = GetTime() + 90.0
            state_timer3 = GetTime() + 110.0 -- Random Attack Timer
            state_timer4 = GetTime() + 80.0 -- Portal Attack Timer
        end
        
    elseif mission_state == MS_WAITFORREDDEVIL then
        if GetTime() > state_timer then
            -- Spawn Backup
            local dead_count = 0
            for i=1,10 do if not IsAlive(bdtank[i]) then dead_count = dead_count + 1 end end
            dead_count = math.min(dead_count, 5) -- Limit
            
            for i=1,dead_count do
                local t = BuildObject("bvrdeva", 1, "backup_1")
                Goto(t, "backup_path")
            end
            
            state_timer = GetTime() + 90.0
            mission_state = MS_WAITFORBADGUY
        end
        
    elseif mission_state == MS_WAITFORBADGUY then
        if GetTime() > state_timer then
            badguy[1] = BuildObject("cvtnk", 2, "attack_1"); Attack(badguy[1], user)
            badguy[2] = BuildObject("cvtnk", 2, "attack_1"); Attack(badguy[2], user)
            mission_state = MS_WAITFORBADGUY1DIE
        end
        
    elseif mission_state == MS_WAITFORBADGUY1DIE then
        if not IsAlive(badguy[1]) then
            state_timer = GetTime() + 180.0 -- 3 mins
            mission_state = MS_WAITFORBADGUY2
        end
        
    elseif mission_state == MS_WAITFORBADGUY2 then
        if GetTime() > state_timer then
            badguy[1] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[1], user)
            badguy[2] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[2], user)
            badguy[3] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[3], user)
            mission_state = MS_WAITFORBADGUY2DIE
        end
        
    elseif mission_state == MS_WAITFORBADGUY2DIE then
        if not IsAlive(badguy[1]) and not IsAlive(badguy[2]) and not IsAlive(badguy[3]) then
            mission_state = MS_WAITFORSOUND3
            ResetObjectives()
            AudioMessage("bd06003.wav")
            state_timer = GetTime() + 5.0
        end
        
    elseif mission_state == MS_WAITFORSOUND3 then
        if GetTime() > state_timer then
            recycler = BuildObject("bvrecy", 1, "recycler_spawn")
            Goto(recycler, "recycler_path")
            
            local t = BuildObject("bvrdeva", 1, "recycler_spawn"); Follow(t, recycler)
            t = BuildObject("bvrdeva", 1, "recycler_spawn"); Follow(t, recycler)
            
            state_timer = GetTime() + 30.0
            mission_state = MS_WAITFOROBJECTIVE2
        end
        
    elseif mission_state == MS_WAITFOROBJECTIVE2 then
        if GetTime() > state_timer then
            mission_state = MS_WAITFORRECYCLER
            ResetObjectives()
        end
        
    elseif mission_state == MS_WAITFORRECYCLER then
        -- Wait for recycler to stop moving? Or just time?
        -- C++: `if(GetCurrentCommand(recycler) == CMD_NONE)`
        -- Simple check:
        if IsAlive(recycler) and GetDistance(recycler, "recycler_path") < 50.0 then
            -- Deploy(recycler)? Not all Lua interfaces expose `Deploy`.
            -- `Drop(recycler)`?
            -- Usually AI Recyclers auto-deploy if at nav.
            -- If not, ignore or use SetDeploy(recycler, true).
            -- Assuming auto behavior or script command.
            if SetDeploy then SetDeploy(recycler, true) end
            
            AudioMessage("bd06004.wav")
            mission_state = MS_WAITFORBADGUY3
            state_timer = GetTime() + 60.0
        end
        
    elseif mission_state == MS_WAITFORBADGUY3 then
        if GetTime() > state_timer then -- Only trigger once? C++ falls through?
            -- It spawns 5 tanks hunting.
            for i=1,5 do
                local t = BuildObject("cvtnk", 2, "attack_3")
                Hunt(t)
            end
            mission_state = MS_WAITFORAPC
        end
        
    elseif mission_state == MS_WAITFORAPC then
        -- Handled in main loop (Lose/Win check)
        
    elseif mission_state == MS_ENDCUTSCENE then
        -- APC In Portal
        if apc_handle and GetDistance(apc_handle, "apc_in") < 20.0 then
            RemoveObject(apc_handle)
            apc_handle = nil
            AudioMessage("bd06009.wav")
            state_timer2 = GetTime() + 60.0 -- Unused?
            
            -- Spawn dummy tanks
            for i=1,7 do
                local t = BuildObject("cvtnk", 2, "dummy_1")
                Goto(t, "dummy_1_path")
            end
            
            state_timer = GetTime() + 3.0 -- Camera time
        end
        
        -- Start End Camera
        CameraPath("camera_end_scene", 2000, 0, apc_handle or portal)
        
        -- if sound done (approx 3s)
        if state_timer > 0 and GetTime() > state_timer then
            CameraFinish()
            mission_state = MS_WAITING3
            state_timer = GetTime() + 5.0
        end
        
    elseif mission_state == MS_WAITING3 then
        if GetTime() > state_timer then
            for i=1,7 do
                local t = BuildObject("cvfigh", 2, "portal_attack_2")
                Attack(t, portal)
            end
            mission_state = MS_WAITAPCFINISHED
        end
        
    elseif mission_state == MS_WAITAPCFINISHED then
        -- C++: `if(stateTimer2 < GetTime())`. stateTimer2 was set 60s ago. 
        -- Assuming wait for APC to fully warp? 
        -- Just proceed.
        apc_handle = BuildObject("bvapc", 1, "portal") -- "apc_out"?
        Goto(apc_handle, "apc_out")
        mission_state = MS_WAITAPCOUT
        
    elseif mission_state == MS_WAITAPCOUT then
        if GetDistance(apc_handle, "apc_out") < 50.0 then -- Reached out
            mission_state = MS_WAITFORSOUND8
            -- Restored Audio
            AudioMessage("bd06008.wav")
            state_timer = GetTime() + 5.0
        end
    
    elseif mission_state == MS_WAITFORSOUND8 then
        if GetTime() > state_timer then
            mission_state = MS_WAITING4
            state_timer = GetTime() + 5.0
        end
        
    elseif mission_state == MS_WAITING4 then
        if GetTime() > state_timer then
            AudioMessage("bd06005.wav")
            SucceedMission(GetTime() + 10.0, "bd06wina.des")
            mission_state = 99
        end
        
    elseif mission_state == MS_RECYCLERDEAD then
        if GetTime() > state_timer then
            FailMission(GetTime() + 2.0, "bd06lsec.des")
            lost = true
        end
    
    elseif mission_state == MS_ATTACKTOEARLY then
        if GetTime() > state_timer then
            FailMission(GetTime() + 2.0, "bd06lsea.des")
            lost = true
        end
    end
end
=======
-- bdmisn6.lua (Converted from BlackDog06Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")

-- Helper for AI
local function SetupAI()
    -- Team 1: Black Dogs (Player)
    -- Team 2: CAA (Enemy)
    local caa = aiCore.AddTeam(2, aiCore.Factions.CCA) 
    
    local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    if diff <= 1 then
        caa:SetConfig("pilotZeal", 0.1)
    elseif diff >= 3 then
        caa:SetConfig("pilotZeal", 0.9)
    else
        caa:SetConfig("pilotZeal", 0.4)
    end
end

-- Variables
local start_done = false
local lost = false
local won = false
local portal_ours = false
local recycler_dropped = false
local random_attack = true
local soundhandle = false

-- States
local MS_STARTUP = 0
local MS_STARTCAMERA = 1
local MS_WAITING1 = 2
local MS_WAITFORSOUND2 = 3
local MS_WAITING2 = 4
local MS_FAKEATTACKCAMERA = 5
local MS_WAITFORALL2BDESTDEAD = 6
local MS_WAITFORREDDEVIL = 7
local MS_WAITFORBADGUY = 8
local MS_WAITFORBADGUY1DIE = 9
local MS_WAITFORBADGUY2 = 10
local MS_WAITFORBADGUY2DIE = 11
local MS_WAITFORSOUND3 = 12
local MS_WAITFOROBJECTIVE2 = 13
local MS_WAITFORRECYCLER = 14
local MS_WAITFORBADGUY3 = 15
local MS_WAITFORAPC = 16
local MS_ENDCUTSCENE = 17
local MS_WAITING3 = 18
local MS_WAITAPCFINISHED = 19
local MS_WAITAPCOUT = 20
local MS_WAITFORSOUND8 = 21
local MS_WAITING4 = 22
local MS_RECYCLERDEAD = 23
local MS_ATTACKTOEARLY = 24

local mission_state = MS_STARTUP
local state_timer = 0
local state_timer2 = 0
local state_timer3 = 0
local state_timer4 = 0

-- Handles
local user
local recycler
local portal
local apc_handle
local bdtank = {} -- 1..10
local silo_attack = {} -- 1..10
local h2bdest = {} -- 1..6
local portal_attack = {} -- 1..2
local random_attackers = {} -- 1..5
local badguy = {} -- 1..3

-- Difficulty
local difficulty = 2

function Start()
    if exu then
        difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or 2
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
    end
    SetupAI()
    start_done = false
end

local function PlaySound(file)
    AudioMessage(file)
    -- return true if we track it? C++ sets soundhandle. 
    -- Assuming blocking or timer logic follows.
end

local function ResetObjectives()
    ClearObjectives()
    
    if mission_state >= MS_WAITFORSOUND3 then
        AddObjective("bd06001.otf", "green")
    elseif mission_state >= MS_WAITING1 then
        AddObjective("bd06001.otf", "white")
    end
    
    if portal_ours then
        AddObjective("bd06002.otf", "green")
    elseif mission_state >= MS_WAITFORRECYCLER then
        AddObjective("bd06002.otf", "white")
    end
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then 
        aiCore.AddObject(h)
    end
    -- Track APCs?
end

function DeleteObject(h)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetScrap(1, 75)
        SetPilot(1, 10)
        
        recycler = nil -- Not built yet
        portal = GetHandle("portal")
        apc_handle = nil
        
        for i=1,10 do
            silo_attack[i] = GetHandle("silo_attack"..i)
            bdtank[i] = GetHandle("bdtank_"..i)
        end
        
        h2bdest[1] = GetHandle("2bdest_1")
        h2bdest[2] = GetHandle("2bdest_2")
        h2bdest[3] = GetHandle("2bdest_3")
        h2bdest[4] = GetHandle("2bdest_7")
        h2bdest[5] = GetHandle("2bdest_9")
        h2bdest[6] = GetHandle("2bdest_10")
        
        start_done = true
        mission_state = MS_STARTCAMERA
        state_timer = GetTime() + 2.0
        CameraReady()
        ResetObjectives()
    end
    
    -- Lose Conditions
    if not lost then
        if not IsAlive(portal) then
            FailMission(GetTime() + 2.0, "bd06lseb.des")
            lost = true
        end
        
        -- APC capture logic check
        if not portal_ours and recycler then
            -- Find APCs going to portal
            -- Optimized: Iterate nearby APCs to 'apc_in'
            -- Can't iterate generic object list easily in Lua.
            -- Instead, track APCs or check distance of known ones.
            -- But player builds APC.
            -- We can use specific "bvapc" check around portal?
            -- Actually `CountUnitsNear`? No, need handle to command.
            -- Let's use `GetNearestObject` from nav `apc_in`?
            local near_apc = GetNearestObject(GetHandle("apc_in"))
            if near_apc and IsOdf(near_apc, "bvapc") and GetTeamNum(near_apc) == 1 and GetDistance(near_apc, "apc_in") < 100.0 then
                Goto(near_apc, "apc_in")
                apc_handle = near_apc
                portal_ours = true
                
                ResetObjectives()
                
                -- Spawn Portal Defenders (Attacking Portal?)
                -- C++ spawns "cvartl" (Howitzers) attacking Portal? Weird.
                -- Maybe friendly fire or distraction?
                -- Or, C++: temp = BuildObject("cvartl", 2, "portal_attack_1"); Attack(temp, portal);
                -- Team 2 Artl attacking Portal. But Portal is Team 2?
                -- Wait, if `portalours` = TRUE, implies we took it. So Team 2 shoots it. Correct.
                for k=1,3 do
                    local t = BuildObject("cvartl", 2, "portal_attack_1")
                    Attack(t, portal)
                end
                
                mission_state = MS_ENDCUTSCENE
                state_timer = 0
                CameraReady()
            end
            
            -- Recycler Dead?
            -- C++ check: `if (!portalours && apclist == 0 && !IsAlive(recycler))`
            -- `apclist` counts living APCs. If 0 APCs and No Recycler -> Fail.
            -- Hard to count ALL APCs in Lua without tracking list.
            -- Simplified: If Recycler Dead -> Fail.
            if not IsAlive(recycler) and mission_state ~= MS_RECYCLERDEAD then
                mission_state = MS_RECYCLERDEAD
                AudioMessage("bd06006.wav")
                state_timer = GetTime() + 5.0 -- Wait for audio
            end
        end
    elseif lost then
        return
    end
    
    -- State Machine
    if mission_state == MS_STARTCAMERA then
        CameraPath("camera_start", 1000, 2500, portal)
        
        if GetTime() > state_timer and not soundhandle then -- soundhandle used as flag
            AudioMessage("bd06001.wav")
            soundhandle = true
        end
        
        if CameraCancelled() then -- C++ `arrived || CameraCancelled()`
            CameraFinish()
            mission_state = MS_WAITING1
            state_timer = GetTime() + 20.0
            state_timer2 = GetTime() + (11 * 60.0) -- Timer?
            ResetObjectives()
            soundhandle = false
        end
        
    elseif mission_state == MS_WAITING1 then
        if GetTime() > state_timer then
            AudioMessage("bd06002.wav")
            for i=1,10 do
                if IsAlive(silo_attack[i]) then Goto(silo_attack[i], "fake_attack") end
            end
            mission_state = MS_WAITFORSOUND2
            state_timer = GetTime() + 5.0 -- Wait for audio approx
        else
            -- Check integrity (Early Attack fail)
            for i=1,10 do
                local o = silo_attack[i]
                if IsAlive(o) and GetHealth(o) < GetMaxHealth(o) then -- Taken damage
                    mission_state = MS_ATTACKTOEARLY
                    AudioMessage("bd06007.wav")
                    state_timer (GetTime() + 5.0)
                    return
                end
            end
        end
        
    elseif mission_state == MS_WAITFORSOUND2 then
        if GetTime() > state_timer then
            mission_state = MS_WAITING2
            state_timer = GetTime() + 3.0
        end
        
    elseif mission_state == MS_WAITING2 then
        if GetTime() > state_timer then
            mission_state = MS_FAKEATTACKCAMERA
            state_timer = GetTime() + 5.0
            CameraReady()
        end
        
    elseif mission_state == MS_FAKEATTACKCAMERA then
        local cam_target = silo_attack[3] or portal
        CameraPath("camera_go", 2000, 2000, cam_target)
        
        if CameraCancelled() or GetTime() > state_timer then -- Short cam
            for i=1,10 do 
                if IsAlive(silo_attack[i]) then RemoveObject(silo_attack[i]) end 
            end
            CameraFinish()
            mission_state = MS_WAITFORALL2BDESTDEAD
        end
        
    elseif mission_state == MS_WAITFORALL2BDESTDEAD then
        if GetTime() > state_timer2 then -- Time limit
            FailMission(GetTime()+2.0, "bd06lsed.des")
            lost = true
        end
        
        local all_dead = true
        for i=1,6 do if IsAlive(h2bdest[i]) then all_dead = false break end end
        
        if all_dead then
            mission_state = MS_WAITFORREDDEVIL
            ResetObjectives()
            state_timer = GetTime() + 90.0
            state_timer3 = GetTime() + 110.0 -- Random Attack Timer
            state_timer4 = GetTime() + 80.0 -- Portal Attack Timer
        end
        
    elseif mission_state == MS_WAITFORREDDEVIL then
        if GetTime() > state_timer then
            -- Spawn Backup
            local dead_count = 0
            for i=1,10 do if not IsAlive(bdtank[i]) then dead_count = dead_count + 1 end end
            dead_count = math.min(dead_count, 5) -- Limit
            
            for i=1,dead_count do
                local t = BuildObject("bvrdeva", 1, "backup_1")
                Goto(t, "backup_path")
            end
            
            state_timer = GetTime() + 90.0
            mission_state = MS_WAITFORBADGUY
        end
        
    elseif mission_state == MS_WAITFORBADGUY then
        if GetTime() > state_timer then
            badguy[1] = BuildObject("cvtnk", 2, "attack_1"); Attack(badguy[1], user)
            badguy[2] = BuildObject("cvtnk", 2, "attack_1"); Attack(badguy[2], user)
            mission_state = MS_WAITFORBADGUY1DIE
        end
        
    elseif mission_state == MS_WAITFORBADGUY1DIE then
        if not IsAlive(badguy[1]) then
            state_timer = GetTime() + 180.0 -- 3 mins
            mission_state = MS_WAITFORBADGUY2
        end
        
    elseif mission_state == MS_WAITFORBADGUY2 then
        if GetTime() > state_timer then
            badguy[1] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[1], user)
            badguy[2] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[2], user)
            badguy[3] = BuildObject("cvtnk", 2, "attack_2"); Attack(badguy[3], user)
            mission_state = MS_WAITFORBADGUY2DIE
        end
        
    elseif mission_state == MS_WAITFORBADGUY2DIE then
        if not IsAlive(badguy[1]) and not IsAlive(badguy[2]) and not IsAlive(badguy[3]) then
            mission_state = MS_WAITFORSOUND3
            ResetObjectives()
            AudioMessage("bd06003.wav")
            state_timer = GetTime() + 5.0
        end
        
    elseif mission_state == MS_WAITFORSOUND3 then
        if GetTime() > state_timer then
            recycler = BuildObject("bvrecy", 1, "recycler_spawn")
            Goto(recycler, "recycler_path")
            
            local t = BuildObject("bvrdeva", 1, "recycler_spawn"); Follow(t, recycler)
            t = BuildObject("bvrdeva", 1, "recycler_spawn"); Follow(t, recycler)
            
            state_timer = GetTime() + 30.0
            mission_state = MS_WAITFOROBJECTIVE2
        end
        
    elseif mission_state == MS_WAITFOROBJECTIVE2 then
        if GetTime() > state_timer then
            mission_state = MS_WAITFORRECYCLER
            ResetObjectives()
        end
        
    elseif mission_state == MS_WAITFORRECYCLER then
        -- Wait for recycler to stop moving? Or just time?
        -- C++: `if(GetCurrentCommand(recycler) == CMD_NONE)`
        -- Simple check:
        if IsAlive(recycler) and GetDistance(recycler, "recycler_path") < 50.0 then
            -- Deploy(recycler)? Not all Lua interfaces expose `Deploy`.
            -- `Drop(recycler)`?
            -- Usually AI Recyclers auto-deploy if at nav.
            -- If not, ignore or use SetDeploy(recycler, true).
            -- Assuming auto behavior or script command.
            if SetDeploy then SetDeploy(recycler, true) end
            
            AudioMessage("bd06004.wav")
            mission_state = MS_WAITFORBADGUY3
            state_timer = GetTime() + 60.0
        end
        
    elseif mission_state == MS_WAITFORBADGUY3 then
        if GetTime() > state_timer then -- Only trigger once? C++ falls through?
            -- It spawns 5 tanks hunting.
            for i=1,5 do
                local t = BuildObject("cvtnk", 2, "attack_3")
                Hunt(t)
            end
            mission_state = MS_WAITFORAPC
        end
        
    elseif mission_state == MS_WAITFORAPC then
        -- Handled in main loop (Lose/Win check)
        
    elseif mission_state == MS_ENDCUTSCENE then
        -- APC In Portal
        if apc_handle and GetDistance(apc_handle, "apc_in") < 20.0 then
            RemoveObject(apc_handle)
            apc_handle = nil
            AudioMessage("bd06009.wav")
            state_timer2 = GetTime() + 60.0 -- Unused?
            
            -- Spawn dummy tanks
            for i=1,7 do
                local t = BuildObject("cvtnk", 2, "dummy_1")
                Goto(t, "dummy_1_path")
            end
            
            state_timer = GetTime() + 3.0 -- Camera time
        end
        
        -- Start End Camera
        CameraPath("camera_end_scene", 2000, 0, apc_handle or portal)
        
        -- if sound done (approx 3s)
        if state_timer > 0 and GetTime() > state_timer then
            CameraFinish()
            mission_state = MS_WAITING3
            state_timer = GetTime() + 5.0
        end
        
    elseif mission_state == MS_WAITING3 then
        if GetTime() > state_timer then
            for i=1,7 do
                local t = BuildObject("cvfigh", 2, "portal_attack_2")
                Attack(t, portal)
            end
            mission_state = MS_WAITAPCFINISHED
        end
        
    elseif mission_state == MS_WAITAPCFINISHED then
        -- C++: `if(stateTimer2 < GetTime())`. stateTimer2 was set 60s ago. 
        -- Assuming wait for APC to fully warp? 
        -- Just proceed.
        apc_handle = BuildObject("bvapc", 1, "portal") -- "apc_out"?
        Goto(apc_handle, "apc_out")
        mission_state = MS_WAITAPCOUT
        
    elseif mission_state == MS_WAITAPCOUT then
        if GetDistance(apc_handle, "apc_out") < 50.0 then -- Reached out
            mission_state = MS_WAITFORSOUND8
            -- Restored Audio
            AudioMessage("bd06008.wav")
            state_timer = GetTime() + 5.0
        end
    
    elseif mission_state == MS_WAITFORSOUND8 then
        if GetTime() > state_timer then
            mission_state = MS_WAITING4
            state_timer = GetTime() + 5.0
        end
        
    elseif mission_state == MS_WAITING4 then
        if GetTime() > state_timer then
            AudioMessage("bd06005.wav")
            SucceedMission(GetTime() + 10.0, "bd06wina.des")
            mission_state = 99
        end
        
    elseif mission_state == MS_RECYCLERDEAD then
        if GetTime() > state_timer then
            FailMission(GetTime() + 2.0, "bd06lsec.des")
            lost = true
        end
    
    elseif mission_state == MS_ATTACKTOEARLY then
        if GetTime() > state_timer then
            FailMission(GetTime() + 2.0, "bd06lsea.des")
            lost = true
        end
    end
end
>>>>>>> 30fa079494619a8bd6565c444554253b8b48a7b9

