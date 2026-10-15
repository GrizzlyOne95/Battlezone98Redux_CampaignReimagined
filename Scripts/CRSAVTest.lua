-- Explicit, offline-only prototype fixture. No mission loads this automatically.
local Test = {}

function Test.Spawn()
    if IsNetGame() then
        return nil, "SAV boarding prototype is offline-only"
    end
    local player = GetPlayerHandle()
    if not player or not IsValid(player) then
        return nil, "No local player"
    end
    local position = GetPosition(player)
    local where = SetVector(position.x + 20, position.y, position.z)
    local unit = BuildObject("avpsav", GetTeamNum(player), where)
    if not unit or not IsValid(unit) then
        return nil, "Could not create avpsav"
    end
    -- Enter by collision while on foot: the engine records the real pilot.
    -- Forcing SetAsUser here would bypass the behavior this fixture tests.
    RemovePilot(unit)
    SetObjectiveName(unit, "Boardable Fury Test")
    SetObjectiveOn(unit)
    print("[CRSAVTest] Spawned empty avpsav. Hop out, enter on foot, then test deploy/land/hop-out/re-entry.")
    return unit
end

return Test
