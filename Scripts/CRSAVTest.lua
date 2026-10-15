-- Explicit, offline-only prototype fixture. No mission loads this automatically.
local Test = {}

local function localPlayer()
    if IsNetGame() then
        return nil, "SAV prototype is offline-only"
    end
    local player = GetPlayerHandle()
    if not player or not IsValid(player) then
        return nil, "No local player"
    end
    return player
end

local function spawn(odf, distance, name, empty)
    local player, reason = localPlayer()
    if not player then return nil, reason end
    local position = GetPosition(player)
    local where = SetVector(position.x + distance, position.y, position.z)
    local unit = BuildObject(odf, GetTeamNum(player), where)
    if not unit or not IsValid(unit) then
        return nil, "Could not create " .. odf
    end
    -- Enter by collision while on foot: the engine records the real pilot.
    -- Forcing SetAsUser here would bypass the behavior this fixture tests.
    if empty then RemovePilot(unit) end
    SetObjectiveName(unit, name)
    SetObjectiveOn(unit)
    return unit
end

function Test.Spawn()
    local unit, reason = spawn("avpsav", 20, "Boardable Fury Test", true)
    if not unit then return nil, reason end
    print("[CRSAVTest] Spawned empty avpsav. Hop out, enter on foot, then test deploy/land/hop-out/re-entry.")
    return unit
end

function Test.SpawnPickup()
    local unit, reason = spawn("avrsav", 80, "Fury Pickup Test", false)
    if not unit then return nil, reason end
    print("[CRSAVTest] Spawned occupied avrsav. On foot, try Pick me up; RequestPickup(unit) tests the native order separately.")
    return unit
end

function Test.RequestPickup(unit)
    local player, reason = localPlayer()
    if not player then return nil, reason end
    if not IsPerson(player) then return nil, "Player must be on foot" end
    if not unit or not IsValid(unit) then return nil, "No pickup Fury" end
    -- Restrict the experimental controller path to our explicit fixture.
    local odf = string.lower(GetOdf(unit) or ""):gsub("%.odf$", "")
    if odf ~= "avrsav" or GetClassLabel(unit) ~= "sav" then
        return nil, "Target must be the avrsav pickup fixture"
    end
    if GetTeamNum(unit) ~= GetTeamNum(player) then return nil, "Pickup Fury must be on the player's team" end
    if not CanCommand(unit) then return nil, "Pickup Fury is not commandable" end
    if not AiCommand or not AiCommand.RESCUE then return nil, "Native RESCUE command unavailable" end
    -- Ordinary player priority: retain command-menu access during the test.
    -- Issuing the order does not prove that native landing/abandon completes.
    SetCommand(unit, AiCommand.RESCUE, 0, player)
    return true
end

return Test
