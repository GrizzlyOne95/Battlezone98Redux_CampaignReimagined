-- aiCore.lua
-- Consolidated AI System for Battlezone 98 Redux
-- Combines functionality from aiFacProd, aiRecProd, aiBuildOS, and aiSpecial
-- Supported Factions: NSDF, CCA, CRA, BDOG

aiCore = {}
aiCore.Debug = false

function aiCore.Save()
    return aiCore.ActiveTeams
end

function aiCore.Load(data)
    if not data then return end
    aiCore.ActiveTeams = data
    
    -- Restore Metatables
    for _, team in pairs(aiCore.ActiveTeams) do
        setmetatable(team, aiCore.Team)
        if team.recyclerMgr then setmetatable(team.recyclerMgr, aiCore.FactoryManager) end
        if team.factoryMgr then setmetatable(team.factoryMgr, aiCore.FactoryManager) end
        if team.constructorMgr then setmetatable(team.constructorMgr, aiCore.ConstructorManager) end
    end
end


----------------------------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
----------------------------------------------------------------------------------

aiCore.Factions = {NSDF = 1, CCA = 2, CRA = 3, BDOG = 4}
aiCore.FactionNames = {[1] = "NSDF", [2] = "CCA", [3] = "CRA", [4] = "BDOG"}

-- Unit ODF Tables (Consolidated)
aiCore.Units = {}

aiCore.Units[aiCore.Factions.NSDF] = {
    -- Buildings
    recycler = "avrecy", factory = "avmuf", armory = "avslf", constructor = "avcnst",
    sPower = "abspow", lPower = "ablpow", wPower = "abwpow",
    gunTower = "abtowe", gunTower2 = "abtowe", 
    silo = "absilo", supply = "absupp", hangar = "abhang",
    barracks = "abbarr", commTower = "abcomm", hq = "abhqcp",
    -- Units
    scavenger = "avscav", turret = "avturr", scout = "avfigh",
    tank = "avtank", lighttank = "avltnk", tug = "avhaul",
    howitzer = "avartl", minelayer = "avmine", rockettank = "avrckt",
    apc = "avapc", bomber = "avhraz", walker = "avwalk",
    unique = "avltmp", ammobot = "ammobot", repair = "aprepa",
    ammo = "apammo"
}

aiCore.Units[aiCore.Factions.CCA] = {
    recycler = "svrecy", factory = "svmuf", armory = "svslf", constructor = "svcnst",
    sPower = "sbspow", lPower = "sblpow", wPower = "sbwpow",
    gunTower = "sbtowe", gunTower2 = "sbtowe",
    silo = "sbsilo", supply = "sbsupp", hangar = "sbhang",
    barracks = "sbbarr", commTower = "sbcomm", hq = "sbhqcp",
    scavenger = "svscav", turret = "svturr", scout = "svfigh",
    tank = "svtank", lighttank = "svltnk", tug = "svhaul",
    howitzer = "svartl", minelayer = "svmine", rockettank = "svrckt",
    apc = "svapc", bomber = "svhraz", walker = "svwalk",
    unique = "svwamp", ammobot = "ammobot", repair = "aprepa",
    ammo = "apammo"
}

aiCore.Units[aiCore.Factions.CRA] = {
    recycler = "cvrecyia", factory = "cvmufia", armory = "cvslf", constructor = "cvcnst",
    sPower = "cbspow", lPower = "cblpow", wPower = "cbwpow",
    gunTower = "cbtowe", gunTower2 = "cblasr",
    silo = "cbsilo", supply = "cbmbld", hangar = "cbhang",
    barracks = "cbbarr", commTower = "cbcomm", hq = "cbhqcp",
    scavenger = "cvscav", turret = "cvturr", scout = "cvfigh",
    tank = "cvtnk", lighttank = "cvltnk", tug = "cvhaul",
    howitzer = "cvartl", minelayer = "cvmine", rockettank = "cvrckt",
    apc = "cvapc", bomber = "cvhraz", walker = "cvwalk",
    unique = "cvhtnk", ammobot = "ammobot", repair = "aprepa",
    ammo = "apammo"
}

aiCore.Units[aiCore.Factions.BDOG] = {
    recycler = "bvrecyia", factory = "bvmufia", armory = "bvslf", constructor = "bvcnstia",
    sPower = "bbspow", lPower = "bblpow", wPower = "bbwpow",
    gunTower = "bbtowe", gunTower2 = "bbtowe",
    silo = "bbsilo", supply = "bbmbld", hangar = "bbhang",
    barracks = "bbbarr", commTower = "bbcomm", hq = "bbhqcp",
    scavenger = "bvscav", turret = "bvturr", scout = "bvfigh",
    tank = "bvtank", lighttank = "bvltnk", tug = "bvhaul",
    howitzer = "bvartl", minelayer = "bvmine", rockettank = "bvrckt",
    apc = "bvapc", bomber = "bvhraz", walker = "bvwalk",
    unique = "bvrdev", ammobot = "ammobot", repair = "aprepa",
    ammo = "apammo"
}

-- Tactical AIP Strategies (from aiSpecial)
-- These lists define unit composition priorities for different strategies
aiCore.Strategies = {
    Balanced = {
        Recycler = {"turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"howitzer", "unique", "unique", "rockettank", "rockettank", "bomber", "bomber", "bomber", "apc", "apc", "lighttank", "lighttank", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "tank", "tank", "minelayer"}
    },
    APC_Heavy = {
        Recycler = {"scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"walker", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc", "apc"}
    },
    Tank_Heavy = {
        Recycler = {"scout", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"rockettank", "unique", "lighttank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank", "tank"}
    },
    Light_Force = {
        Recycler = {"scout", "scout", "scout", "scout", "scout", "turret", "turret", "turret", "turret", "scout", "scout", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"rockettank", "rockettank", "rockettank", "rockettank", "scout", "scout", "scout", "scout", "scout", "lighttank", "minelayer", "lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "tank"}
    },
    Howitzer_Heavy = {
        Recycler = {"scout", "turret", "turret", "turret", "turret", "scout", "scout", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"rockettank", "rockettank", "rockettank", "lighttank", "lighttank", "lighttank", "scout", "scout", "scout", "tank", "minelayer", "tank", "tank", "howitzer", "howitzer", "howitzer", "howitzer", "howitzer", "howitzer"}
    },
    Bomber_Heavy = {
        Recycler = {"scout", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"unique", "apc", "lighttank", "scout", "scout", "scout", "tank", "tank", "tank", "tank", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber", "bomber"}
    },
    Rocket_Heavy = {
        Recycler = {"scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"lighttank", "lighttank", "lighttank", "lighttank", "lighttank", "scout", "scout", "bomber", "bomber", "bomber", "bomber", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank", "rockettank"}
    },
    Mine_Heavy = {
        Recycler = {"scout", "scout", "turret", "turret", "turret", "turret", "turret", "turret", "turret", "turret", "scout", "scout", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger", "scavenger"},
        Factory = {"howitzer", "walker", "walker", "unique", "unique", "unique", "unique", "lighttank", "scout", "tank", "tank", "tank", "minelayer", "minelayer", "minelayer", "minelayer", "minelayer", "minelayer"}
    }
}

----------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------------------------

function aiCore.GetNearestInTable(h, table)
    if next(table) ~= nil then
        local nearest = nil
        local minDist = 999999
        for i=1, #table do
            if IsValid(table[i]) then
                local d = GetDistance(h, table[i])
                if d < minDist then
                    minDist = d
                    nearest = table[i]
                end
            end
        end
        return nearest
    end
    return nil
end

function aiCore.RemoveDead(tbl)
    for i = #tbl, 1, -1 do
        if not IsAlive(tbl[i]) then
            table.remove(tbl, i)
        end
    end
end

function aiCore.NilToString(s)
    if s == nil then return "NIL" end
    return s
end

function aiCore.Lift(h, height)
    if not IsValid(h) then return end
    local pos = GetPosition(h)
    pos.y = pos.y + height
    SetPosition(h, pos)
end

function aiCore.GuessPilotOdf(barracksHandle)
    local pilotOdf = "aspilo"
    local fac = GetOdf(barracksHandle)
    local prefix = string.sub(fac,1,1)
    local guessed = prefix .. "spilo"
    if OpenODF(guessed) then
        return guessed
    end
    return pilotOdf
end

-- Vector Helpers
function aiCore.GetFlankPosition(target, dist, angleDeg)
    if not IsValid(target) then return nil end
    local tPos = GetPosition(target)
    local rad = math.rad(angleDeg)
    return {
        x = tPos.x + math.cos(rad) * dist,
        y = tPos.y, -- Assume flat for now, or use GetTerrainHeight
        z = tPos.z + math.sin(rad) * dist
    }
end

-- Vector Helpers
function aiCore.GetFlankPosition(target, dist, angleDeg)
    if not IsValid(target) then return nil end
    local tPos = GetPosition(target)
    local rad = math.rad(angleDeg)
    return {
        x = tPos.x + math.cos(rad) * dist,
        y = tPos.y, -- Assume flat for now, or use GetTerrainHeight
        z = tPos.z + math.sin(rad) * dist
    }
end


----------------------------------------------------------------------------------
-- CLASSES
----------------------------------------------------------------------------------

-- Generic Build Queue Item
aiCore.BuildItem = {
    odf = "",
    priority = 0,
    path = nil -- for constructor builds
}
aiCore.BuildItem.__index = aiCore.BuildItem

-- Factory Manager (Handles Factory & Recycler Unit Production)
aiCore.FactoryManager = {
    handle = nil,
    team = 0,
    queue = {},
    pulseTimer = 0.0,
    pulsePeriod = 3.0,
    isRecycler = false
}
aiCore.FactoryManager.__index = aiCore.FactoryManager

function aiCore.FactoryManager:new(team, isRecycler)
    local fm = setmetatable({}, self)
    fm.team = team
    fm.isRecycler = isRecycler
    fm.queue = {}
    return fm
end

function aiCore.FactoryManager:update()
    if not IsValid(self.handle) then
        if self.isRecycler then
            self.handle = GetRecyclerHandle(self.team)
        else
            self.handle = GetFactoryHandle(self.team)
        end
        return
    end

    if #self.queue == 0 then return end

    if CanBuild(self.handle) and IsDeployed(self.handle) and not IsBusy(self.handle) then
        local item = self.queue[1]
        local scrapCost = GetODFInt(OpenODF(item.odf),"GameObjectClass","scrapCost")
        
        if GetScrap(self.team) >= scrapCost then
            if GetTime() > self.pulseTimer then
                Build(self.handle, item.odf, 0)
                self.pulseTimer = GetTime() + self.pulsePeriod + math.random(-1, 1)
                
                if aiCore.Debug then print("Team " .. self.team .. " building " .. item.odf) end
                
                -- We remove from queue when the unit is successfully added to the world via AddObject
                -- But to prevent spam-building the same thing if logic fails, we cycle or wait
                -- For now, relying on external management (Team class) to manage the list
                -- This queue is just "what to build next"
                
            end
        end
    end
end

-- Constructor Manager
aiCore.ConstructorManager = {
    handle = nil,
    team = 0,
    queue = {},
    pulseTimer = 0.0,
    pulsePeriod = 8.0,
    sentToRecycler = false
}
aiCore.ConstructorManager.__index = aiCore.ConstructorManager

function aiCore.ConstructorManager:new(team)
    local cm = setmetatable({}, self)
    cm.team = team
    cm.queue = {}
    return cm
end

function aiCore.ConstructorManager:update()
    if not IsValid(self.handle) then
        self.handle = GetConstructorHandle(self.team)
        self.sentToRecycler = false
        return
    end

    if #self.queue == 0 then
        -- Return to recycler if idle
        local recycler = GetRecyclerHandle(self.team)
        if IsValid(recycler) and not self.sentToRecycler then
            if GetDistance(self.handle, recycler) > 50 then
                Goto(self.handle, recycler, 0)
                self.sentToRecycler = true
            end
        end
        return
    end

    self.sentToRecycler = false
    local item = self.queue[1]

    if CanBuild(self.handle) and not IsBusy(self.handle) then
        local dist = GetDistance(self.handle, item.path)
        if dist > 60 then
            if not string.match(aiCore.NilToString(AiCommand[GetCurrentCommand(self.handle)]), "GO") then
                Goto(self.handle, item.path, 0)
            end
        else
            -- Check for existing buildings or blocking
            local existing = false
            for obj in ObjectsInRange(40, item.path) do
                if IsOdf(obj, item.odf) and GetTeamNum(obj) == self.team then
                    existing = true
                    break
                end
            end

            if existing then
                table.remove(self.queue, 1) -- Remove if already built
            else
                local scrapCost = GetODFInt(OpenODF(item.odf),"GameObjectClass","scrapCost")
                if GetScrap(self.team) >= scrapCost and GetTime() > self.pulseTimer then
                    Build(self.handle, item.odf, 1) -- Drop building here
                    self.pulseTimer = GetTime() + self.pulsePeriod
                end
            end
        end
    end
end

end

-- Squad Class (Formations & Flanking)
aiCore.Squad = {
    leader = nil,
    members = {},
    state = "idling", -- idling, moving_to_flank, attacking
    targetPos = nil,
    formation = "V",
    maxSize = 3
}
aiCore.Squad.__index = aiCore.Squad

function aiCore.Squad:new(leader)
    local s = setmetatable({}, self)
    s.leader = leader
    s.members = {}
    return s
end

function aiCore.Squad:AddMember(h)
    table.insert(self.members, h)
    -- Order follow
    if IsValid(self.leader) then
        Follow(h, self.leader, 0)
    end
end

function aiCore.Squad:Update()
    if not IsValid(self.leader) then
        -- Promote new leader if possible
        if #self.members > 0 then
            self.leader = table.remove(self.members, 1)
            -- Re-order followers
            for _, m in ipairs(self.members) do
                if IsValid(m) then Follow(m, self.leader, 0) end
            end
        else
            return false -- Dead squad
        end
    end
    
    -- State Machine
    if self.state == "moving_to_flank" then
        if self.targetPos then
            if GetDistance(self.leader, self.targetPos) < 60 then
                self.state = "attacking"
                -- Find nearest enemy to flank pos
                local enemy = GetNearestEnemy(self.leader)
                if IsValid(enemy) then
                    Attack(self.leader, enemy)
                    for _, m in ipairs(self.members) do Attack(m, enemy) end
                end
            else
                 -- Ensure moving
                 if not string.match(aiCore.NilToString(AiCommand[GetCurrentCommand(self.leader)]), "GO") then
                    Goto(self.leader, self.targetPos)
                 end
            end
        end
    elseif self.state == "attacking" then
        -- If idle, attack nearest
        if not IsBusy(self.leader) then
             local enemy = GetNearestEnemy(self.leader)
             if IsValid(enemy) then
                Attack(self.leader, enemy)
                for _, m in ipairs(self.members) do Attack(m, enemy) end
             end
        end
    end
    
    return true
end

-- Squad Class (Formations & Flanking)
aiCore.Squad = {
    leader = nil,
    members = {},
    state = "idling", -- idling, moving_to_flank, attacking
    targetPos = nil,
    formation = "V",
    maxSize = 3
}
aiCore.Squad.__index = aiCore.Squad

function aiCore.Squad:new(leader)
    local s = setmetatable({}, self)
    s.leader = leader
    s.members = {}
    return s
end

function aiCore.Squad:AddMember(h)
    table.insert(self.members, h)
    -- Order follow
    if IsValid(self.leader) then
        Follow(h, self.leader, 0)
    end
end

function aiCore.Squad:Update()
    if not IsValid(self.leader) then
        -- Promote new leader if possible
        if #self.members > 0 then
            self.leader = table.remove(self.members, 1)
            -- Re-order followers
            for _, m in ipairs(self.members) do
                if IsValid(m) then Follow(m, self.leader, 0) end
            end
        else
            return false -- Dead squad
        end
    end
    
    -- State Machine
    if self.state == "moving_to_flank" then
        if self.targetPos then
            if GetDistance(self.leader, self.targetPos) < 60 then
                self.state = "attacking"
                -- Find nearest enemy to flank pos
                local enemy = GetNearestEnemy(self.leader)
                if IsValid(enemy) then
                    Attack(self.leader, enemy)
                    for _, m in ipairs(self.members) do Attack(m, enemy) end
                end
            else
                 -- Ensure moving
                 if not string.match(aiCore.NilToString(AiCommand[GetCurrentCommand(self.leader)]), "GO") then
                    Goto(self.leader, self.targetPos)
                 end
            end
        end
    elseif self.state == "attacking" then
        -- If idle, attack nearest
        if not IsBusy(self.leader) then
             local enemy = GetNearestEnemy(self.leader)
             if IsValid(enemy) then
                Attack(self.leader, enemy)
                for _, m in ipairs(self.members) do Attack(m, enemy) end
             end
        end
    end
    
    return true
end

----------------------------------------------------------------------------------
-- TEAM CLASS (The Brain)
----------------------------------------------------------------------------------

aiCore.Team = {
    teamNum = 0,
    faction = 0,
    recyclerMgr = nil,
    factoryMgr = nil,
    constructorMgr = nil,
    
    -- Production Lists (Desired State)
    recyclerBuildList = {}, -- {priority = {odf="", handle=nil}}
    factoryBuildList = {},
    buildingList = {},      -- {priority = {odf="", handle=nil, path=""}}
    
    -- Tactics
    strategy = "Balanced",
    strategyLocked = false,
    
    -- Tactical Groups (from aiSpecial)
    howitzers = {},     -- list of handles
    howitzerGuards = {},
    apcs = {},
    minelayers = {},
    pilots = {},        -- technicians/snipers
    
    -- Tactical State
    howitzerState = {}, -- {attacking=bool, outbound=bool, target=handle}
    wreckerTimer = 0,
    upgradeTimer = 0,
    
    -- Targets
    enemyTargets = {},  -- prioritized list of enemy buildings
}
aiCore.Team.__index = aiCore.Team

function aiCore.Team:new(teamNum, faction)
    local t = setmetatable({}, self)
    t.teamNum = teamNum
    
    -- Auto-detect faction if not provided or flexible
    if not faction then
        -- Simple detection based on recycler ODF
        local rec = GetRecyclerHandle(teamNum)
        if IsValid(rec) then
            local odf = GetOdf(rec)
            local char = string.sub(odf, 1, 1)
            if char == "a" then faction = 1
            elseif char == "s" then faction = 2
            elseif char == "c" then faction = 3
            elseif char == "b" then faction = 4
            end
        end
    end
    t.faction = faction or 1 -- Default to NSDF if unknown
    
    t.recyclerMgr = aiCore.FactoryManager:new(teamNum, true)
    t.factoryMgr = aiCore.FactoryManager:new(teamNum, false)
    t.constructorMgr = aiCore.ConstructorManager:new(teamNum)
    
    t.recyclerBuildList = {}
    t.factoryBuildList = {}
    t.buildingList = {}
    
    t.pilots = {}
    t.combatUnits = {} 
    
    t.pool = {} -- Units waiting for assignment
    t.squads = {} -- Active squads
    
    return t
end

function aiCore.Team:SetStrategy(stratName)
    if self.strategyLocked then return end
    
    local strat = aiCore.Strategies[stratName]
    if not strat then strat = aiCore.Strategies.Balanced end
    self.strategy = stratName
    
    -- Reset Lists
    self.recyclerBuildList = {}
    self.factoryBuildList = {}
    self.recyclerMgr.queue = {}
    self.factoryMgr.queue = {}
    
    -- Populate Build Lists (Prioritized from back to front in the arrays)
    -- Recycler List
    for i = #strat.Recycler, 1, -1 do
        local unitType = strat.Recycler[i]
        local odf = aiCore.Units[self.faction][unitType]
        if odf then 
            self:AddUnitToBuildList(self.recyclerBuildList, odf, i) 
        end
    end
    
    -- Factory List
    for i = #strat.Factory, 1, -1 do
        local unitType = strat.Factory[i]
        local odf = aiCore.Units[self.faction][unitType]
        if odf then 
            self:AddUnitToBuildList(self.factoryBuildList, odf, i) 
        end
    end
    
    if aiCore.Debug then print("Team " .. self.teamNum .. " strategy set to " .. stratName) end
end

function aiCore.Team:AddUnitToBuildList(list, odf, priority)
    list[priority] = {odf = odf, priority = priority, handle = nil}
end

function aiCore.Team:AddBuilding(odf, path, priority)
    self.buildingList[priority] = {odf = odf, priority = priority, path = path, handle = nil}
end

function aiCore.Team:Update()
    -- Manager Updates
    self.recyclerMgr:update()
    self.factoryMgr:update()
    self.constructorMgr:update()
    
    -- Replenish Queues from Build Lists
    self:CheckBuildList(self.recyclerBuildList, self.recyclerMgr)
    self:CheckBuildList(self.factoryBuildList, self.factoryMgr)
    self:CheckConstruction()
    
    -- Tactics
    self:UpdateHowitzers()
    self:UpdateAPCs()
    self:UpdateMinelayers()
    self:UpdateAdvancedWeapons()
    self:UpdatePilots()
    self:UpdateUpgrades()
    self:UpdateWrecker()
    self:UpdateWrecker()
    self:UpdateSquads() -- NEW
    
    -- Base Maintenance (Auto-Rebuild)
    self:UpdateBaseMaintenance()
end

function aiCore.Team:UpdateBaseMaintenance()
    -- Ensure critical units exist (Constructor, Factory, Armory)
    -- Only runs if we have a Recycler
    if not IsValid(self.recyclerMgr.handle) then return end
    
    -- Helper to check if item is already in queue
    local function IsInQueue(mgr, odf)
        for _, item in ipairs(mgr.queue) do
            if item.odf == odf then return true end
        end
        return false
    end
    
    -- 1. Constructor
    if not IsValid(self.constructorMgr.handle) then
        local odf = aiCore.Units[self.faction].constructor
        if not IsInQueue(self.recyclerMgr, odf) then
            -- Check if one exists but just isn't linked (e.g. just built)
            -- (AddObject should link it, but let's be safe: Object scanning is slow, so we rely on manager state)
            -- Priority 0 (High)
            if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Constructor.") end
            table.insert(self.recyclerMgr.queue, 1, {odf = odf, priority = 0}) 
        end
    end
    
    -- 2. Factory
    if not IsValid(self.factoryMgr.handle) then
        -- Are we supposed to have one? Yes, usually.
        -- Check if we merely haven't deployed it yet (e.g. "avmuf" vehicle exists)
        local odf = aiCore.Units[self.faction].factory
        local pending = false
        
        -- Check if an undeployed factory vehicle exists
        local nearby = GetNearestObject(self.recyclerMgr.handle)
        if IsValid(nearby) and GetTeamNum(nearby) == self.teamNum and IsOdf(nearby, odf) then
            -- It exists, maybe tell it to deploy?
            if not IsDeployed(nearby) and not IsBusy(nearby) then
                 Deploy(nearby)
            end
            pending = true
        end
        
        if not pending and not IsInQueue(self.recyclerMgr, odf) then
             if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Factory.") end
             table.insert(self.recyclerMgr.queue, 1, {odf = odf, priority = 0})
        end
    end
    
    -- 3. Armory (Optional? Assume yes for AI)
    local armory = GetArmoryHandle(self.teamNum)
    if not IsValid(armory) then
        local odf = aiCore.Units[self.faction].armory
        
        -- Similar check for undeployed armory vehicle
        local pending = false
        local nearby = GetNearestObject(self.recyclerMgr.handle)
         -- Reuse nearby check is flimsy if they are far apart, but usually they build near recycler.
         -- Ideally we scan, but for now rely on queue.
         
        if not IsInQueue(self.recyclerMgr, odf) then
            -- Only build armory if we assume we need one. 
            -- Let's check config or just default to yes.
             if aiCore.Debug then print("Team " .. self.teamNum .. " ordering replacement Armory.") end
             -- Insert at priority 2 (lower than constructor/factory)
             table.insert(self.recyclerMgr.queue, {odf = odf, priority = 0.5})
             table.sort(self.recyclerMgr.queue, function(a,b) return a.priority < b.priority end) -- Sort for priority
        end
    end
end

-- Configuration / Dynamic Difficulty Hooks
aiCore.Team.Config = {
    -- Pilots
    pilotZeal = 0.4,       -- Chance to be a sniper
    sniperStealth = 0.5,   -- Chance to retreat
    techInterval = 60,     -- Seconds between technician spawns
    
    -- Weapons
    thumperChance = 20,    -- % Chance to use thumper
    mortarChance = 30,     -- % Chance to use mortar
    doubleWeaponChance = 20, -- % Chance for double weapon mask
    
    -- Minelayers
    minefields = {},       -- List of path names or positions
    
    -- Upgrades
    upgradeInterval = 240,
    wreckerInterval = 600,
    
    -- Reinforcements
    orbitalReinforce = true
}

-- Setter for Difficulty Tweaking
function aiCore.Team:SetConfig(key, value)
    if self.Config[key] ~= nil then
        self.Config[key] = value
        if aiCore.Debug then print("Team " .. self.teamNum .. " config " .. key .. " set to " .. tostring(value)) end
    end
end

function aiCore.Team:SetMinefields(fields)
    -- fields can be a table of path names {"path1", "path2"}
    self.Config.minefields = fields
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC EXTENSIONS
----------------------------------------------------------------------------------

function aiCore.Team:UpdateMinelayers()
    aiCore.RemoveDead(self.minelayers)
    if #self.minelayers == 0 then return end
    
    -- Need minefields to work
    if #self.Config.minefields == 0 then
        -- Auto-generate if empty? Or just return?
        -- aiSpecial generates random fields near recycler if none set. Let's do that.
        if IsValid(self.recyclerMgr.handle) then
            for i=1, 3 do
                local pos = GetPositionNear(GetPosition(self.recyclerMgr.handle), 150, 400)
                table.insert(self.Config.minefields, pos)
            end
        end
        return 
    end
    
    for i, m in ipairs(self.minelayers) do
        if IsAlive(m) and not IsBusy(m) then
            -- If full ammo, go lay mines
            if GetAmmo(m) > 0.9 then
                local field = self.Config.minefields[math.random(#self.Config.minefields)]
                -- Can be path string or vector
                local pos = field
                if type(field) == "string" then pos = GetPathPoint(field, 0) end -- Simplified
                
                -- Check if friendlies nearby (simple safety)
                local safe = true
                -- (Skip complex safety checks for brevity, rely on BZ engine pathing)
                
                if safe then
                    -- Go and Mine
                    Mine(m, field, 1)
                end
            elseif GetAmmo(m) < 0.2 then
                -- Go reload
                local sup = GetNearestObject(m) -- Simple find, should look for supply depot
                -- Logic to find supply depot:
                -- ... (omitted for brevity, generalized)
                if IsValid(self.recyclerMgr.handle) then
                    Goto(m, self.recyclerMgr.handle, 1) -- Return to base
                end
            end
        end
    end
end

function aiCore.Team:UpdateAdvancedWeapons()
    -- Logic to periodically toggle Weapon Masks for Thumpers, Mortars, etc.
    -- aiSpecial does this with complex timers. We'll simplify with random pulse.
    
    if math.random() < 0.05 then -- Low chance per tick
        -- 1. Thumpers (Wingmen)
        for _, u in ipairs(self.apcs) do -- Checking APC list? No, need unit list.
             -- Current Team structure doesn't track ALL combat units, just specific types.
             -- We need to track generic combat units if we want this.
             -- HOWEVER, we can scan our build lists or just scan the map for team units.
             -- Scanning map is expensive.
             -- Let's stick to known lists or add a generic 'combatUnits' list if needed.
             -- For now, let's look at Howitzers/Tanks if we track them.
        end
        
        -- To properly support this like aiSpecial, we need to track all "Wingman" class units.
        -- Let's add that to AddObject.
    end
end

function aiCore.Team:UpdatePilots()
    -- Logic from aiSpecial: Spawn technicians from barracks
    -- techTable, barracksTable handling
    
    -- 1. Scan for barracks
    local barracks = {}
    -- Helper to find barracks since we don't track them explicitly in a list yet
    -- relying on GetObjectByClass or similar is hard in Lua without scanning
    -- For efficiency, we can scan near the recycler or factory
    if IsValid(self.recyclerMgr.handle) then
        for obj in ObjectsInRange(200, self.recyclerMgr.handle) do
            local cls = aiCore.NilToString(GetClassLabel(obj))
            if string.find(cls, "barracks") or string.find(cls, "training") then
                table.insert(barracks, obj)
            end
        end
    end
    
    -- 2. Spawn Techs periodically
    if #barracks > 0 then
        if not self.techTimer then self.techTimer = GetTime() + self.Config.techInterval end
        
        -- Cap number of pilots
        if #self.pilots < self.Config.techMax then
            if GetTime() > self.techTimer then
                local fac = barracks[math.random(#barracks)]
                if IsValid(fac) and IsAlive(fac) then
                    local pilotOdf = aiCore.GuessPilotOdf(fac)
                    local pos = GetPosition(fac)
                    pos.z = pos.z + 10 -- Offset exit
                    
                    local pilot = BuildObject(pilotOdf, self.teamNum, pos)
                    if IsValid(pilot) then
                        table.insert(self.pilots, pilot)
                        -- Order them to roam
                        local roamPos = GetPositionNear(pos, 50, self.Config.techRange)
                        Goto(pilot, roamPos)
                        if aiCore.Debug then print("Team " .. self.teamNum .. " deployed technician.") end
                    end
                end
                self.techTimer = GetTime() + self.Config.techInterval + math.random(0, 10)
            end
        end
    end
    
    -- 3. Update Pilots (remove dead, defend, sniper logic)
    aiCore.RemoveDead(self.pilots)
    for _, p in ipairs(self.pilots) do
        if IsAlive(p) then
            local weapon0 = GetWeaponClass(p, 0)
            local enemy = GetNearestEnemy(p)
            local dist = 9999
            if IsValid(enemy) then dist = GetDistance(p, enemy) end
            
            -- SNIPER LOGIC (Adapted from aiSpecial)
            -- If pilot has a handgun and is aggressive, give them a sniper rifle
            if weapon0 and string.find(weapon0, "handgun") then
                -- 40% chance to become a sniper (simulate pilotZeal)
                -- We only check this once or periodically. For simplicity, we check if they are attacking.
                if IsValid(enemy) and dist < 200 and not IsCloaked(enemy) then
                    Attack(p, enemy)
                    -- Upgrade to Sniper Rifle if not player/special
                    if math.random() > 0.6 then 
                        GiveWeapon(p, "gsnipe", 0)
                        if aiCore.Debug then print("Pilot upgraded to Sniper!") end
                    end
                end
            
            -- If they have a Sniper Rifle, manage behavior
            elseif weapon0 and string.find(weapon0, "gsnipe") then
                if IsValid(enemy) then
                    -- If out of ammo, switch back or retreat
                    if GetAmmo(p) < 0.2 then
                        GiveWeapon(p, "handgun", 0)
                        -- 50% chance to retreat (SniperStealth)
                        if math.random() > 0.5 then
                            Stop(p)
                            if aiCore.Debug then print("Sniper out of ammo, retreating.") end
                        end
                    -- If enemy too far, revert to normal
                    elseif dist > 250 then
                        GiveWeapon(p, "handgun", 0)
                        Stop(p)
                    else
                        -- Keep attacking
                        Attack(p, enemy)
                    end
                else
                    -- No enemy, revert
                    GiveWeapon(p, "handgun", 0)
                end
            end
            
            -- General roaming if idle
            if not IsBusy(p) and not IsValid(enemy) then
                 -- maybe patrol?
            end
        end
    end
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC EXTENSIONS
----------------------------------------------------------------------------------

function aiCore.Team:UpdateSquads()
    -- 1. Manage Pool (Form Squads)
    aiCore.RemoveDead(self.pool)
    if #self.pool >= 3 then
        local leader = table.remove(self.pool, 1)
        if IsValid(leader) then
            local newSquad = aiCore.Squad:new(leader)
            
            -- Add 2 members
            for i=1, 2 do
                local m = table.remove(self.pool, 1)
                if IsValid(m) then newSquad:AddMember(m) end
            end
            
            -- Assign Flank Mission
            -- Find target (Player Recycler/Factory or just Enemy)
            local target = GetNearestEnemy(leader)
            if IsValid(target) then
                -- Pick random angle
                local angle = math.random(0, 360)
                local dist = 300 + math.random(200)
                local flankPos = aiCore.GetFlankPosition(target, dist, angle)
                
                newSquad.targetPos = flankPos
                newSquad.state = "moving_to_flank"
                Goto(leader, flankPos)
                if aiCore.Debug then print("Team " .. self.teamNum .. " formed squad. Flanking...") end
            end
            
            table.insert(self.squads, newSquad)
        end
    end
    
    -- 2. Update Squads
    for i = #self.squads, 1, -1 do
        local sq = self.squads[i]
        if not sq:Update() or (#sq.members == 0 and not IsValid(sq.leader)) then
            table.remove(self.squads, i)
        end
    end
end


function aiCore.Team:UpdateUpgrades()
    -- Logic from aiSpecial: Upgrade turrets and launch powerups
    if not self.upgradeTimer then self.upgradeTimer = GetTime() + 240 end
    
    if GetTime() > self.upgradeTimer then
        self.upgradeTimer = GetTime() + 240 -- 4 mins
        
        -- Launch Powerups from Armory
        local armory = GetArmoryHandle(self.teamNum)
        if IsValid(armory) and CanBuild(armory) then
            -- Find targets (Turrets without ammo, damaged buildings)
            local target = nil
            local powerup = "apammo"
            
            -- 1. Heal/Resupply Turrets
            for obj in ObjectsInRange(500, armory) do -- Range check optimization
                if GetTeamNum(obj) == self.teamNum then
                    if GetHealth(obj) < 0.5 then
                        target = obj
                        powerup = "aprepa"
                        break
                    elseif GetAmmo(obj) < 0.3 then
                        target = obj
                        powerup = "apammo"
                        break
                    end
                end
            end
            
            if IsValid(target) then
                BuildAt(armory, powerup, target, 1)
                if aiCore.Debug then print("Team " .. self.teamNum .. " launching " .. powerup) end
            end
        end
    end
end


function aiCore.Team:CheckBuildList(list, mgr)
    for p, item in pairs(list) do
        if not IsValid(item.handle) then
            -- Check if we already have it in the world but didn't link it (e.g. pre-placed)
            local nearby = GetNearestObject(mgr.handle or GetRecyclerHandle(self.teamNum))
            if IsValid(nearby) and IsOdf(nearby, item.odf) and GetDistance(nearby, mgr.handle) < 100 and GetTeamNum(nearby) == self.teamNum then
                 -- Is this handle already taken by another priority?
                 local taken = false
                 for _, other in pairs(list) do 
                    if other.handle == nearby then taken = true break end 
                 end
                 if not taken then
                    item.handle = nearby
                 end
            end
            
            -- If still nil, add to queue if not present
            if not IsValid(item.handle) then
                local inQueue = false
                for _, qItem in ipairs(mgr.queue) do
                    if qItem.priority == p then inQueue = true break end
                end
                
                if not inQueue then
                    table.insert(mgr.queue, {odf = item.odf, priority = p})
                    -- Sort queue by priority (Low to High? No, usually High priority first. 
                    -- But wait, standard lua sort is <.
                    -- If Priority 1 is "High" and 10 is "Low", we want 1 first.
                    -- My previous sort was a.priority > b.priority (10 first).
                    -- Let's stick to: 0 is Highest (Emergency). 1 is High. 10 is Low.
                    -- So we want Ascending order (lowest number first).
                    table.sort(mgr.queue, function(a,b) return a.priority < b.priority end)
                end
            end
        end
    end
end

function aiCore.Team:CheckConstruction()
    for p, item in pairs(self.buildingList) do
        if not IsValid(item.handle) then
            -- define search radius
            local found = nil
            for obj in ObjectsInRange(50, item.path) do
                if IsOdf(obj, item.odf) and GetTeamNum(obj) == self.teamNum then
                    found = obj
                    break
                end
            end
            
            if found then
                item.handle = found
            else
                -- Add to constructor queue if not present
                local inQueue = false
                for _, qItem in ipairs(self.constructorMgr.queue) do
                    if qItem.priority == p then inQueue = true break end
                end
                if not inQueue then
                    table.insert(self.constructorMgr.queue, {odf = item.odf, path = item.path, priority = p})
                    table.sort(self.constructorMgr.queue, function(a,b) return a.priority < b.priority end)
                end
            end
        end
    end
end

function aiCore.Team:AddObject(h)
    local odf = GetOdf(h)
    
    -- Link to build lists
    local function link(list, mgr)
        if mgr.queue[1] and mgr.queue[1].odf == odf then
            -- It matches the top of queue, assumes it's the one we just built
            -- Strict linking can be hard in BZ Lua, this is a "best guess" association
            -- Ideally we check distance to factory
            if IsValid(mgr.handle) and GetDistance(h, mgr.handle) < 150 then
                local priority = mgr.queue[1].priority
                list[priority].handle = h
                table.remove(mgr.queue, 1)
            end
        end
    end
    
    link(self.recyclerBuildList, self.recyclerMgr)
    link(self.factoryBuildList, self.factoryMgr)
    
    -- Constructor linking checks path distance
    if self.constructorMgr.queue[1] and self.constructorMgr.queue[1].odf == odf then
        local qItem = self.constructorMgr.queue[1]
        if GetDistance(h, qItem.path) < 60 then
            self.buildingList[qItem.priority].handle = h
            table.remove(self.constructorMgr.queue, 1)
        end
    end
    
    -- Add to tactical lists
    local cls = aiCore.NilToString(GetClassLabel(h))
    if string.find(cls, "howitzer") then
        table.insert(self.howitzers, h)
    elseif string.find(cls, "apc") then
        table.insert(self.apcs, h)
    elseif string.find(cls, "minelayer") then
        table.insert(self.minelayers, h)
    elseif string.find(cls, "wingman") or string.find(cls, "walker") then
        -- Instead of dumping into combatUnits immediately, put into POOL for squads
        table.insert(self.pool, h)
        -- Send to rally point (near recycler)
        if IsValid(self.recyclerMgr.handle) then
            Goto(h, self.recyclerMgr.handle)
        end
    end
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC
----------------------------------------------------------------------------------

function aiCore.Team:UpdateAdvancedWeapons()
    -- Advanced Weapon Logic: Periodically switch weapon masks for units with multiple weapons (Thumpers, Double guns)
    if not self.weaponTimer then self.weaponTimer = GetTime() + 15 end
    if GetTime() > self.weaponTimer then
        self.weaponTimer = GetTime() + 15 + math.random(5)
        
        aiCore.RemoveDead(self.combatUnits)
        for _, u in ipairs(self.combatUnits) do
            -- Thumper Logic (aiSpecial "Thumper Behavior")
            if math.random(100) < self.Config.thumperChance then
                local hasThumper = GetWeaponSlot(u, "gquake")
                if hasThumper > -1 then
                    -- Toggle Thumper Mask (Mask 1 = 0, 2=1, 4=2, 8=3)
                    -- If currently using normal, switch to thumper? 
                    -- Or simplified: SetWeaponMask based on simple random
                    local current = GetWeaponMask(u)
                    -- If not using thumper, maybe switch
                    local thumperMask = 2 ^ hasThumper -- Bitwise check approx
                    SetWeaponMask(u, thumperMask)
                    -- Note: Should reset later. aiSpecial has complex timers for this.
                    -- Simplification: Just randomizing masks occasionally creates dynamic behavior.
                end
            else
                -- Reset to All Weapons (Mask 15 usually safe, or smart detect)
                SetWeaponMask(u, 7) -- 0,1,2
            end
            
            -- Double Weapon Logic
            if math.random(100) < self.Config.doubleWeaponChance then
               -- Set mask to 0+1 (3)
               SetWeaponMask(u, 3) 
            end
        end
    end
end

-- Helper for SetWeaponMask bits
function GetWeaponSlot(h, odf)
    for i=0,4 do
        local w = GetWeaponClass(h, i)
        if w and string.find(w, odf) then return i end
    end
    return -1
end

function aiCore.Team:UpdateHowitzers()
    aiCore.RemoveDead(self.howitzers)
    if #self.howitzers == 0 then return end
    
    -- Simple Howitzer Logic: Pick enemy target, go there, shoot
    -- This is a simplified version of aiSpecial logic
    
    -- Step 1: Find Target
    local target = GetNearestEnemy(self.howitzers[1])
    if not IsValid(target) then return end
    
    for i, h in ipairs(self.howitzers) do
        if not IsBusy(h) then
            local dist = GetDistance(h, target)
            if dist > 300 then
                Attack(h, target) -- Attack moves them in range usually
            end
        end
    end
end

function aiCore.Team:UpdateAPCs()
    aiCore.RemoveDead(self.apcs)
    for _, apc in ipairs(self.apcs) do
        if IsAlive(apc) then
            -- Deploy if near enemy
            local enemy = GetNearestEnemy(apc)
            if IsValid(enemy) and GetDistance(apc, enemy) < 100 and not IsDeployed(apc) then
                Deploy(apc)
            end
        end
    end
end

function aiCore.Team:UpdateWrecker()
    -- Simplified Day Wrecker Logic
    -- Check strategies
    if self.strategy == "Tank_Heavy" or self.strategy == "Howitzer_Heavy" then
        if self.wreckerTimer < GetTime() then
            self.wreckerTimer = GetTime() + 600 -- 10 mins
            
            local armory = GetArmoryHandle(self.teamNum)
            if IsValid(armory) and CanBuild(armory) then
                local enemies = {} -- Build logic to finding enemy base
                -- Mockup: simple random enemy object
                local enemy = GetNearestEnemy(armory)
                if IsValid(enemy) then
                    BuildAt(armory, "apwrck", enemy, 1)
                    if aiCore.Debug then print("Team " .. self.teamNum .. " launching Day Wrecker!") end
                end
            end
        end
    end
end

----------------------------------------------------------------------------------
-- MAIN INTERFACE
----------------------------------------------------------------------------------

aiCore.ActiveTeams = {}

function aiCore.AddTeam(teamNum, faction)
    local t = aiCore.Team:new(teamNum, faction)
    aiCore.ActiveTeams[teamNum] = t
    return t
end

function aiCore.Update()
    for _, team in pairs(aiCore.ActiveTeams) do
        team:Update()
    end
end

function aiCore.AddObject(h)
    local teamNum = GetTeamNum(h)
    local team = aiCore.ActiveTeams[teamNum]
    if team then
        team:AddObject(h)
    end
end

function aiCore.DeleteObject(h)
    -- Cleanup if needed
end

-- Helper to set up construction
function aiCore.SetupBase(teamNum, buildings)
    -- buildings = {{odf="avrecy", path="path1"}, ...}
    local team = aiCore.ActiveTeams[teamNum]
    if not team then return end
    
    for i, b in ipairs(buildings) do
        team:AddBuilding(b.odf, b.path, i)
    end
end

return aiCore
