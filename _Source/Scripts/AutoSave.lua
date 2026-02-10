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
--- Internal: Save File Generation
---

function AutoSave._WriteSaveFile(file)
    -- 1. Write header
    AutoSave._WriteHeader(file)
    
    -- 2. Write all game objects
    local objectCount = 0
    for obj in AllGameObjects() do
        if IsValid(obj) then
            AutoSave._WriteGameObject(file, obj)
            objectCount = objectCount + 1
        end
    end
    
    print("AutoSave: Serialized " .. objectCount .. " objects")
end

function AutoSave._WriteHeader(file)
    file:Writeln("version [1] =")
    file:Writeln("2016")
    file:Writeln("binarySave [1] =")
    file:Writeln("false")
    
    -- Mission filename
    local missionName = GetMapTRNFilename() or "misn01.bzn"
    missionName = string.gsub(missionName, "%.trn$", ".bzn")
    file:Writeln("msn_filename = " .. missionName)
    
    -- Sequence count (will be updated later if needed)
    file:Writeln("seq_count [1] =")
    file:Writeln("1000")  -- Placeholder
    
    file:Writeln("missionSave [1] =")
    file:Writeln("false")
    file:Writeln("runType [1] =")
    file:Writeln("0")
    
    -- Save description (hex encoded timestamp)
    local desc = AutoSave._GenerateSaveDescription()
    file:Writeln("saveGameDesc = " .. desc)
    
    file:Writeln("nPlayerSide = usa")  -- TODO: Make dynamic
    file:Writeln("nMissionStatus [1] =")
    file:Writeln("0")
    file:Writeln("nOldMissionMode [1] =")
    file:Writeln("0")
    
    local terrainName = string.gsub(missionName, "%.bzn$", "")
    file:Writeln("TerrainName = " .. terrainName)
    
    file:Writeln("start_time [1] =")
    file:Writeln(tostring(GetTime()))
    
    file:Writeln("size [1] =")
    file:Writeln("63")  -- Placeholder
end

function AutoSave._GenerateSaveDescription()
    -- Generate hex-encoded save description
    -- Format: "Auto-Save <timestamp>" encoded as hex + null padding
    local text = "Auto-Save " .. os.date("%m/%d/%Y %I:%M:%S %p")
    local hex = ""
    for i = 1, #text do
        hex = hex .. string.format("%02x", string.byte(text, i))
    end
    
    -- Pad with zeros to match engine format (512 chars)
    while #hex < 512 do
        hex = hex .. "00"
    end
    
    return hex
end

function AutoSave._WriteGameObject(file, obj)
    file:Writeln("[GameObject]")
    
    -- Basic identity
    local odf = GetOdf(obj)
    if odf then
        file:Writeln("PrjID [1] =")
        file:Writeln(odf)
    end
    
    -- Sequence number (unique ID)
    local seqno = GetSeqNo(obj)
    if seqno then
        file:Writeln("seqno [1] =")
        file:Writeln(tostring(seqno))
    end
    
    -- Position
    local pos = GetPosition(obj)
    if pos then
        file:Writeln("pos [1] =")
        file:Writeln("  x [1] =")
        file:Writeln(tostring(pos.x))
        file:Writeln("  y [1] =")
        file:Writeln(tostring(pos.y))
        file:Writeln("  z [1] =")
        file:Writeln(tostring(pos.z))
    end
    
    -- Team
    local team = GetTeamNum(obj)
    if team then
        file:Writeln("team [1] =")
        file:Writeln(tostring(team))
    end
    
    -- Label
    local label = GetLabel(obj)
    if label and label ~= "" then
        file:Writeln("label = " .. label)
    end
    
    -- Is user (player)
    local isUser = (obj == GetPlayerHandle())
    file:Writeln("isUser [1] =")
    file:Writeln(isUser and "1" or "0")
    
    -- Transform matrix (simplified - identity for now)
    file:Writeln("transform [1] =")
    AutoSave._WriteTransform(file, obj)
    
    -- Health
    local curHealth = GetCurHealth(obj)
    local maxHealth = GetMaxHealth(obj)
    if curHealth and maxHealth then
        file:Writeln("curHealth [1] =")
        file:Writeln(tostring(curHealth))
        file:Writeln("maxHealth [1] =")
        file:Writeln(tostring(maxHealth))
        file:Writeln("healthRatio [1] =")
        file:Writeln(tostring(maxHealth > 0 and curHealth / maxHealth or 0))
    end
    
    -- Ammo
    local curAmmo = GetCurAmmo(obj)
    local maxAmmo = GetMaxAmmo(obj)
    if curAmmo and maxAmmo then
        file:Writeln("curAmmo [1] =")
        file:Writeln(tostring(curAmmo))
        file:Writeln("maxAmmo [1] =")
        file:Writeln(tostring(maxAmmo))
        file:Writeln("ammoRatio [1] =")
        file:Writeln(tostring(maxAmmo > 0 and curAmmo / maxAmmo or 0))
    end
    
    -- Pilot
    local pilot = GetPilotClass(obj)
    if pilot and pilot ~= "" then
        file:Writeln("curPilot [1] =")
        file:Writeln(pilot)
    end
end

function AutoSave._WriteTransform(file, obj)
    -- Write identity transform for now
    -- TODO: Extract actual rotation matrix if possible
    file:Writeln("  right_x [1] = 1")
    file:Writeln("  right_y [1] = 0")
    file:Writeln("  right_z [1] = 0")
    file:Writeln("  up_x [1] = 0")
    file:Writeln("  up_y [1] = 1")
    file:Writeln("  up_z [1] = 0")
    file:Writeln("  front_x [1] = 0")
    file:Writeln("  front_y [1] = 0")
    file:Writeln("  front_z [1] = 1")
    
    local pos = GetPosition(obj)
    if pos then
        file:Writeln("  posit_x [1] = " .. tostring(pos.x))
        file:Writeln("  posit_y [1] = " .. tostring(pos.y))
        file:Writeln("  posit_z [1] = " .. tostring(pos.z))
    end
end

return AutoSave
