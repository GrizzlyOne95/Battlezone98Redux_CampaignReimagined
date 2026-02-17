-- DiffUtils.lua
---@diagnostic disable: lowercase-global, undefined-global
-- Centralized Difficulty Scaling for Battlezone 98 Redux
-- Constants and helpers for Resources, Enemies, AI, and Timers.

local exu = require("exu")
local DiffUtils = {}

-- Returns a table of multipliers based on current game difficulty
-- 0: Very Easy, 1: Easy, 2: Medium, 3: Hard, 4: Very Hard
function DiffUtils.Get()
    local d = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    local m = {
        index = (d >= 0 and d <= 4) and d or 2,
        res = ({ 1.5, 1.25, 1.0, 0.75, 0.5 })[d + 1] or 1.0,
        enemy = ({ 0.5, 0.75, 1.0, 1.5, 2.0 })[d + 1] or 1.0,
        timer = ({ 1.5, 1.25, 1.0, 0.8, 0.7 })[d + 1] or 1.0,
        zeal = ({ 0.1, 0.2, 0.4, 0.8, 1.0 })[d + 1] or 0.4,
        enemyTurbo = (d >= 4),

        -- aiCore Specifics
        thumperChance = ({ 0, 5, 10, 20, 40 })[d + 1] or 10,
        mortarChance = ({ 0, 10, 20, 35, 50 })[d + 1] or 20,
        fieldChance = ({ 0, 5, 10, 15, 30 })[d + 1] or 10,
        doubleWeaponChance = ({ 0, 10, 20, 40, 80 })[d + 1] or 20,
        howitzerChance = ({ 10, 30, 50, 75, 100 })[d + 1] or 50,

        upgradeInterval = ({ 600, 400, 240, 180, 120 })[d + 1] or 240,
        wreckerInterval = ({ 1200, 900, 600, 450, 300 })[d + 1] or 600,
        pilotTopoff = ({ 2, 3, 4, 6, 8 })[d + 1] or 4,
        resourceBoost = (d >= 2), -- Medium and above get boosts

        -- New: Tactical Features
        enableWreckers = (d >= 3),     -- Hard and above
        enableParatroopers = (d >= 4), -- Very Hard
        paratrooperChance = ({ 0, 0, 10, 25, 40 })[d + 1] or 0,
        paratrooperInterval = ({ 0, 0, 600, 400, 300 })[d + 1] or 600,

        -- Player QOL (Low Difficulty)
        scavengerAssist = (d <= 1),
        stickToPlayer = (d <= 1),
        autoRescue = (d == 0),
        passiveRegen = (d <= 1),
        regenRate = ({ 50.0, 25.0, 0.0, 0.0, 0.0 })[d + 1],

        -- Unit Skill Scaling
        sniperTraining = ({ 25, 50, 75, 90, 100 })[d + 1],
        sniperStealth = ({ 0.1, 0.25, 0.5, 0.75, 1.0 })[d + 1],

        -- Auto-Repair (Low Difficulty)
        autoRepairWingmen = (d <= 1),

        -- Unit Caps (Difficulty based)
        unitCaps = {
            scout = ({ 1, 2, 4, 6, 8 })[d + 1],
            tank = ({ 2, 4, 8, 12, 16 })[d + 1],
            heavy = ({ 0, 1, 2, 4, 6 })[d + 1],
            siege = ({ 0, 1, 2, 4, 6 })[d + 1],
            bomber = ({ 0, 1, 2, 4, 6 })[d + 1],
            apc = ({ 0, 1, 2, 3, 4 })[d + 1],
            missile = ({ 1, 2, 3, 4, 6 })[d + 1],
            tower = ({ 2, 4, 6, 10, 15 })[d + 1],
            minelayer = ({ 0, 1, 2, 3, 4 })[d + 1]
        }
    }
    return m
end

-- Scales a value by the relevant multiplier
function DiffUtils.ScaleRes(val) return math.floor(val * DiffUtils.Get().res) end

function DiffUtils.ScaleEnemy(val) return math.ceil(val * DiffUtils.Get().enemy) end

function DiffUtils.ScaleTimer(val) return val * DiffUtils.Get().timer end

-- Standard Player/Enemy Setup for aiCore
function DiffUtils.SetupTeams(playerFaction, enemyFaction, enemyTeamNum)
    local m = DiffUtils.Get()

    -- Player Team (Smarter Allies + Helping Hands)
    local playerTeam = aiCore.AddTeam(1, playerFaction)
    playerTeam:SetConfig("pilotZeal", 1.0)
    playerTeam:SetConfig("scavengerAssist", m.scavengerAssist)
    playerTeam:SetConfig("stickToPlayer", m.stickToPlayer)
    playerTeam:SetConfig("autoRescue", m.autoRescue)
    playerTeam:SetConfig("passiveRegen", m.passiveRegen)
    playerTeam:SetConfig("regenRate", m.regenRate)
    playerTeam:SetConfig("autoRepairWingmen", m.autoRepairWingmen)

    -- Enemy Team (Adaptive zeal & settings)
    local enemyTeam = aiCore.AddTeam(enemyTeamNum or 2, enemyFaction)
    enemyTeam:SetConfig("pilotZeal", m.zeal)
    enemyTeam:SetConfig("thumperChance", m.thumperChance)
    enemyTeam:SetConfig("mortarChance", m.mortarChance)
    enemyTeam:SetConfig("fieldChance", m.fieldChance)
    enemyTeam:SetConfig("doubleWeaponChance", m.doubleWeaponChance)
    enemyTeam:SetConfig("howitzerChance", m.howitzerChance)
    enemyTeam:SetConfig("upgradeInterval", m.upgradeInterval)
    enemyTeam:SetConfig("wreckerInterval", m.wreckerInterval)
    enemyTeam:SetConfig("pilotTopoff", m.pilotTopoff)
    enemyTeam:SetConfig("resourceBoost", m.resourceBoost)
    enemyTeam:SetConfig("unitCaps", m.unitCaps)

    -- New: Difficulty Features
    enemyTeam:SetConfig("enableWreckers", m.enableWreckers)
    enemyTeam:SetConfig("enableParatroopers", m.enableParatroopers)
    enemyTeam:SetConfig("paratrooperChance", m.paratrooperChance)
    enemyTeam:SetConfig("paratrooperInterval", m.paratrooperInterval)

    -- Enemy Skill Settings
    enemyTeam:SetConfig("sniperTraining", m.sniperTraining)
    enemyTeam:SetConfig("sniperStealth", m.sniperStealth)

    -- Global Environment
    if exu then
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end

    return playerTeam, enemyTeam
end

return DiffUtils
