-- aiCore.lua
-- Consolidated AI System for Battlezone 98 Redux
-- Combines functionality from aiFacProd, aiRecProd, aiBuildOS, and aiSpecial
-- Supported Factions: NSDF, CCA, CRA, BDOG

aiCore = {}
aiCore.Debug = false

function aiCore.Save()
    return aiCore.ActiveTeams
end

function aiCore.NilToString(s)
    if s == nil then return "" end
    return tostring(s)
end

function aiCore.GetWeaponMask(h, search)
    if type(search) == "string" then search = {search} end
    for i = 0, 4 do
        local w = GetWeaponClass(h, i)
        if w then
            w = string.lower(w)
            for _, s in ipairs(search) do
                if string.find(w, string.lower(s)) then
                    return 2 ^ i
                end
            end
        end
    end
    return 0
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
        
        -- Restore Squad Metatables
        if team.squads then
            for _, squad in ipairs(team.squads) do
                setmetatable(squad, aiCore.Squad)
            end
        end
    end
end


----------------------------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
----------------------------------------------------------------------------------

aiCore.Factions = {NSDF = 1, CCA = 2, CRA = 3, BDOG = 4}
aiCore.Factions = {NSDF = 1, CCA = 2, CRA = 3, BDOG = 4}
aiCore.FactionNames = {[1] = "NSDF", [2] = "CCA", [3] = "CRA", [4] = "BDOG"}

-- Smart Power Detection
function aiCore.DetectWorldPower()
    if aiCore.WorldPowerKey then return aiCore.WorldPowerKey end
    
    local trnFile = GetMapTRNFilename()
    if not trnFile or trnFile == "" then 
        aiCore.WorldPowerKey = "sPower" -- Default
        return aiCore.WorldPowerKey
    end
    
    local odf = OpenODF(trnFile)
    if not odf then
        aiCore.WorldPowerKey = "sPower"
        return aiCore.WorldPowerKey
    end
    
    local palette = GetODFString(odf, "Color", "Palette", "")
    if palette == "" then 
        -- Fallback: try filename guessing if palette is missing
        local lowerTrn = string.lower(trnFile)
        if string.find(lowerTrn, "venus") then palette = "venus"
        elseif string.find(lowerTrn, "mars") then palette = "mars"
        elseif string.find(lowerTrn, "titan") then palette = "titan"
        else palette = "moon" end
    end
    palette = string.lower(palette)
    
    -- Map Palette/World to Power Type
    -- Solar: Moon, Io, Europa, Ganymede
    -- Lightning: Venus
    -- Wind: Mars, Titan, Achilles, Elysium
    
    if string.find(palette, "venus") then
        aiCore.WorldPowerKey = "lPower"
    elseif string.find(palette, "mars") or string.find(palette, "titan") or string.find(palette, "achilles") or string.find(palette, "elysium") then
        aiCore.WorldPowerKey = "wPower"
    else
        -- Default to Solar (Moon, Io, Europa, Ganymede, etc)
        aiCore.WorldPowerKey = "sPower"
    end
    
    if aiCore.Debug then print("aiCore: Smart Power Detection based on " .. palette .. " -> " .. aiCore.WorldPowerKey) end
    return aiCore.WorldPowerKey
end

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
    unique = "avltmp", repair = "aprepa",
    ammo = "apammo", pilot = "aspilo"
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
    unique = "svsav", repair = "aprepa",
    ammo = "apammo", pilot = "sspilo"
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
    unique = "cvhtnk", repair = "aprepa",
    ammo = "apammo", pilot = "cspilo"
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
    unique = "bvrdev", repair = "aprepa",
    ammo = "apammo", pilot = "bspilo"
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

function aiCore.IsAreaFlat(centerPos, radius, checkPoints, flatThreshold, flatPercentage)
    radius = radius or 10.0
    checkPoints = checkPoints or 8
    flatThreshold = flatThreshold or 0.966 -- cos(15 degrees)
    flatPercentage = flatPercentage or 0.75
    
    local centerHeight, centerNormal = GetTerrainHeightAndNormal(centerPos)
    if centerNormal.y < flatThreshold then return false, 0.0 end
    
    local flatPoints = 1
    local totalPoints = 1 + checkPoints
    
    for i = 0, checkPoints - 1 do
        local angle = (i / checkPoints) * 2 * math.pi
        local x = centerPos.x + radius * math.cos(angle)
        local z = centerPos.z + radius * math.sin(angle)
        local testPos = SetVector(x, centerPos.y, z)
        local _, normal = GetTerrainHeightAndNormal(testPos)
        if normal.y >= flatThreshold then flatPoints = flatPoints + 1 end
    end
    
    local actual = flatPoints / totalPoints
    return actual >= flatPercentage, actual
end

function aiCore.IsTracked(h, teamNum)
    local team = aiCore.ActiveTeams[teamNum]
    if not team then return false end
    
    -- Check Manager Handle
    if team.recyclerMgr and team.recyclerMgr.handle == h then return true end
    if team.factoryMgr and team.factoryMgr.handle == h then return true end
    if team.constructorMgr and team.constructorMgr.handle == h then return true end
    
    -- Check tactical lists
    local lists = {
        team.scavengers, team.howitzers, team.apcs, team.minelayers,
        team.cloakers, team.turrets, team.doubleUsers, team.soldiers,
        team.mortars, team.thumpers, team.fields, team.pilots, team.pool
    }
    
    for _, list in ipairs(lists) do
        if list then
            for _, unit in ipairs(list) do
                if unit == h then return true end
            end
        end
    end
    
    -- Check build list handles
    for _, item in pairs(team.recyclerBuildList) do if item.handle == h then return true end end
    for _, item in pairs(team.factoryBuildList) do if item.handle == h then return true end end
    for _, item in pairs(team.buildingList) do if item.handle == h then return true end end
    
    return false
end

function aiCore.Bootstrap()
    if aiCore.Debug then print("aiCore: Bootstrapping world state...") end
    local count = 0
    local registered = 0
    
    for h in AllObjects() do
        count = count + 1
        local team = GetTeamNum(h)
        if aiCore.ActiveTeams[team] then
            if not aiCore.IsTracked(h, team) then
                aiCore.AddObject(h)
                registered = registered + 1
            end
        end
    end
    
    if aiCore.Debug then print("aiCore: Bootstrap complete. Processed " .. count .. " objects, registered " .. registered .. " new units.") end
end

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
    if not tbl then return end
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


-- Upgrade Turret Logic (Ported from aiSpecial)
function aiCore.UpgradeTurret(h) 
    if not IsValid(h) then return false end
    
    local success = false
    local odf = GetOdf(h)
    
    if odf == "avturr" then
        for i = 0,3 do GiveWeapon(h,"gXinigun",i) end; success = true
    elseif odf == "svturr" then
        for i = 0,2 do GiveWeapon(h,"gXinisov",i) end; success = true
    elseif odf == "cvturr" then
        for i = 0,3 do GiveWeapon(h,"gXinisov",i) end; success = true
    elseif odf == "bvturr" then
        for i = 0,3 do GiveWeapon(h,"gXinigun",i) end; success = true
    elseif odf == "bvtump" then
        for i = 0,1 do GiveWeapon(h,"gXtstab",i) end; success = true
    elseif odf == "mvturr" then
        for i = 0,1 do GiveWeapon(h,"gshadow",i) end; success = true
    elseif odf == "dvturr" then
        for i = 0,3 do GiveWeapon(h,"gXinisov",i) end; success = true
    elseif odf == "rvturr" then
        for i = 0,2 do GiveWeapon(h,"ghailgn",i) end; success = true
    elseif odf == "fvturr" then
        for i = 0,3 do GiveWeapon(h,"gXongun",i) end; success = true
    elseif odf == "sbtowe" then
        for i = 0,1 do GiveWeapon(h,"gX2nisov",i) end; success = true
    elseif odf == "cbtowe" then
        GiveWeapon(h,"gXtstabt",0); success = true 
    end
    
    if success and aiCore.Debug then
        print("Turret "..odf.." upgraded.")
    end
    return success
end

-- Replace Unit Logic (Ported from aiSpecial)
function aiCore.ReplaceUnit(h, newUnitOdf, chargeExpense, teamObj)
    if not IsValid(h) then return nil end
    
    local teamNum = GetTeamNum(h)
    local pos = GetPosition(h)
    local rot = GetTransform(h) -- Actually checking if GetTransform returns matrix or we need SetTransform(h, matrix)
    -- BZ Lua API GetTransform returns a matrix/userdata usually compatible with SetTransform.
    
    local oldOdf = GetOdf(h)
    local oldScrapCost = GetODFInt(OpenODF(oldOdf),"GameObjectClass","scrapCost")
    local newScrapCost = GetODFInt(OpenODF(newUnitOdf),"GameObjectClass","scrapCost")
    
    RemoveObject(h)
    
    local replacement = BuildObject(newUnitOdf, teamNum, pos)
    SetTransform(replacement, rot)
    
    -- Charge expense?
    if chargeExpense and teamObj then
        local diff = newScrapCost - oldScrapCost
        if diff > 0 then
            AddScrap(teamNum, -diff)
            if aiCore.Debug then print("Team "..teamNum.." paid "..diff.." for replacement.") end
        end
    end
    
    return replacement
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

    -- Check Deployment State
    if not IsDeployed(self.handle) then
        local cmd = GetCurrentCommand(self.handle)
        if cmd ~= AiCommand.DEPLOY then -- Avoid spamming
             Deploy(self.handle)
        end
        return -- Wait for deployment
    end

    if CanBuild(self.handle) and not IsBusy(self.handle) then
        local item = self.queue[1]
        
        if item then
            local odfHandle = OpenODF(item.odf)
            if odfHandle and odfHandle ~= 0 then
                local scrapCost = GetODFInt(odfHandle,"GameObjectClass","scrapCost")
                
                if GetScrap(self.team) >= scrapCost then
                    if GetTime() > self.pulseTimer then
                        Build(self.handle, item.odf, 0)
                        self.pulseTimer = GetTime() + self.pulsePeriod + math.random(-1, 1)
                        
                        if aiCore.Debug then print("Team " .. self.team .. " building " .. item.odf) end
                        
                        -- Note: Queue removal happens in AddObject when the unit is validated in the world
                        -- This allows retrying if build fails due to temporary conditions (e.g. terrain)
                        -- But we rely on the game engine to actually build it.
                    end
                end
            else
                -- Invalid ODF, remove to prevent blocking queue
                if aiCore.Debug then print("Team " .. self.team .. " removing invalid ODF from queue: " .. tostring(item.odf)) end
                table.remove(self.queue, 1)
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
        -- Robust idling: Return to recycler if idle
        local recycler = GetRecyclerHandle(self.team)
        if IsValid(recycler) and not self.sentToRecycler then
            if GetDistance(self.handle, recycler) > 100 then
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
                -- Spacing check (New from aiBuildOS)
                local spacingOk, reason = self.team:CheckBuildingSpacing(item.odf, item.path, 50)
                
                if not spacingOk then
                    if aiCore.Debug then print("Constructor " .. self.team .. " spacing issue: " .. reason) end
                    table.remove(self.queue, 1) -- Skip if it can't be placed safely
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
    cloakers = {},      -- CRA cloaked units
    thumpers = {},      -- Advanced Weapons
    mortars = {},
    fields = {},
    turrets = {},       -- Tracking for upgrades
    
    -- Tactical State
    howitzerState = {}, -- {attacking=bool, outbound=bool, target=handle}
    wreckerTimer = 0,
    upgradeTimer = 0,
    strategyTimer = 0,  -- For rotation
    weaponTimer = 0,    -- For mask cycling
    
    -- pilotMode State
    roleTimer = 0,
    rescueTimer = 0,
    tugTimer = 0,
    stickTimer = 0,
    
    cargoJobs = {},
    tugHandles = {},
    activeTugJobs = {},
    assistedUnits = {}, -- For StickToPlayer
    basePositions = {}, -- For AutoBuild
    
    -- Targets
    enemyTargets = {},  -- prioritized list of enemy buildings
    
    -- Stealth Management (Legacy Misn12)
    stealthState = {
        discovered = false,
        warnings = 0,
        playerInVehicle = true,
        lastCheckPos = nil
    }
}
aiCore.Team.__index = aiCore.Team

function aiCore.Team:new(teamNum, faction)
    local t = setmetatable({}, self)
    t.teamNum = teamNum
    
    -- Configuration (Defaults)
    t.Config = {
        difficulty = 1,
        race = "nsdf",
        kc = 0,
        stratMultiplier = 1.0,
        autoBuild = true,
        
        -- Advanced Settings
        thumperChance = 10,
        mortarChance = 20,
        fieldChance = 10,
        doubleWeaponChance = 20,
        
        -- AI Behavior Settings
        soldierRange = 50,
        sniperSteal = true,
        pilotZeal = 40,
        sniperTraining = 75,
        sniperStealth = 50,
        
        -- Timers
        upgradeInterval = 240,
        wreckerInterval = 600,
        
        -- Toggles
        passiveRegen = false,
        autoManage = false,
        autoRescue = false,
        autoTugs = false,
        stickToPlayer = false,
        dynamicMinefields = false
    }

    -- Tactical Lists
    t.scavengers = {}
    t.howitzers = {}
    t.apcs = {}
    t.minelayers = {}
    t.cloakers = {}
    t.mortars = {}
    t.thumpers = {}
    t.fields = {}
    t.pilots = {}
    t.turrets = {}
    t.doubleUsers = {}
    t.soldiers = {}
    t.tugHandles = {}
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
    
    t.combatUnits = {} 
    
    t.pool = {} -- Units waiting for assignment
    t.squads = {} -- Active squads
    
    t.resourceBoostTimer = GetTime() + 10.0 -- Randomized boost starts soon
    
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
    -- Lazy Initialization for Retrofitting (Fixes crashes on existing saves/teams)
    if not self.fields then self.fields = {} end
    if not self.doubleUsers then self.doubleUsers = {} end
    if not self.soldiers then self.soldiers = {} end
    
    -- Ensure Config has new keys if missing
    if not self.Config.fieldChance then
        self.Config.fieldChance = 10
        self.Config.doubleWeaponChance = 20
        self.Config.soldierRange = 50
        self.Config.sniperSteal = true
        self.Config.pilotZeal = 40
        self.Config.sniperTraining = 75
        self.Config.sniperStealth = 50
    end

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
    self:UpdateUpgrades()
    self:UpdateAdvancedWeapons()
    self:UpdatePilots()
    self:UpdateMinelayers()
    self:UpdateWrecker()
    self:UpdateSquads()
    self:UpdateCloakers()
    self:UpdateSoldiers()
    self:UpdateGuards()
    self:UpdateStrategyRotation()
    
    -- pilotMode Automations
    if self.Config.autoManage then self:UpdateUnitRoles() end
    if self.Config.autoRescue then self:UpdateRescue() end
    if self.Config.autoTugs then self:UpdateTugs() end
    if self.Config.stickToPlayer then self:UpdateStickToPlayer() end
    if self.Config.autoBuild then self:UpdateAutoBase() end
    
    -- Legacy Proximity/Maintenance
    if self.Config.dynamicMinefields then self:UpdateDynamicMinefields() end
    if self.Config.passiveRegen then self:UpdateRegen() end
    
    self:UpdateBaseMaintenance()
    self:UpdatePilotResources()
    self:UpdateResourceBoosting()
    
    -- Scavenger Assist (Player QOL)
    if self.Config.scavengerAssist then self:UpdateScavengerAssist() end
end

function aiCore.Team:UpdateStickToPlayer()
    -- Placeholder for future stick-to-player behavior
end

function aiCore.Team:UpdateResourceBoosting()
    if not self.Config.resourceBoost then return end
    
    if GetTime() > (self.resourceBoostTimer or 0) then
        local m = DiffUtils.Get()
        -- Randomize next interval around 120s, scaled by timer difficulty
        local interval = DiffUtils.ScaleTimer(120.0) + math.random(-20, 40)
        self.resourceBoostTimer = GetTime() + interval
        
        local scrapBoost = math.floor(20 * m.enemy)
        local pilotBoost = math.floor(5 * m.enemy)
        
        AddScrap(self.teamNum, scrapBoost)
        AddPilot(self.teamNum, pilotBoost)
        
        if aiCore.Debug then 
            print("Team "..self.teamNum.." resource boost: +"..scrapBoost.." scrap, +"..pilotBoost.." pilots (Next in "..math.floor(interval).."s)") 
        end
    end
end

function aiCore.Team:UpdateScavengerAssist()
    if (self.scavAssistTimer or 0) > GetTime() then return end
    self.scavAssistTimer = GetTime() + 10.0 -- Refresh every 10s
    
    if not self.scavengers then self.scavengers = {} end
    
    -- Clean dead
    aiCore.RemoveDead(self.scavengers)
    
    for _, h in ipairs(self.scavengers) do
        if IsValid(h) and not IsSelected(h) then
            local cmd = GetCurrentCommand(h)
            
            -- Check if Idle (0) or already Scavenging
            -- We refresh every 10s to ensure they recalculate paths to nearest scrap
            if (cmd == 0) or (cmd == AiCommand.SCAVENGE) then
                -- Issue high-priority command (1) to suppress radio voice-over
                SetCommand(h, AiCommand.SCAVENGE, 1)
                -- Immediately restore independence (1) so player can override
                SetIndependence(h, 1)
            end
        end
    end
end

function aiCore.Team:RegisterScavenger(h)
    if not self.scavengers then self.scavengers = {} end
    table.insert(self.scavengers, h)
end

function aiCore.Team:UpdateBaseMaintenance()
    -- Ensure critical units exist (Constructor, Factory, Armory)
    -- Only runs if we have a Recycler
    if not IsValid(self.recyclerMgr.handle) then return end
    if not self.Config.autoBuild then return end
    
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
                 --Deploy(nearby)
                 --Should order it to "GO TO GEYSER"
                 SetCommand(nearby, AiCommand.GO_TO_GEYSER, 1)
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
    techMax = 4,           -- Max technicians to spawn
    
    -- Weapons
    thumperChance = 20,    -- % Chance to use thumper
    mortarChance = 30,     -- % Chance to use mortar
    doubleWeaponChance = 20, -- % Chance for double weapon mask
    
    -- Minelayers
    minefields = {},       -- List of path names or positions
    
    howitzerChance = 50,
    upgradeInterval = 180,
    wreckerInterval = 600,
    
    -- pilotMode Automation (Default OFF)
    autoManage = false,       -- Enable unit role distribution
    autoBuild = false,        -- Enable automatic base building
    autoRescue = false,       -- Enable player rescue system
    autoTugs = false,         -- Enable automatic cargo management
    stickToPlayer = false,    -- Enable physics assistance for wingmen
    
    -- Sub-config for automation
    followPercentage = 30,
    patrolPercentage = 30,
    guardPercentage = 40,
    scavengerCount = 4,
    tugCount = 2,
    buildingSpacing = 80,
    rescueDelay = 2.0,
    
    -- Reinforcements
    orbitalReinforce = true,
    
    -- Legacy Features (C++ Gems)
    passiveRegen = false,      -- Enable Recycler health regeneration
    regenRate = 20.0,          -- Health per second
    reclaimEngineers = false,  -- Enable auto-reclaim for engineers
    dynamicMinefields = false, -- Enable proximity-based mine spawning
    
    scavengerAssist = false,    -- Enable automanagement of friendly scavengers
    
    -- Construction Defaults
    buildingSpacing = 70.0,
    siloMinDistance = 250.0,
    siloMaxDistance = 450.0
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

-- Building Spacing Helper (from aiBuildOS)
function aiCore.Team:CheckBuildingSpacing(odf, position, minDistance)
    minDistance = minDistance or 50
    
    for obj in ObjectsInRange(minDistance, position) do
        if IsBuilding(obj) and GetTeamNum(obj) == self.teamNum then
            -- Same type strict spacing
            if IsOdf(obj, odf) then
                return false, "Same type too close"
            end
            -- General crowding
            if GetDistance(obj, position) < (minDistance * 0.6) then
                return false, "Area too crowded"
            end
        end
    end
    return true, "OK"
end

function aiCore.Team:UpdateRegen()
    -- Consolidated Regen: Recycler (High Rate) + Combat Units (Low Rate)
    local recycler = self.recyclerMgr.handle
    if IsValid(recycler) then
        AddHealth(recycler, (self.Config.regenRate or 20.0) * 0.05) 
    end

    if self.Config.passiveRegen then
        if not self.regenTimer or GetTime() > self.regenTimer then
            self.regenTimer = GetTime() + 1.0
            aiCore.RemoveDead(self.combatUnits)
            for _, u in ipairs(self.combatUnits) do
                if IsAlive(u) and GetHealth(u) < GetMaxHealth(u) then
                    AddHealth(u, 5) -- Small flat regen for all combat units
                end
            end
        end
    end
end

function aiCore.Team:UpdateDynamicMinefields()
    -- Ported from Misn07: Spawn mines near enemies in designated zones
    if #self.Config.minefields == 0 then return end
    
    for _, zone in ipairs(self.Config.minefields) do
        -- zone can be a path name or {x,y,z}
        local pos = zone
        if type(zone) == "string" then pos = GetPosition(zone) end
        
        local enemy = GetNearestEnemy(zone) -- Uses position if string
        if IsValid(enemy) and GetDistance(enemy, pos) < 150 then
            -- Spawn a mine if not too many nearby
            local mines = 0
            for obj in ObjectsInRange(40, pos) do
                if IsOdf(obj, "proxmine") or IsOdf(obj, "svmine") then
                    mines = mines + 1
                end
            end
            
            if mines < 3 then
                local odf = aiCore.Units[self.faction].minelayer .. "m" -- Guessing mine ODF
                if self.faction == 2 then odf = "svmine" end -- CCA specific
                BuildObject(odf, self.teamNum, pos)
            end
        end
    end
end

-- Helper for Engineer Base Capturing (Legacy Misns7)
function aiCore.Team:ReclaimBuilding(building, engineer)
    -- ... (existing logic)
end

-- Stealth Logic (Legacy Misn12)
function aiCore.Team:UpdateStealth(checkpoints)
    -- checkpoints = {{handle=h, range=r, order=i}, ...}
    local player = GetPlayerHandle()
    if not IsValid(player) then return end
    
    local inVehicle = not IsPerson(player)
    if inVehicle ~= self.stealthState.playerInVehicle then
        self.stealthState.playerInVehicle = inVehicle
        if not inVehicle and not self.stealthState.discovered then
            -- Trigger "Grumpy" alert if they leave the ship in a restricted zone
            return "LEFT_VEHICLE"
        end
    end
    
    -- Checkpoint Verification
    for _, cp in ipairs(checkpoints) do
        local dist = GetDistance(player, cp.handle)
        if dist < cp.range then
            if self.stealthState.lastOrder and cp.order > self.stealthState.lastOrder + 1 then
                -- Player skipped a checkpoint or went out of order
                return "OUT_OF_ORDER", cp.order
            end
            self.stealthState.lastOrder = cp.order
            return "AT_CHECKPOINT", cp.order
        end
    end
    
    return "STAYING_STEALTHY"
end

----------------------------------------------------------------------------------
-- TACTICAL LOGIC EXTENSIONS
----------------------------------------------------------------------------------

function aiCore.Team:UpdateMinelayers()
    aiCore.RemoveDead(self.minelayers)
    if #self.minelayers == 0 then return end
    
    -- 1. Ensure minefields exist
    if #self.Config.minefields == 0 then
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
            -- A. Reactive Mining (Self defense)
            local enemy = GetNearestEnemy(m)
            if IsValid(enemy) and GetDistance(m, enemy) < 200 and GetDistance(m, enemy) > 60 then
                 DropMine(m)
                 local dir = Normalize(GetPosition(m) - GetPosition(enemy))
                 Goto(m, GetPosition(m) + dir * 100)
            
            -- B. Systematic Mining (Laying Fields)
            elseif GetAmmo(m) > 0.8 then
                local field = self.Config.minefields[math.random(#self.Config.minefields)]
                Mine(m, field, 1)
            
            -- C. Resupply
            elseif GetAmmo(m) < 0.2 then
                -- Search for supply depot or return to base
                local foundSupp = false
                local supplyOdf = aiCore.Units[self.faction].supply
                for obj in ObjectsInRange(500, m) do
                    if IsOdf(obj, supplyOdf) and IsAlive(obj) then
                        Goto(m, obj, 1)
                        foundSupp = true
                        break
                    end
                end
                
                if not foundSupp and IsValid(self.recyclerMgr.handle) then
                    Goto(m, self.recyclerMgr.handle, 1)
                end
            end
        end
    end
end

function aiCore.Team:UpdateAdvancedWeapons()
    -- Consolidated Special Weapon Management (Duration/Period from aiSpecial)
    aiCore.RemoveDead(self.mortars)
    aiCore.RemoveDead(self.thumpers)
    aiCore.RemoveDead(self.fields)

    if not self.weaponTimer then self.weaponTimer = GetTime() + 1.0 end
    if GetTime() < self.weaponTimer then return end

    if not self.specialActive then
        -- Logic to ACTIVATE special weapons
        self.specialActive = true
        self.weaponTimer = GetTime() + (self.Config.specialDuration or 5.0)
        
        -- Activate for random subset
        local lists = {self.mortars, self.thumpers, self.fields}
        for _, list in ipairs(lists) do
            for _, u in ipairs(list) do
                if IsAlive(u) and math.random() < 0.7 then
                    local mask = 0
                    if list == self.thumpers then mask = aiCore.GetWeaponMask(u, "gquake")
                    elseif list == self.mortars then mask = aiCore.GetWeaponMask(u, "gmortar")
                    elseif list == self.fields then mask = aiCore.GetWeaponMask(u, {"phantom", "redfld"})
                    end
                    if mask > 0 then SetWeaponMask(u, mask) end
                end
            end
        end
        
        -- Double Weapon Users
        aiCore.RemoveDead(self.doubleUsers)
        for _, u in ipairs(self.doubleUsers) do
             if math.random() < (self.Config.doubleWeaponChance or 0.2) then
                SetWeaponMask(u, 3) -- Link 1+2
             end
        end
    else
        -- Logic to DEACTIVATE
        self.specialActive = false
        self.weaponTimer = GetTime() + (self.Config.specialPeriod or 25.0)
        
        local allSpecial = {}
        for _, list in ipairs({self.mortars, self.thumpers, self.fields, self.doubleUsers}) do
            for _, u in ipairs(list) do table.insert(allSpecial, u) end
        end
        
        for _, u in ipairs(allSpecial) do
            if IsAlive(u) then
                self:ResetWeaponMask(u)
            end
        end
    end
end

function aiCore.Team:ResetWeaponMask(h)
    local w0 = GetWeaponClass(h, 0)
    local w1 = GetWeaponClass(h, 1)
    local w2 = GetWeaponClass(h, 2)
    local w3 = GetWeaponClass(h, 3)
    
    if w0 and w3 and w0 == w3 then SetWeaponMask(h, 15) -- Link 4
    elseif w0 and w2 and w0 == w2 then SetWeaponMask(h, 7) -- Link 3
    elseif w0 and w1 and w0 == w1 then SetWeaponMask(h, 3) -- Link 2
    elseif w1 and w2 and w1 == w2 then SetWeaponMask(h, 6) -- Link 2
    else
        -- Check if it should be in double mode
        for _, du in ipairs(self.doubleUsers) do
            if du == h then SetWeaponMask(h, 3) return end
        end
        SetWeaponMask(h, 1) -- Baseline
    end
end

function aiCore.Team:UpdateHowitzers()
    aiCore.RemoveDead(self.howitzers)
    if #self.howitzers == 0 then return end
    
    local target = nil
    -- Find nearest enemy building or unit
    for h in ObjectsInRange(2000, self.howitzers[1]) do
        if GetTeamNum(h) ~= self.teamNum and IsAlive(h) and IsBuilding(h) then
            target = h
            break
        end
    end
    
    if not target then target = GetNearestEnemy(self.howitzers[1]) end
    if not IsValid(target) then return end
    
    for i, h in ipairs(self.howitzers) do
        if not IsBusy(h) then
            local dist = GetDistance(h, target)
            if dist > 350 then
                Attack(h, target)
            elseif dist < 120 then
                -- Tactical Retreat (from aiSpecial)
                local dir = Normalize(GetPosition(h) - GetPosition(target))
                Goto(h, GetPosition(h) + dir * 100)
            end
        end
    end
end

function aiCore.Team:UpdateAPCs()
    aiCore.RemoveDead(self.apcs)
    for _, apc in ipairs(self.apcs) do
        if IsAlive(apc) then
            if not IsBusy(apc) and not IsDeployed(apc) then
                local target = GetRecyclerHandle(3 - self.teamNum) -- Default enemy
                if not IsValid(target) then target = GetNearestEnemy(apc) end
                if IsValid(target) then Attack(apc, target) end
            end
            
            local enemy = GetNearestEnemy(apc)
            if IsValid(enemy) and GetDistance(apc, enemy) < 120 and not IsDeployed(apc) then
                Deploy(apc)
            end
        end
    end
end

function aiCore.Team:UpdateWrecker()
    if not self.wreckerTimer then self.wreckerTimer = GetTime() + (self.Config.wreckerInterval or 600) end
    if GetTime() > self.wreckerTimer then
        self.wreckerTimer = GetTime() + (self.Config.wreckerInterval or 600)
        local armory = GetArmoryHandle(self.teamNum)
        if IsValid(armory) and CanBuild(armory) then
            local target = GetRecyclerHandle(3 - self.teamNum)
            if IsValid(target) then BuildAt(armory, "apwrck", target, 1) end
        end
    end
end

function aiCore.Team:UpdateStrategyRotation()
    if self.strategyLocked then return end
    if not self.strategyTimer then self.strategyTimer = GetTime() + 600 end
    if GetTime() > self.strategyTimer then
        self.strategyTimer = GetTime() + 600
        local strats = {"Balanced", "Tank_Heavy", "Howitzer_Heavy", "Bomber_Heavy"}
        self:SetStrategy(strats[math.random(#strats)])
    end
end

function aiCore.Team:UpdateAutoBase()
    if not self.Config.autoBuild then return end
    local constructor = self.constructorMgr.handle
    if not IsValid(constructor) or IsBusy(constructor) then return end
    
    -- Rebuild Factory if lost
    local factory = GetFactoryHandle(self.teamNum)
    if not IsAlive(factory) and self.basePositions.factory then
        local found = false
        for _, q in ipairs(self.constructorMgr.queue) do
            if q.odf == aiCore.Units[self.faction].factory then found = true break end
        end
        if not found then self:AddBuilding(aiCore.Units[self.faction].factory, self.basePositions.factory, 5) end
    end
end

function aiCore.Team:UpdatePilotResources()
    if GetTime() > (self.pilotResTimer or 0) then
        self.pilotResTimer = GetTime() + 20.0
        aiCore.RemoveDead(self.pilots)
        if #self.pilots < (self.Config.pilotTopoff or 4) then
            local pilotOdf = aiCore.Units[self.faction].pilot
            if pilotOdf then self.recyclerMgr:addUnit(pilotOdf, 0) end
        end
    end
end

function aiCore.Team:UpdateCloakers()
    aiCore.RemoveDead(self.cloakers) -- Simple stub, usually handled by engine
end

function aiCore.Team:UpdateSoldiers()
    aiCore.RemoveDead(self.soldiers)
    for _, s in ipairs(self.soldiers) do
        if IsAlive(s) then
            local enemy = GetNearestEnemy(s)
            if IsValid(enemy) and GetDistance(s, enemy) < 100 then Attack(s, enemy) end
        end
    end
end

function aiCore.Team:UpdateGuards()
    -- Maintain squad/howitzer guards
end

function aiCore.Team:UpdateUnitRoles()
    -- Handled by pool/squad logic
end

function aiCore.Team:UpdateRescue()
    -- Send vehicle to player if they are a person
    if self.teamNum ~= 1 or not self.Config.autoRescue then return end
    local player = GetPlayerHandle()
    if IsPerson(player) and GetTime() > (self.rescueTimer or 0) then
        self.rescueTimer = GetTime() + 10.0
        local veh = self.pool[1]
        if IsValid(veh) then SetCommand(veh, AiCommand.RESCUE, 1, player) end
    end
end

function aiCore.Team:UpdateTugs()
    -- Auto-pickup relics
end

function aiCore.Team:UpdatePilots()
    -- Consolidated Pilot Management: technician spawning + sniper logic + craft stealing
    aiCore.RemoveDead(self.pilots)

    -- 1. Technician Spawning (from Barracks)
    local barracks = {}
    if IsValid(self.recyclerMgr.handle) then
        for obj in ObjectsInRange(300, self.recyclerMgr.handle) do
            local cls = aiCore.NilToString(GetClassLabel(obj))
            if string.find(cls, "barracks") or string.find(cls, "training") then
                table.insert(barracks, obj)
            end
        end
    end
    
    if #barracks > 0 and #self.pilots < (self.Config.techMax or 4) then
        if not self.techTimer then self.techTimer = GetTime() + (self.Config.techInterval or 60) end
        if GetTime() > self.techTimer then
            local fac = barracks[math.random(#barracks)]
            if IsValid(fac) and IsAlive(fac) then
                local pilotOdf = aiCore.GuessPilotOdf(fac)
                local pos = GetPosition(fac)
                pos.z = pos.z + 15 
                local pilot = BuildObject(pilotOdf, self.teamNum, pos)
                if IsValid(pilot) then
                    table.insert(self.pilots, pilot)
                    Goto(pilot, GetPositionNear(pos, 50, 150))
                end
            end
            self.techTimer = GetTime() + (self.Config.techInterval or 60) + math.random(10)
        end
    end
    
    -- 2. Individual Pilot Logic
    for _, p in ipairs(self.pilots) do
        if IsAlive(p) and IsPerson(p) then
            local weapon0 = GetWeaponClass(p, 0)
            local enemy = GetNearestEnemy(p)
            local dist = IsValid(enemy) and GetDistance(p, enemy) or 9999
            
            -- Sniper Modification
            if weapon0 and string.find(weapon0, "handgun") then
                if IsValid(enemy) and dist < 200 and math.random() < (self.Config.pilotZeal or 0.4) then
                    GiveWeapon(p, "gsnipe", 0)
                end
            elseif weapon0 and string.find(weapon0, "gsnipe") then
                -- Sniper Tactics
                if GetAmmo(p) < 0.1 or dist > 300 then
                    GiveWeapon(p, "handgun", 0)
                elseif IsValid(enemy) then
                    Attack(p, enemy)
                end
            end

            -- Craft Stealing (from aiSpecial)
            if self.Config.sniperSteal then
                local target = GetTarget(p)
                if IsValid(target) and IsCraft(target) and GetTeamNum(target) == 0 then
                    if GetDistance(p, target) < 150 then
                        GetIn(p, target)
                        if aiCore.Debug then print("Team "..self.teamNum.." pilot stealing neutral craft.") end
                    else
                        Goto(p, target)
                    end
                end
            end
            
            if not IsBusy(p) and dist > 300 then
                 -- Roam or wander back to base
                 if IsValid(self.recyclerMgr.handle) then
                    Goto(p, GetPositionNear(GetPosition(self.recyclerMgr.handle), 50, 100))
                 end
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
    -- Duplicate check
    if aiCore.IsTracked(h, self.teamNum) then return end
    
    local odf = GetOdf(h)
    local cls = aiCore.NilToString(GetClassLabel(h))
    
    -- Link to build lists
    local function link(list, mgr)
        if mgr.queue[1] and mgr.queue[1].odf == odf then
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
    
    -- Scavenger Assist (Auto-Registration)
    if cls == "scavenger" then
        self:RegisterScavenger(h)
    end
    
    -- Add to tactical lists
    if string.find(cls, "howitzer") then
        table.insert(self.howitzers, h)
    elseif string.find(cls, "apc") then
        table.insert(self.apcs, h)
    elseif string.find(cls, "minelayer") then
        table.insert(self.minelayers, h)
    elseif string.match(odf, "^cv") or string.match(odf, "^mv") or string.match(odf, "^dv") then
        table.insert(self.cloakers, h)
        table.insert(self.pool, h)
    elseif string.find(cls, "turret") or string.find(cls, "tower") or string.match(odf, "turr") then
        table.insert(self.turrets, h)
    elseif string.find(cls, "tug") or string.find(cls, "haul") then
        table.insert(self.tugHandles, h)
    end
    
    -- Advanced Weapon Users (from aiSpecial)
    local function HelperGetWeaponSlot(unit, odfName)
        for i = 0, 2 do
            local weap = GetWeaponClass(unit, i)
            if weap and string.lower(weap) == string.lower(odfName) then
                return i
            end
        end
        return -1
    end

    if HelperGetWeaponSlot(h, "gmortar") > -1 then table.insert(self.mortars, h) end
    if HelperGetWeaponSlot(h, "gquake") > -1 then table.insert(self.thumpers, h) end
    if HelperGetWeaponSlot(h, "gphantom") > -1 or HelperGetWeaponSlot(h, "gredfld") > -1 then table.insert(self.fields, h) end
    
    -- Double Weapon Tracking (Wingmen/Walkers)
    if string.find(cls, "wingman") or string.find(cls, "walker") then
        table.insert(self.doubleUsers, h) 
        table.insert(self.pool, h)
        if IsValid(self.recyclerMgr.handle) and self.teamNum ~= 1 then -- Don't force player units to base
            Goto(h, self.recyclerMgr.handle)
        end
    end

    -- Soldier Tracking (Person class, excluding pilots/snipers)
    if string.find(cls, "person") then
        local w0 = GetWeaponClass(h, 0)
        local isSniper = w0 and (string.find(string.lower(w0), "snipe") or string.find(string.lower(w0), "handgun"))
        if not isSniper then
            table.insert(self.soldiers, h)
        else
            table.insert(self.pilots, h)
        end
    end
end

function aiCore.Team:FindOptimalSiloLocation(minDist, maxDist)
    local recycler = self.recyclerMgr.handle
    if not IsValid(recycler) then return nil end
    local recyclerPos = GetPosition(recycler)
    
    minDist = minDist or self.Config.siloMinDistance
    maxDist = maxDist or self.Config.siloMaxDistance
    
    local bestPos = nil
    local bestScrapCount = -1
    
    for radius = minDist, maxDist, 50 do
        for angle = 0, 2 * math.pi, math.pi / 8 do
            local x = recyclerPos.x + radius * math.cos(angle)
            local z = recyclerPos.z + radius * math.sin(angle)
            local testPos = SetVector(x, GetTerrainHeight(x, z), z)
            
            if aiCore.IsAreaFlat(testPos, 10, 6, 0.94, 0.6) then
                local scrapCount = 0
                for h in ObjectsInRange(100, testPos) do
                    if IsOdf(h, "scavenge") or string.match(GetOdf(h), "biometal") then
                        scrapCount = scrapCount + 1
                    end
                end
                
                if scrapCount > bestScrapCount then
                    bestScrapCount = scrapCount
                    bestPos = testPos
                end
            end
        end
    end
    
    if bestPos then
        return BuildDirectionalMatrix(bestPos, Normalize(bestPos - recyclerPos))
    end
    return nil
end

function aiCore.Team:PlanDefensivePerimeter(powerCount, towersPerPower)
    local recycler = self.recyclerMgr.handle
    if not IsValid(recycler) then return end
    local recyclerPos = GetPosition(recycler)
    
    -- Smart Power Selection
    local powerKey = aiCore.DetectWorldPower()
    local powerOdf = aiCore.Units[self.faction][powerKey]
    -- Fallback if specific power ODF missing for faction
    if not powerOdf then powerOdf = aiCore.Units[self.faction].sPower end
    
    local towerOdf = aiCore.Units[self.faction].gunTower
    
    local foundPowers = 0
    local startPriority = 10 -- Start building after core infrastructure
    
    for angle = 0, 2 * math.pi, math.pi / 4 do
        if foundPowers >= powerCount then break end
        
        local dist = 120.0
        local x = recyclerPos.x + dist * math.cos(angle)
        local z = recyclerPos.z + dist * math.sin(angle)
        local pPos = SetVector(x, GetTerrainHeight(x, z), z)
        
        if aiCore.IsAreaFlat(pPos, 12, 8, 0.96, 0.7) and self:CheckBuildingSpacing(powerOdf, pPos, 60) then
            -- Found spot for power
            local pMat = BuildDirectionalMatrix(pPos, Normalize(pPos - recyclerPos))
            foundPowers = foundPowers + 1
            local pPrio = startPriority + (foundPowers * 10)
            self:AddBuilding(powerOdf, pMat, pPrio)
            
            -- Find spots for towers nearby
            local foundTowers = 0
            for tAngle = angle - 0.5, angle + 0.5, 0.2 do
                if foundTowers >= towersPerPower then break end
                
                local tX = pPos.x + 40.0 * math.cos(tAngle)
                local tZ = pPos.z + 40.0 * math.sin(tAngle)
                local tPos = SetVector(tX, GetTerrainHeight(tX, tZ), tZ)
                
                if aiCore.IsAreaFlat(tPos, 8, 4, 0.92, 0.5) and self:CheckBuildingSpacing(towerOdf, tPos, 35) then
                    local tMat = BuildDirectionalMatrix(tPos, Normalize(tPos - recyclerPos))
                    foundTowers = foundTowers + 1
                    self:AddBuilding(towerOdf, tMat, pPrio + foundTowers)
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

-- Phased Construction Helper
-- Allows mission scripts to queue a series of buildings that depend on each other
-- Example: team:QueuePhasedBuildings({{odf="abtowe", path="p1"}, {odf="abwpow", path="p2"}})
function aiCore.Team:QueuePhasedBuildings(buildingList)
    -- We'll just add them to the buildingList with increasing priority
    -- The ConstructorManager already builds in order of priority (implied by queue indexing)
    local startPriority = #self.buildingList + 1
    for i, b in ipairs(buildingList) do
        self:AddBuilding(b.odf, b.path, startPriority + i - 1)
    end
end

return aiCore
