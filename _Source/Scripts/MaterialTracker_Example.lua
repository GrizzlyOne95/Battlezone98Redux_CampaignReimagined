-- MaterialTracker_Example.lua
-- Example usage of the MaterialTracker module

local MatTracker = require("MaterialTracker")

-- Example: Initialize in Start()
function Start()
    -- Initialize material tracker
    if MatTracker.Init() then
        print("Material tracking enabled!")
        print(MatTracker.GetStats())
    else
        print("Material tracking failed to initialize")
    end
end

-- Example: Query materials in Update()
function Update()
    -- Get player position
    local player = GetPlayerHandle()
    if not IsValid(player) then return end
    
    local pos = GetPosition(player)
    
    -- Get material at player position
    local material = MatTracker.GetMaterialAt(pos.x, pos.z)
    if material then
        -- Apply terrain-based effects
        if material == 0 then
            -- Default terrain - no effect
        elseif material == 1 then
            -- Rocky terrain - slow movement
            print("Player on rocky terrain (material " .. material .. ")")
            -- Could apply: SetMaxSpeed(player, 0.8)
        elseif material == 2 then
            -- Smooth terrain - speed boost
            print("Player on smooth terrain (material " .. material .. ")")
            -- Could apply: SetMaxSpeed(player, 1.2)
        elseif material == 5 then
            -- Lava/acid - damage over time
            print("Player on hazardous terrain (material " .. material .. ")!")
            -- Could apply: Damage(player, 10)
        end
    end
end

-- Example: Advanced material-based spawn system
function SpawnEnemyNearPlayer()
    local player = GetPlayerHandle()
    if not IsValid(player) then return end
    
    local pos = GetPosition(player)
    
    -- Search for suitable spawn location
    for radius = 100, 500, 50 do
        for angle = 0, 2 * math.pi, math.pi / 8 do
            local x = pos.x + radius * math.cos(angle)
            local z = pos.z + radius * math.sin(angle)
            
            -- Check terrain material
            local mat = MatTracker.GetMaterialAt(x, z)
            
            -- Only spawn on "safe" materials (not lava, water, etc.)
            if mat and mat >= 0 and mat <= 3 then
                local spawnPos = SetVector(x, GetTerrainHeight(x, z), z)
                BuildObject("svtank", 2, spawnPos)
                print("Spawned enemy on material " .. mat)
                return
            end
        end
    end
    
    print("No suitable spawn location found")
end

-- Example: Material-aware pathfinding cost modifier
function GetTerrainCost(x, z)
    local mat = MatTracker.GetMaterialAt(x, z)
    if not mat then return 1.0 end
    
    -- Higher cost = avoid this terrain
    local costs = {
        [0] = 1.0,  -- Default
        [1] = 1.5,  -- Rocky
        [2] = 0.8,  -- Smooth
        [5] = 10.0, -- Hazard (avoid!)
    }
    
    return costs[mat] or 1.0
end

-- Example: Debug visualization
function DebugPrintMaterialGrid()
    print("Material grid around player:")
    
    local player = GetPlayerHandle()
    if not IsValid(player) then return end
    
    local pos = GetPosition(player)
    local startX = math.floor(pos.x / 10) * 10 - 50
    local startZ = math.floor(pos.z / 10) * 10 - 50
    
    for z = startZ, startZ + 100, 10 do
        local line = ""
        for x = startX, startX + 100, 10 do
            local mat = MatTracker.GetMaterialAt(x, z)
            line = line .. (mat or "?") .. " "
        end
        print(line)
    end
end
