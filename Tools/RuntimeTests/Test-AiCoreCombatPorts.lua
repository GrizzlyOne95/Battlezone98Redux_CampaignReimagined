-- Regression coverage for the BZP-inspired combat ports in aiCore: fire-lane target penalty,
-- attack-close, range-gated weapon masks, stuck detection, UpdateCombatOnly native sync and the
-- tank/walker native profiles. Mock engine only; run from the repository root.
local H = dofile("Tools/RuntimeTests/AiCoreTestHarness.lua")
local aiCore = H.load(arg and arg[1] or "Scripts/aiCore.lua")
local check, handle = H.check, H.handle
local FORMATION, ATTACK, GO, FOLLOW = AiCommand.FORMATION, AiCommand.ATTACK, AiCommand.GO, AiCommand.FOLLOW

-- ODF-level facts the mock engine reports (aiName tokens, weapon ranges).
local odfStrings = {
    avtank = { aiName = "RocketTankFriend", aiName2 = "RocketTankEnemy" },
    avltnk = { aiName = "RocketTankFriend", aiName2 = "RocketTankEnemy" },
    avwalk = { aiName = "GechFriend", aiName2 = "GechEnemy" },
    avturr2 = { aiName = "TurretTankFriend", aiName2 = "TurretTankEnemy" },
    avbomb = { aiName = "BomberFriend", aiName2 = "BomberEnemy" },
    avscout = { aiName = "ScoutFriend", aiName2 = "ScoutEnemy" },
}
local weaponRange = { cpgun = 100.0, cprkt = 400.0, cpgun2 = 120.0, cpmid = 150.0 }
GetODFString = function(odf, _, key, default)
    local entry = type(odf) == "table" and odfStrings[odf.odf]
    if entry and entry[key] then return entry[key] end
    return default
end
GetODFFloat = function(odf, _, key, default)
    if key == "maxRange" and type(odf) == "table" and weaponRange[odf.odf] then return weaponRange[odf.odf] end
    return default
end

local function newTeam(num)
    local t = aiCore.Team:new(num, 2)
    t.Config.manageBase, t.Config.manageTacticalOrders, t.Config.manageSpecialCombat = false, true, true
    aiCore.ActiveTeams[num] = t
    return t
end

local function craft(fields)
    fields.craft = true
    fields.class = fields.class or "wingman"
    return H.addObject(fields)
end

local function pos(x, y, z) return { x = x, y = y or 0, z = z or 0 } end

-- 1. Fire-lane penalty ------------------------------------------------------------------
H.try("lane", function()
    H.objects = {}
    aiCore.ResetObjectCacheTracking()
    aiCore.LaneCache = {}
    local team = newTeam(2)
    check("lane: native target scoring installs", aiCore.InstallNativeTargetScoring() == true and H.scoreHandler ~= nil)
    local unit = craft { team = 2, odf = "svfigh", pos = pos(0, 0, 0) }
    local foe = craft { team = 1, odf = "avfigh", pos = pos(0, 0, 100) }
    local ally = craft { team = 2, odf = "svfigh", pos = pos(0, 0, 50) }
    for _, h in ipairs({ unit, foe, ally }) do aiCore.TrackWorldObject(h) end

    local clear
    ally.pos = pos(60, 0, 50)
    H.now = 10.0
    clear = H.scoreHandler(unit, foe, 100.0)
    ally.pos = pos(0, 0, 50)
    H.now = 11.0
    local blocked = H.scoreHandler(unit, foe, 100.0)
    check("lane: an ally in the lane adds the 120 penalty", math.abs((blocked - clear) - 120.0) < 1e-6)

    ally.pos = pos(40, 0, 50)           -- off the line (angle ~38 deg)
    H.now = 12.0
    check("lane: an off-lane ally adds nothing", H.scoreHandler(unit, foe, 100.0) == clear)
    ally.pos = pos(0, 0, -50)           -- behind the shooter
    H.now = 13.0
    check("lane: an ally behind the unit adds nothing", H.scoreHandler(unit, foe, 100.0) == clear)
    ally.pos = pos(0, 0, 150)           -- beyond the target
    H.now = 14.0
    check("lane: an ally beyond the candidate adds nothing", H.scoreHandler(unit, foe, 100.0) == clear)
    ally.pos = pos(0, 0, 3)             -- inside the 5 m minimum
    H.now = 15.0
    check("lane: an ally closer than 5 m adds nothing", H.scoreHandler(unit, foe, 100.0) == clear)
    -- Close to the 8.5 degree cone edge but ~15 m off the line at 100 m: the perpendicular cap rejects it.
    local far = craft { team = 1, odf = "avfigh", pos = pos(0, 0, 400) }
    aiCore.TrackWorldObject(far)
    ally.pos = pos(10, 0, 300)          -- cosine > 0.9994 but 10 m off: still inside the 12 m cap
    H.now = 16.0
    local capHit = H.scoreHandler(unit, far, 400.0)
    ally.pos = pos(13, 0, 300)          -- cosine ~0.9991 (inside cone) but 13 m off the line
    H.now = 17.0
    local capMiss = H.scoreHandler(unit, far, 400.0)
    check("lane: the 12 m perpendicular cap limits the long-range cone", math.abs((capHit - capMiss) - 120.0) < 1e-6)

    -- Allied (not same-team) craft block too.
    H.allied["2:3"] = true
    local friend = craft { team = 3, odf = "avfigh", pos = pos(0, 0, 50) }
    aiCore.TrackWorldObject(friend)
    ally.pos = pos(60, 0, 50)
    H.now = 18.0
    check("lane: an allied-team craft blocks the lane", H.scoreHandler(unit, foe, 100.0) - clear >= 120.0 - 1e-6)
    H.allied["2:3"] = nil

    -- Config off.
    friend.valid = false
    ally.pos = pos(0, 0, 50)
    team.Config.nativeTargetBlockedPenalty = 0
    H.now = 19.0
    check("lane: penalty 0 disables the check", H.scoreHandler(unit, foe, 100.0) == clear)
    team.Config.nativeTargetBlockedPenalty = 120.0

    -- Cache rebuilt at most once per 0.5 s.
    H.now = 30.0
    H.scoreHandler(unit, foe, 100.0)
    local builds = aiCore.LaneCache[2].builds
    for _ = 1, 20 do H.scoreHandler(unit, foe, 100.0) end
    H.now = 30.4
    H.scoreHandler(unit, foe, 100.0)
    check("lane: the friendly cache is not rebuilt within 0.5 s", aiCore.LaneCache[2].builds == builds)
    H.now = 30.6
    H.scoreHandler(unit, foe, 100.0)
    check("lane: the friendly cache refreshes after 0.5 s", aiCore.LaneCache[2].builds == builds + 1)
    aiCore.ActiveTeams = {}
end)

-- 2. Attack-close -------------------------------------------------------------------------
H.try("attack close", function()
    H.objects, H.playerHandle = {}, nil
    aiCore.ResetObjectCacheTracking()
    aiCore.CommandState = {}
    local team = newTeam(2)
    local function setup(unitFields, targetFields)
        unitFields, targetFields = unitFields or {}, targetFields or {}
        unitFields.team, unitFields.odf = unitFields.team or 2, unitFields.odf or "svfigh"
        unitFields.pos = unitFields.pos or pos(0, 0, 0)
        targetFields.team, targetFields.odf = targetFields.team or 1, targetFields.odf or "avfigh"
        targetFields.pos = targetFields.pos or pos(0, 12, 80)
        local u, t = craft(unitFields), craft(targetFields)
        u.command, u.target = ATTACK, t
        team.combatUnits = { u }
        team.attackCloseState, team.attackCloseAt = nil, 0.0
        return u, t
    end
    local function tick() H.now = H.now + 1.0; team.attackCloseAt = 0.0; team:UpdateAttackClose() end

    H.now = 100.0
    local u, t = setup()
    tick()
    check("attack close: an elevated target within 125 m starts FORMATION", u.command == FORMATION and u.target == t)
    u.pos = pos(0, 12, 50)              -- now 30 m from the target
    tick()
    check("attack close: reverts to ATTACK inside 40 m", u.command == ATTACK and u.target == t)
    check("attack close: state cleared after revert", team.attackCloseState[u].target == nil)
    u.pos = pos(0, 0, 0)
    tick()
    check("attack close: an 8 s cooldown blocks an immediate restart", u.command == ATTACK)
    H.now = H.now + 9.0
    tick()
    check("attack close: restarts after the cooldown", u.command == FORMATION)

    u, t = setup()
    tick()
    local before = #H.commands
    check("attack close: started", u.command == FORMATION)
    H.now = H.now + 7.0
    team.attackCloseAt = 0.0
    team:UpdateAttackClose()
    check("attack close: reverts after 6 s", u.command == ATTACK and #H.commands == before + 1)

    u, t = setup()
    tick()
    u.command = GO                      -- a script took over
    before = #H.commands
    tick()
    check("attack close: a changed command is dropped silently", #H.commands == before and u.command == GO
        and team.attackCloseState[u].target == nil)

    u, t = setup()
    tick()
    t.alive = false
    before = #H.commands
    tick()
    check("attack close: a dead target clears state without a command", #H.commands == before
        and team.attackCloseState[u].target == nil)
    t.alive = true

    u, t = setup(nil, { pos = pos(0, 2, 80) })
    tick()
    check("attack close: a level target does not start it", u.command == ATTACK)

    u, t = setup(nil, { pos = pos(0, 0, 80) })
    H.playerHandle = t
    tick()
    check("attack close: a human-piloted target starts it", u.command == FORMATION)
    H.playerHandle = nil

    u, t = setup()
    t.aimedAt = u
    tick()
    check("attack close: a target already dueling us does not start it", u.command == ATTACK)

    u, t = setup({ class = "walker" })
    tick()
    check("attack close: walkers are skipped", u.command == ATTACK)
    u, t = setup({ odf = "avrckt" })
    tick()
    check("attack close: rocket tanks are skipped", u.command == ATTACK)
    u, t = setup({ odf = "avbomb" })
    tick()
    check("attack close: bomber-role craft are skipped", u.command == ATTACK)
    u, t = setup({ class = "apc" })
    tick()
    check("attack close: APCs are skipped", u.command == ATTACK)
    u, t = setup({ odf = "avtank" })
    tick()
    check("attack close: RocketTank-AI gun tanks (kiting role) are skipped", u.command == ATTACK)
    u, t = setup({ odf = "avscout" })
    tick()
    check("attack close: scouts (kiting role) are skipped", u.command == ATTACK)
    u, t = setup({ odf = "avwalk" })
    tick()
    check("attack close: Gech-AI walkers are skipped by role", u.command == ATTACK)
    u, t = setup(nil, { pos = pos(0, 12, 200) })
    tick()
    check("attack close: targets beyond 125 m do not start it", u.command == ATTACK)

    u, t = setup()
    local oldDifficulty = exu.GetDifficulty
    exu.GetDifficulty = function() return 0 end
    tick()
    check("attack close: off at difficulty 0", u.command == ATTACK)
    exu.GetDifficulty = oldDifficulty

    u, t = setup()
    team.Config.attackClose = false
    tick()
    check("attack close: attackClose=false disables it", u.command == ATTACK)
    team.Config.attackClose = true

    u, t = setup()
    aiCore.SetHumanTeam(2, true)
    tick()
    check("attack close: human teams are skipped", u.command == ATTACK)
    aiCore.SetHumanTeam(2, nil)

    u, t = setup()
    team.combatUnits = {}
    team.specialTrackedSet = { [u] = true }
    tick()
    check("attack close: special (mission-scripted) objects are never touched", u.command == ATTACK)
    team.specialTrackedSet = {}

    -- A wingman saving its command mid attack-close must save ATTACK, not the drive-in FORMATION.
    u, t = setup()
    tick()
    check("attack close: started for the wingman save", u.command == FORMATION)
    local entry = { unit = u }
    aiCore.WingmanManager.SavePreviousCommand(nil, entry, nil, nil)
    check("wingman: FORMATION on an enemy is saved as ATTACK",
        entry.previousCommand == ATTACK and entry.previousTarget == t)
    u.command = GO
    H.now = H.now + 5.0
    aiCore.WingmanManager.RestorePreviousCommand(nil, entry)
    check("wingman: the restored command is ATTACK on the target", u.command == ATTACK and u.target == t)
    local ally = craft { team = 2, odf = "svfigh", pos = pos(0, 0, 20) }
    local entry2 = { unit = u }
    aiCore.WingmanManager.SavePreviousCommand(nil, entry2, FORMATION, ally)
    check("wingman: FORMATION on an allied target stays FORMATION", entry2.previousCommand == FORMATION)
    aiCore.ActiveTeams = {}
end)

-- 3. Range-gated weapon masks -------------------------------------------------------------
H.try("range gating", function()
    H.objects = {}
    local team = newTeam(2)
    local mgr = team.weaponMgr
    local function setup(weapons, mask, dist)
        local u = craft { team = 2, odf = "svfigh", weapons = weapons, mask = mask }
        local t = craft { team = 1, odf = "avfigh", pos = pos(0, 0, dist) }
        u.command, u.target = ATTACK, t
        team.combatUnits = { u }
        mgr.rangeGateState, mgr.retaliationState, mgr.thumperUsers = {}, {}, {}
        return u, t
    end
    local function tick() H.now = H.now + 1.0; mgr.rangeGateAt = 0.0; mgr:UpdateRangeGating() end
    local mixed = { [0] = "cpgun", [1] = "cprkt" }

    H.now = 200.0
    local u, t = setup(mixed, 3, 300)
    tick()
    check("range gate: only the slot that reaches the target stays enabled", u.mask == 2)
    t.pos = pos(0, 0, 60)
    tick()
    check("range gate: the base mask returns once every weapon reaches", u.mask == 3 and mgr.rangeGateState[u] == nil)
    t.pos = pos(0, 0, 300)
    tick()
    u.command = AiCommand.NONE
    tick()
    check("range gate: no target restores the base mask", u.mask == 3)

    u, t = setup(mixed, 3, 300)
    tick()
    u.mask = 1                          -- someone else changed the mask
    tick()
    check("range gate: another owner's mask is neither overwritten nor restored over",
        u.mask == 1 and mgr.rangeGateState[u] == nil)

    u, t = setup(mixed, 3, 300)
    mgr.retaliationState[u] = { at = H.now, prior = 3 }
    tick()
    check("range gate: backs off during a retaliation hold", u.mask == 3)
    mgr.retaliationState[u] = nil
    mgr.thumperUsers = { { handle = u } }
    tick()
    check("range gate: backs off for a thumper/field/mortar/mine user", u.mask == 3)
    mgr.thumperUsers = {}
    tick()
    check("range gate: gates once no other owner is active", u.mask == 2)
    team.Config.rangeGatedWeapons = false
    tick()
    check("range gate: rangeGatedWeapons=false restores the base mask", u.mask == 3)
    team.Config.rangeGatedWeapons = true

    u, t = setup({ [0] = "cpgun", [1] = "cpgun2" }, 3, 300)
    tick()
    check("range gate: similar weapon ranges are never gated", u.mask == 3)

    u, t = setup(mixed, 3, 300)
    tick()
    local masksBefore = #H.weaponMasks
    tick()
    check("range gate: an unchanged mask is not rewritten every tick", #H.weaponMasks == masksBefore)

    -- An owner taking over a gated unit gets the real base mask back before it runs.
    u, t = setup(mixed, 3, 300)
    tick()
    check("range gate: gated before an owner takes over", u.mask == 2)
    mgr.thumperUsers = { { handle = u } }
    mgr:ReleaseOwnedRangeGates()
    check("range gate: owner takeover releases the gate (base mask back, state dropped)",
        u.mask == 3 and mgr.rangeGateState[u] == nil)
    mgr.thumperUsers = {}
    tick()
    mgr.retaliationState[u] = { at = H.now, prior = 3 }
    tick()
    check("range gate: a retaliation owner also releases a live gate", u.mask == 3 and mgr.rangeGateState[u] == nil)
    mgr.retaliationState[u] = nil

    -- A gated unit leaving the collected craft set is released.
    u, t = setup(mixed, 3, 300)
    tick()
    check("range gate: gated before leaving the set", u.mask == 2)
    team.combatUnits = {}
    tick()
    check("range gate: a unit no longer collected gets its mask back", u.mask == 3 and mgr.rangeGateState[u] == nil)

    -- Hysteresis: an enabled slot stays on until the target is 10% past its range.
    u, t = setup({ [0] = "cpgun", [1] = "cprkt", [2] = "cpmid" }, 7, 140)
    tick()
    check("range gate: hysteresis setup gates the short gun", u.mask == 6)
    t.pos = pos(0, 0, 155)              -- cpmid range 150, but 150*1.1 = 165
    local writes = #H.weaponMasks
    tick()
    check("range gate: a slot just past its range stays enabled (no flicker)", u.mask == 6 and #H.weaponMasks == writes)
    t.pos = pos(0, 0, 170)
    tick()
    check("range gate: the slot drops once beyond range * 1.1", u.mask == 2)
    t.pos = pos(0, 0, 108)              -- the gun was off: no hysteresis for a disabled slot
    tick()
    check("range gate: a disabled slot needs the strict range to come back", u.mask == 6)

    -- Retaliation switching while gated must remember the base mask, not the gated one.
    u, t = setup({ [0] = "cpgun", [1] = "cprkt", [2] = "gpopgun" }, 7, 300)
    local sniper = H.addObject { team = 1, odf = "aspilo", class = "person", person = true }
    tick()
    check("range gate: gated before retaliation", u.mask == 6)
    u.shotBy, u.lastShot = sniper, H.now
    mgr.retaliationUpdateAt = 0.0
    mgr:UpdateRetaliation(0.1)
    check("range gate: retaliation records the base mask as the prior mask", mgr.retaliationState[u].prior == 7)
    aiCore.ActiveTeams = {}
end)

-- 4. Stuck detection ----------------------------------------------------------------------
H.try("unstick", function()
    H.objects = {}
    aiCore.CommandState, aiCore.UnstickState = {}, {}
    local team = newTeam(2)
    local function setup(opts)
        opts = opts or {}
        H.objects = {}
        local u = craft { team = 2, odf = "svtank", pos = pos(0, 0, 0), vel = opts.vel }
        local leader = craft { team = 2, odf = "svfigh", pos = pos(0, 0, opts.goalDist or 300) }
        local building = H.addObject { team = 2, odf = "sbpgen", building = true, class = "powerplant",
            pos = pos(opts.blockerDist or 20, 0, 0) }
        u.command, u.target = FOLLOW, leader
        team.combatUnits = { u }
        aiCore.UnstickState = {}
        team.unstickAt = 0.0
        return u, leader, building
    end
    local function tick() H.now = H.now + 1.0; team.unstickAt = 0.0; team:UpdateUnstick() end
    local function count(cmd) local n = 0 for _, c in ipairs(H.commands) do if c.command == cmd then n = n + 1 end end return n end

    H.now = 300.0
    H.reset()
    local u = setup()
    tick(); tick()
    check("unstick: nothing before 3 s", #H.commands == 0)
    tick()
    check("unstick: the same command is re-issued after 3 s stuck", count(FOLLOW) == 1)
    local posBefore = u.pos
    for _ = 1, 2 do tick() end
    check("unstick: no nudge until stuck again for 3 s", u.pos == posBefore)
    tick()
    check("unstick: a second stuck spell nudges 1.5 m away from the building",
        u.pos ~= posBefore and math.abs(u.pos.x - (-1.5)) < 1e-6 and u.pos.z == 0 and u.pos.y == 0)
    check("unstick: the nudge zeroes velocity", u.vel and u.vel.x == 0 and u.vel.z == 0)
    local commandsAfterNudge = #H.commands
    for _ = 1, 10 do tick() end
    check("unstick: 15 s cooldown after a nudge", #H.commands == commandsAfterNudge and u.pos.x == -1.5)

    H.reset()
    u = setup { vel = { x = 20, y = 0, z = 0 } }
    for _ = 1, 8 do tick() end
    check("unstick: a moving unit is never stuck", #H.commands == 0 and u.pos.x == 0)

    u = setup { blockerDist = 80 }
    for _ = 1, 8 do tick() end
    check("unstick: no building within 50 m means no unstick", #H.commands == 0)

    u = setup { goalDist = 100 }
    for _ = 1, 8 do tick() end
    check("unstick: a FOLLOW goal under 150 m is close enough", #H.commands == 0)

    u = setup()
    H.playerHandle = u
    for _ = 1, 8 do tick() end
    check("unstick: human-piloted craft are skipped", #H.commands == 0)
    H.playerHandle = nil

    u = setup()
    u.deployed = true
    for _ = 1, 8 do tick() end
    check("unstick: deployed units are skipped", #H.commands == 0)

    u = setup()
    u.command = AiCommand.NONE
    for _ = 1, 8 do tick() end
    check("unstick: idle units are skipped", #H.commands == 0)

    -- Mission-scripted (special tracked) objects are never unstuck.
    H.reset()
    u = setup()
    team.combatUnits, team.specialTrackedSet = {}, { [u] = true }
    for _ = 1, 8 do tick() end
    check("unstick: special tracked objects are excluded", #H.commands == 0 and u.pos.x == 0)
    team.specialTrackedSet = {}

    -- The re-issue keeps the priority the order was issued with.
    H.reset()
    local leader
    u, leader = setup()
    aiCore.CommandState = {}
    aiCore.TrySetCommand(u, FOLLOW, 7, leader)
    H.reset()
    for _ = 1, 3 do tick() end
    check("unstick: the re-issue keeps the recorded priority", count(FOLLOW) == 1 and H.commands[1].priority == 7)

    -- Nudges keep the height above ground and are capped at 3 per goal.
    local realTerrain = GetTerrainHeightAndNormal
    GetTerrainHeightAndNormal = function(p) return (p.x or 0) * 0.1, { x = 0, y = 1, z = 0 } end
    H.reset()
    u, leader = setup()
    u.pos = pos(0, 5, 0)
    for _ = 1, 9 do tick() end
    check("unstick: a nudge preserves height above the terrain", math.abs(u.pos.y - (5 - 0.15)) < 1e-6)
    GetTerrainHeightAndNormal = realTerrain

    H.reset()
    u, leader = setup()
    for _ = 1, 150 do tick() end
    check("unstick: three nudges, then it gives up on that goal", aiCore.UnstickState[u].nudges == 3
        and math.abs(u.pos.x - (-4.5)) < 1e-6)
    local cmdsAtCap = #H.commands
    for _ = 1, 60 do tick() end
    check("unstick: no more commands or nudges after the cap", #H.commands == cmdsAtCap
        and math.abs(u.pos.x - (-4.5)) < 1e-6)
    local leader2 = craft { team = 2, odf = "svfigh", pos = pos(0, 0, 300) }
    u.target = leader2
    for _ = 1, 9 do tick() end
    check("unstick: a new target resets the nudge budget", aiCore.UnstickState[u].nudges == 1)

    -- GO to a remembered position (no target handle) uses the position aiCore recorded.
    u = setup()
    u.target = nil
    aiCore.CommandState = {}
    aiCore.TrySetCommand(u, GO, 1, nil, pos(0, 0, 200))
    H.reset()
    for _ = 1, 3 do tick() end
    check("unstick: a GO position order is re-issued with its position", count(GO) == 1
        and H.commands[1].position and H.commands[1].position.z == 200)
    u = setup()
    u.target, u.command = nil, GO
    aiCore.CommandState = {}
    H.reset()
    for _ = 1, 8 do tick() end
    check("unstick: a GO whose position is unknown is left alone", #H.commands == 0)
    aiCore.ActiveTeams = {}
end)

-- 5a. UpdateCombatOnly -------------------------------------------------------------------
H.try("combat only sync", function()
    local realSync = aiCore.SyncNativeTactics
    local syncs = 0
    aiCore.SyncNativeTactics = function() syncs = syncs + 1 end
    aiCore._nativeTargetScoringInstalled = false
    H.scoreHandler = nil
    aiCore.ActiveTeams, aiCore.GlobalDepotManagers, aiCore.GlobalOffenseManagers = {}, {}, {}
    local ok = pcall(aiCore.UpdateCombatOnly)
    aiCore.SyncNativeTactics = realSync
    check("combat only: UpdateCombatOnly runs", ok)
    check("combat only: it syncs native tactics", syncs == 1)
    check("combat only: it installs native target scoring",
        aiCore._nativeTargetScoringInstalled == true and H.scoreHandler ~= nil)
end)

-- 5b. Tank / walker profiles --------------------------------------------------------------
H.try("profiles", function()
    local aiNative = require("aiNative")
    local function role(odf) return aiCore.GetNativeAiRole(aiCore.GetOdfMeta(odf)) end
    check("profiles: RocketTank AI names resolve to the tank profile role",
        role("avtank") == "rockettank" and role("avltnk") == "rockettank")
    check("profiles: Gech AI names resolve to the walker role", role("avwalk") == "walker")
    check("profiles: turret tanks and bombers keep their own roles", role("avturr2") == nil and role("avbomb") == "bomber")

    local function policyFor(odf, class)
        local u = craft { team = 2, odf = odf, class = class, weapons = { [0] = "cpgun2" } }
        aiNative.ClearUnit(u)
        aiCore.ApplyNativeTactics(u, nil)
        return aiNative.GetUnitPolicy(u)
    end
    local tank = policyFor("avtank", "wingman")
    check("profiles: tank kites only at close range", tank and tank.kiteEnterRange and math.abs(tank.kiteEnterRange - 36.0) < 1e-6
        and math.abs(tank.kiteDesiredRange - 48.0) < 1e-6 and math.abs(tank.kiteExitRange - 60.0) < 1e-6
        and tank.kiteStrafe == 0.40 and tank.kiteSwitchPeriod == 3.0)
    check("profiles: tank has no standoff and a 2 s retarget", tank.weaponRangeMin == nil and tank.retargetPeriod == 2.0)
    local light = policyFor("avltnk", "wingman")
    check("profiles: the light tank shares the tank profile", light and light.kiteStrafe == 0.40)
    local walker = policyFor("avwalk", "walker")
    check("profiles: walker gets a retarget period only", walker and walker.retargetPeriod == 2.0
        and walker.kiteEnterRange == nil and walker.weaponRangeMin == nil)
    local turret = policyFor("avturr2", "turrettank")
    check("profiles: turret tanks are not matched by the tank profile", turret == nil)
    local scout = aiCore.DefaultNativeConfig.nativeUnitProfiles
    check("profiles: scout and bomber profiles are untouched", scout.scout.kiteStrafe == 0.55 and scout.bomber.engageRange == 300.0)
end)

-- 6. Save/load -----------------------------------------------------------------------------
H.try("load", function()
    H.objects, H.playerHandle = {}, nil
    aiCore.CommandState, aiCore.UnstickState = {}, {}
    local team, custom = newTeam(2), newTeam(3)
    local defaults = aiCore.DefaultNativeConfig.nativeUnitProfiles
    team.Config.nativeUnitProfiles.rockettank, team.Config.nativeUnitProfiles.walker = nil, nil
    team.Config.nativeUnitProfiles.scout.kiteStrafe = 0.9
    custom.Config.nativeUnitProfiles.rockettank = { standoff = true }
    aiCore.Load({ teams = { [2] = team, [3] = custom } })
    local p = team.Config.nativeUnitProfiles
    check("load: missing rockettank/walker profiles are filled from the defaults",
        p.rockettank and p.rockettank.kiteStrafe == 0.40 and p.walker and p.walker.retargetPeriod == 2.0)
    check("load: backfilled profiles are copies, not the shared default tables",
        p.rockettank ~= defaults.rockettank and p.walker ~= defaults.walker)
    check("load: existing profiles are not overwritten",
        p.scout.kiteStrafe == 0.9 and custom.Config.nativeUnitProfiles.rockettank.standoff == true
        and custom.Config.nativeUnitProfiles.rockettank.kiteStrafe == nil)

    -- Absolute-time combat state resets after a load.
    H.now = 50.0
    local u = craft { team = 2, odf = "svfigh", pos = pos(0, 0, 0) }
    local t = craft { team = 1, odf = "avfigh", pos = pos(0, 12, 80) }
    u.command, u.target = FORMATION, t
    local gated = craft { team = 2, odf = "svfigh", weapons = { [0] = "cpgun", [1] = "cprkt" }, mask = 2 }
    team.attackCloseState = { [u] = { target = t, started = 9999.0 } }
    team.attackCloseAt, team.unstickAt = 9999.0, 9999.0
    team.weaponMgr.rangeGateAt = 9999.0
    team.weaponMgr.rangeGateState = { [gated] = { base = 3, applied = 2 } }
    aiCore.UnstickState = { [u] = { stuck = 2.0, lastAt = 9999.0 } }
    aiCore.LaneCache = { [2] = { at = 9999.0, list = {} } }
    aiCore.FinishPostLoad()
    check("load: an active attack-close unit goes back to ATTACK on its target", u.command == ATTACK and u.target == t)
    check("load: attack-close state is cleared", next(team.attackCloseState) == nil)
    check("load: throttle timestamps are reset",
        team.attackCloseAt == 0.0 and team.unstickAt == 0.0 and team.weaponMgr.rangeGateAt == 0.0)
    check("load: range-gate state is released (base mask back)", gated.mask == 3
        and next(team.weaponMgr.rangeGateState) == nil)
    check("load: unstick and lane caches are cleared", next(aiCore.UnstickState) == nil and aiCore.LaneCache[2] == nil)
    aiCore.ActiveTeams = {}
end)

H.finish("aiCore combat-port")
