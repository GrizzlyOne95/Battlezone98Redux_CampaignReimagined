--Wingman auto rearm module written by GrizzlyOne95 2025
--Optimized version with pre-indexed repair and supply objects
--VALUES THAT CAN BE TWEAKED FOR CUSTOMIZATION:
local autorepair = {}

local checkPeriod = 0.25      -- Time (in seconds) between repair checks. Basically how often units scan for supplies.
local podChance = 1           -- Chance (0.0 to 1.0) for unit to decide to go to a pod. You can make it a random chance if youd like.
local podSearchRadius = 275.0 -- Distance within which pods and repair/supply depots are searched. If none lie within this range, the unit won't look for them.
local followThreshold = 110   -- Distance between unit and its follow target. If unit is in a follow state and the follow target goes beyond this distance, it will immediately stop looking for supplies and resume following.
local enemySearchRadius = 200 -- Distance within which units will be marked as "in combat"
local commandDelay = 10       -- Delay between reissuing commands to avoid spam (this is PER UNIT). Only really needed to recalculate pathing occasionally if a unit gets stuck on a Goto order.
local followVelocity = 3	  -- Velocity check in which a unit will have a longer range to resupply. Say its following a deployed Recycler, itll be able to go to the longer range than if it was following a moving tank. 
local followVelocityThreshold = 250 -- Longer range to use for a follow target that is slow moving or stationary. 
--*************************************************

local debugMode = false -- Set to true for debugging

-- Independent variables and tables
local wingmanTable = {}       -- Table to store all wingman units
local repairDepotTable = {}   -- Table to store repair depots
local supplyDepotTable = {}   -- Table to store supply depots
local repairPodTable = {}     -- Table to store repair pods
local ammoPodTable = {}       -- Table to store ammo pods


local checkRepairTimer = 0    -- Timer for periodic repair checks: no need to modify this, just a variable to track time

-- Function to find the nearest supply depot with adjustable search radius
function FindNearestSupplyDepot(unit, searchRadius)
    local nearestDepot = nil
    local closestDistance = searchRadius or podSearchRadius  -- Use provided radius or default

    for depot, _ in pairs(supplyDepotTable) do
        if GetTeamNum(unit) == GetTeamNum(depot) or IsAlly(unit, depot) then
            local distance = GetDistance(unit, depot)
            if distance < closestDistance then
                closestDistance = distance
                nearestDepot = depot  -- Update nearestDepot if a closer one is found
            end
        end
    end

    return nearestDepot
end

-- Optimized function to find the nearest repair depot with adjustable search radius
function FindNearestRepairDepot(unit, searchRadius)
    local nearestDepot = nil
    local closestDistance = searchRadius or podSearchRadius  -- Use provided radius or default

    for depot, _ in pairs(repairDepotTable) do
        if GetTeamNum(unit) == GetTeamNum(depot) or IsAlly(unit, depot) then
            local distance = GetDistance(unit, depot)
            if distance < closestDistance then
                closestDistance = distance
                nearestDepot = depot  -- Update nearestDepot if a closer one is found
            end
        end
    end

    return nearestDepot
end

-- Function to find nearest repair pod with adjustable search radius
function FindNearestRepairPod(unit, searchRadius)
    local nearestPod = nil
    local podType = ""
    local closestDistance = searchRadius or podSearchRadius  -- Use provided radius or default

    for pod, _ in pairs(repairPodTable) do
        local distance = GetDistance(unit, pod)
        local podHeight, _ = GetTerrainHeightAndNormal(pod) -- Get the terrain height under the pod
        local podAboveGround = GetPosition(pod).y - podHeight -- Calculate the height above ground
        
        if distance < closestDistance and podAboveGround <= 5.0 then
            closestDistance = distance
            nearestPod = pod  -- Update nearestPod if a closer one is found
            podType = "repair"  -- Store the pod type
        end
    end

    return nearestPod, podType
end

-- Function to find nearest ammo pod with adjustable search radius
function FindNearestAmmoPod(unit, searchRadius)
    local nearestPod = nil
    local podType = ""
    local closestDistance = searchRadius or podSearchRadius  -- Use provided radius or default

    for pod, _ in pairs(ammoPodTable) do
        local distance = GetDistance(unit, pod)
        local podHeight, _ = GetTerrainHeightAndNormal(pod) -- Get the terrain height under the pod
        local podAboveGround = GetPosition(pod).y - podHeight -- Calculate the height above ground
        
        if distance < closestDistance and podAboveGround <= 5.0 then
            closestDistance = distance
            nearestPod = pod  -- Update nearestPod if a closer one is found
            podType = "ammo"  -- Store the pod type
        end
    end

    return nearestPod, podType
end



-- Function to add wingmen by iterating through all crafts. This function is called only once on start to add all matching objects into the tables.
function Start()
    for h in AllObjects() do
		local class = GetClassLabel(h)
    if class == "wingman" then
        wingmanTable[h] = { 
            unit = h, 
            lastCommandTime = 0, 
            previousCommand = nil, 
            previousTarget = nil 
        }
      if debugMode then
        print("Added wingman to wingmanTable.")
      end
    end
	
	-- you will be searching using the key, so the true is just there to say
-- "something exists here", it's not necessary to store it twice
	--repairDepotTable[h] = true
	
		if class == "repairdepot" then
            repairDepotTable[h] = true  -- Store handle in the table
        elseif class == "supplydepot" then
			supplyDepotTable[h] = true  -- Store handle in the table
        elseif class == "repairkit" then
			repairPodTable[h] = true  -- Store handle in the table
        elseif class == "ammopack" then
			ammoPodTable[h] = true  -- Store handle in the table
        end
    end
end

function DeleteObject(h)
	repairDepotTable[h] = nil
	supplyDepotTable[h] = nil 
	repairPodTable[h] = nil
	ammoPodTable[h] = nil
	wingmanTable[h] = nil
end

-- This function is called on any new object added to the world
function AddObject(h)
local class = GetClassLabel(h)
    if class == "wingman" then
        wingmanTable[h] = { 
            unit = h, 
            lastCommandTime = 0, 
            previousCommand = nil, 
            previousTarget = nil 
        }
      if debugMode then
        print("Added wingman to wingmanTable.")
      end
    end
	
	-- you will be searching using the key, so the true is just there to say
-- "something exists here", it's not necessary to store it twice
	--repairDepotTable[h] = true
	
		if class == "repairdepot" then
            repairDepotTable[h] = true  -- Store handle in the table
        elseif class == "supplydepot" then
			supplyDepotTable[h] = true  -- Store handle in the table
        elseif class == "repairkit" then
			repairPodTable[h] = true  -- Store handle in the table
        elseif class == "ammopack" then
			ammoPodTable[h] = true  -- Store handle in the table
        end
end

-- Function to save the unit's previous command and target
function SavePreviousCommand(entry)
    local unit = entry.unit
    entry.previousCommand = GetCurrentCommand(unit)
    entry.previousTarget = GetCurrentWho(unit)
end

-- Function to restore the unit's previous command and target
function RestorePreviousCommand(entry)
    if entry.previousCommand then
        SetCommand(entry.unit, entry.previousCommand,0,entry.previousTarget)
		if debugMode then
        print("Restored previous command for unit.")
		end
        entry.previousCommand = nil
        entry.previousTarget = nil
    end
end

-- Function to generate a random dice roll (returns true if roll is successful)
function DiceRoll(chance)
    return math.random() <= chance
end

function IsInBattle(unit) --determines if a unit is attacking, hunting, or could be threatened based on range of closest enemy
	local enemy = GetNearestEnemy(unit)
	if enemy and GetDistance(enemy, unit) <= enemySearchRadius and IsCraft(enemy) then
		return true
    end
	if GetCurrentCommand(unit) == AiCommand["ATTACK"] or GetCurrentCommand(unit) == AiCommand["HUNT"] then
		return true --unit is ordered to ATTACK or Hunt
	end
    return false -- No enemies nearby
end


-- Main update function with the improved logic
function Update()
    if GetTime() >= checkRepairTimer then
        checkRepairTimer = GetTime() + checkPeriod
        for _, entry in pairs(wingmanTable) do
            local unit = entry.unit
            local health = GetHealth(unit)
            local ammo = GetAmmo(unit)
            local healthThreshold, ammoThreshold
            local commandIssued = false
            local currentCommand = GetCurrentCommand(unit)
            local unitHeight, _ = GetTerrainHeightAndNormal(unit) -- Get the terrain height under unit
            local unitAboveGround = GetPosition(unit).y - unitHeight -- Calculate the height above ground
            
            -- Adjust thresholds based on activity
            if IsInBattle(unit) then
                healthThreshold = 0.05
                ammoThreshold = 0.025
            else
                healthThreshold = 0.75
                ammoThreshold = 0.75
            end
            
            -- Determine search radius based on follow state
            local searchRadius = podSearchRadius -- Default search radius
            
            -- If unit is following something, restrict search radius to follow threshold
            if currentCommand == AiCommand["FOLLOW"] or 
               currentCommand == AiCommand["DEFEND"] or 
               currentCommand == AiCommand["FORMATION"] then
                local target = GetCurrentWho(unit)
                if IsValid(target) then
                    -- Check the velocity of the target
                    local velocityVector = GetVelocity(target) or { x = 0, y = 0, z = 0 }
                    local velocityMagnitude = math.sqrt(velocityVector.x^2 + velocityVector.y^2 + velocityVector.z^2)
                    
                    if velocityMagnitude < followVelocity then
                        -- Target is slow/stationary - can use regular search radius but capped at follow threshold
                        searchRadius = math.min(podSearchRadius, followThreshold)
                    else
                        -- Target is moving - restrict search radius to follow threshold
                        searchRadius = math.min(podSearchRadius, followThreshold * 0.8) -- 80% of follow threshold for safety margin
                    end
                end
            end

            -- Check if unit is in dynamic state - meaning it can act somewhat independently if enemies are nearby.
            if currentCommand == AiCommand["NONE"] 
                or (currentCommand == AiCommand["FOLLOW"]) 
                or (currentCommand == AiCommand["DEFEND"])
                or (currentCommand == AiCommand["FORMATION"])
                or (currentCommand == AiCommand["ATTACK"]) 
                or (currentCommand == AiCommand["HUNT"])
                or (currentCommand == AiCommand["PATROL"])
                or (currentCommand == AiCommand["GET_REPAIR"] and GetHealth(unit) >= 0.95)
                or (currentCommand == AiCommand["GET_RELOAD"] and GetAmmo(unit) >= 0.95) then

                -- Check for health and prioritize repair depot
                if health <= healthThreshold then
                    local nearestRepairDepot = FindNearestRepairDepot(unit, searchRadius)
                    if nearestRepairDepot and GetTime() >= entry.lastCommandTime + commandDelay then
                        SavePreviousCommand(entry)
                        SetCommand(unit, AiCommand.GET_REPAIR, 0, nearestRepairDepot)
                        entry.lastCommandTime = GetTime()
                        commandIssued = true
                        if debugMode then
                            print("Moving unit to repair depot. Search radius: " .. searchRadius)
                        end
                    end
                end

                -- Skip further checks if a command was issued
                if not commandIssued and ammo <= ammoThreshold then
                    local nearestSupplyDepot = FindNearestSupplyDepot(unit, searchRadius)
                    if nearestSupplyDepot and GetClassLabel(nearestSupplyDepot) == "supplydepot" and GetTime() >= entry.lastCommandTime + commandDelay then
                        SavePreviousCommand(entry)
                        SetCommand(unit, AiCommand.GET_RELOAD, 0, nearestSupplyDepot)
                        entry.lastCommandTime = GetTime()
                        commandIssued = true
                        if debugMode then
                            print("Moving unit to supply depot. Search radius: " .. searchRadius)
                        end
                    end
                end

                -- Repair pod logic (fallback if no depot available)
                if not commandIssued and health <= healthThreshold and GetTime() >= entry.lastCommandTime + commandDelay and unitAboveGround <= 5 then
                    local nearestRepPod, podType = FindNearestRepairPod(unit, searchRadius)
                    if nearestRepPod and DiceRoll(podChance) then
                        SavePreviousCommand(entry)
                        Goto(unit, nearestRepPod, 0)
                        entry.lastCommandTime = GetTime()
                        if debugMode then
                            print("Moving unit to nearest " .. podType .. " pod. Search radius: " .. searchRadius)
                        end
                        commandIssued = true
                    elseif debugMode then
                        print("No repair pods within radius: " .. searchRadius)
                    end
                end

                -- Ammo pod logic (fallback if no depot available)
                if not commandIssued and ammo <= ammoThreshold and GetTime() >= entry.lastCommandTime + commandDelay and unitAboveGround <= 5 then
                    local nearestAmmoPod, podType = FindNearestAmmoPod(unit, searchRadius)
                    if nearestAmmoPod and DiceRoll(podChance) then
                        SavePreviousCommand(entry)
                        Goto(unit, nearestAmmoPod, 0)
                        entry.lastCommandTime = GetTime()
                        if debugMode then
                            print("Moving unit to nearest " .. podType .. " pod. Search radius: " .. searchRadius)
                        end
                        commandIssued = true
                    elseif debugMode then
                        print("No ammo pods within radius: " .. searchRadius)
                    end
                end
            end

            -- Check if the unit has completed its pod task
            if (currentCommand == AiCommand["NONE"] --idle after powerup pickup, so resume command
                or currentCommand == AiCommand["GET_REPAIR"] and GetHealth(unit) >= 0.95 --no need to stay by hangar anymore
                or currentCommand == AiCommand["GET_RELOAD"] and GetAmmo(unit) >= 0.95) -- no need to stay by supply anymore
                and IsValid(entry.previousTarget) and entry.previousCommand then --make sure previous target is valid and there IS a previous command
                RestorePreviousCommand(entry)
            end
        end
    end
end

-- Expose functions for the game
autorepair.AddObject = AddObject
autorepair.Start = Start
autorepair.Update = Update

return autorepair