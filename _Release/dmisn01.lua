-- dmisn01.lua (Converted from DemoMission.cpp)

-- Compatibility and Library Setup
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local bzfile = require("bzfile")
local DiffUtils = require("DiffUtils")

-- Variables
local start_done = false
local camera1 = false
local camera2 = false
local angle = 0
local camera_time = -99999.0
local lost = false
local first_start = false
local cycle_count = 0
local frame_count = 0
local mission_start_time = 0
local cycle_start_time = 0
local last_time = 0

-- Handles
local target, foe1, foe2, foe3, foe4, friend1, art1
local buildings = {} -- build1 to build8

-- Data
local moveX = 4142.0
local moveZ = 98568.0

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    start_done = false
    mission_start_time = 0
    cycle_count = 0
    frame_count = 0
end

function AddObject(h)
    -- This is a benchmark, we track all objects
end

function DeleteObject(h)
end

local function KillStuff()
    -- Lua optimization: loop and remove everything except user
    -- Since this is a benchmark, we use the engine's object list if possible,
    -- but usually missions keep track of spawned handles.
    local to_kill = {target, foe1, foe2, foe3, foe4, friend1, art1}
    for _, h in ipairs(to_kill) do if h and IsAlive(h) then RemoveObject(h) end end
    for _, h in ipairs(buildings) do if h and IsAlive(h) then RemoveObject(h) end end
end

function Update()
    local user = GetPlayerHandle()
    frame_count = frame_count + 1
    
    if not start_done then
        cycle_start_time = GetTime()
        if not first_start then
            first_start = true
            mission_start_time = GetTime()
            CameraReady()
        end
        
        -- C++ line 360-377
        target = BuildObject("avdemo", 1, "spawn_point")
        Goto(target, "go_path")
        
        foe1 = BuildObject("svhraz", 2, "foe1")
        foe2 = BuildObject("svltnk", 2, "foe2")
        foe3 = BuildObject("svltnk", 2, "foe2")
        foe4 = BuildObject("svrckt", 2, "foe2")
        
        friend1 = BuildObject("avhraz", 1, "friend1")
        art1 = BuildObject("avartl", 1, "art1")
        
        buildings[1] = BuildObject("sbcomm", 2, "build1")
        buildings[2] = BuildObject("sbspow", 2, "build2")
        buildings[3] = BuildObject("sbhang", 2, "build3")
        buildings[4] = BuildObject("sblpow", 2, "build4")
        buildings[5] = BuildObject("sbhqcp", 2, "build5")
        buildings[6] = BuildObject("sbwpow", 2, "build6")
        buildings[7] = BuildObject("sbwpow", 2, "build7")
        buildings[8] = BuildObject("sbwpow", 2, "build8")
        
        Goto(foe1, buildings[1])
        Goto(foe2, buildings[1])
        Goto(foe3, buildings[1])
        Goto(foe4, buildings[1])
        Follow(friend1, target)
        
        start_done = true
        camera1 = true
        camera2 = false
        angle = 0
        camera_time = GetTime() + 7.0
    end
    
    if lost then return end
    
    -- Camera Case 0/1/2 (C++ 390-409)
    if camera1 then
        local cam_offsets = {
            [0] = {0, 800, -1500},
            [1] = {-1500, 800, 0},
            [2] = {0, 800, 1500}
        }
        local off = cam_offsets[angle]
        CameraObject(target, off[1], off[2], off[3], target)
        
        if GetTime() > camera_time then
            camera_time = GetTime() + 7.0
            angle = (angle + 1) % 3
        end
        
        if GetDistance(foe1, target) < 200.0 then
            camera1 = false
            camera2 = true
            Attack(art1, foe1)
            angle = 0 -- Reset for camera2
        end
    end
    
    -- Camera Case 2 (C++ 428)
    if camera2 then
        if IsAlive(buildings[2]) then Damage(buildings[2], 50) end
        
        if angle == 0 then
            CameraPath("camera1", 1000, 0, target)
        elseif angle == 1 then
            if IsAlive(foe1) then
                CameraObject(target, -600, 400, 0, foe1)
            elseif IsAlive(foe2) then
                CameraObject(target, -600, 400, 0, foe2)
            end
        end
        
        if GetTime() > camera_time then
            camera_time = GetTime() + 7.0
            angle = (angle + 1) % 2
        end
    end
    
    -- End of Cycle (C++ 458)
    if (not IsAlive(target)) or (GetTime() > cycle_start_time + DiffUtils.ScaleTimer(55.0)) then
        cycle_count = cycle_count + 1
        
        if cycle_count >= 5 then
            if not lost then
                -- Benchmark Reporting
                local tottime = GetTime() - mission_start_time
                local fps = frame_count / tottime
                
                local filePath = bzfile.GetWorkingDirectory() .. "addon\\bzbench.des"
                local f = bzfile.Open(filePath, "w", "trunc")
                if f then
                    f:Writeln("Battlezone Benchmark Test")
                    f:Writeln("")
                    f:Writeln(string.format("Total time : %f", tottime))
                    f:Writeln(string.format("Average frame rate : %f", fps))
                    f:Writeln("")
                    f:Writeln("This benchmark was created by George Collins.")
                    f:Close()
                end
                
                -- Finsh
                lost = true
                SucceedMission(GetTime() + 1.0, "bzbench.des")
            end
        else
            -- Restart Cycle
            KillStuff()
            start_done = false
            camera1 = false
            camera2 = false
        end
    end
end

