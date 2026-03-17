-- AutoSave_Example.lua
-- Example: Programmatic auto-save using bzfile synthesis

local AutoSave = require("AutoSave")

function Start()
    -- Enable auto-save every 5 minutes
    AutoSave.EnableAutoSave(300)
    
    -- Use save slot 1
    AutoSave.SetSlot(1)
    
    print("Auto-save enabled: Slot 1, every 5 minutes")
end

function Update()
    -- Run auto-save timer
    AutoSave.Update()
    
    -- Example: Manual save on keypress
    if LastGameKey == "Ctrl+S" then
        print("Manual save triggered...")
        AutoSave.CreateSave()
    end
end

-- Example: Save on objective completion
function CompleteObjective(objName)
    print("Objective complete: " .. objName)
    -- Trigger immediate auto-save
    AutoSave.CreateSave()
end

-- Example: Save before risky action
function BeforeDangerousEvent()
    print("Creating safety save...")
    AutoSave.SetSlot(9)  -- Use slot 9 for safety saves
    AutoSave.CreateSave()
    AutoSave.SetSlot(1)  -- Back to regular slot
end
