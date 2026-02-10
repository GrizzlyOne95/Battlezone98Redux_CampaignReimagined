-- AutoSave.lua
-- Programmatic Save File Synthesis for Battlezone 98 Redux
-- Generates .sav files using bzfile I/O to enable true auto-save

local bzfile = require("bzfile")

local AutoSave = {}

-- Configuration
AutoSave.Config = {
    enabled = false,
    autoSaveInterval = 300,  -- Auto-save every 5 minutes
    currentSlot = 1,          -- Which save slot to use (1-10)
    saveOnObjective = false   -- Auto-save when objectives complete
}

-- State
AutoSave.timer = 0.0
AutoSave.lastSaveTime = 0.0

---
--- Public API
---

-- Create a save file in the specified slot (1-10)
function AutoSave.CreateSave(slotNumber)
    slotNumber = slotNumber or AutoSave.Config.currentSlot
    if slotNumber < 1 or slotNumber > 10 then
        print("AutoSave: Invalid slot number " .. slotNumber)
        return false
    end
    
    local saveDir = bzfile.GetWorkingDirectory() .. "\\save"
    local filename = saveDir .. "\\game" .. slotNumber .. ".sav"
    
    print("AutoSave: Generating save file: " .. filename)
    
    -- Open file for writing (truncate existing)
    local file = bzfile.Open(filename, "w", "trunc")
    if not file then
        print("AutoSave: Failed to open file for writing")
        return false
    end
    
    -- Write save file content
    AutoSave._WriteSaveFile(file)
    
    -- Close file
    file:Close()
    
    print("AutoSave: Save complete!")
    AutoSave.lastSaveTime = GetTime()
    return true
end

-- Enable auto-save with specified interval (seconds)
function AutoSave.EnableAutoSave(interval)
    AutoSave.Config.enabled = true
    AutoSave.Config.autoSaveInterval = interval or 300
    print("AutoSave: Enabled (interval: " .. AutoSave.Config.autoSaveInterval .. "s)")
end

function AutoSave.DisableAutoSave()
    AutoSave.Config.enabled = false
    print("AutoSave: Disabled")
end

-- Set which save slot to use
function AutoSave.SetSlot(slotNumber)
    if slotNumber >= 1 and slotNumber <= 10 then
        AutoSave.Config.currentSlot = slotNumber
    end
end

-- Update function (call from mission Update())
function AutoSave.Update()
    if not AutoSave.Config.enabled then return end
    
    AutoSave.timer = AutoSave.timer + GetTimeStep()
    if AutoSave.timer >= AutoSave.Config.autoSaveInterval then
        AutoSave.CreateSave()
        AutoSave.timer = 0.0
    end
end

---
--- Internal Writers
---

function AutoSave._WriteSaveFile(file)
    [cite_start]-- Write Header Information based on game1.sav [cite: 1]
    file:Writeln("version [1] = 2016")
    file:Writeln("binarySave [1] = false")
    file:Writeln("msn_filename = " .. GetMissionFilename())
    file:Writeln("seq_count [1] = 1000") -- Placeholder high count
    file:Writeln("missionSave [1] = false")
    file:Writeln("runType [1] = 0")
    [cite_start]file:Writeln("nPlayerSide = usa") -- Default to USA side [cite: 3]
    file:Writeln("TerrainName = " .. GetMapName())
    [cite_start]file:Writeln("start_time [1] = " .. tostring(GetTime())) [cite: 4]
    
    -- Iterate through all game objects
    for i = 1, 1024 do
        local obj = GetHandle(i)
        if IsValid(obj) then
            AutoSave._WriteGameObject(file, obj)
        end
    end
end

function AutoSave._WriteGameObject(file, obj)
    [cite_start]file:Writeln("[GameObject]") [cite: 5]
    [cite_start]file:Writeln("PrjID [1] = " .. GetCfg(obj)) [cite: 5]
    [cite_start]file:Writeln("team [1] = " .. tostring(GetTeamNum(obj))) [cite: 7]
    [cite_start]file:Writeln("label = " .. (GetLabel(obj) or "")) [cite: 7]
    
    [cite_start]-- Position and Rotation Fix [cite: 8, 11]
    AutoSave._WriteTransform(file, obj)
    
    [cite_start]-- Physics Momentum Fix [cite: 18, 19]
    AutoSave._WritePhysics(file, obj)
    
    -- Stats
    AutoSave._WriteHealthAmmo(file, obj)
    
    [cite_start]-- AI State Fix [cite: 27, 28]
    AutoSave._WriteAIState(file, obj)
    
    [cite_start]-- Pilot Information [cite: 31]
    local pilot = GetPilotClass(obj)
    if pilot and pilot ~= "" then
        file:Writeln("curPilot [1] = " .. pilot)
    end
end

function AutoSave._WriteTransform(file, obj)
    [cite_start]local transform = GetTransform(obj) [cite: 8]
    if transform then
        file:Writeln("transform [1] =")
        [cite_start]-- Orientation Matrix [cite: 9, 10, 11]
        file:Writeln("  right_x [1] = " .. tostring(transform.right.x))
        file:Writeln("  right_y [1] = " .. tostring(transform.right.y))
        file:Writeln("  right_z [1] = " .. tostring(transform.right.z))
        file:Writeln("  up_x [1] = " .. tostring(transform.up.x))
        file:Writeln("  up_y [1] = " .. tostring(transform.up.y))
        file:Writeln("  up_z [1] = " .. tostring(transform.up.z))
        file:Writeln("  front_x [1] = " .. tostring(transform.front.x))
        file:Writeln("  front_y [1] = " .. tostring(transform.front.y))
        file:Writeln("  front_z [1] = " .. tostring(transform.front.z))
        [cite_start]-- Origin Position [cite: 11, 12]
        file:Writeln("  posit_x [1] = " .. tostring(transform.posit.x))
        file:Writeln("  posit_y [1] = " .. tostring(transform.posit.y))
        file:Writeln("  posit_z [1] = " .. tostring(transform.posit.z))
    end
end

function AutoSave._WritePhysics(file, obj)
    [cite_start]local vel = GetVelocity(obj) [cite: 17, 18]
    [cite_start]local omega = GetOmega(obj) [cite: 19]
    [cite_start]local v_mag = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2) [cite: 16]

    file:Writeln(" v_mag [1] = " .. tostring(v_mag))
    [cite_start]file:Writeln(" v_mag_inv [1] = " .. tostring(v_mag > 0 and 1/v_mag or 1e+030)) [cite: 16]
    
    file:Writeln(" v [1] =")
    file:Writeln("  x [1] = " .. tostring(vel.x))
    file:Writeln("  y [1] = " .. tostring(vel.y))
    file:Writeln("  z [1] = " .. tostring(vel.z))
    
    file:Writeln(" omega [1] =")
    file:Writeln("  x [1] = " .. tostring(omega.x))
    file:Writeln("  y [1] = " .. tostring(omega.y))
    file:Writeln("  z [1] = " .. tostring(omega.z))
end

function AutoSave._WriteHealthAmmo(file, obj)
    [cite_start]-- Health [cite: 25]
    local curHealth = GetCurHealth(obj)
    local maxHealth = GetMaxHealth(obj)
    if curHealth and maxHealth then
        file:Writeln("curHealth [1] = " .. tostring(curHealth))
        file:Writeln("maxHealth [1] = " .. tostring(maxHealth))
        file:Writeln("healthRatio [1] = " .. tostring(maxHealth > 0 and curHealth / maxHealth or 0))
    end
    
    [cite_start]-- Ammo [cite: 26]
    local curAmmo = GetCurAmmo(obj)
    local maxAmmo = GetMaxAmmo(obj)
    if curAmmo and maxAmmo then
        file:Writeln("curAmmo [1] = " .. tostring(curAmmo))
        file:Writeln("maxAmmo [1] = " .. tostring(maxAmmo))
        file:Writeln("ammoRatio [1] = " .. tostring(maxAmmo > 0 and curAmmo / maxAmmo or 0))
    end
end

function AutoSave._WriteAIState(file, obj)
    [cite_start]local cmd = GetCurrentCommand(obj) [cite: 27]
    [cite_start]-- .sav format requires two command blocks (Primary and Secondary) [cite: 28, 29]
    for i = 1, 2 do
        if i == 1 and cmd then
            file:Writeln("priority [1] = " .. tostring(cmd.priority or 0))
            file:Writeln("what = " .. string.format("%08x", cmd.command or 0))
            file:Writeln("who [1] = " .. tostring(cmd.who or 0))
            file:Writeln("where = " .. string.format("%08x", cmd.where or 0))
            file:Writeln("param [1] = " .. tostring(cmd.param or ""))
        else
            [cite_start]-- Empty secondary command block [cite: 29, 30]
            file:Writeln("priority [1] = 0")
            file:Writeln("what = 00000000")
            file:Writeln("who [1] = 0")
            file:Writeln("where = 00000000")
            file:Writeln("param [1] = ")
        end
    end
end

return AutoSave