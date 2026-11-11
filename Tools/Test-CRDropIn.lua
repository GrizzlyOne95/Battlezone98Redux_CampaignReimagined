-- Dropship insertion (Scripts/CRDropIn.lua): pure choreography, then the runtime against engine mocks.
-- Verifies script decisions only: no Redux physics, floor collision or SDF animation.
package.path = "Scripts/?.lua;" .. package.path
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local function V(x, y, z) return { x = x, y = y, z = z } end
_G.SetVector = V
package.loaded.CRDropIn = nil
local Drop = require("CRDropIn")

-- 1. Hold slots: humans first, alternating lanes, front row first; six rows per lane.
do
    local a1, l1 = Drop.Slot(1)
    local a2, l2 = Drop.Slot(2)
    check(a1 == 6 and l1 == -7 and a2 == 6 and l2 == 7, "row 1 is CR04Drop's player/wingman spot")
    local seen = {}
    for j = 1, 12 do
        local along, lat = Drop.Slot(j)
        check(along and lat, "slot " .. j .. " exists")
        local key = along .. ":" .. lat
        check(not seen[key], "slot " .. j .. " is unique")
        seen[key] = true
        check(math.abs(lat) + 3 < 35 / 2, "slot " .. j .. " fits the 35 m hold")
        check(along < Drop.HINGE, "slot " .. j .. " is inside the hold, not on the ramp")
    end
    check(Drop.Slot(13) == nil and Drop.Slot(0) == nil, "the hold takes 12")
end

-- 2. Poses at key times are pure functions of the plan and the clock.
local ship = { x = 100, z = 200, y = 20, sx = 0, sz = 1, lx = 1, lz = 0, delay = 2.5 }
do
    local up, back = Drop.Offsets(ship, 0)
    check(near(up, Drop.START_UP) and near(back, Drop.START_BACK), "waiting ships hold at the start pose")
    up, back = Drop.Offsets(ship, 2.5)
    check(near(up, 320) and near(back, 260), "the descent starts at its delay")
    up, back = Drop.Offsets(ship, 2.5 + 8)
    check(near(up, 40) and near(back, 65), "halfway down: k^3 and k^2 of the start pose")
    up, back = Drop.Offsets(ship, Drop.Touchdown(ship))
    check(near(up, 0) and near(back, 0), "touchdown is on the spot")
    up, back = Drop.Offsets(ship, 99)
    check(near(up, 0) and near(back, 0), "a landed ship stays on the spot")
    check(Drop.Touchdown(ship) == 18.5 and Drop.Stage(ship, 18.4) == "fly" and Drop.Stage(ship, 18.5) == "landed",
        "stage switches at touchdown")
    local x, y, z = Drop.HullPos(ship, 2.5)
    check(near(x, 100) and near(y, 340) and near(z, 460), "hull starts up and out behind its stern")
    x, y, z = Drop.HoldPos(ship, 6, -7, Drop.Touchdown(ship))
    check(near(x, 93) and near(y, 20 + Drop.HOLD_UP) and near(z, 206), "a carried craft rides its slot on the deck")
    local hx, hy, hz, dx, dz = Drop.HoldPos(ship, 6, -7, 5)
    local sx, sy, sz = Drop.HullPos(ship, 5)
    check(near(hy - sy, Drop.HOLD_UP) and near(hx - sx, -7) and near(hz - sz, 6), "carried craft travel with the hull")
    check(dx == ship.sx and dz == ship.sz, "carried craft face the ramp")
    local ships = { { delay = 0 }, ship }
    check(near(Drop.ReleaseTime(ships, 2), 2.5 + 16 + 2.6), "release follows the last ship's ramps")
    up, back = Drop.LiftOffsets(4)
    check(near(up, 24) and near(back, -9.6), "lift-off climbs and noses forward")
    local flat = function() return 20 end
    local _, deckIn = Drop.Deck(ship, 10, 0, flat)
    local _, deckMid = Drop.Deck(ship, 32, 0, flat)
    local _, deckLip = Drop.Deck(ship, Drop.LIP, 0, flat)
    check(near(deckIn, 24.5) and deckMid < deckIn and deckMid > 20 and near(deckLip, 20), "deck: floor, ramp, ground")
    local ex, _, ez = Drop.ExitPos(ship, 6, -7, flat)
    check(near(ex, 93) and ez - 200 > Drop.LIP, "a load sets a carried craft down past the lip")
    local _, _, ez2 = Drop.ExitPos(ship, -2, 7, flat)
    check(ez2 > ez, "rear rows are set down behind the front rows")
end

-- 3. Sites: deterministic, sterns toward the anchors, the flattest unblocked candidate wins.
do
    local bumpy = function(x, z) return 20 + math.sin(x * 0.05) * 3 + math.cos(z * 0.03) * 4 end
    local anchors = { { x = 1916, z = 100683 }, { x = 1908, z = 100764 } }
    local a, d1 = Drop.Sites(anchors, bumpy)
    local b, d2 = Drop.Sites(anchors, bumpy)
    check(d1 == d2 and #a == 2, "same inputs, same anchor distance")
    for i = 1, 2 do
        for _, k in ipairs({ "x", "z", "y", "sx", "sz", "lx", "lz" }) do check(a[i][k] == b[i][k], "same inputs, same plan") end
    end
    for i = 1, 2 do
        -- the anchor lies d metres out along the stern, give or take the side-by-side slide
        local f = a[i]
        local out = (anchors[i].x - f.x) * f.sx + (anchors[i].z - f.z) * f.sz
        check(near(out, d1, 1e-6), "ship " .. i .. " stern faces its anchor at d")
        check(near(f.sx * f.lx + f.sz * f.lz, 0), "stern and lateral are perpendicular")
    end
    local apart = math.sqrt((a[1].x - a[2].x) ^ 2 + (a[1].z - a[2].z) ^ 2)
    check(apart > 2 * Drop.SHIP_GAP - 1, "two ships stand apart")
    local blockedFirst = function(x, z) return math.abs(x - a[1].x) < 1 and math.abs(z - a[1].z) < 1 end
    local c = Drop.Sites(anchors, bumpy, blockedFirst)
    check(not (near(c[1].x, a[1].x) and near(c[1].z, a[1].z)), "a blocked site is not chosen")
    local one = Drop.Sites({ { x = 0, z = 0 } }, function() return 5 end, nil, { x = 0, z = 1 })
    check(#one == 1 and near(one[1].lz, 1) and one[1].y == 5, "a single anchor uses the given lateral line")
end

-- 4. Runtime against engine mocks.
local now, objects, nextId, calls, log, masks, camera, owned
local function dist2(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
local function count(name, odf)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name and (odf == nil or c[2] == odf) then n = n + 1 end end
    return n
end
local function locked() return next(masks) ~= nil end
-- the "FIRE CONTROLS LOCKED" overlay (CRLockBadge) as the fake EXU sees it
local overlay = {}
local function badge() return overlay.visible == true and overlay.caption == "FIRE CONTROLS LOCKED" end

-- opts: noExu, noShips, network, leader (default true), team (default 1), player (default 3)
local function reset(opts)
    opts = opts or {}
    now, objects, nextId, calls, log, masks = 0, {}, 0, {}, {}, {}
    camera = { ready = 0, finish = 0, cancel = false }
    owned = {}
    local function add(odf, pos, label)
        nextId = nextId + 1
        objects[nextId] = { odf = odf, pos = pos, vel = V(0, 0, 0), label = label, health = 500, max = 1000 }
        return nextId
    end
    -- stock misn04 layout (Missions/misn04cr.bzn), on flat ground at y 20
    add("avrec4", V(1933, 20, 100685), "avrecy-1_recycler")
    add("avmuf4", V(1899, 20, 100681), "avmuf0_factory")
    add("player", V(1908, 20, 100764), "player-1_hover")
    add("avfigh", V(1915, 20, 100770), "avfigh0_wingman")
    add("avtank", V(1950, 20, 100780), "guest_tank")
    _G.GetTime = function() return now end
    _G.GetTerrainHeightAndNormal = function() return 20, V(0, 1, 0) end
    _G.BuildDirectionalMatrix = function(p, d) return { pos = V(p.x, p.y, p.z), dir = d } end
    _G.IsValid = function(h) return h ~= nil and objects[h] ~= nil end
    _G.IsBuilding = function() return false end
    _G.IsCraft = function() return true end
    _G.GetPosition = function(h) local p = objects[h].pos; return V(p.x, p.y, p.z) end
    _G.GetVelocity = function(h) local v = objects[h].vel; return V(v.x, v.y, v.z) end
    _G.SetTransform = function(h, m)
        if opts.network and not opts.leaderSim then
            check(owned[h], "a peer moved an object it does not own: " .. tostring(objects[h].label or objects[h].odf))
        end
        calls[#calls + 1] = { "SetTransform", objects[h].label or objects[h].odf }
        objects[h].pos = V(m.pos.x, m.pos.y, m.pos.z)
    end
    _G.SetVelocity = function(h, v) objects[h].vel = V(v.x, v.y, v.z) end
    _G.SetCurHealth = function(h, v) objects[h].health = v end
    _G.GetMaxHealth = function(h) return objects[h].max end
    _G.BuildObject = function(odf, team, where)
        calls[#calls + 1] = { "BuildObject", odf, team }
        if opts.noShips and odf:find("^avdrop") then return nil end
        return add(odf, where.pos or where)
    end
    _G.RemoveObject = function(h) calls[#calls + 1] = { "RemoveObject", objects[h].odf }; objects[h] = nil end
    _G.Stop = function(h, priority)   -- Stop brakes a hovercraft; the mock simply halts it
        calls[#calls + 1] = { "Stop", objects[h].label, priority }
        objects[h].vel = V(0, 0, 0)
    end
    _G.GetOdf = function(h) return objects[h].odf end
    _G.IsOdf = function(h, odf) return objects[h].odf == odf end
    _G.AllObjects = function()
        local list = {}
        for h in pairs(objects) do list[#list + 1] = h end
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    _G.ObjectsInRange = nil
    package.loaded.CRDropIn = nil
    local D = require("CRDropIn")
    local exu = not opts.noExu and {
        CONTROL = { ALL = 4095 },
        SetPlayerControlMask = function(owner, mask)
            if opts.maskRefuses then return false end -- an older bundled EXU refuses multiplayer
            masks[owner] = mask; return true
        end,
        GetPlayerControlState = function() return { reason = "multiplayer-unsupported" } end,
        ClearPlayerControlMask = function(owner) masks[owner] = nil end,
    } or nil
    overlay = {}
    if exu then
        for _, f in ipairs({ "CreateOverlayElement", "AddOverlay2D", "SetOverlayZOrder", "SetOverlayMetricsMode",
            "AddOverlayElementChild", "SetOverlayTextFont", "SetOverlayMaterial", "SetOverlayParameter",
            "SetOverlayPosition", "SetOverlayDimensions", "SetOverlayTextCharHeight", "SetOverlayTextColor",
            "ShowOverlayElement", "HideOverlay", "RemoveOverlayElementChild", "DestroyOverlayElement",
            "RemoveOverlay2D" }) do exu[f] = function() return true end end
        exu.CreateOverlay = function() overlay.created = true; return true end
        exu.SetOverlayCaption = function(_, text) overlay.caption = text; return true end
        exu.ShowOverlay = function() overlay.visible = overlay.created; return true end
        exu.DestroyOverlay = function() overlay.created, overlay.visible = false, false; return true end
    end
    local player = opts.player or 3
    local state = {}
    D.Configure({
        present = function(op, ...) calls[#calls + 1] = { "present", op, ... }; D.Apply(state, op, ...) end,
        isLeader = function() return opts.leader ~= false end,
        isNetwork = function() return opts.network == true end,
        myTeam = function() return opts.team or 1 end,
        player = function() return player end,
        forEachHuman = function(fn) fn(3); if opts.network then fn(5) end end,
        exu = exu, owner = "mission:test-drop",
        log = function(line) log[#log + 1] = line end,
        cameraReady = function() camera.ready = camera.ready + 1 end,
        cameraObject = function(base, r, u, f, target)
            check(camera.ready > camera.finish, "CameraObject without a ready camera")
            check(objects[base] and objects[target], "camera on a missing object")
            camera.frames = (camera.frames or 0) + 1
        end,
        cameraFinish = function() camera.finish = camera.finish + 1 end,
        cameraCancelled = function() return camera.cancel end,
    })
    D.Reset()
    return D, state
end

local function spec(teams)
    local pr, pf, pw = objects[1].pos, objects[2].pos, objects[4].pos
    return { exclude = { [1] = true, [2] = true, [3] = true, [4] = true }, ships = {
        { anchor = { x = (pr.x + pf.x) / 2, z = (pr.z + pf.z) / 2 }, delay = 0, cargo = {
            { h = 1, goal = { x = pr.x, z = pr.z }, along = 0, lat = -8 },
            { h = 2, goal = { x = pf.x, z = pf.z }, along = 2, lat = 10 } } },
        { anchor = { x = objects[3].pos.x, z = objects[3].pos.z }, delay = 2.5, crew = teams or { 1 },
            cargo = { { h = 4, goal = { x = pw.x, z = pw.z } } } },
    } }
end

local function step(D, s, dt, onTick)
    now = now + dt
    for _, o in pairs(objects) do
        o.pos = V(o.pos.x + o.vel.x * dt, o.pos.y, o.pos.z + o.vel.z * dt)
    end
    if onTick then onTick() end
    return D.Update(s)
end

-- 4a. Offline: the full landing, release and lift-off (CR04Drop's sequence).
do
    local D, s = reset()
    check(D.Begin(s, spec()) == true, "the leader begins the drop")
    check(D.Update(s) == true, "the drop holds the stock start while ships descend")
    check(count("BuildObject", "avdropc") == 2 and count("BuildObject", "apcamr") == 1, "two flying ships, one camera pod")
    check(camera.ready == 1 and masks["mission:test-drop"] == 4095, "camera up and controls locked at once")
    check(badge(), "the FIRE CONTROLS LOCKED overlay shows while locked")
    do -- an abort mid-drop must take the badge down with the mask
        local D2, s2 = reset()
        D2.Begin(s2, spec()); D2.Update(s2)
        check(badge(), "badge up before the abort")
        for _ = 1, 30 * 5 do step(D2, s2, 1 / 30) end
        check(objects[3].pos.y > 100, "the player is aloft before the abort")
        D2.Abort(s2)
        check(not locked() and not badge(), "an abort clears the mask and the badge")
        check(camera.finish == 1, "an abort mid-drop finishes the drop camera")
        check(objects[3].pos.y < 40 and objects[1].pos.y < 40, "an abort mid-drop sets the carried craft down")
        for _, o in pairs(objects) do check(not o.odf:find("^avdrop") and o.odf ~= "apcamr", "abort leaves no ship or pod") end
        check(s2.phase == "done" and D2.Update(s2) == false, "an aborted drop holds nothing")
        D, s = reset(); D.Begin(s, spec()); D.Update(s)
    end
    check(s.crew[1].ship == 2 and s.crew[1].along == 6 and s.crew[1].lat == -7, "the player rides row 1 of the personnel ship")
    check(s.lead.cargo[3].along == 6 and s.lead.cargo[3].lat == 7, "the wingman takes the next lane slot")
    local inFlight, released
    for _ = 1, 30 * 60 do
        local hold = step(D, s, 1 / 30)
        if now > 5 and now < 6 then inFlight = objects[3].pos.y end
        if not hold and not released then released = now; break end
    end
    check(inFlight and inFlight > 100, "the player rides the descending ship")
    check(objects[1].health == 1000 and objects[3].health == 1000, "carried craft are kept whole")
    check(count("BuildObject", "avdropo") == 2, "both ships swapped to the landed model")
    check(released and released >= 16 + 2.5 + 2.6 - 0.05 and released < 16 + 2.5 + 2.6 + 0.2,
        "release follows the second ship's ramps")
    check(not locked() and camera.finish == 1 and count("RemoveObject", "apcamr") == 1, "release: unlock, camera, pod")
    check(not badge(), "release hides the overlay")
    check(camera.frames > 0, "the shared camera follows the personnel ship")
    for _ = 1, 30 * 120 do
        step(D, s, 1 / 30, function() objects[3].pos = V(objects[3].pos.x, 20, objects[3].pos.z + 0.5) end)
        if s.phase == "done" then break end
    end
    local stops = {}
    for _, c in ipairs(calls) do if c[1] == "Stop" and c[3] == 0 then stops[c[2]] = true end end
    check(stops["avrecy-1_recycler"] and stops["avmuf0_factory"] and stops["avfigh0_wingman"],
        "every AI cargo unit is handed back to its AI")
    check(dist2(objects[1].pos, V(1933, 0, 100685)) < 5 and dist2(objects[2].pos, V(1899, 0, 100681)) < 5,
        "recycler and factory park on their stock spots")
    check(objects[1].pos.y < 40, "recycler is back on the ground")
    check(s.phase == "done" and count("BuildObject", "avdropx") == 2, "both ships close their ramps and leave")
    for _, o in pairs(objects) do check(not o.odf:find("^avdrop"), "no ship left behind") end
    check(D.Update(s) == false, "done stays done")
end

-- 4b. Offline skip: both ships touch down at once; the ramps still take OPEN_T.
do
    local D, s = reset()
    D.Begin(s, spec())
    for _ = 1, 30 * 3 do step(D, s, 1 / 30) end
    camera.cancel = true
    step(D, s, 1 / 30)
    check(count("BuildObject", "avdropo") == 2, "skip touches both ships down")
    local released
    for _ = 1, 30 * 5 do if not step(D, s, 1 / 30) then released = now; break end end
    check(released and released < 3 + 2.6 + 0.2, "skip still waits only for the ramps")
    check(not locked() and camera.finish == 1, "skip unlocks and finishes the camera")
end

-- 4c. A save mid-drop: ships gone, AI cargo on its spot, the player set down past the ramp, unlocked.
do
    local D, s = reset()
    D.Begin(s, spec())
    for _ = 1, 30 * 8 do step(D, s, 1 / 30) end
    masks = {}   -- EXU masks are not saved
    D.OnLoad(s)
    check(D.Update(s) == false, "a loaded drop does not hold the mission")
    for _, o in pairs(objects) do check(not o.odf:find("^avdrop") and o.odf ~= "apcamr", "no ship survives the load") end
    check(s.phase == "done" and not locked() and camera.finish == 0, "finished, unlocked, no camera popped")
    check(dist2(objects[1].pos, V(1933, 0, 100685)) < 1 and objects[1].pos.y < 25, "recycler set down on its spot")
    check(objects[3].pos.y < 25 and objects[3].pos.y > 20, "the player is set down, not left in the air")
    local f = s.ships[2]
    local out = (objects[3].pos.x - f.x) * f.sx + (objects[3].pos.z - f.z) * f.sz
    check(out > Drop.LIP, "the player is set down past the ramp lip")
end

-- 4d. No EXU control mask: the landing still plays.
do
    local D, s = reset({ noExu = true })
    D.Begin(s, spec())
    check(D.Update(s) == true, "landing plays without the mask")
    local found
    for _, line in ipairs(log) do if line:find("control lock unavailable") then found = true end end
    check(found, "missing mask is logged")
end

-- 4e. Ship art missing: fail closed, nothing sent, the stock opening runs.
do
    local D, s = reset({ noShips = true })
    check(D.Begin(s, spec()) == false and D.Update(s) == false, "no ships, no hold")
    check(s.phase == "done" and not locked() and camera.ready == 0 and count("present") == 0, "stock opening untouched")
end

-- 4f. Network leader: the plan goes out as numbers, the mask locks this peer, the camera cannot be skipped
--     through the module (the mission's CameraCancelled is false in network games).
do
    local D, s = reset({ network = true, leaderSim = true })
    D.Begin(s, spec({ 1, 2, 3, 4 }))
    check(masks["mission:test-drop"] == 4095, "the mask locks the leader in co-op too")
    check(badge(), "the overlay shows in co-op too")
    local ships, crew, go = 0, 0, 0
    for _, c in ipairs(calls) do
        if c[1] == "present" then
            for i = 3, #c do check(type(c[i]) == "number", "plan events carry numbers only") end
            if c[2] == "DropShip" then ships = ships + 1 elseif c[2] == "DropCrew" then crew = crew + 1 else go = go + 1 end
        end
    end
    check(ships == 2 and crew == 4 and go == 1, "DropShip x2, DropCrew per human, one DropGo")
    local lats = {}
    for team = 1, 4 do
        local c = s.crew[team]
        check(c and c.ship == 2, "team " .. team .. " rides the personnel ship")
        lats[c.along .. ":" .. c.lat] = true
    end
    local n = 0; for _ in pairs(lats) do n = n + 1 end
    check(n == 4, "four humans, four slots")
    check(s.lead.cargo[3].along == -10, "the wingman rides behind four humans")
end

-- 4g. Network guest: applies the leader's plan, pins only its own craft, builds nothing, cannot advance time.
do
    local D, s = reset({ network = true, leader = false, team = 2, player = 5 })
    owned[5] = true
    local plan = {
        { "DropShip", 1, 2, 1900, 100600, 20, 0, -1, 1, 0, 0 },
        { "DropShip", 2, 2, 1910, 100700, 20, 0, -1, 1, 0, 2.5 },
        { "DropCrew", 1, 2, 6, -7 }, { "DropCrew", 2, 2, 6, 7 },
        { "DropGo" },
    }
    D.Apply(s, "DropShip", 1, 2, 0 / 0, 0, 0, 0, 1, 1, 0, 0)
    check(s.ships == nil, "a NaN plan field is rejected")
    D.Apply(s, "DropShip", 3, 2, 0, 0, 0, 0, 1, 1, 0, 0)
    check(s.ships == nil, "an out-of-range ship index is rejected")
    for _, e in ipairs(plan) do D.Apply(s, unpack(e)) end
    check(s.go and s.t0 == 0, "DropGo starts this peer's clock")
    local pins = 0
    camera.cancel = true -- a guest skip never reaches the module; even if it did, a guest has no lead
    for _ = 1, 30 * 10 do
        step(D, s, 1 / 30)
        pins = count("SetTransform")
    end
    check(pins > 0 and count("BuildObject") == 0 and count("present") == 0, "guest pins its craft, builds and sends nothing")
    check(s.t0 == 0 and not s.released, "a guest cannot move the shared timeline")
    local x, y, z = Drop.HoldPos(s.ships[2], 6, 7, now)
    check(near(objects[5].pos.x, x) and near(objects[5].pos.y, y) and near(objects[5].pos.z, z),
        "the guest rides its own slot at the plan's pose")
    for _ = 1, 30 * 12 do step(D, s, 1 / 30) end
    check(s.released and s.phase == "done", "the guest releases at the plan's time")
    local after = count("SetTransform")
    step(D, s, 1)
    check(count("SetTransform") == after, "a released guest no longer pins")
    -- an incomplete plan never strands a peer
    local D2, s2 = reset({ network = true, leader = false, team = 2, player = 5 })
    owned[5] = true
    D2.Apply(s2, "DropCrew", 2, 2, 6, 7)
    D2.Apply(s2, "DropGo")
    check(s2.phase == "done" and D2.Update(s2) == false, "a plan missing its ships is dropped, not held")
end

-- 4i. A guest that applies DropGo late joins at the leader's clock; a skewed clock is capped and still drops.
do
    local plan = {
        { "DropShip", 1, 2, 1900, 100600, 20, 0, -1, 1, 0, 0 },
        { "DropShip", 2, 2, 1910, 100700, 20, 0, -1, 1, 0, 2.5 },
        { "DropCrew", 2, 2, 6, 7 },
    }
    local D, s = reset({ network = true, leader = false, team = 2, player = 5 })
    owned[5] = true
    now = 30
    for _, e in ipairs(plan) do D.Apply(s, unpack(e)) end
    D.Apply(s, "DropGo", 25)   -- sent 5 s ago: still holding
    check(s.go and s.t0 == 25, "a slightly late DropGo starts the clock at the leader's elapsed time")
    D, s = reset({ network = true, leader = false, team = 2, player = 5 })
    owned[5] = true
    now = 40
    for _, e in ipairs(plan) do D.Apply(s, unpack(e)) end
    D.Apply(s, "DropGo", 10)   -- 30 s by this peer's clock: skew, not a real stall
    check(s.go and s.phase == "drop" and s.t0 == 40 - 5 and locked(), "a skewed clock is capped at MAX_LATE and still drops")
end

-- 4j. An invalid plan is rejected before anything is built or sent.
do
    local D, s = reset()
    local bad = spec()
    bad.ships[2].anchor.x = 0 / 0
    check(D.Begin(s, bad) == false and s.phase == "done", "a NaN anchor aborts the drop")
    check(count("present") == 0 and count("BuildObject") == 0 and not locked(), "no Drop event sent, nothing built")
    D, s = reset()
    bad = spec()
    bad.ships[1].delay = "soon"
    check(D.Begin(s, bad) == false and count("present") == 0, "a non-numeric delay aborts the drop")
end

-- 4k. A recovered (post-load) drop removes ships only by ODF: a stale saved handle may name anything.
do
    local D, s = reset()
    D.Begin(s, spec())
    for _ = 1, 30 * 4 do step(D, s, 1 / 30) end
    local hull1 = s.lead.hulls[1].h
    s.lead.hulls[1].h = 5      -- stale: now a tank (guest_tank)
    s.lead.pod = 4             -- stale: now the wingman
    D.OnLoad(s)
    D.Update(s)
    check(objects[5] ~= nil and objects[4] ~= nil, "stale hull and pod handles are not removed")
    check(objects[hull1] == nil, "the real ship is still removed by the ODF sweep")
end

-- 4l. A failing SetTransform or BuildObject does not break the opening.
do
    local D, s = reset()
    D.Begin(s, spec())
    _G.SetTransform = function() error("boom") end
    local ok = pcall(function() for _ = 1, 30 * 25 do step(D, s, 1 / 30) end end)
    check(ok and s.released, "SetTransform errors are contained")
    D, s = reset()
    local base, built = _G.BuildObject, 0
    _G.BuildObject = function(...) built = built + 1; if built == 3 then error("no pod") end return base(...) end
    check(D.Begin(s, spec()) == false and s.phase == "done", "an error while building aborts the drop")
    for _, o in pairs(objects) do check(not o.odf:find("^avdrop"), "an aborted start leaves no ship behind") end
    check(count("present") == 0 and not locked(), "an aborted start sends nothing")
end

-- 4h. Determinism: two runs of the same plan put every carried craft at the same place at the same time.
do
    local function trace()
        local D, s = reset()
        D.Begin(s, spec())
        local out = {}
        for i = 1, 30 * 20 do
            step(D, s, 1 / 30)
            if i % 30 == 0 then out[#out + 1] = string.format("%.6f,%.6f,%.6f", objects[3].pos.x, objects[3].pos.y, objects[3].pos.z) end
        end
        return table.concat(out, ";")
    end
    check(trace() == trace(), "the same plan replays the same poses")
end

-- 4h. An older bundled EXU refuses the mask in co-op: logged, and the drop still runs pinned.
do
    local D, s = reset({ network = true, leaderSim = true, maskRefuses = true })
    D.Begin(s, spec({ 1, 2, 3, 4 }))
    check(not locked(), "a refused mask leaves nothing set")
    check(not badge(), "a refused mask shows no overlay: fire is not locked")
    local logged = false
    for _, l in ipairs(log) do if tostring(l):find("control lock unavailable", 1, true) then logged = true end end
    check(logged, "a refused mask is logged")
    check(s.phase ~= "done", "the drop goes on without the mask")
end

print(string.format("CRDropIn: %d checks passed", checks))
