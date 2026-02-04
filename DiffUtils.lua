-- DiffUtils.lua
-- Centralized Difficulty Scaling for Battlezone 98 Redux
-- Constants and helpers for Resources, Enemies, AI, and Timers.

local DiffUtils = {}

-- Returns a table of multipliers based on current game difficulty
-- 0: Very Easy, 1: Easy, 2: Medium, 3: Hard, 4: Very Hard
function DiffUtils.Get()
    local d = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    return {
        index = d,
        res = ({1.5, 1.25, 1.0, 0.75, 0.5})[d+1] or 1.0,
        enemy = ({0.5, 0.75, 1.0, 1.5, 2.0})[d+1] or 1.0,
        timer = ({1.5, 1.25, 1.0, 0.8, 0.7})[d+1] or 1.0,
        zeal = ({0.1, 0.2, 0.4, 0.8, 1.0})[d+1] or 0.4,
        enemyTurbo = (d >= 4)
    }
end

-- Scales a value by the relevant multiplier
function DiffUtils.ScaleRes(val) return math.floor(val * DiffUtils.Get().res) end
function DiffUtils.ScaleEnemy(val) return math.ceil(val * DiffUtils.Get().enemy) end
function DiffUtils.ScaleTimer(val) return val * DiffUtils.Get().timer end

-- Standard Player/Enemy Setup for aiCore
function DiffUtils.SetupTeams(playerFaction, enemyFaction, enemyTeamNum)
    local m = DiffUtils.Get()
    
    -- Player Team (Smarter Allies)
    local playerTeam = aiCore.AddTeam(1, playerFaction)
    playerTeam:SetConfig("pilotZeal", 1.0)
    
    -- Enemy Team (Adaptive Zeal)
    local enemyTeam = aiCore.AddTeam(enemyTeamNum or 2, enemyFaction)
    enemyTeam:SetConfig("pilotZeal", m.zeal)
    
    -- Global Environment
    if exu then
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    
    return playerTeam, enemyTeam
end

return DiffUtils
