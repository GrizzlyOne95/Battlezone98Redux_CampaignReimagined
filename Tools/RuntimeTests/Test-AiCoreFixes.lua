-- Regression coverage for the aiCore correctness fixes (bug numbers refer to the aiCore audit).
-- Each case fails against the pre-fix aiCore.lua.
local H = dofile("Tools/RuntimeTests/AiCoreTestHarness.lua")
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
    aiCore.Update()   -- the object cache rebuild waits for the first Update after Load
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
    -- The manager holds each roll for 30-45 s; it must not re-roll every second.
    local mgr = t.weaponMgr
    mgr.doubleUsers = { tank }
    mgr.doubleMaskCheckAt = {}
    local rolls = 0
    local realSet = t.SetDoubleWeaponMask
    t.SetDoubleWeaponMask = function(self, h, ...) rolls = rolls + 1 end
    local start = H.now
    for s = 0, 29 do H.now = start + s; mgr:UpdateDoubleWeapons(1.0) end
    check("bug 16: one roll in the first 30 s, not one per second", rolls == 1)
    for s = 30, 46 do H.now = start + s; mgr:UpdateDoubleWeapons(1.0) end
    check("bug 16: the unit re-rolls once the hold expires", rolls == 2)
    t.SetDoubleWeaponMask = realSet
    H.now = start
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

-- Bug 31: dynamic minefields used a non-existent "<minelayer>m" ODF and counted the wrong mine.
H.try("bug 31", function()
    aiCore.Units[4] = { minelayer = "cvmine", mine = "cvmineo", recycler = "cvrecy" }
    local t = newTeam(2, 4)
    local pos = { x = 0, y = 0, z = 0 }
    t.Config.minefields = { pos }
    local enemy = handle { team = 1, odf = "avtank", class = "wingman", craft = true, pos = { x = 10, y = 0, z = 0 } }
    H.nearestEnemy = enemy
    H.reset()
    t.dynamicMinefieldAt = 0
    t:UpdateDynamicMinefields()
    check("bug 31: the faction's mine ODF is laid (not the minelayer vehicle + 'm')",
        #H.built == 1 and H.built[1].odf == "cvmineo")
    for i = 1, 3 do H.addObject { team = 2, odf = "cvmineo", pos = { x = i, y = 0, z = 0 } } end
    H.reset()
    t.dynamicMinefieldAt = 0
    t:UpdateDynamicMinefields()
    check("bug 31: existing mines of that ODF are counted", #H.built == 0)
    H.nearestEnemy = nil
    H.objects = {}
end)

-- Bug 32: regen compared a 0..1 fraction with absolute HP and ran per frame without dt.
H.try("bug 32", function()
    local t = newTeam(2, 2)
    t.Config.passiveRegen, t.Config.regenRate = true, 10.0
    H.maxHealth = 1000
    local rec = handle { team = 2, odf = "svrecy", class = "recycler", craft = true, hp = 500 }
    local full = handle { team = 2, odf = "svmuf", class = "factory", craft = true, hp = 1000 }
    t.recyclerMgr.handle, t.factoryMgr.handle = rec, full
    H.reset()
    H.now = 200.0
    t:UpdateRegen()                    -- seeds the clock
    H.now = 200.5
    t:UpdateRegen()
    check("bug 32: regen is rate * elapsed seconds", math.abs((H.healed[rec] or 0) - 5.0) < 1e-6)
    check("bug 32: a unit at max health is not healed", H.healed[full] == nil)
    H.now = 260.0
    t:UpdateRegen()
    check("bug 32: a long gap is clamped to one second", math.abs((H.healed[rec] or 0) - 15.0) < 1e-6)
    H.maxHealth = nil
end)

-- Bug 33: DecoyState and friends were never pruned.
H.try("bug 33", function()
    local t = newTeam(2, 2)
    aiCore.ActiveTeams[2] = t
    local dead = handle { team = 2, odf = "svtank", craft = true }
    local live = handle { team = 2, odf = "svtank", craft = true }
    aiCore.DecoyState[dead], aiCore.DecoyState[live] = { nextTime = 1 }, { nextTime = 1 }
    aiCore.CommandState[dead] = { time = 0 }
    aiCore.CountermeasureState[dead] = {}
    t.producerDeployState[dead] = {}
    t.scrapOrderState[dead] = {}
    dead.valid = false
    aiCore._commandStateCleanupTimer = 0
    aiCore.UpdateCombatOnly()
    check("bug 33: the shared 60 s cleanup drops dead handles from every state table",
        aiCore.DecoyState[dead] == nil and aiCore.CommandState[dead] == nil
        and aiCore.CountermeasureState[dead] == nil and t.producerDeployState[dead] == nil
        and t.scrapOrderState[dead] == nil and aiCore.DecoyState[live] ~= nil)
    aiCore.DeleteObject(live)
    check("bug 33: DeleteObject clears the decoy state", aiCore.DecoyState[live] == nil)
    aiCore.ActiveTeams[2] = nil
end)

-- Bug 34: team 1 was hard-coded as the human team (command priority, turbo, difficulty source).
H.try("bug 34", function()
    aiCore.SetHumanTeam(3, true)
    local u = handle { team = 3, odf = "avtank", class = "wingman", craft = true }
    H.reset()
    aiCore.TrySetCommand(u, AiCommand.GO, 1, nil, { x = 1, y = 0, z = 1 })
    check("bug 34: a configured human team gets commandable priority", H.commands[#H.commands].priority == 0)
    H.turbo[u] = nil
    aiCore.TrySetTurbo(u, false)
    check("bug 34: a configured human team keeps turbo", H.turbo[u] == true)
    aiCore.SetHumanTeam(3, nil)
    local ai = handle { team = 3, odf = "avtank", class = "wingman", craft = true }
    local savedExu = exu.GetDifficulty
    exu.GetDifficulty = function() return 4 end
    aiCore.TrySetTurbo(ai, true)
    check("bug 34: AI turbo follows exu.GetDifficulty (very hard)", H.turbo[ai] == true)
    exu.GetDifficulty = function() return 1 end
    aiCore.TrySetTurbo(ai, true)
    check("bug 34: AI turbo is off below very hard", H.turbo[ai] == false)
    exu.GetDifficulty = savedExu
end)

-- Bug 35: units that change team stayed in manager lists.
H.try("bug 35", function()
    local t = newTeam(2, 2)
    local u = handle { team = 2, odf = "svhowi", class = "howitzer", craft = true }
    t.howitzerMgr.howitzers[1] = u
    t.apcMgr.apcs[1] = u
    t.minelayerMgr.minelayers[1] = u
    t.wingmanMgr.wingmen[u] = { unit = u }
    t.offensiveRetaliation[u] = { lastHealth = 1 }
    u.team = 1
    t:PruneForeignUnits()
    check("bug 35: howitzer/apc/minelayer/wingman/retaliation entries drop a captured unit",
        #t.howitzerMgr.howitzers == 0 and #t.apcMgr.apcs == 0 and #t.minelayerMgr.minelayers == 0
        and t.wingmanMgr.wingmen[u] == nil and t.offensiveRetaliation[u] == nil)
    local mgr = aiCore.OffenseRetaliationManager.new(5)
    local v = handle { team = 5, odf = "avtank", class = "wingman", craft = true }
    mgr:AddObject(v)
    v.team = 1
    mgr.updateTimer = 10
    mgr:Update()
    check("bug 35: the global offense manager drops a unit that changed team", mgr.units[v] == nil)
end)

-- Bug 36: human teams never ran offensive retaliation; the Team copy used teamNum == 1.
H.try("bug 36", function()
    aiCore.SetHumanTeam(4, true)
    local t = aiCore.Team:new(4, 1)
    check("bug 36: human defaults switch tactical orders off", t.Config.manageTacticalOrders == false)
    local w = handle { team = 4, odf = "avtank", class = "wingman", craft = true, command = AiCommand.NONE }
    local enemy = handle { team = 2, odf = "svtank", class = "wingman", craft = true }
    t.combatUnits = { w }
    w.shotBy, w.lastShot = enemy, H.now
    H.reset()
    t.offensiveRetaliationTimer = 10
    t:UpdateOffensiveRetaliation()
    check("bug 36: an idle human-team wingman retaliates (non-1 human team)",
        #H.commands == 1 and H.commands[1].command == AiCommand.ATTACK and H.commands[1].target == enemy)
    local called = false
    t.UpdateOffensiveRetaliation = function() called = true end
    pcall(t.Update, t)
    check("bug 36: Team:Update still dispatches it for a human team", called)
    aiCore.SetHumanTeam(4, nil)
end)

-- Bug 37: retreat picked the first depot, pulled artillery and never restored the order.
H.try("bug 37", function()
    local t = newTeam(2, 2)
    local far = handle { team = 2, odf = "sbrepair", class = "repairdepot", building = true, pos = { x = 500, y = 0, z = 0 } }
    local near = handle { team = 2, odf = "sbrepair", class = "repairdepot", building = true, pos = { x = 40, y = 0, z = 0 } }
    t.depotMgr.depots = { [far] = { type = "repair" }, [near] = { type = "repair" } }
    local target = handle { team = 1, odf = "avtank", class = "wingman", craft = true }
    local walker = handle { team = 2, odf = "svwalk", class = "walker", craft = true, health = 0.1,
        command = AiCommand.ATTACK, target = target }
    local howi = handle { team = 2, odf = "svhowi", class = "howitzer", craft = true, health = 0.1 }
    t.combatUnits = { walker, howi }
    H.reset()
    H.now = H.now + 10
    t.retreatTimer = 0
    t:UpdateRetreat()
    check("bug 37: the nearest repair depot is chosen", walker.command == AiCommand.GET_REPAIR and walker.target == near)
    check("bug 37: artillery is left alone", howi.command ~= AiCommand.GET_REPAIR)
    walker.health, walker.command, walker.target = 1.0, AiCommand.NONE, nil
    H.now = H.now + 3
    t:UpdateRetreat()
    check("bug 37: the interrupted order is restored after repair",
        walker.command == AiCommand.ATTACK and walker.target == target)
end)

-- Bug 38: stale isCloaked made a damaged cloaker flip-flop in combat; max health could be 0.
H.try("bug 38", function()
    local t = newTeam(2, 2)
    local u = handle { team = 2, odf = "cvtnk", class = "wingman", craft = true, health = 0.2, command = AiCommand.ATTACK }
    t.cloakMgr.cloakers = { u }
    H.reset()
    for _ = 1, 3 do
        t.cloakMgr.pulseTimer = 10
        t.cloakMgr:Update(0)
    end
    local decloaks = 0
    for _, c in ipairs(H.cloaks) do if not c.cloak then decloaks = decloaks + 1 end end
    check("bug 38: a damaged cloaker stays cloaked in combat", u.cloaked == true and decloaks == 0)
    H.maxHealth = 0
    t.cloakMgr.pulseTimer = 10
    local ok = pcall(t.cloakMgr.Update, t.cloakMgr, 0)
    H.maxHealth = nil
    check("bug 38: zero max health does not divide by zero", ok)
end)

-- Bug 39: the first WeaponManager:Update saw dt = whole game time.
H.try("bug 39", function()
    H.now = 5000.0
    local mgr = aiCore.WeaponManager.new(2)
    local seen
    mgr.UpdateThumpers = function(_, dt) seen = dt end
    mgr:Update()
    check("bug 39: the first update has dt 0", seen == 0)
    mgr.lastUpdate = 1.0
    mgr:Update()
    check("bug 39: dt is clamped to 5 s", seen == 5.0)
end)

-- Bug 40: failed native pushes were never retried; policies of dead handles lingered.
H.try("bug 40", function()
    local aiNative = require("aiNative")
    local savedFloat, savedString = GetODFFloat, GetODFString
    GetODFFloat = function(odf, _, key, default)
        if key == "maxRange" and type(odf) == "table" and odf.odf == "cpgun2" then return 120.0 end
        return default
    end
    GetODFString = function(odf, _, key, default)
        if type(odf) == "table" and odf.odf == "avtank" and key == "aiName" then return "RocketTankFriend" end
        return default
    end
    local u = H.addObject { team = 2, odf = "avtank", class = "wingman", craft = true, weapons = { [0] = "cpgun2" } }
    aiNative.ClearUnit(u)
    aiCore._nativeSyncChecked, aiCore._nextNativeTacticsSync = {}, 0
    H.nativeAttempts, H.nativeFail = 0, true
    H.now = H.now + 100
    aiCore.SyncNativeTactics()
    check("bug 40: the first sweep tries the push", H.nativeAttempts == 1)
    H.now = H.now + 1.5
    aiCore.SyncNativeTactics()
    check("bug 40: a failed push is not retried every second", H.nativeAttempts == 1)
    H.nativeFail = false
    H.now = H.now + 11
    aiCore.SyncNativeTactics()
    check("bug 40: a failed push is retried after 10 s", H.nativeAttempts == 2 and aiNative.GetUnitPolicy(u) ~= nil)
    H.objects = {}
    GetODFFloat, GetODFString = savedFloat, savedString

    local real = loadfile("Scripts/aiNative.lua")()
    local dead = { valid = false }
    real.policies[dead] = { engageRange = 1 }
    real.PruneInvalid()
    check("bug 40: aiNative.PruneInvalid drops invalid handles", real.policies[dead] == nil)
end)

-- Bug 41: a Lua error in the native target-score handler must not reach the engine.
H.try("bug 41", function()
    local t = newTeam(2, 2)
    aiCore.ActiveTeams[2] = t
    aiCore._nativeTargetScoringInstalled = false
    aiCore.InstallNativeTargetScoring()
    local unit = handle { team = 2, odf = "avtank", class = "wingman", craft = true, weapons = { [0] = "cpgun2" } }
    local cand = handle { team = 1, odf = "svtank", class = "wingman", craft = true, pos = { x = 100, y = 0, z = 0 } }
    local base = H.scoreHandler(unit, cand, 100.0, 0)
    check("bug 41: the handler scores a normal candidate", type(base) == "number")
    local savedTarget = GetTarget
    GetTarget = function() error("boom") end
    local okCall, result = pcall(H.scoreHandler, unit, cand, 100.0, 0)
    GetTarget = savedTarget
    check("bug 41: a Lua error returns nil (stock score) instead of propagating", okCall and result == nil)
    t.squads = { { leader = unit, members = {}, currentTarget = cand } }
    t.Config.nativeFocusFire = true
    aiCore.LaneCache = {}
    H.now = H.now + 10
    local focused = H.scoreHandler(unit, cand, 100.0, 0)
    t.squads[1].currentTarget = nil
    local cached = H.scoreHandler(unit, cand, 100.0, 0)
    H.now = H.now + 0.5
    local fresh = H.scoreHandler(unit, cand, 100.0, 0)
    check("bug 41: the squad target is cached for ~0.25 s, then refreshed", cached == focused and fresh > focused)
    aiCore.ActiveTeams[2] = nil
end)

-- Bug 42: raiders left the pool even when the attack order failed, and never came back.
H.try("bug 42", function()
    local t = newTeam(2, 2)
    local victim = handle { team = 1, odf = "avscav", class = "scavenger", craft = true }
    t.scrapHotspots = { { denyTarget = victim } }
    local r = handle { team = 2, odf = "svtank", class = "wingman", craft = true, command = AiCommand.NONE }
    t.pool = { r }
    H.now = H.now + 100
    aiCore.CommandState[r] = { time = H.now, cmd = AiCommand.FOLLOW }   -- throttled: TryAttack fails
    t.raiderTimer = 0
    t:UpdateRaiders()
    check("bug 42: a failed raid order leaves the unit in the pool", #t.pool == 1)
    aiCore.CommandState[r] = nil
    H.now = H.now + 20
    t:UpdateRaiders()
    check("bug 42: a dispatched raider leaves the pool", #t.pool == 0 and r.command == AiCommand.ATTACK)
    victim.alive = false
    H.now = H.now + 20
    t:UpdateRaiders()
    check("bug 42: the raider returns to the pool when its target is dead", #t.pool == 1)
end)

-- Bug 43: a player briefly in a wingman craft must not unregister it; players on foot are not soldiers.
H.try("bug 43", function()
    local t = newTeam(1, 1)
    local w = handle { team = 1, odf = "avfigh", class = "wingman", craft = true }
    t.wingmanMgr:AddObject(w)
    H.playerHandle = w
    t.wingmanMgr.updateTimer = 100
    t.wingmanMgr:Update()
    check("bug 43: a human hop-in only skips the tick", t.wingmanMgr.wingmen[w] ~= nil)
    H.playerHandle = nil
    w.team = 3
    t.wingmanMgr.updateTimer = 100
    t.wingmanMgr:Update()
    check("bug 43: a foreign-team craft is removed", t.wingmanMgr.wingmen[w] == nil)

    local onFoot = handle { team = 1, odf = "aspilo", class = "person", person = true }
    H.playerHandle = onFoot
    t:AddObject(onFoot)
    H.playerHandle = nil
    check("bug 43: a human on foot is not registered", not t.trackedSet[onFoot])
end)

-- Misc: APC sweep skip, PlayerRush cleanup, faction guard.
H.try("bug 44", function()
    local t = newTeam(2, 2)
    H.allCraftCalls = 0
    t.apcMgr.updateTimer = 100
    t.apcMgr:Update(0)
    check("bug 44: an APC manager without APCs skips the AllCraft sweep", H.allCraftCalls == 0)

    local savedExu = exu.GetDifficulty
    exu.GetDifficulty = function() return 3 end
    local stale = handle { team = 2, odf = "svtank", craft = true }
    aiCore.PlayerRushState = { nextCheck = 1e9, cleanupTime = 0, shooterCooldown = { [stale] = 1.0 } }
    stale.valid = false
    aiCore.UpdatePlayerRushAggression()
    exu.GetDifficulty = savedExu
    check("bug 44: shooter cooldown cleanup runs before the early returns",
        aiCore.PlayerRushState.shooterCooldown[stale] == nil)

    local noUnits = aiCore.Team:new(2, 9)
    local person = handle { team = 2, odf = "sspilo", class = "person", person = true }
    check("bug 44: a team with an unknown faction registers a person without error",
        pcall(noUnits.AddObject, noUnits, person))
end)

-- Save/load keeps SetHumanTeam overrides; older saves without them still load.
H.try("bug 45", function()
    aiCore.SetHumanTeam(7, true)
    local data = aiCore.Save()
    aiCore.SetHumanTeam(7, nil)
    check("bug 45: override cleared before load", aiCore.IsHumanTeam(7) == false)
    aiCore.Load(data)
    check("bug 45: human team overrides survive a save/load", aiCore.IsHumanTeam(7) == true)
    local older = aiCore.Save()
    older.humanTeamOverrides = nil
    aiCore.Load(older)
    check("bug 45: saves without overrides still load", aiCore.IsHumanTeam(7) == true)
    aiCore.SetHumanTeam(7, nil)
end)


-- Bugs 46-51: special-weapon switching (thumper/field/mine/retaliation) is context driven.
-- Weapon ranges the mock engine reports for the names below (fresh names: ranges are cached).
local specialRange = { gquake2 = 100.0, gpopgun2 = 150.0, gmortar2 = 400.0, gthrower2 = 60.0,
    cpgun2 = 100.0, cprkt2 = 400.0 }
local priorGetODFFloat = GetODFFloat
GetODFFloat = function(odf, section, key, default)
    if key == "maxRange" and type(odf) == "table" and specialRange[odf.odf] then return specialRange[odf.odf] end
    return priorGetODFFloat(odf, section, key, default)
end

local function maskWrites(u)
    local n = 0
    for _, w in ipairs(H.weaponMasks) do if w.handle == u then n = n + 1 end end
    return n
end
local function selections(u, mask)
    local n = 0
    for _, w in ipairs(H.weaponMasks) do if w.handle == u and w.mask == mask then n = n + 1 end end
    return n
end

-- Bug 46: an idle thumper user reset its mask every frame, wiping the double-weapon pick.
H.try("bug 46", function()
    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    H.now, H.nearestEnemy = 500.0, nil
    local u = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [1] = "gchain", [2] = "gcannon", [3] = "gquake2" }, mask = 7 }
    mgr.thumperUsers = { { handle = u, mask = 8 } }
    H.weaponMasks = {}
    for _ = 1, 150 do
        H.now = H.now + 0.1
        mgr:UpdateThumpers(0.1)
    end
    check("bug 46: an idle thumper user never writes the mask", maskWrites(u) == 0)
    check("bug 46: the double-weapon mask survives", u.mask == 7)
    check("bug 46: an idle thumper user is not a mask owner", next(mgr.thumperUsers[1]) ~= nil
        and not mgr.thumperUsers[1].active)
end)

-- Bug 47: the thumper fires at a walker in reach, ignores one out of reach, and switches off
-- after the walker is gone for 3 s.
H.try("bug 47", function()

    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    H.now = 600.0
    local walker = handle { team = 1, odf = "avwalk", class = "walker", craft = true, pos = { x = 0, y = 0, z = 500 } }
    local u = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [1] = "gchain", [3] = "gquake2" }, mask = 3 }
    local user = { handle = u, mask = 8 }
    mgr.thumperUsers = { user }
    H.nearestEnemy = walker
    H.weaponMasks = {}
    u.target = walker                       -- targeted walker at 500 m: out of the 100 m reach
    for _ = 1, 20 do H.now = H.now + 0.1; mgr:UpdateThumpers(0.1) end
    check("bug 47: a walker at 500 m draws no thumper", not user.active and maskWrites(u) == 0 and u.mask == 3)

    walker.pos = { x = 0, y = 0, z = 80 }
    H.now = H.now + 0.1
    mgr:UpdateThumpers(0.1)
    check("bug 47: a walker in reach switches the thumper on", user.active and u.mask == 8 and maskWrites(u) == 1)
    H.now = H.now + 0.1
    mgr:UpdateThumpers(0.1)
    check("bug 47: it stays on without rewriting the mask", user.active and maskWrites(u) == 1)

    walker.pos = { x = 0, y = 0, z = 500 }
    H.now = H.now + 2.0
    mgr:UpdateThumpers(0.1)
    check("bug 47: it stays on for the 3 s hold", user.active)
    H.now = H.now + 1.5
    mgr:UpdateThumpers(0.1)
    check("bug 47: it switches off once, restoring the mask", not user.active and u.mask == 3 and maskWrites(u) == 2)
    for _ = 1, 20 do H.now = H.now + 0.1; mgr:UpdateThumpers(0.1) end
    check("bug 47: no further mask writes while idle", maskWrites(u) == 2)

    -- Unknown weapon range falls back to the 60 m constant; a human-piloted craft is never touched.
    local u2 = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [3] = "gthumper9" }, mask = 1 }
    local user2 = { handle = u2, mask = 8 }
    mgr.thumperUsers = { user2 }
    walker.pos = { x = 0, y = 0, z = 80 }
    H.weaponMasks = {}
    mgr:UpdateThumpers(0.1)
    check("bug 47: unknown range uses the 60 m fallback", not user2.active)
    walker.pos = { x = 0, y = 0, z = 50 }
    mgr:UpdateThumpers(0.1)
    check("bug 47: a walker inside the fallback reach is thumped", user2.active)
    H.playerHandle = u2
    mgr:UpdateThumpers(0.1)
    H.playerHandle = nil
    check("bug 47: a human-piloted craft is released without touching its mask", not user2.active and u2.mask == 8)
    H.nearestEnemy = nil
end)

-- Bug 48: the random thumper trigger rolled every frame; it rolls once per period.
H.try("bug 48", function()
    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    H.now = 700.0
    local tank = handle { team = 1, odf = "avtank", class = "wingman", craft = true, pos = { x = 0, y = 0, z = 30 } }
    local u = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [1] = "gchain", [3] = "gquake2" }, mask = 3 }
    local user = { handle = u, mask = 8 }
    mgr.thumperUsers = { user }
    H.nearestEnemy = tank
    local rolls, roll = 0, 99
    local realRandom = math.random
    math.random = function() rolls = rolls + 1; return roll end
    for _ = 1, 100 do H.now = H.now + 0.1; mgr:UpdateThumpers(0.1) end
    check("bug 48: one failed roll in 10 s, no thump", rolls == 1 and not user.active and u.mask == 3)
    H.now = H.now + 6.0
    roll = 1
    mgr:UpdateThumpers(0.1)
    check("bug 48: the next period rolls again and a success switches the thumper on", rolls == 2 and user.active)
    H.now = H.now + 0.6
    mgr:UpdateThumpers(0.1)
    check("bug 48: the burst ends after thumperDuration", not user.active and u.mask == 3 and rolls == 2)
    math.random = realRandom
    H.nearestEnemy = nil
end)

-- Bug 49: an inactive thumper user is range gated; an active one is left alone.
H.try("bug 49", function()
    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    H.now = 800.0
    local foe = handle { team = 1, odf = "avfigh", class = "wingman", craft = true, pos = { x = 0, y = 0, z = 300 } }
    local u = handle { team = 2, odf = "svfigh", class = "wingman", craft = true,
        weapons = { [0] = "cpgun2", [1] = "cprkt2", [3] = "gthumper9" }, mask = 11,
        command = AiCommand.ATTACK, target = foe }
    t.combatUnits = { u }
    local user = { handle = u, mask = 8 }
    mgr.thumperUsers, mgr.retaliationState, mgr.rangeGateState = { user }, {}, {}
    mgr.rangeGateAt = 0.0
    mgr:UpdateRangeGating()
    check("bug 49: an inactive thumper user is range gated", u.mask == 10)
    u.mask, mgr.rangeGateState, mgr.rangeGateAt, user.active = 11, {}, 0.0, true
    mgr:UpdateRangeGating()
    check("bug 49: an active thumper user keeps its mask", u.mask == 11)
end)

-- Bug 50: person retaliation respects weapon range, the mortar minimum and aiming.
H.try("bug 50", function()
    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    H.now = 900.0
    local function shotBy(u, sniper)
        u.shotBy, u.lastShot = sniper, H.now
        mgr.retaliationUpdateAt = 0
        mgr:UpdateRetaliation(0.1)
    end
    local function sniperAt(z)
        return handle { team = 1, odf = "aspilo", class = "person", person = true, pos = { x = 0, y = 0, z = z } }
    end
    local function unit(weapons, mask)
        local u = handle { team = 2, odf = "svfigh", class = "wingman", craft = true, weapons = weapons, mask = mask }
        t.combatUnits = { u }
        mgr.retaliationState = {}
        return u
    end

    H.weaponMasks = {}
    local u = unit({ [0] = "gchain", [1] = "gpopgun2", [2] = "gproxmin2" }, 1)
    shotBy(u, sniperAt(250))
    check("bug 50: a sniper at 250 m draws neither popgun nor mine", u.mask == 1 and maskWrites(u) == 0
        and mgr.retaliationState[u] == nil)

    -- Popgun in range: selected once and held, not rewritten every tick.
    u = unit({ [0] = "gchain", [1] = "gpopgun2" }, 1)
    local s = sniperAt(100)
    H.weaponMasks = {}
    shotBy(u, s)
    check("bug 50: the popgun is selected at 100 m", u.mask == 2)
    H.now = H.now + 0.25
    shotBy(u, s)
    check("bug 50: the selection is not rewritten every tick", maskWrites(u) == 1)

    -- Person at 15 m: the mortar's minimum range rules it out, the mine is considered.
    u = unit({ [0] = "gchain", [1] = "gmortar2", [2] = "gproxmin2" }, 1)
    H.weaponMasks = {}
    s = sniperAt(15)
    shotBy(u, s)
    check("bug 50: at 15 m the mortar is skipped and the mine is selected", u.mask == 4)
    H.now = H.now + 0.25
    shotBy(u, s)
    check("bug 50: the mine mask is a short burst, then the prior mask returns", u.mask == 1)
    for _ = 1, 7 do H.now = H.now + 0.25; shotBy(u, s) end
    check("bug 50: no second mine within 3 s", selections(u, 4) == 1 and u.mask == 1)
    H.now = H.now + 1.5
    shotBy(u, s)
    check("bug 50: a second mine after 3 s", selections(u, 4) == 2)

    -- Same mortar at 100 m is fine.
    u = unit({ [0] = "gchain", [1] = "gmortar2" }, 1)
    shotBy(u, sniperAt(100))
    check("bug 50: the mortar is used outside its minimum range", u.mask == 2)

    -- Walker: the thumper needs the walker inside its reach.
    u = unit({ [0] = "gchain", [1] = "gquake2" }, 1)
    local walker = handle { team = 1, odf = "avwalk", class = "walker", craft = true, pos = { x = 0, y = 0, z = 500 } }
    shotBy(u, walker)
    check("bug 50: a far walker draws no retaliation thumper", u.mask == 1)
    walker.pos = { x = 0, y = 0, z = 50 }
    shotBy(u, walker)
    check("bug 50: a walker in reach does", u.mask == 2)
end)

-- Bug 51: field/mine users roll once per period, mines need an enemy close by, and absolute
-- timestamps are cleared when a game is loaded.
H.try("bug 51", function()
    local t = newTeam(2, 2)
    local mgr = t.weaponMgr
    H.now = 1000.0
    local foe = handle { team = 1, odf = "avtank", class = "wingman", craft = true, pos = { x = 0, y = 0, z = 100 } }
    local u = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [3] = "gproxmin2" }, mask = 1 }
    mgr.mineUsers = { { handle = u, mask = 8 } }
    H.nearestEnemy = foe
    local rolls = 0
    local realRandom = math.random
    math.random = function() rolls = rolls + 1; return 1 end
    H.weaponMasks = {}
    for _ = 1, 50 do H.now = H.now + 0.1; mgr:UpdateMines(0.1) end
    check("bug 51: no mine with the enemy 100 m away", rolls == 0 and maskWrites(u) == 0)
    foe.pos = { x = 0, y = 0, z = 30 }
    for _ = 1, 50 do H.now = H.now + 0.1; mgr:UpdateMines(0.1) end
    check("bug 51: one roll and one mine burst in 5 s with the enemy near",
        rolls == 1 and selections(u, 8) == 1 and maskWrites(u) == 2 and u.mask == 1)
    math.random = realRandom

    local f = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [3] = "gphantom" }, mask = 1 }
    local fuser = { handle = f, mask = 8 }
    mgr.fieldUsers = { fuser }
    math.random = function() rolls = rolls + 1; return 1 end
    rolls = 0
    for _ = 1, 150 do H.now = H.now + 0.1; mgr:UpdateFields(0.1) end   -- 15 s
    check("bug 51: a field rolls once per 40 s period", rolls == 1)
    math.random = realRandom
    check("bug 51: the field burst is over: one switch on, one reset", not fuser.active and f.mask == 1
        and maskWrites(f) == 2)

    -- Load: stale timestamps and active flags are dropped.
    local th = handle { team = 2, odf = "svtank", class = "wingman", craft = true,
        weapons = { [0] = "gchain", [1] = "gchain", [3] = "gquake2" }, mask = 8 }
    local tuser = { handle = th, mask = 8, active = true, holdUntil = 99999.0, nextRollAt = 99999.0 }
    mgr.thumperUsers = { tuser }
    fuser.nextRollAt, fuser.holdUntil = 99999.0, 99999.0
    mgr.retaliationUpdateAt = 99999.0
    local prevTeams = aiCore.ActiveTeams
    aiCore.ActiveTeams = { [2] = t }
    aiCore.ResetCombatStateAfterLoad()
    aiCore.ActiveTeams = prevTeams
    check("bug 51: a load clears thumper state and restores the mask",
        not tuser.active and tuser.holdUntil == nil and tuser.nextRollAt == nil and th.mask == 3)
    check("bug 51: a load clears field and retaliation timestamps", fuser.nextRollAt == nil
        and fuser.holdUntil == nil and mgr.retaliationUpdateAt == 0.0)
    H.nearestEnemy = nil
end)

-- Pilot/sniper audit (A1, A2, A5): any non-rifle slot-0 weapon is the sidearm, allies are never
-- sniped or stolen from, and an unreachable target is blacklisted after a timeout.
H.try("pilot sniper audit", function()
    local realRandom = math.random
    GiveWeapon = function(h, w, slot) h.weapons = h.weapons or {}; h.weapons[slot] = w end
    GetIn = function(h, target) h.gotIn = target end
    IsAliveAndPilot = function(h) return IsAlive(h) and h.occupied == true end
    SetTarget = function(h, target) h.aimedAt = target end

    local function refresh()
        aiCore.ResetObjectCacheTracking()
        for _, o in ipairs(H.objects) do aiCore.TrackWorldObject(o) end
        aiCore.RefreshObjectCache(true)
    end
    local function setup(pilotWeapon, sniper)
        H.objects, H.nearestEnemy = {}, nil
        H.reset()
        local t = newTeam(2, 2)
        local p = H.addObject { team = 2, odf = "sspilo", class = "person", person = true,
            weapons = { [0] = pilotWeapon } }
        t.pilots = { p }
        t.sniperState = { [p] = sniper }
        return t, p
    end
    local function tick(t, n)
        for _ = 1, n or 1 do H.now = H.now + 1.0; t.pilotUpdateAt = 0.0; t:UpdatePilots() end
    end
    local function gos(target)
        local n = 0
        for _, c in ipairs(H.commands) do
            if c.command == AiCommand.GO and c.target == target then n = n + 1 end
        end
        return n
    end

    -- A1: an aprifle pilot arms gsnipe, and the saved rifle comes back (not "handgun").
    H.now = 500.0
    math.random = function() return 1 end
    local t, p = setup("aprifle", true)
    local enemy = H.addObject { team = 1, odf = "avtank", class = "wingman", craft = true, occupied = true,
        pos = { x = 0, y = 0, z = 100 } }
    refresh()
    H.nearestEnemy = enemy
    tick(t, 2)
    check("A1: the pilot is ordered to attack the occupied enemy craft", p.command == AiCommand.ATTACK and p.target == enemy)
    tick(t, 2)
    check("A1: an aprifle pilot equips gsnipe", p.weapons[0] == "gsnipe" and t.pilotOrigWeapon[p] == "aprifle")
    enemy.alive = false
    tick(t, 2)
    check("A1: the original sidearm is restored, not handgun", p.weapons[0] == "aprifle")

    -- A2: never snipe an allied or own-team occupied craft.
    H.allied["2:3"] = true
    t, p = setup("sprifle", true)
    local allyCraft = H.addObject { team = 3, odf = "avtank", class = "wingman", craft = true, occupied = true,
        pos = { x = 0, y = 0, z = 100 } }
    local ownCraft = H.addObject { team = 2, odf = "svtank", class = "wingman", craft = true, occupied = true,
        pos = { x = 0, y = 0, z = 90 } }
    refresh()
    for _, cand in ipairs({ allyCraft, ownCraft }) do
        H.nearestEnemy = cand
        tick(t, 4)
    end
    check("A2: allied/own occupied craft are not sniped", p.weapons[0] == "sprifle" and p.command ~= AiCommand.ATTACK)

    -- A2/A3/A6: steal the nearest empty, armed craft that is not an ally's; two pilots never share one.
    t, p = setup("sprifle", false)
    local allyEmpty = H.addObject { team = 3, odf = "avtank", class = "wingman", craft = true,
        weapons = { [0] = "gcannon" }, pos = { x = 30, y = 0, z = 0 } }
    local farEmpty = H.addObject { team = 0, odf = "avtank", class = "wingman", craft = true,
        weapons = { [0] = "gcannon" }, pos = { x = 120, y = 0, z = 0 } }
    local nearEmpty = H.addObject { team = 0, odf = "avtank", class = "wingman", craft = true,
        weapons = { [0] = "gcannon" }, pos = { x = 60, y = 0, z = 0 } }
    local unarmed = H.addObject { team = 0, odf = "avscav", class = "scavenger", craft = true,
        pos = { x = 20, y = 0, z = 0 } }
    refresh()
    tick(t, 1)
    check("A2/A3: the nearest armed, non-allied empty craft is chosen",
        t.pilotStealTarget[p] == nearEmpty and gos(nearEmpty) == 1 and gos(allyEmpty) == 0 and gos(unarmed) == 0)
    local p2 = H.addObject { team = 2, odf = "sspilo", class = "person", person = true, weapons = { [0] = "sprifle" } }
    t.pilots = { p, p2 }
    t.sniperState[p2] = false
    tick(t, 2)
    check("A6: a second pilot takes a different craft",
        t.pilotStealTarget[p2] == farEmpty and t.pilotStealTarget[p] == nearEmpty)

    -- A5: no progress for 20 s blacklists the target for this pilot for ~60 s.
    t, p = setup("sprifle", false)
    local stuck = H.addObject { team = 0, odf = "avtank", class = "wingman", craft = true,
        weapons = { [0] = "gcannon" }, pos = { x = 100, y = 0, z = 0 } }
    refresh()
    tick(t, 12)
    check("A5: still pursuing before the timeout", t.pilotStealTarget[p] == stuck)
    tick(t, 12)
    check("A5: the unreachable craft is dropped and blacklisted",
        t.pilotStealTarget[p] == nil and (t.pilotBlacklist[p][stuck] or 0) > H.now)
    tick(t, 30)
    check("A5: it is not picked again during the blacklist", t.pilotStealTarget[p] == nil)
    tick(t, 40)
    check("A5: it is eligible again once the blacklist expires", t.pilotStealTarget[p] == stuck)

    math.random = realRandom
    H.nearestEnemy = nil
    H.allied = {}
    H.objects = {}
    local human = aiCore.AddTeam(1, 1)
    check("A4: human teams default to no pilot specials/stealing",
        human.Config.managePilotSpecials == false and human.Config.sniperSteal == false)
    aiCore.ActiveTeams = {}
end)

-- Howitzer squads (B1-B4): persistent target, range-based stand-off, once-per-target player assist.
H.try("howitzer squads", function()
    local realRandom = math.random
    local function refresh()
        aiCore.ResetObjectCacheTracking()
        for _, o in ipairs(H.objects) do aiCore.TrackWorldObject(o) end
        aiCore.RefreshObjectCache(true)
    end
    H.objects, H.nearestEnemy = {}, nil
    H.reset()
    H.now = 1000.0
    local t = newTeam(2, 2)
    t.Config.howitzerChance = 100
    local mgr = t.howitzerMgr
    local how = H.addObject { team = 2, odf = "svartl", class = "howitzer", craft = true, pos = { x = 0, y = 0, z = 0 } }
    local recy = H.addObject { team = 1, odf = "avrecy", class = "recycler", building = true,
        pos = { x = 1000, y = 0, z = 0 } }
    H.core.recycler[1] = recy
    refresh()
    mgr.howitzers = { how }

    -- B2: out of range (250 m fallback) -> GO to a stand-off point at 0.8 x range from the target.
    mgr:Update(100.0)
    local go = H.commands[1]
    check("B2: an out-of-range target draws a GO, not an attack", go and go.command == AiCommand.GO and #H.commands == 1)
    local sx = go and go.position and go.position.x or 0
    check("B2: the stand-off point is 0.8 x range from the target", math.abs((1000 - sx) - 200) < 1.0)
    local state = mgr.squadState[how]
    check("B1: the squad has a persistent target", state and state.target == recy)

    -- B3: idle at the stand-off point -> immediate attack without waiting for the 30 s cycle.
    how.pos = { x = 800, y = 0, z = 0 }
    how.command = AiCommand.NONE
    H.commands = {}
    H.now = H.now + 3.0
    mgr:Update(0.1)
    check("B3/B2: an idle howitzer in range is ordered to attack at once",
        #H.commands == 1 and H.commands[1].command == AiCommand.ATTACK and H.commands[1].target == recy)

    -- Hysteresis: between 0.9 x and 1.0 x range it keeps attacking (no new GO).
    how.pos = { x = 760, y = 0, z = 0 }   -- 240 m
    H.commands = {}
    H.now = H.now + 3.0
    mgr:UpdateSquadOrders(true)
    check("B2: an attacking howitzer keeps attacking until past full range", #H.commands == 0)

    -- B1: a higher-priority target appearing does not steal the squad's target.
    H.addObject { team = 1, odf = "avslf", class = "supplydepot", building = true, pos = { x = 500, y = 0, z = 0 } }
    refresh()
    for _ = 1, 3 do H.now = H.now + 31.0; mgr:Update(100.0) end
    check("B1: the target persists across evaluations", mgr.squadState[how].target == recy)
    recy.alive = false
    H.now = H.now + 3.0
    mgr:Update(0.1)
    local depot = mgr.squadState[how] and mgr.squadState[how].target
    check("B1: a dead target is replaced at once", depot ~= nil and depot ~= recy and depot.class == "supplydepot")

    -- B6: a howitzer is registered once.
    mgr.howitzers = {}
    mgr:AddObject(how)
    mgr:AddObject(how)
    check("B6: AddObject does not duplicate a howitzer", #mgr.howitzers == 1)

    -- B4: the player-team assist sends one stand-off GO per target and never overrides a player GO.
    H.objects, H.commands = {}, {}
    local human = aiCore.AddTeam(1, 1)
    local pm = human.howitzerMgr
    local ph = H.addObject { team = 1, odf = "avartl", class = "howitzer", craft = true, pos = { x = 0, y = 0, z = 0 } }
    local far = H.addObject { team = 2, odf = "svrecy", class = "recycler", building = true,
        pos = { x = 3000, y = 0, z = 0 } }
    pm.howitzers = { ph }
    ph.command, ph.target = AiCommand.ATTACK, far
    for _ = 1, 4 do H.now = H.now + 1.0; pm:UpdatePlayerHowitzerOrders() end
    local goCount = 0
    for _, c in ipairs(H.commands) do if c.command == AiCommand.GO then goCount = goCount + 1 end end
    check("B4: the stand-off GO is issued once per target", goCount == 1)
    ph.command, ph.target = AiCommand.GO, nil          -- the player now gives their own GO
    H.commands = {}
    for _ = 1, 3 do H.now = H.now + 1.0; pm:UpdatePlayerHowitzerOrders() end
    check("B4: a GO the player gave is never overridden", #H.commands == 0)

    math.random = realRandom
    H.objects = {}
    aiCore.ActiveTeams = {}
end)

H.finish("aiCore fix")
