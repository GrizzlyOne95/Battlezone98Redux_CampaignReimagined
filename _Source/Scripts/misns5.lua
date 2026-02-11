-- Misns5 Mission Script (Converted from Misns5Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CCA, aiCore.Factions.NSDF, 2)
end

-- Variables
local camera1 = false
local start_done = false
local defender = false
local com_dead = false
local last_phase = false
local third_attack = false
local fourth_attack = false
local won = false
local lost = false
local second_message = false
local third_message = false
local art_dead = false
local apc_here = false

-- Timers
local add_defender = 99999.0
local wave_timer = 99999.0
local chaff = 99999.0
local camera_time = 99999.0
local apc_wave = 99999.0

-- Handles
local player
local a1, a2
local t1, t2, t3, t4
local h1, h2
local geyser1, geyser2
local recy, muf
local commander
local cam1
local killme

-- Counters
local wave_count = 0

-- Config
local difficulty = 2

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    
    player = GetPlayerHandle()
    start_done = false
end

function AddObject(h)
    local team = GetTeamNum(h)
    if team == 2 then
        aiCore.AddObject(h)
        
        -- Identify Commander
        if IsOdf(h, "avwalk") and (not commander) then
            commander = h
        end
        
        -- Default orders for specific units (C++ logic)
        -- If light tank, razor, fighter -> Go to Recycler
        if IsOdf(h, "bvltnk") or IsOdf(h, "bvhraz") or IsOdf(h, "avfigh") then
            if IsAlive(recy) then Goto(h, recy) end -- Attack/Go Recy
        end
    end
    -- Unit Turbo based on difficulty
    if exu and exu.SetUnitTurbo and IsCraft(h) then
        if team ~= 0 then
             if difficulty >= 3 then exu.SetUnitTurbo(h, true) end
        end
    end
end

function DeleteObject(h)
end

function Update()
    player = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        recy = GetHandle("svrecy0_recycler")
        AddScrap(1, DiffUtils.ScaleRes(10))
        camera1 = true
        camera_time = GetTime() + DiffUtils.ScaleTimer(17.0)
        apc_wave = GetTime() + DiffUtils.ScaleTimer(70.0)
        
        t4 = GetHandle("sbhang0_repairdepot")
        a1 = BuildObject("avartl", 2, "spawn1")
        a2 = BuildObject("avartl", 2, "spawn2")
        
        CameraReady()
        AudioMessage("misns501.wav")
        -- Store start time of audio if needed, or rely on IsAudioMessageDone(0) check if unique?
        -- Lua API doesn't return handle for AudioMessage usually unless extended.
        -- We'll rely on camera_time or standard done check if available.
        -- Assuming IsAudioMessageDone takes checksum or filename in refined API, or we just wait.
        
        start_done = true
    end
    
    if camera1 then
        CameraPath("campath", 5000, 2500, t4)
        
        -- Audio chaining
        -- C++ uses handle 'aud' from previous call. Lua: check if specific msg done?
        -- We'll use timer approximation or state check.
        if (not second_message) and (GetTime() > camera_time - 7.0) then -- Approx
            AudioMessage("misns503.wav")
            second_message = true
        end
        
        if CameraCancelled() or (GetTime() > camera_time) then
            chaff = GetTime() + DiffUtils.ScaleTimer(180.0)
            
            t1 = GetHandle("sblpow2_powerplant")
            t2 = GetHandle("sblpow3_powerplant")
            t3 = GetHandle("sblpow4_powerplant")
            recy = GetHandle("svrecy0_recycler")
            muf = GetHandle("svmuf0_factory")
            geyser1 = GetHandle("eggeizr11_geyser")
            geyser2 = GetHandle("eggeizr12_geyser")
            
            -- Move Base!
            Goto(recy, geyser1)
            Goto(muf, geyser2)
            
            Attack(a1, t1)
            Attack(a2, t2)
            
            add_defender = GetTime() + DiffUtils.ScaleTimer(10.0)
            CameraFinish()
            ClearObjectives()
            AddObjective("misns501.otf", "white")
            -- StopAudioMessage?
            camera1 = false
        end
    end
    
    -- Target switching for Artillery
    if defender and (not third_attack) and (not IsAlive(t1)) then
        Attack(a1, t3)
        third_attack = true
    end
    if defender and (not fourth_attack) and (not IsAlive(t2)) then
        Attack(a2, t4)
        fourth_attack = true
    end
    
    -- Spawn Defenders
    if (GetTime() > add_defender) then
        BuildObject("avwalk", 2, "spawn3")
        -- Restoration: BuildObject("avtank",2,"spawn3"); (Commented out in C++)
        BuildObject("avtank", 2, "spawn3")
        
        add_defender = 99999.0
        SetPilot(2, 30)
        defender = true
    end
    
    -- Art killed msg
    if defender and (not art_dead) and (not IsAlive(a1)) and (not IsAlive(a2)) then
        AudioMessage("misns504.wav")
        art_dead = true
    end
    
    -- APC arrival check
    if defender and h1 and (not apc_here) and IsAlive(h1) and (GetDistance(h1, muf) < 100.0) then
        apc_here = true
        AudioMessage("misns505.wav")
    end
    
    -- Chaff (Fighters)
    if (GetTime() > chaff) then
        chaff = GetTime() + DiffUtils.ScaleTimer(50.0) + math.random(4) * 10
        BuildObject("avfigh", 2, "spawn5")
    end
    
    -- APC Wave spawn
    if (GetTime() > apc_wave) then
        h1 = BuildObject("avapc", 2, "spawn6")
        h2 = BuildObject("avapc", 2, "spawn6")
        killme = BuildObject("avrecy", 2, "spawn7") -- Fake recycler target for defense?
        
        local p1 = BuildObject("bvtank", 2, "spawn7"); Defend(p1, killme)
        local p2 = BuildObject("bvtank", 2, "spawn7"); Defend(p2, killme)
        
        Attack(h1, muf)
        Attack(h2, muf)
        apc_wave = 99999.0
    end
    
    -- Commander Death Trigger (Speeds up waves)
    if defender and (not IsAlive(commander)) and (not com_dead) then
        wave_timer = GetTime() + DiffUtils.ScaleTimer(120.0)
        com_dead = true
    end
    
    -- Waves Logic
    if (GetTime() > wave_timer) then
        wave_count = wave_count + 1
        wave_timer = GetTime() + DiffUtils.ScaleTimer(180.0)
        
        AudioMessage("misns505.wav")
        
        if wave_count ~= 1 then
            BuildObject("bvltnk", 2, "spawn5")
            BuildObject("bvltnk", 2, "spawn5")
            BuildObject("bvltnk", 2, "spawn5")
        else -- Wave 1
            BuildObject("bvhraz", 2, "spawn6")
            BuildObject("bvhraz", 2, "spawn6")
            BuildObject("bvhraz", 2, "spawn6")
        end
        
        if wave_count == 3 then
            last_phase = true
            -- killme was built earlier (apc_wave), or we rely on logic?
            -- C++ says: // key is it commented out killme = BuildObject...
            -- And C++ AddObject sets: if (wave_count==3) ...
            -- Actually C++ code: 
            -- if (wave_count==3) {
            --    // killme=BuildObject("avrecy",2,"spawn7"); <-- Commented out
            --    BuildObject("avscav",2,"spawn7"); ...
            --    SetObjectiveOn(killme); 
            -- }
            -- So `killme` MUST have been built earlier (in apc_wave block).
            
            BuildObject("avscav", 2, "spawn7")
            BuildObject("avscav", 2, "spawn7")
            local sam = BuildObject("spcamr", 1, "camera1") -- Camera marker?
            
            if IsAlive(killme) then SetObjectiveOn(killme) end
            AddObjective("misns502.otf", "white")
            AudioMessage("misns506.wav")
            
            SetAIP("misns5.aip")
        end
    end
    
    -- Victory
    if last_phase and (not IsAlive(killme)) and (not won) and (not lost) then
        won = true
        AudioMessage("misns508.wav")
        SucceedMission(GetTime() + 10.0, "misns5w1.des")
    end
    
    -- Defeat
    if (not IsAlive(recy)) and (not lost) and (not won) then
        lost = true
        AudioMessage("misns507.wav")
        FailMission(GetTime() + 10.0, "misns5l1.des")
    end
end

