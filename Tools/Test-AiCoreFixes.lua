-- Regression coverage for the aiCore correctness fixes (bug numbers refer to the aiCore audit).
-- Each case fails against the pre-fix aiCore.lua.
local H = dofile("Tools/AiCoreTestHarness.lua")
local source = arg and arg[1] or "Scripts/aiCore.lua"
local aiCore = H.load(source)
local check, handle = H.check, H.handle

aiCore.Units[1] = { recycler = "avrecy", factory = "avmuf", constructor = "avcnst", armory = "avslf",
    scavenger = "avscav", scout = "avfigh", turret = "avturr", pilot = "aspilo", tank = "avtank", soldier = "aspilo" }
aiCore.Units[2] = { recycler = "svrecy", factory = "svmuf", constructor = "svcnst", armory = "svslf",
    scavenger = "svscav", scout = "svfigh", turret = "svturr", pilot = "sspilo", tank = "svtank" }
aiCore.Units[3] = { recycler = "cvrecy", factory = "cvmuf", constructor = "cvcnst", armory = "cvslf",
    scavenger = "cvscav", scout = "cvfigh", turret = "cvturr", pilot = "cspilo", tank = "cvtnk" }

local function newTeam(num, faction)
    local t = aiCore.Team:new(num, faction or 1)
    -- Fixture teams are AI teams: let the mocks drive them regardless of human defaults.
    t.Config.manageBase, t.Config.manageFactories, t.Config.manageConstructor = true, true, true
    t.Config.autoBuild, t.Config.manageTacticalOrders, t.Config.manageSpecialCombat = true, true, true
    return t
end

-- Bug 1: pilots/basePositions/... were class-level tables shared by every team.
H.try("bug 1", function()
    local a, b = newTeam(2), newTeam(5)
    local shared = false
    for _, key in ipairs({ "pilots", "basePositions", "activeTugJobs", "cargoJobs", "assistedUnits", "enemyTargets" }) do
        if rawget(a, key) == nil or rawget(b, key) == nil or a[key] == b[key] then shared = true end
    end
    check("bug 1: teams own their pilots/basePositions/job tables", not shared)
    a.basePositions.center = { x = 1 }
    check("bug 1: one team's base position does not leak into another", b.basePositions.center == nil)
end)

-- Bug 2: addUnit shadow entries (no build-list slot) were never consumed.
H.try("bug 2", function()
    local t = newTeam(2, 2)
    local rec = handle { team = 2, odf = "svrecy", class = "recycler", craft = true, deployed = true }
    H.core.recycler[2] = rec
    t.recyclerMgr.handle = rec
    t.recyclerMgr:addUnit("sspilo", 0)
    check("bug 2: pilot job queued once", #t.recyclerMgr.queue == 1)
    local pilot = handle { team = 2, odf = "sspilo", class = "person", person = true, pos = { x = 10, y = 0, z = 0 } }
    t:AddObject(pilot)
    check("bug 2: producing the unit consumes its shadow entry", #t.recyclerMgr.queue == 0)
    H.reset()
    t.recyclerMgr:addUnit("sspilo", 0)
    check("bug 2: the slot can be queued again afterwards", #t.recyclerMgr.queue == 1)
end)

-- Bug 3: retaliation must not pick the inert mdmgun, and must restore the prior mask.
H.try("bug 3", function()
    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    local tank = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [3] = "gmdmgun" }, mask = 3 }
    local sniper = handle { team = 1, odf = "aspilo", class = "person", person = true }
    t.combatUnits = { tank }
    tank.shotBy, tank.lastShot = sniper, H.now
    mgr.retaliationUpdateAt = 0
    mgr:UpdateRetaliation(0.1)
    check("bug 3: inert mdmgun is never selected as the retaliation weapon", tank.mask == 3)

    local gunner = handle { team = 2, odf = "svfigh", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [1] = "gpopgun" }, mask = 1 }
    t.combatUnits = { gunner }
    gunner.shotBy, gunner.lastShot = sniper, H.now
    mgr.retaliationUpdateAt = 0
    mgr:UpdateRetaliation(0.1)
    check("bug 3: popgun is selected against the sniper", gunner.mask == 2)
    H.now = H.now + 10.0
    gunner.shotBy = nil
    mgr.retaliationUpdateAt = 0
    mgr:UpdateRetaliation(0.1)
    check("bug 3: the prior weapon mask is restored when retaliation ends", gunner.mask == 1)
end)

-- Bug 4: time-sliced managers got one frame's step instead of the time since their last run.
H.try("bug 4", function()
    local t = newTeam(2, 2)
    t.Config.manageBase, t.Config.autoBuild = false, false
    local seen = {}
    t.cloakMgr.Update = function(_, dt) seen[#seen + 1] = dt end
    for _ = 1, 9 do
        H.now = H.now + 0.1
        pcall(t.Update, t)
    end
    check("bug 4: cloak manager receives the elapsed time between its runs",
        #seen >= 2 and math.abs(seen[2] - 0.4) < 0.05)
    local cm = aiCore.CloakingManager.new(2)
    cm.teamObj = t
    local u = handle { team = 2, odf = "cvfigh", class = "wingman", craft = true }
    cm.cloakers = { u }
    H.cloaks = {}
    cm:Update(1.5); cm:Update(1.5)
    check("bug 4: cloak pulse period is measured in elapsed time, not frames", #H.cloaks == 1)
end)

-- Bug 5: a destroyed factory (MUF) is a recycler build, never a constructor job.
H.try("bug 5", function()
    local t = newTeam(2, 2)
    local rec = handle { team = 2, odf = "svrecy", class = "recycler", craft = true, deployed = true }
    local con = handle { team = 2, odf = "svcnst", class = "constructionrig", craft = true }
    H.core.recycler[2], H.core.constructor[2], H.core.factory[2] = rec, con, nil
    t.recyclerMgr.handle, t.constructorMgr.handle = rec, con
    t.basePositions.factory = { x = 5, y = 0, z = 5 }
    t.expandTimer = H.now + 1000
    t:UpdateAutoBase()
    check("bug 5: no constructor job is created for the factory vehicle", #t.constructorMgr.queue == 0 and next(t.buildingList) == nil)
    local queued = false
    for _, q in ipairs(t.recyclerMgr.queue) do if q.odf == "svmuf" then queued = true end end
    check("bug 5: the recycler is asked to build the replacement factory", queued)
end)

-- Bug 6: neighbouring same-type plans must not alias to one building.
H.try("bug 6", function()
    local t = newTeam(2, 2)
    local rec = handle { team = 2, odf = "svrecy", class = "recycler", craft = true }
    H.core.recycler[2] = rec
    t.constructorMgr.handle = nil
    t.buildingList = {
        [10] = { odf = "svtowe", path = { x = 0, y = 0, z = 0 }, priority = 10 },
        [11] = { odf = "svtowe", path = { x = 35, y = 0, z = 0 }, priority = 11 },
    }
    H.objects = {}
    H.addObject { team = 2, odf = "svtowe", building = true, class = "turret", pos = { x = 0, y = 0, z = 0 } }
    t:CheckConstruction()
    check("bug 6: first tower links to the existing tower", t.buildingList[10].handle ~= nil)
    check("bug 6: the second tower plan is not aliased to the first tower", t.buildingList[11].handle == nil)
    local queuedSecond = false
    for _, q in ipairs(t.constructorMgr.queue) do if q.priority == 11 then queuedSecond = true end end
    check("bug 6: the second tower is queued to be built", queuedSecond)
    H.objects = {}
end)

-- Bug 7: one failing team/manager must not stop every other team.
H.try("bug 7", function()
    local savedTeams = aiCore.ActiveTeams
    local ran = {}
    aiCore.ActiveTeams = {
        [2] = { Update = function() error("boom from team 2") end },
        [5] = { Update = function() ran[5] = (ran[5] or 0) + 1 end },
    }
    local out = {}
    local realPrint = print
    print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
    local ok1 = pcall(aiCore.Update)
    H.now = H.now + 0.2
    local ok2 = pcall(aiCore.Update)
    print = realPrint
    aiCore.ActiveTeams = savedTeams
    check("bug 7: aiCore.Update survives a failing team", ok1 and ok2)
    check("bug 7: the other team keeps updating", ran[5] == 2)
    local logged = 0
    for _, line in ipairs(out) do if string.find(line, "boom from team 2", 1, true) then logged = logged + 1 end end
    check("bug 7: the same error is logged once", logged == 1)
end)

-- Bug 8: CRA scavengers (cv* odfs) must not enter the combat pool.
H.try("bug 8", function()
    local t = newTeam(3, 3)
    local rec = handle { team = 3, odf = "cvrecy", class = "recycler", craft = true }
    H.core.recycler[3] = rec
    t.recyclerMgr.handle = rec
    t.recyclerBuildList[1] = { odf = "cvscav", priority = 1 }
    t.recyclerMgr.queue = { { odf = "cvscav", priority = 1 } }
    local scav = handle { team = 3, odf = "cvscav", class = "scavenger", craft = true, pos = { x = 5, y = 0, z = 0 } }
    t:AddObject(scav)
    local inPool, inCloakers = false, false
    for _, u in ipairs(t.pool) do if u == scav then inPool = true end end
    for _, u in ipairs(t.cloakers) do if u == scav then inCloakers = true end end
    check("bug 8: a linked CRA scavenger is not added to the combat pool", not inPool and not inCloakers)
    t.recyclerBuildList[2] = { odf = "cvtnk", priority = 2 }
    t.recyclerMgr.queue = { { odf = "cvtnk", priority = 2 } }
    local tank = handle { team = 3, odf = "cvtnk", class = "wingman", craft = true, pos = { x = 5, y = 0, z = 0 } }
    t:AddObject(tank)
    local tankInPool = false
    for _, u in ipairs(t.pool) do if u == tank then tankInPool = true end end
    check("bug 8: a CRA combat tank still joins the pool", tankInPool)
end)

-- Bug 9: the cloak manager never touches a human-piloted craft.
H.try("bug 9", function()
    local t = newTeam(1, 3)
    local mine = handle { team = 1, odf = "cvfigh", class = "wingman", craft = true }
    H.playerHandle = mine
    t.cloakMgr.cloakers = { mine }
    H.cloaks = {}
    t.cloakMgr.pulseTimer = 100.0
    t.cloakMgr:Update(10.0)
    check("bug 9: a human-piloted CRA craft is not re-cloaked", #H.cloaks == 0)
    H.playerHandle = nil
end)

-- Bug 10: weapon-mask resets must not hit a human-piloted craft.
H.try("bug 10", function()
    local t = newTeam(1, 1)
    local mine = handle { team = 1, odf = "avtank", class = "wingman", craft = true,
        weapons = { [0] = "gquake", [1] = "gchain" }, mask = 2 }
    H.playerHandle = mine
    local mgr = t.weaponMgr
    mgr.thumperUsers = { { handle = mine, mask = 1, timer = 5.0 } }
    mgr.fieldUsers = { { handle = mine, mask = 1, timer = 15.0 } }
    mgr.mineUsers = { { handle = mine, mask = 1, timer = 5.0 } }
    H.weaponMasks = {}
    mgr:UpdateThumpers(0.1)
    mgr:UpdateFields(0.1)
    mgr:UpdateMines(0.1)
    check("bug 10: the player's weapon mask is never rewritten", #H.weaponMasks == 0 and mine.mask == 2)
    H.playerHandle = nil
end)

-- Bug 12: StripCircular drops only true cycles, not shared (DAG) tables.
H.try("bug 12", function()
    local shared = { x = 1, y = 2 }
    local data = { plan = { path = shared }, job = { path = shared } }
    local out = aiCore.StripCircular(data)
    check("bug 12: a table referenced twice survives in both places", out.plan.path and out.job.path
        and out.plan.path.x == 1 and out.job.path.y == 2)
    local cyc = { name = "a" }
    cyc.self = cyc
    local out2 = aiCore.StripCircular({ c = cyc })
    check("bug 12: a real cycle is still cut", out2.c.name == "a" and out2.c.self == nil)
end)

-- Bug 13: Load restores squad.teamObj and rebuilds the object cache.
H.try("bug 13", function()
    local t = newTeam(2, 2)
    local leader = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
    local sq = aiCore.Squad:new(leader)
    sq.teamObj = t
    t.squads = { sq }
    aiCore.ActiveTeams = { [2] = t }
    local saved = aiCore.Save()
    H.objects = {}
    local alive1 = H.addObject { team = 2, odf = "svtank", class = "wingman", craft = true }
    aiCore.ResetObjectCacheTracking()
    aiCore.Load(saved)
    local loadedTeam = aiCore.ActiveTeams[2]
    check("bug 13: loaded squads point back at their team", loadedTeam.squads[1].teamObj == loadedTeam)
    check("bug 13: the object cache is repopulated after Load", #aiCore.GetCachedTeamCraft(2) == 1
        and aiCore.GetCachedTeamCraft(2)[1] == alive1)
    check("bug 1/13: loaded teams keep their own tables",
        type(rawget(loadedTeam, "pilots")) == "table" and type(rawget(loadedTeam, "basePositions")) == "table")
    H.objects = {}
    aiCore.ActiveTeams = {}
end)

-- Bug 14: a constructor job the engine keeps rejecting must time out and free the queue.
H.try("bug 14", function()
    H.buildAts = {}
    local t = newTeam(2, 2)
    local con = handle { team = 2, odf = "svcnst", class = "constructionrig", craft = true, canBuild = true }
    H.core.constructor[2] = con
    t.constructorMgr.handle = con
    t.Config.buildingPlacementRetryDelay = 1
    t.CanIssueBuildingByRules = function() return true end
    t.ValidateBuildingPlacement = function() return true end
    t.constructorMgr.queue = {
        { odf = "svtowe", path = { x = 0, y = 0, z = 0 }, priority = 1 },
        { odf = "svpowr", path = { x = 200, y = 0, z = 0 }, priority = 2 },
    }
    H.costs.svtowe = 10
    local mgr = t.constructorMgr
    local reachedSecond = false
    for _ = 1, 600 do
        H.now = H.now + 3.0
        mgr.pulseTimer = 0
        mgr:update()
        if mgr.activeJob and mgr.activeJob.odf == "svpowr" then reachedSecond = true break end
    end
    check("bug 14: a rejected constructor job eventually lets the next job start", reachedSecond)
    local attempts = 0
    for _, b in ipairs(H.buildAts) do if b.odf == "svtowe" then attempts = attempts + 1 end end
    check("bug 14: BuildAt retries are capped", attempts <= 6 * 3)
end)

-- Bug 15: SetStrategy must not requeue a composition that is already in the producer.
H.try("bug 15", function()
    H.reset()
    local t = newTeam(2, 2)
    local rec = handle { team = 2, odf = "svrecy", class = "recycler", craft = true, deployed = true }
    H.core.recycler[2] = rec
    t.recyclerMgr.handle = rec
    t:SetStrategy("Balanced")
    t:CheckBuildList(t.recyclerBuildList, t.recyclerMgr)
    t:CheckBuildList(t.factoryBuildList, t.factoryMgr)
    local before = #(producer.Queue[2] or {})
    t:SetStrategy("Balanced")
    t:CheckBuildList(t.recyclerBuildList, t.recyclerMgr)
    t:CheckBuildList(t.factoryBuildList, t.factoryMgr)
    local after = #(producer.Queue[2] or {})
    check("bug 15: the composition was queued", before > 0)
    check("bug 15: re-setting the strategy does not double the queued work", after == before)
end)

-- Bug 16: a failed double-weapon roll resets to single weapons; no unbounded list growth.
H.try("bug 16", function()
    local t = newTeam(2, 2)
    local tank = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [1] = "gcannon" }, mask = 1 }
    local realRandom = math.random
    math.random = function() return 1 end
    t:SetDoubleWeaponMask(tank, 100, 0)
    check("bug 16: a successful roll applies the double mask", tank.mask == 3)
    math.random = function() return 100 end
    t:SetDoubleWeaponMask(tank, 1, 0)
    math.random = realRandom
    check("bug 16: a failed roll puts the unit back on single weapons", tank.mask == 1)
    local grew = t.doubleUsers and #t.doubleUsers or 0
    math.random = function() return 1 end
    for _ = 1, 10 do t:SetDoubleWeaponMask(tank, 100, 0) end
    math.random = realRandom
    check("bug 16: repeated successes do not grow the team list", (t.doubleUsers and #t.doubleUsers or 0) == grew)
end)

-- Bug 17: a minelayer with no reachable depot must retry instead of sticking in "reloading".
H.try("bug 17", function()
    local t = newTeam(2, 2)
    local mgr = t.minelayerMgr
    local ml = handle { team = 2, odf = "svmine", class = "minelayer", craft = true, ammo = 0.05 }
    mgr.minelayers = { ml }
    mgr.minefields = { { x = 100, y = 0, z = 0 } }
    mgr.currentField[ml], mgr.outbound[ml], mgr.laying[ml], mgr.reloading[ml] = 0, false, false, false
    H.objects = {}
    H.commands = {}
    mgr:Update()
    check("bug 17: no depot yet, nothing issued", #H.commands == 0)
    local depot = H.addObject { team = 2, odf = "svsupp", class = "supplydepot", building = true, pos = { x = 50, y = 0, z = 0 } }
    H.now = H.now + 6.0
    mgr:Update()
    check("bug 17: the unit is sent to the depot once one exists",
        #H.commands == 1 and H.commands[1].command == AiCommand.GO and H.commands[1].target == depot)
    H.objects = {}
end)

-- Bug 18: fewer than three howitzers still form a squad and get orders.
H.try("bug 18", function()
    local t = newTeam(2, 2)
    local mgr = t.howitzerMgr
    local how = handle { team = 2, odf = "svartl", class = "howitzer", craft = true, pos = { x = 0, y = 0, z = 0 } }
    mgr.howitzers = { how }
    mgr:Update(100.0)
    check("bug 18: a single howitzer forms a squad", mgr.squads[1] ~= nil and mgr.squads[1][1] == how)
    mgr.howitzers = {}
    mgr:Update(100.0)
    check("bug 18: losing every howitzer clears the stale squads", next(mgr.squads) == nil)
end)

-- Bug 19: a built-but-unforwarded unit must not be rebuilt by stuck-order recovery.
H.try("bug 19", function()
    H.reset()
    H.objects = {}
    local t = newTeam(2, 2)
    local rec = handle { team = 2, odf = "svrecy", class = "recycler", craft = true, deployed = true }
    H.core.recycler[2] = rec
    t.recyclerMgr.handle = rec
    t.constructorMgr.handle = nil
    t.CanIssueUnitByRules = function() return true end
    t.UpdateBuildAccountState = function() end
    H.objects[1] = rec
    producer.QueueJob("svtank", 2, nil, nil, { priority = 1, type = "unit", producer = "recycler" })
    producer.ProcessQueues(t)
    check("bug 19: the build was ordered", #H.builds == 1 and producer.Orders[rec] ~= nil)
    -- The unit appears, but nothing calls aiCore.AddObject for it.
    H.addObject { team = 2, odf = "svtank", class = "wingman", craft = true, pos = { x = 20, y = 0, z = 0 } }
    H.now = H.now + 25.0
    producer.ProcessQueues(t)
    check("bug 19: the finished build is not requeued", producer.Orders[rec] == nil and #producer.Queue[2] == 0)
    H.objects = {}
end)

-- Bug 20: craft whose team changed leave the per-team lists.
H.try("bug 20", function()
    local t = newTeam(2, 2)
    local stolen = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
    t.combatUnits = { stolen }
    t.pool = { stolen }
    t.weaponMgr.mortarUsers = { { handle = stolen, mask = 1 } }
    stolen.team = 5
    t:PruneForeignUnits()
    check("bug 20: stolen craft are dropped from the team lists",
        #t.combatUnits == 0 and #t.pool == 0 and #t.weaponMgr.mortarUsers == 0)
end)

-- Bug 21: overrides for a team that does not exist yet must not rewrite the global default.
H.try("bug 21", function()
    local before = aiCore.DefaultNativeConfig.nativeStandoffFraction
    aiCore.SetNativeTacticsConfig(9, { nativeStandoffFraction = 0.123 })
    check("bug 21: the global default config is untouched", aiCore.DefaultNativeConfig.nativeStandoffFraction == before)
    local team = aiCore.AddTeam(9, 1)
    check("bug 21: the parked override applies once the team exists", team.Config.nativeStandoffFraction == 0.123)
    aiCore.ActiveTeams[9] = nil
end)

-- Bug 22: negative missile-threat lookups are cached.
H.try("bug 22", function()
    H.openOdfCalls = {}
    for _ = 1, 20 do aiCore.GetMissileThreatType("gplainbullet") end
    check("bug 22: a non-missile ordnance odf is opened once, not per bullet", (H.openOdfCalls["gplainbullet"] or 0) == 1)
end)

-- Bug 23: empty native-tactics results are not re-probed every second.
H.try("bug 23", function()
    local t = aiCore.AddTeam(7, 1)
    t.Config.nativeTactics = true
    H.addObject { team = 7, odf = "avfighx", class = "wingman", craft = true, weapons = { [0] = "gnorange" } }
    H.now = H.now + 2.0
    aiCore.SyncNativeTactics()
    local first = (H.openOdfCalls["gnorange"] or 0)
    H.now = H.now + 2.0
    aiCore.SyncNativeTactics()
    H.now = H.now + 2.0
    aiCore.SyncNativeTactics()
    check("bug 23: no ODF re-probe every second for an empty policy", (H.openOdfCalls["gnorange"] or 0) == first)
    H.objects = {}
    aiCore.ActiveTeams[7] = nil
end)

-- Bug 25: class labels are compared after stripping null padding.
H.try("bug 25", function()
    local t = newTeam(1, 1)
    local w = handle { team = 1, odf = "avfigh", class = "wingman\0\0", craft = true }
    t.wingmanMgr:AddObject(w)
    check("bug 25: a null-padded wingman class still registers", t.wingmanMgr.wingmen[w] ~= nil)
    local d = handle { team = 1, odf = "abhang", class = "repairdepot\0", building = true }
    t.wingmanMgr:AddObject(d)
    check("bug 25: a null-padded depot class still registers", t.wingmanMgr.repairDepots[d] == true)
end)

-- Bug 27: maintain list priority order is deterministic.
H.try("bug 27", function()
    local t = newTeam(2, 2)
    t:SetMaintainList({ tank = 1, scout = 2, turret = 1 }, { tank = 2, scout = 1 }, false)
    local strat = aiCore.Strategies["__custom__2"]
    local rec = table.concat(strat.Recycler, ",")
    local fac = table.concat(strat.Factory, ",")
    check("bug 27: maintain list order is sorted by unit type", rec == "scout,scout,tank,turret" and fac == "scout,tank,tank")
end)

-- Bug 30: a throttled/blocked wingman command must not commit its bookkeeping.
H.try("bug 30", function()
    local t = newTeam(1, 1)
    local w = handle { team = 1, odf = "avfigh", class = "wingman", craft = true, health = 0.1, command = AiCommand.FOLLOW }
    t.wingmanMgr:AddObject(w)
    local depot = handle { team = 1, odf = "abhang", class = "repairdepot", building = true, pos = { x = 30, y = 0, z = 0 } }
    t.wingmanMgr.repairDepots[depot] = true
    aiCore.CommandState[w] = { time = H.now, cmd = AiCommand.FOLLOW }   -- throttled
    local entry = t.wingmanMgr.wingmen[w]
    entry.lastCommandTime = -1000
    t.wingmanMgr:UpdateWingman(entry)
    check("bug 30: a rejected command leaves previousCommand and the cooldown untouched",
        entry.previousCommand == nil and entry.lastCommandTime == -1000)
    H.now = H.now + 2.0
    t.wingmanMgr:UpdateWingman(entry)
    check("bug 30: once allowed, the previous command is saved", entry.previousCommand == AiCommand.FOLLOW)
end)

-- exu.GetMass/SetMass casing and no global shadowing.
H.try("mass", function()
    local u = handle { team = 2, odf = "svtank", class = "walker", craft = true }
    aiCore.ApplyDynamicMass(u)
    check("exu.SetMass (not the lowercase name) is used", H.exuMass[u] == 4000)
    check("aiCore no longer defines global GetMass/SetMass", rawget(_G, "GetMass") == nil and rawget(_G, "SetMass") == nil)
end)

-- TrySetTurbo has no lowercase fallback.
H.try("turbo", function()
    local u = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
    aiCore.TrySetTurbo(u, true)
    check("TrySetTurbo uses exu.SetUnitTurbo only", H.lowerTurboCalls == 0 and H.turbo[u] ~= nil)
    local saved = exu.SetUnitTurbo
    exu.SetUnitTurbo = nil
    local ok = aiCore.TrySetTurbo(u, true)
    exu.SetUnitTurbo = saved
    check("TrySetTurbo does not fall back to a lowercase name", ok == false and H.lowerTurboCalls == 0)
end)

H.finish("aiCore fix")
