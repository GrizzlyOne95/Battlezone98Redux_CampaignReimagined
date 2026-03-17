-- LavaEffects_Example.lua
-- Example integration of lava terrain effects

local MatTracker = require("MaterialTracker")
local LavaEffects = require("LavaEffects")

function Start()
    -- Initialize material tracker
    if not MatTracker.Init() then
        print("Failed to initialize MaterialTracker")
        return
    end
    
    -- Configure lava effects
    LavaEffects.SetSlowdownFactor(0.3)     -- 30% speed on lava
    LavaEffects.SetDamagePerSecond(2)       -- 2 damage per second
    LavaEffects.SetUpdateInterval(0.5)      -- Check twice per second
    LavaEffects.Enable()
    
    print("Lava effects enabled!")
    if MatTracker.GetLavaMaterialIndex() then
        print("  Lava material: " .. MatTracker.GetLavaMaterialIndex())
    end
end

function Update()
    -- Run lava effects system
    LavaEffects.Update()
end

---
--- Alternative: Manual integration without LavaEffects module
---

-- Uncomment this version if you want to integrate directly:
--[[
local MatTracker = require("MaterialTracker")
local lavaSlowdownFactor = 0.3
local lavaUpdateTimer = 0.0

function Start()
    MatTracker.Init()
end

function Update()
    lavaUpdateTimer = lavaUpdateTimer + GetTimeStep()
    if lavaUpdateTimer < 0.5 then return end
    lavaUpdateTimer = 0.0
    
    -- Check all craft
    for craft in AllCraft() do
        if IsValid(craft) and IsAlive(craft) and not IsBuilding(craft) then
            local pos = GetPosition(craft)
            if pos then
                local mat = MatTracker.GetMaterialAt(pos.x, pos.z)
                
                -- Slow down if on lava
                if mat and MatTracker.IsLavaMaterial(mat) then
                    local vel = GetVelocity(craft)
                    if vel then
                        SetVelocity(craft, {
                            x = vel.x * lavaSlowdownFactor,
                            y = vel.y,
                            z = vel.z * lavaSlowdownFactor
                        })
                    end
                end
            end
        end
    end
end
]]--
