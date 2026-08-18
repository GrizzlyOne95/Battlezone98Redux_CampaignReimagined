aiBuildOS = {}
--table of odfs for each faction
--[[
NSDF = 1
CCA = 2
CRA = 3
BDOG = 4
WGER = 5
PDRA = 6
RWLF = 7
PEX = 8
]]--

aiBuildOS.Factions = {NSDF = 1, CCA = 2, CRA = 3, BDOG = 4, WGER = 5, PDRA = 6, RWLF = 7, PEX = 8}

aiBuildOS.Faction = {}

aiBuildOS.Faction[aiBuildOS.Factions.NSDF] = 
{
	constructor = "avcnst",
	sPower = "abspow",
	lPower = "ablpow",
	wPower = "abwpow",
	gunTower = "abtowe",
	gunTower2 = "abtowe",
	aagn = "abaagn",
	silo = "absilo",
	biosilo = "abfilt",
	nukesilo = "abnuke",
	supply = "absupp",
	hangar = "abhang",
	lpad = "ablpad",
	barracks = "abbarr",
	cafeteria = "abcafe",
	commTower = "abcomm",
	commbunker = "abcbunk",
	hq = "abhqcp",
	mbld = "abmbld",
	storage = "abstor",
	shield = "abshld",
	recycler = "avrecy",
	factory = "avmuf",
	armory = "avslf",
	scavenger = "avscav",
	turret = "avturr",
	flak = "avflak",
	mac = "avstrl",
	scout = "avfigh",
	tank = "avtank",
	tank2 = "avtankr",
	heavytank = "avhtnk",
	superheavytank = "avshtnk",
	vtol = "avvtol",
	mru = "avmru",
	repairdepot = "avcarri",
	carrier = "avdcarr",
	drone = "avharpy",
	supporttank = "avtrum",
	lighttank = "avltnk",
	interceptor = "avrdev",
	striker = "avstrike",
	airstriker = "avastr",
	cruise = "avcruz",
	tug = "avhaul",
	howitzer = "avartl",
	heavyhowitzer = "avhartl",
	minelayer = "avmine",
	rockettank = "avrckt",
	apc = "avapc",
	bomber = "avhraz",
	walker = "avwalk",
	unique = "avltmp",
	ammo = "apammo",
	bot = "ammobot",
	repair = "aprepa"
}
	
aiBuildOS.Faction[aiBuildOS.Factions.CCA] = 
{
	constructor = "svcnst",
	sPower = "sbspow",
	lPower = "sblpow",
	wPower = "sbwpow",
	gunTower = "sbtowe",
	gunTower2 = "sbtowe",
	laser = "sblasd",
	aagn = "sbaagn",
	silo = "sbsilo",
	biosilo = "sbbios",
	supply = "sbsupp",
	hangar = "sbhang",
	lpad = "sblpad",
	barracks = "sbbarr",
	cafeteria = "sbcafe",
	commTower = "sbcomm",
	hq = "sbhqcp",
	mbld = "sbmbld",
	storage = "abstor",
	shield = "sbshld",
	recycler = "svrecy",
	factory = "svmuf",
	armory = "svslf",
	scavenger = "svscav",
	turret = "svturr",
	scout = "svfigh",
	tank = "svtank",
	heavytank = "svmtnk",
	superheavytank = "svshtnk",
	vtol = "svhind",
	mru = "svmru",
	carrier = "svcarr",
	drone = "svdrone",
	supporttank = "svktnk",
	lighttank = "svltnk",
	interceptor = "svmort",
	airstriker = "svastr",
	rammer = "svramm",
	cruise = "svcruz",
	tug = "svhaul",
	howitzer = "svartl",
	heavyhowitzer = "svhartl",
	minelayer = "svmine",
	rockettank = "svrckt",
	apc = "svapc",
	bomber = "svhraz",
	walker = "svwalk",
	ammo = "apammo",
	repair = "aprepa"
}

aiBuildOS.Faction[aiBuildOS.Factions.CRA] = 
{
	constructor = "cvcnst",
	sPower = "cbspow",
	lPower = "cblpow",
	wPower = "cbwpow",
	gunTower = "cbtowe",
	gunTower2 = "cblasr",
	silo = "cbsilo",
	supply = "cbmbld",
	hangar = "cbhang",
	barracks = "cbbarr",
	cafeteria = "cbcafe",
	commTower = "cbcomm",
	hq = "cbhqcp",
	mbld = "sbsupp",
	storage = "abstor",
	shield = "sbshld",
	recycler = "cvrecyia",
	factory = "cvmufia",
	armory = "cvslf",
	scavenger = "cvscav",
	turret = "cvturr",
	scout = "cvfigh",
	tank = "cvtnk",
	lighttank = "cvltnk",
	tug = "cvhaul",
	howitzer = "cvartl",
	minelayer = "cvmine",
	rockettank = "cvrckt",
	apc = "cvapc",
	bomber = "cvhraz",
	walker = "cvwalk",
	unique = "cvhtnk",
	ammo = "apammo",
	repair = "aprepa"
}

aiBuildOS.Faction[aiBuildOS.Factions.BDOG] = 
{
	constructor = "bvcnst",
	sPower = "bbspow",
	lPower = "bblpow",
	wPower = "bbwpow",
	gunTower = "bbtowe",
	gunTower2 = "bbtowe",
	silo = "bbsilo",
	supply = "bbsupp",
	hangar = "bbhang",
	barracks = "bbbarr",
	cafeteria = "bbcafe",
	commTower = "bbcomm",
	hq = "bbhqcp",
	mbld = "bbmbld",
	storage = "abstor",
	shield = "bbshld",
	recycler = "bvrecyia",
	factory = "bvmufia",
	armory = "bvslf",
	scavenger = "bvscav",
	turret = "bvturr",
	scout = "bvfigh",
	tank = "bvtank",
	lighttank = "bvltnk",
	tug = "bvhaul",
	howitzer = "bvartl",
	minelayer = "bvmine",
	rockettank = "bvrckt",
	apc = "bvapc",
	bomber = "bvhraz",
	walker = "bvwalk",
	interceptor = "bvrdev",
	ammo = "apammo",
	repair = "aprepa",
	
	superheavytank = "bvshtnk",
	heavytank = "bvmtnk",
	mru = "bvmru",
	supporttank = "bvtrum"
}

aiBuildOS.Faction[aiBuildOS.Factions.WGER] = 
{
	constructor = "wvcnst",
	sPower = "wbpowe",
	lPower = "wbpowe",
	wPower = "wbpowe",
	gunTower = "wbtowe",
	gunTower2 = "wbtowe",
	silo = "wbsilo",
	supply = "wbsupp",
	hangar = "wbhang",
	barracks = "wbbarr",
	cafeteria = "abcafe",
	commTower = "wbcomm",
	hq = "wbcomm",
	mbld = "wbsupp",
	storage = "abstor",
	shield = "abshld",
	recycler = "wvrecy",
	factory = "wvmuf",
	armory = "wvslf",
	scavenger = "wvscav",
	turret = "wvturr",
	scout = "wvfigh",
	tank = "wvhtnk",
	lighttank = "wvltnk",
	tug = "wvhaul",
	howitzer = "wvartl",
	minelayer = "wvmine",
	rockettank = "wvrckt",
	apc = "wvapc",
	bomber = "wvhraz",
	walker = "wvwalk",
	unique = "wvscout",
	ammo = "apammo",
	repair = "aprepa"
}

aiBuildOS.Faction[aiBuildOS.Factions.PDRA] = 
{
	constructor = "dvcnst",
	sPower = "cbspow",
	lPower = "cblpow",
	wPower = "cbwpow",
	gunTower = "dblasr",
	gunTower2 = "dbtowe",
	silo = "dbsilo",
	supply = "dbmbld",
	hangar = "dbhang",
	barracks = "dbbarr",
	cafeteria = "cbcafe",
	commTower = "dbcomm",
	hq = "cbhqcp",
	mbld = "sbsupp",
	storage = "abstor",
	shield = "sbshld",
	recycler = "dvrecy",
	factory = "dvmuf",
	armory = "dvslf",
	scavenger = "dvscav",
	turret = "dvturr",
	scout = "dvfigh",
	tank = "dvtnk",
	lighttank = "dvltnk",
	tug = "dvhaul",
	howitzer = "dvartl",
	minelayer = "dvmine",
	rockettank = "dvrckt",
	apc = "dvapc",
	bomber = "dvhraz",
	walker = "dvwalk",
	unique = "dvhtnk"
}

aiBuildOS.Faction[aiBuildOS.Factions.RWLF] = 
{
	constructor = "rvcnst",
	sPower = "sbspow",
	lPower = "sblpow",
	wPower = "sbwpow",
	gunTower = "rbtowe",
	gunTower2 = "rbtowe",
	silo = "sbsilo",
	supply = "sbsupp",
	hangar = "sbhang",
	barracks = "rbbarr",
	cafeteria = "sbcafe",
	commTower = "sbcomm",
	hq = "sbhqcp",
	mbld = "sbmbld",
	storage = "abstor",
	shield = "sbshld",
	recycler = "rvrecy",
	factory = "rvmuf",
	armory = "rvslf",
	scavenger = "rvscav",
	turret = "rvturr",
	scout = "rvfigh",
	tank = "rvtank",
	lighttank = "rvltnk",
	tug = "rvhaul",
	howitzer = "rvartl",
	minelayer = "rvmine",
	rockettank = "rvrckt",
	apc = "rvapc",
	bomber = "rvhraz",
	walker = "rvwalk",
	unique = "rvhtnk"
}

aiBuildOS.Faction[aiBuildOS.Factions.PEX] = 
{
	constructor = "fvcnst",
	sPower = "abspow",
	lPower = "ablpow",
	wPower = "abwpow",
	gunTower = "fbtowe",
	gunTower2 = "fbtowe",
	silo = "bbsilo",
	supply = "abmbld",
	hangar = "bbhang",
	barracks = "abbarr",
	cafeteria = "abcafe",
	commTower = "bbcomm",
	hq = "bbhqcp",
	mbld = "absupp",
	storage = "abstor",
	shield = "abshld",
	recycler = "fvrecy",
	factory = "fvmuf",
	armory = "fvslf",
	scavenger = "fvscav",
	turret = "fvbtur",
	scout = "fvbfig",
	tank = "fvbtan",
	lighttank = "fvbltn",
	tug = "fvhaul",
	howitzer = "fvartl",
	minelayer = "fvmine",
	rockettank = "fvbrck",
	apc = "fvbap",
	bomber = "fvbhra",
	walker = "fvwalk",
	unique = "fvsav"
}

--table of directional vectors, for use with aiBuild to control which direction a building will face when built
vecFacing = {N = SetVector(0,0,1), NE = SetVector(0.70,0.00,0.70),
            E = SetVector(1,0,0), SE = SetVector(0.70,0.00,-0.70), 
            S = SetVector(0,0,-1), SW = SetVector(-0.70,0.00,-0.70), 
            W = SetVector(-1,0,0), NW = SetVector(-0.70,0.00,0.70)}

aiBuildOS.Building = 
{
	handle = nil,
	odf = "",
	path = "",
	priority = 0
}
aiBuildOS.Building.__index = aiBuildOS.Building

aiBuildOS.Constructor = 
{
	handle = nil,
	team = 0,
	teamNum = 0,  -- NEW: Store team number separately
	queue = {},
	pulseTimer = 0.0,
	pulsePeriod = 8.0,
	sentToRecyclerArea = false  -- NEW: Track if we've already sent constructor to recycler
}

-- Updated Constructor:update() function with enhanced logic and ALL FIXES APPLIED
function aiBuildOS.Constructor:update()
	--sort the queue by priority
	table.sort(self.queue, function(one, two) return one.priority > two.priority end)
	
	--if we have a bad object in the queue, just remove it
	if self.queue[1] == nil then
		table.remove(self.queue, 1)
	end
	
	if IsValid(self.handle) then
		if #self.queue == 0 then
			-- ENHANCED FIX: All buildings are complete - manage constructor intelligently
			if IsValid(GetRecyclerHandle(self.teamNum)) then  -- FIXED: use teamNum
				local recycler = GetRecyclerHandle(self.teamNum)  -- FIXED: use teamNum
				local currentCommand = GetCurrentCommand(self.handle)
				local currentCommandStr = AiCommand[currentCommand] or "UNKNOWN"
				local distanceToRecycler = GetDistance(self.handle, recycler)
				
				-- Only send to recycler area once when all buildings are complete
				if not self.sentToRecyclerArea and distanceToRecycler >= 50.0 then
					Goto(self.handle, recycler, 0)
					self.sentToRecyclerArea = true
					print("Constructor completed all base buildings - returning to recycler area")
				end
				
				-- CRITICAL: Never issue Stop commands when near recycler!
				-- Constructor should be freely commandable by player once base is built
				-- The AI should not interfere with manual constructor control
			end
		else
			-- Reset the flag when we have buildings to construct
			self.sentToRecyclerArea = false
			
			-- Normal building logic
			if CanBuild(self.handle) and not IsBusy(self.handle) then
				--if the constructor isn't close to its target path, tell it to go until it is close, then consider building
				if not string.match(AiCommand[GetCurrentCommand(self.handle)], "GO") and GetDistance(self.handle, self.queue[1].path) > 60.0 then 
				    Goto(self.handle, self.queue[1].path, 0)
					-- In aiBuildOS.Constructor:update(), before BuildAt() call:
					elseif GetDistance(self.handle, self.queue[1].path) <= 60.0 then 
						-- Check to see if you have enough scrap
						if (GetScrap(self.teamNum) >= GetODFInt(OpenODF(self.queue[1].odf),"GameObjectClass","scrapCost")) then  -- FIXED: use teamNum
							-- ADDITIONAL CHECK: Verify no building already exists at target
							local existingBuilding = nil
							for obj in ObjectsInRange(40, self.queue[1].path) do
								if IsOdf(obj, self.queue[1].odf) and GetTeamNum(obj) == self.teamNum then  -- FIXED: use teamNum
									existingBuilding = obj
									break
								end
							end
							
							if existingBuilding then
								print("Cancelling build - "..self.queue[1].odf.." already exists at location")
								-- Associate the existing building and remove from queue
								-- FIXED: Now self.team refers to the team object with buildingList
								self.team.buildingList[self.queue[1].priority].handle = existingBuilding
								table.remove(self.queue, 1)
							else
								-- Only build if pulse timer conditions are met
								if GetTime() <= self.pulseTimer then
									-- Keep waiting
								else
									BuildAt(self.handle, self.queue[1].odf, self.queue[1].path)
									self.pulseTimer = self.pulsePeriod + math.random((0*self.pulsePeriod ),self.pulsePeriod) + GetTime()
								end
							end
						end
					end
			end
		end
	else
	    if GetConstructorHandle(self.teamNum) ~= nil then  -- FIXED: use teamNum
	        self.pulseTimer = self.pulsePeriod + math.random((0*self.pulsePeriod ),self.pulsePeriod) + GetTime()
		    self.handle = GetConstructorHandle(self.teamNum)  -- FIXED: use teamNum
		    self.sentToRecyclerArea = false  -- Reset flag for new constructor
		end
	end
end

aiBuildOS.Constructor.__index = aiBuildOS.Constructor

aiBuildOS.Team = 
{
	teamNum = 0,
	faction = 0,
	constructor = nil,
	makingNewConst = false,
	buildingList = {}
}

--num = team number, f = faction num
function aiBuildOS.Team.new(num, f)
	--In order to fully enable NEWAI on reaload, we will attempt to surmise the new AI's faction before defaulting to the provided faction.
	local aiFacOdf = ""
    local factionPrefix = ""
	if IsValid(GetRecyclerHandle(num)) then
		aiFacOdf = GetOdf(GetRecyclerHandle(num))
		print("aiBuildOS: Team "..num.."'s recycler is "..aiFacOdf)
    elseif IsValid(GetFactoryHandle(num)) then
		aiFacOdf = GetOdf(GetFactoryHandle(num))
		print("aiBuildOS: Team "..num.."'s factory is "..aiFacOdf)
    elseif IsValid(GetArmoryHandle(num)) then
		aiFacOdf = GetOdf(GetArmoryHandle(num))
		print("aiBuildOS: Team "..num.."'s armory is "..aiFacOdf)
    elseif IsValid(GetConstructorHandle(num)) then
		aiFacOdf = GetOdf(GetConstructorHandle(num))
		print("aiBuildOS: Team "..num.."'s constructor is "..aiFacOdf)
    else
		aiFacOdf = "NONE"
		print("aiBuildOS: Team "..num.." does not have any living production units, and so the faction defaults to the provided parameter, which is "..f)
    end

	factionPrefix = string.sub(aiFacOdf,1,1)
	print("aiBuildOS: The faction prefix of team "..num.." is "..factionPrefix)
	
	if factionPrefix=="a" then
		f = 1
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="s" then
		f = 2
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="b" then
		f = 4
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="c" then
		f = 3
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="m" then
		f = 5
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="p" then
		f = 6
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="f" then
		f = 8
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	elseif factionPrefix=="r" then
		f = 7
		print("aiBuildOS: The faction of team "..num.." was therefore surmised to be "..f)
	else
		print("aiBuildOS: The faction prefix of team "..num.." does not match any known records, and so the faction defaults to the provided parameter, which is "..f)
	end
	

	local newTeam = setmetatable({}, aiBuildOS.Team)
	newTeam.teamNum = num
	newTeam.faction = f
	newTeam.buildingList = {}
	
	newTeam.constructor = setmetatable({}, aiBuildOS.Constructor)
	-- FIXED: Store both team object reference AND team number
	newTeam.constructor.team = newTeam  -- Store reference to team object
	newTeam.constructor.teamNum = num   -- Store team number for functions that need it
	newTeam.constructor.handle = GetConstructorHandle(num)  -- FIXED: Use num instead of teamNum
	newTeam.constructor.queue = {}
	newTeam.constructor.pulsePeriod = 8.0
	newTeam.constructor.pulseTimer = 0.0 
	newTeam.constructor.sentToRecyclerArea = false  -- Initialize the new flag
	
	return newTeam
end

--this should be called inside of the Script's function Update()
function aiBuildOS.Team:update()
    self.constructor:update()
    
    for p, b in pairs(self.buildingList) do
        if not IsValid(b.handle) then
            -- Enhanced area-based building search
            local foundBuilding = nil
            local bestDistance = 61 -- Start beyond our threshold
            
            -- Check all objects within reasonable distance of target location
            for obj in ObjectsInRange(80, b.path) do
                if IsOdf(obj, b.odf) and GetTeamNum(obj) == self.teamNum then
                    local dist = GetDistance(obj, b.path)
                    if dist < bestDistance then
                        foundBuilding = obj
                        bestDistance = dist
                    end
                end
            end
            
            if foundBuilding and bestDistance < 60 then
                b.handle = foundBuilding
                print("Found existing building "..b.odf.." at distance "..bestDistance)
            else
                -- Additional check: scan for any buildings of same type too close
                local tooClose = false
                for nearby in ObjectsInRange(50, b.path) do -- Minimum spacing check
                    if IsOdf(nearby, b.odf) and GetTeamNum(nearby) == self.teamNum then
                        tooClose = true
                        print("Skipping "..b.odf.." - too close to existing building")
                        break
                    end
                end
                
                if not tooClose then
                    local inQueue = false
                    for i, v in ipairs(self.constructor.queue) do
                        if v.priority == p then
                            inQueue = true
                            break
                        end
                    end
                
                    if not inQueue then
                        table.insert(self.constructor.queue, b)
                        print("Building "..b.odf.." (priority: "..b.priority..") added to constructor queue")
                    end
                end
            end
        end
    end  
end

--this should be called from within the Script's function AddObject(h)
function aiBuildOS.Team:addObject(h)
    if GetTeamNum(h) ~= self.teamNum then
        return
    end
    
    if IsBuilding(h) or (string.match(GetClassLabel(h), "turret") and not string.match(GetClassLabel(h), "turrettank")) then
        if self.constructor.queue[1] ~= nil then
            local targetBuilding = self.constructor.queue[1]
            -- Check if this is the right building type AND close to intended location
            if IsOdf(h, targetBuilding.odf) and GetDistance(h, targetBuilding.path) < 60 then
                self.buildingList[targetBuilding.priority].handle = h
                table.remove(self.constructor.queue, 1)
                self.constructor.pulseTimer = self.constructor.pulsePeriod + math.random((0*self.constructor.pulsePeriod ),self.constructor.pulsePeriod) + GetTime()
                print("Successfully associated "..targetBuilding.odf.." with handle at intended location")
            end
        end
    end
end

function aiBuildOS.Team:addBuilding(odf, path, priority)
	local newBuilding = setmetatable({}, aiBuildOS.Building)
	newBuilding.handle = nil
	newBuilding.odf = odf
	newBuilding.path = path
	if priority == nil then --if no priority given, insert it at the bottom of the table and move everybody else up
	    newBuilding.priority = 1 --new unit needs to be the bottom priority
	    if self.buildingList[1] ~= nil then --no need to move anyone in the table
            for i = #self.buildingList, 1, -1 do --starting from the end of the table, scootch everybody up one to make room
                self.buildingList[i+1] = self.buildingList[i]
                self.buildingList[i+1].priority = self.buildingList[i+1].priority + 1
            end
        end
        --table.insert(self.buildingList,newBuilding) --doesn't seem to play well with metatables? anyway normally I would just use this...
        self.buildingList[1] = newBuilding --and with room now availale at the bottom of the priority list, slide our new friend in at the back of the line
	else --if priority given, then set priority based on what was specified. notice that manually set priorities can get overwritten by unprioritized items with this logic
	    newBuilding.priority = priority
	    --self.buildingList[path] = newBuilding
	    self.buildingList[newBuilding.priority] = newBuilding
	end
	if debugPrint then
        print("Building "..newBuilding.odf.." added to buildingList of team "..self.teamNum.." with priority "..newBuilding.priority)
        print("The buildingList of team "..self.teamNum.." now consists of:")
        for p, b in pairs(self.buildingList) do
            print(b.odf..", priority "..b.priority)
        end
    end
end

function aiBuildOS.Team:checkBuildingSpacing(odf, position, minDistance)
    minDistance = minDistance or 50 -- Default minimum spacing
    
    for obj in ObjectsInRange(minDistance, position) do
        if IsBuilding(obj) and GetTeamNum(obj) == self.teamNum then
            -- For same building types, use stricter spacing
            if IsOdf(obj, odf) then
                return false, "Same building type too close"
            end
            -- For different buildings, allow closer placement but still maintain some space
            if GetDistance(obj, position) < (minDistance * 0.6) then
                return false, "Different building too close"
            end
        end
    end
    
    return true, "Spacing OK"
end

aiBuildOS.Team.__index = aiBuildOS.Team

-- Return the module
return aiBuildOS