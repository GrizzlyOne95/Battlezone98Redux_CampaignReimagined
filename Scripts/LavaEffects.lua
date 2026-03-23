-- LavaEffects.lua
-- Applies movement slowdown to craft on lava terrain
-- Requires MaterialTracker module

local MatTracker = require("MaterialTracker")

local LavaEffects = {}

-- Configuration
LavaEffects.Config = {
    enabled = true,
    slowdownFactor = 0.3,      -- Reduce speed to 30% on lava
    updateInterval = 1.0,      -- Check every second
    damagePerSecond = 0,       -- Optional: damage per second on lava (0 = disabled)
    affectBuildings = false    -- Whether lava affects buildings too
}

-- Internal state
LavaEffects.updateTimer = 0.0
LavaEffects.craftOnLava = {}  -- Track which craft are currently on lava

---
--- Main Update Function
---

function LavaEffects.Update()
    if not LavaEffects.Config.enabled then return end
    if not MatTracker.IsLoaded() then return end
    
    -- Update timer
    LavaEffects.updateTimer = LavaEffects.updateTimer + GetTimeStep()
    if LavaEffects.updateTimer < LavaEffects.Config.updateInterval then
        return
    end
    LavaEffects.updateTimer = 0.0
    
    -- Check all craft for lava contact
    local newCraftOnLava = {}
    
    for craft in AllCraft() do
        if IsValid(craft) and IsAlive(craft) then
            -- Skip buildings unless configured
            local shouldProcess = true
            if not LavaEffects.Config.affectBuildings and IsBuilding(craft) then
                shouldProcess = false
            end
            
            if shouldProcess then
                -- Get craft position
                local pos = GetPosition(craft)
                if pos then
                    -- Query material at position
                    local material = MatTracker.GetMaterialAt(pos.x, pos.z)
                    if material then
                        -- Check if on lava
                        if MatTracker.IsLavaMaterial(material) then
                            LavaEffects._ApplyLavaEffects(craft)
                            newCraftOnLava[craft] = true
                        else
                            -- Restore normal speed if leaving lava
                            if LavaEffects.craftOnLava[craft] then
                                LavaEffects._RemoveLavaEffects(craft)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Update tracking
    LavaEffects.craftOnLava = newCraftOnLava
end

---
--- Internal Functions
---

function LavaEffects._ApplyLavaEffects(craft)
    -- Apply movement slowdown
    -- Note: BZR doesn't have SetMaxSpeed, so we use SetVelocity scaling as a workaround
    local vel = GetVelocity(craft)
    if vel then
        -- Scale velocity to simulate slowdown
        local scaledVel = {
            x = vel.x * LavaEffects.Config.slowdownFactor,
            y = vel.y,  -- Don't affect vertical
            z = vel.z * LavaEffects.Config.slowdownFactor
        }
        SetVelocity(craft, scaledVel)
    end
    
    -- Optional: Apply damage
    if LavaEffects.Config.damagePerSecond > 0 then
        local damageAmount = LavaEffects.Config.damagePerSecond * LavaEffects.Config.updateInterval
        Damage(craft, damageAmount)
    end
    
    -- Track for debugging
    if not LavaEffects.craftOnLava[craft] then
        -- print("LavaEffects: " .. GetOdf(craft) .. " entered lava terrain")
    end
end

function LavaEffects._RemoveLavaEffects(craft)
    -- Effects are automatically removed when craft leaves lava
    -- (velocity scaling stops being applied)
    -- print("LavaEffects: " .. GetOdf(craft) .. " left lava terrain")
end

---
--- Configuration API
---

function LavaEffects.SetSlowdownFactor(factor)
    LavaEffects.Config.slowdownFactor = math.max(0.0, math.min(1.0, factor))
end

function LavaEffects.SetDamagePerSecond(damage)
    LavaEffects.Config.damagePerSecond = math.max(0, damage)
end

function LavaEffects.SetUpdateInterval(interval)
    LavaEffects.Config.updateInterval = math.max(0.1, interval)
end

function LavaEffects.Enable()
    LavaEffects.Config.enabled = true
end

function LavaEffects.Disable()
    LavaEffects.Config.enabled = false
end

return LavaEffects
