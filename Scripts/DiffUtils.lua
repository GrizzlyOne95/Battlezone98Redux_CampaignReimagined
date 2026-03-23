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
        timer = ({ 1.5, 1.25, 1.0, 0.75, 0.5 })[d + 1] or 1.0,
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
        sniperTimeout = ({ 10.0, 9.0, 8.0, 7.0, 6.0 })[d + 1] or 8.0,
        soldierRange = ({ 40, 45, 50, 60, 70 })[d + 1] or 50,
        flankFormationRushChance = ({ 10, 20, 40, 55, 70 })[d + 1] or 40,
        resourceBoost = (d >= 2), -- Medium and above get boosts

        -- Tactical/Strategic AI
        scavengerCount = ({ 2, 3, 4, 5, 6 })[d + 1] or 4,
        minScavengers = ({ 0, 0, 1, 2, 2 })[d + 1] or 0,
        tacticalRecomputeInterval = ({ 12.0, 10.0, 8.0, 6.0, 5.0 })[d + 1] or 8.0,
        tacticalThreatPriority = ({ 120.0, 135.0, 150.0, 175.0, 190.0 })[d + 1] or 150.0,
        tacticalDistancePriority = ({ 4.0, 3.5, 3.0, 2.5, 2.2 })[d + 1] or 3.0,
        tacticalDefendBuildingsPriority = ({ 24.0, 28.0, 30.0, 34.0, 38.0 })[d + 1] or 30.0,
        tacticalAttackEnemyBasePriority = ({ 55.0, 65.0, 75.0, 90.0, 105.0 })[d + 1] or 75.0,
        tacticalPersistencePriority = ({ 18.0, 24.0, 30.0, 36.0, 42.0 })[d + 1] or 30.0,
        tacticalScriptedPriority = ({ 40.0, 45.0, 50.0, 62.0, 75.0 })[d + 1] or 50.0,
        tacticalMinMatchingForceRatio = ({ 1.35, 1.20, 1.00, 0.90, 0.80 })[d + 1] or 1.0,
        tacticalMaxMatchingForceRatio = ({ 2.00, 2.10, 2.25, 2.35, 2.50 })[d + 1] or 2.25,
        tacticalBuildingDefenseForceMin = ({ 1.20, 1.10, 1.00, 0.90, 0.80 })[d + 1] or 1.0,
        tacticalBuildingDefenseForceMax = ({ 1.80, 1.90, 2.00, 2.15, 2.30 })[d + 1] or 2.0,
        tacticalThreatRadius = ({ 180.0, 200.0, 220.0, 250.0, 280.0 })[d + 1] or 220.0,
        tacticalGoalRadius = ({ 240.0, 250.0, 260.0, 280.0, 300.0 })[d + 1] or 260.0,
        tacticalMinSquadUnits = ({ 2, 2, 3, 3, 4 })[d + 1] or 3,
        tacticalMaxSquadUnits = ({ 4, 4, 5, 6, 6 })[d + 1] or 5,
        tacticalDefenseBias = ({ 22.0, 18.0, 15.0, 12.0, 9.0 })[d + 1] or 15.0,
        tacticalRelaxationCycles = ({ 1, 1, 2, 2, 3 })[d + 1] or 2,
        tacticalRelaxationStep = ({ 220.0, 200.0, 180.0, 170.0, 160.0 })[d + 1] or 180.0,
        tacticalRelaxationCoefficient = ({ 0.25, 0.35, 0.45, 0.55, 0.65 })[d + 1] or 0.45,
        strategicFsmInterval = ({ 28.0, 22.0, 18.0, 14.0, 10.0 })[d + 1] or 18.0,
        strategicPressureThreshold = ({ 5.5, 4.8, 4.0, 3.4, 3.0 })[d + 1] or 4.0,
        strategicSiegeTime = ({ 1200.0, 1050.0, 900.0, 750.0, 600.0 })[d + 1] or 900.0,
        strategicRecoverScrapRatio = ({ 0.35, 0.28, 0.22, 0.18, 0.15 })[d + 1] or 0.22,
        strategicAttackRatio = ({ 1.35, 1.25, 1.15, 1.05, 0.95 })[d + 1] or 1.15,
        strategicRecoverRatio = ({ 1.00, 0.85, 0.72, 0.62, 0.55 })[d + 1] or 0.72,
        buildAccountBias = ({ 1.4, 1.8, 2.2, 2.8, 3.2 })[d + 1] or 2.2,
        buildAccountSpendDecay = ({ 0.05, 0.07, 0.09, 0.12, 0.15 })[d + 1] or 0.09,
        buildAccountSpendScale = ({ 24.0, 20.0, 18.0, 15.0, 12.0 })[d + 1] or 18.0,

        -- Scrap Economy
        scrapHotspotInterval = ({ 18.0, 15.0, 12.0, 9.0, 7.0 })[d + 1] or 12.0,
        scrapHotspotMinValue = ({ 12.0, 10.0, 8.0, 7.0, 6.0 })[d + 1] or 8.0,
        scrapHotspotBattleWeight = ({ 1.0, 1.2, 1.4, 1.7, 2.0 })[d + 1] or 1.4,
        scrapHotspotSiloValue = ({ 20.0, 17.0, 14.0, 12.0, 10.0 })[d + 1] or 14.0,
        scrapHotspotSiloDropoffDistance = ({ 320.0, 290.0, 260.0, 230.0, 210.0 })[d + 1] or 260.0,
        scrapDenyRadius = ({ 110.0, 135.0, 160.0, 190.0, 220.0 })[d + 1] or 160.0,
        scrapHotspotExtraScavengerValue = ({ 24.0, 20.0, 16.0, 12.0, 10.0 })[d + 1] or 16.0,
        scrapHotspotExtraScavengerStep = ({ 14.0, 12.0, 10.0, 8.0, 7.0 })[d + 1] or 10.0,
        scrapHotspotMaxExtraScavengers = ({ 1, 2, 3, 4, 5 })[d + 1] or 3,

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
            lighttank = ({ 1, 2, 4, 6, 8 })[d + 1],
            tank = ({ 2, 4, 8, 12, 16 })[d + 1],
            rockettank = ({ 1, 2, 3, 5, 7 })[d + 1],
            walker = ({ 0, 1, 2, 4, 6 })[d + 1],
            heavy = ({ 0, 1, 2, 4, 6 })[d + 1],
            howitzer = ({ 0, 1, 2, 4, 6 })[d + 1],
            siege = ({ 0, 1, 2, 4, 6 })[d + 1],
            bomber = ({ 0, 1, 2, 4, 6 })[d + 1],
            apc = ({ 0, 1, 2, 3, 4 })[d + 1],
            missile = ({ 1, 2, 3, 4, 6 })[d + 1],
            scavenger = ({ 2, 3, 5, 7, 9 })[d + 1],
            tug = ({ 0, 1, 2, 2, 3 })[d + 1],
            turret = ({ 2, 4, 6, 10, 15 })[d + 1],
            tower = ({ 2, 4, 6, 10, 15 })[d + 1],
            minelayer = ({ 0, 1, 2, 3, 4 })[d + 1]
        },

        -- Player-rule caps, optionally handicapped on lower difficulties.
        slotCaps = {
            offense = ({ 6, 8, 10, 10, 10 })[d + 1],
            defense = ({ 6, 8, 10, 10, 10 })[d + 1],
            utility = ({ 6, 8, 10, 10, 10 })[d + 1],
            recycler = 1,
            factory = 1,
            armory = 1,
            constructor = 1
        },
        buildingCaps = {
            power = ({ 4, 5, 6, 7, 7 })[d + 1],
            comm = ({ 3, 4, 5, 6, 7 })[d + 1],
            repair = ({ 3, 4, 5, 6, 7 })[d + 1],
            supply = ({ 3, 4, 5, 6, 7 })[d + 1],
            silo = ({ 4, 5, 6, 7, 7 })[d + 1],
            barracks = ({ 2, 3, 4, 5, 6 })[d + 1],
            guntower = ({ 4, 5, 6, 7, 7 })[d + 1]
        }
    }
    return m
end

local function SetTeamConfig(team, key, value)
    if team and team.SetConfig and value ~= nil then
        team:SetConfig(key, value)
    end
end

function DiffUtils.ApplyAiCoreDifficulty(team, role, teamNum)
    if not team or not team.SetConfig then return nil end

    local m = DiffUtils.Get()
    local resolvedRole = role
    if resolvedRole == nil then
        local resolvedTeamNum = teamNum
        if resolvedTeamNum == nil and team.teamNum ~= nil then
            resolvedTeamNum = team.teamNum
        end
        resolvedRole = (resolvedTeamNum == 1) and "player" or "enemy"
    end

    SetTeamConfig(team, "difficulty", m.index)

    if resolvedRole == "player" then
        SetTeamConfig(team, "pilotZeal", 1.0)
        SetTeamConfig(team, "scavengerAssist", m.scavengerAssist)
        SetTeamConfig(team, "stickToPlayer", m.stickToPlayer)
        SetTeamConfig(team, "autoRescue", m.autoRescue)
        SetTeamConfig(team, "passiveRegen", m.passiveRegen)
        SetTeamConfig(team, "regenRate", m.regenRate)
        SetTeamConfig(team, "autoRepairWingmen", m.autoRepairWingmen)
        return m
    end

    SetTeamConfig(team, "pilotZeal", m.zeal)
    SetTeamConfig(team, "thumperChance", m.thumperChance)
    SetTeamConfig(team, "mortarChance", m.mortarChance)
    SetTeamConfig(team, "fieldChance", m.fieldChance)
    SetTeamConfig(team, "doubleWeaponChance", m.doubleWeaponChance)
    SetTeamConfig(team, "howitzerChance", m.howitzerChance)
    SetTeamConfig(team, "upgradeInterval", m.upgradeInterval)
    SetTeamConfig(team, "wreckerInterval", m.wreckerInterval)
    SetTeamConfig(team, "pilotTopoff", m.pilotTopoff)
    SetTeamConfig(team, "sniperTimeout", m.sniperTimeout)
    SetTeamConfig(team, "soldierRange", m.soldierRange)
    SetTeamConfig(team, "flankFormationRushChance", m.flankFormationRushChance)
    SetTeamConfig(team, "resourceBoost", m.resourceBoost)
    SetTeamConfig(team, "scavengerCount", m.scavengerCount)
    SetTeamConfig(team, "minScavengers", m.minScavengers)
    SetTeamConfig(team, "tacticalRecomputeInterval", m.tacticalRecomputeInterval)
    SetTeamConfig(team, "tacticalThreatPriority", m.tacticalThreatPriority)
    SetTeamConfig(team, "tacticalDistancePriority", m.tacticalDistancePriority)
    SetTeamConfig(team, "tacticalDefendBuildingsPriority", m.tacticalDefendBuildingsPriority)
    SetTeamConfig(team, "tacticalAttackEnemyBasePriority", m.tacticalAttackEnemyBasePriority)
    SetTeamConfig(team, "tacticalPersistencePriority", m.tacticalPersistencePriority)
    SetTeamConfig(team, "tacticalScriptedPriority", m.tacticalScriptedPriority)
    SetTeamConfig(team, "tacticalMinMatchingForceRatio", m.tacticalMinMatchingForceRatio)
    SetTeamConfig(team, "tacticalMaxMatchingForceRatio", m.tacticalMaxMatchingForceRatio)
    SetTeamConfig(team, "tacticalBuildingDefenseForceMin", m.tacticalBuildingDefenseForceMin)
    SetTeamConfig(team, "tacticalBuildingDefenseForceMax", m.tacticalBuildingDefenseForceMax)
    SetTeamConfig(team, "tacticalThreatRadius", m.tacticalThreatRadius)
    SetTeamConfig(team, "tacticalGoalRadius", m.tacticalGoalRadius)
    SetTeamConfig(team, "tacticalMinSquadUnits", m.tacticalMinSquadUnits)
    SetTeamConfig(team, "tacticalMaxSquadUnits", m.tacticalMaxSquadUnits)
    SetTeamConfig(team, "tacticalDefenseBias", m.tacticalDefenseBias)
    SetTeamConfig(team, "tacticalRelaxationCycles", m.tacticalRelaxationCycles)
    SetTeamConfig(team, "tacticalRelaxationStep", m.tacticalRelaxationStep)
    SetTeamConfig(team, "tacticalRelaxationCoefficient", m.tacticalRelaxationCoefficient)
    SetTeamConfig(team, "strategicFsmInterval", m.strategicFsmInterval)
    SetTeamConfig(team, "strategicPressureThreshold", m.strategicPressureThreshold)
    SetTeamConfig(team, "strategicSiegeTime", m.strategicSiegeTime)
    SetTeamConfig(team, "strategicRecoverScrapRatio", m.strategicRecoverScrapRatio)
    SetTeamConfig(team, "strategicAttackRatio", m.strategicAttackRatio)
    SetTeamConfig(team, "strategicRecoverRatio", m.strategicRecoverRatio)
    SetTeamConfig(team, "buildAccountBias", m.buildAccountBias)
    SetTeamConfig(team, "buildAccountSpendDecay", m.buildAccountSpendDecay)
    SetTeamConfig(team, "buildAccountSpendScale", m.buildAccountSpendScale)
    SetTeamConfig(team, "scrapHotspotInterval", m.scrapHotspotInterval)
    SetTeamConfig(team, "scrapHotspotMinValue", m.scrapHotspotMinValue)
    SetTeamConfig(team, "scrapHotspotBattleWeight", m.scrapHotspotBattleWeight)
    SetTeamConfig(team, "scrapHotspotSiloValue", m.scrapHotspotSiloValue)
    SetTeamConfig(team, "scrapHotspotSiloDropoffDistance", m.scrapHotspotSiloDropoffDistance)
    SetTeamConfig(team, "scrapDenyRadius", m.scrapDenyRadius)
    SetTeamConfig(team, "scrapHotspotExtraScavengerValue", m.scrapHotspotExtraScavengerValue)
    SetTeamConfig(team, "scrapHotspotExtraScavengerStep", m.scrapHotspotExtraScavengerStep)
    SetTeamConfig(team, "scrapHotspotMaxExtraScavengers", m.scrapHotspotMaxExtraScavengers)
    SetTeamConfig(team, "unitCaps", m.unitCaps)
    SetTeamConfig(team, "slotCaps", m.slotCaps)
    SetTeamConfig(team, "buildingCaps", m.buildingCaps)

    SetTeamConfig(team, "enableWreckers", m.enableWreckers)
    SetTeamConfig(team, "enableParatroopers", m.enableParatroopers)
    SetTeamConfig(team, "paratrooperChance", m.paratrooperChance)
    SetTeamConfig(team, "paratrooperInterval", m.paratrooperInterval)
    SetTeamConfig(team, "sniperTraining", m.sniperTraining)
    SetTeamConfig(team, "sniperStealth", m.sniperStealth)

    return m
end

-- Scales a value by the relevant multiplier
function DiffUtils.ScaleRes(val) return math.floor(val * DiffUtils.Get().res) end

function DiffUtils.ScaleEnemy(val) return math.ceil(val * DiffUtils.Get().enemy) end

function DiffUtils.ScaleTimer(val) return val * DiffUtils.Get().timer end

-- Standard Player/Enemy Setup for aiCore
function DiffUtils.SetupTeams(playerFaction, enemyFaction, enemyTeamNum)
    local playerTeam = aiCore.AddTeam(1, playerFaction)
    local enemyTeam = aiCore.AddTeam(enemyTeamNum or 2, enemyFaction)

    DiffUtils.ApplyAiCoreDifficulty(playerTeam, "player", 1)
    DiffUtils.ApplyAiCoreDifficulty(enemyTeam, "enemy", enemyTeamNum or 2)

    -- Global Environment
    if exu then
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end

    return playerTeam, enemyTeam
end

return DiffUtils
