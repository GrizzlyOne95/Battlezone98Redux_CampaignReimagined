-- Single-player dropship opening for misn04 (Scripts/CR04Drop.lua) against engine mocks.
-- Verifies script decisions only: no Redux physics, floor collision or SDF animation.
package.path = "Scripts/?.lua;" .. package.path
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local now, objects, nextId, calls, log, masks, camera
local function V(x, y, z) return { x = x, y = y, z = z } end
local function dist2(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
local function count(name, odf)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name and (odf == nil or c[2] == odf) then n = n + 1 end end
    return n
end

local function reset(opts)
    opts = opts or {}
    now, objects, nextId, calls, log, masks = 0, {}, 0, {}, {}, {}
    camera = { ready = 0, finish = 0, cancel = false }
    local function add(odf, pos, label)
        nextId = nextId + 1
        objects[nextId] = { odf = odf, pos = pos, vel = V(0, 0, 0), label = label }
        return nextId
    end
    -- stock misn04 layout (Missions/misn04.bzn), on flat ground at y 20
    add("avrec4", V(1933, 20, 100685), "avrecy-1_recycler")
    add("avmuf4", V(1899, 20, 100681), "avmuf0_factory")
    add("player", V(1908, 20, 100764), "player-1_hover")
    add("avfigh", V(1915, 20, 100770), "avfigh0_wingman")
    _G.SetVector = V
    _G.GetTime = function() return now end
    _G.GetTerrainHeightAndNormal = function() return 20, V(0, 1, 0) end
    _G.BuildDirectionalMatrix = function(p, d) return { pos = V(p.x, p.y, p.z), dir = d } end
    _G.IsValid = function(h) return h ~= nil and objects[h] ~= nil end
    _G.GetHandle = function(label)
        for h, o in pairs(objects) do if o.label == label then return h end end
    end
    _G.GetPlayerHandle = function() return 3 end
    _G.GetPosition = function(h) local p = objects[h].pos; return V(p.x, p.y, p.z) end
    _G.GetVelocity = function(h) local v = objects[h].vel; return V(v.x, v.y, v.z) end
    _G.SetTransform = function(h, m) objects[h].pos = V(m.pos.x, m.pos.y, m.pos.z) end
    _G.SetVelocity = function(h, v) objects[h].vel = V(v.x, v.y, v.z) end
    _G.BuildObject = function(odf, team, where)
        calls[#calls + 1] = { "BuildObject", odf }
        if opts.noShips and odf:find("^avdrop") then return nil end
        return add(odf, where.pos or where)
    end
    _G.RemoveObject = function(h) calls[#calls + 1] = { "RemoveObject", objects[h].odf }; objects[h] = nil end
    _G.Stop = function(h, priority)   -- Stop brakes a hovercraft; the mock simply halts it
        calls[#calls + 1] = { "Stop", objects[h].label, priority }
        objects[h].vel = V(0, 0, 0)
    end
    _G.CameraObject = function(base, r, u, f, target)
        check(camera.ready > camera.finish, "CameraObject without a ready camera")
        check(objects[base] and objects[target], "camera on a missing object")
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
    package.loaded.CR04Drop = nil
    local Drop = require("CR04Drop")
    local exu = not opts.noExu and {
        CONTROL = { ALL = 4095 },
        SetPlayerControlMask = function(owner, mask) masks[owner] = mask; return true end,
        ClearPlayerControlMask = function(owner) masks[owner] = nil end,
    } or nil
    Drop.Configure({
        exu = exu,
        log = function(line) log[#log + 1] = line end,
        cameraReady = function() camera.ready = camera.ready + 1 end,
        cameraFinish = function() camera.finish = camera.finish + 1 end,
        cameraCancelled = function() return camera.cancel end,
    })
    Drop.Reset()
    return Drop
end

local function locked() return next(masks) ~= nil end
local function step(Drop, M, dt, onTick)
    now = now + dt
    for _, o in pairs(objects) do
        o.pos = V(o.pos.x + o.vel.x * dt, o.pos.y, o.pos.z + o.vel.z * dt)
    end
    if onTick then onTick() end
    return Drop.Update(M)
end

-- 1. Full single-player landing, release and lift-off.
do
    local Drop = reset()
    local M = {}
    check(Drop.Update(M) == true, "opening must hold the stock start while ships descend")
    check(count("BuildObject", "avdropc") == 2, "two flying ships")
    check(count("BuildObject", "apcamr") == 1, "one camera pod")
    check(camera.ready == 1 and locked(), "camera up and controls locked at once")
    check(masks["mission:misn04-dropship"] == 4095, "the whole control mask")
    local playerInFlight
    local released
    for _ = 1, 30 * 60 do
        local hold = step(Drop, M, 1 / 30)
        if now > 5 and now < 6 then playerInFlight = objects[3].pos.y end
        if not hold and not released then released = now end
        if released then break end
    end
    check(playerInFlight and playerInFlight > 100, "the player rides the descending ship")
    check(count("BuildObject", "avdropo") == 2, "both ships swapped to the landed model")
    check(released and released >= 16 + 2.5 + 2.6 - 0.05, "release waits for the second ship's ramps")
    check(released < 16 + 2.5 + 2.6 + 0.2, "release follows the ramps without delay")
    check(not locked(), "controls unlocked at release")
    check(camera.finish == 1, "camera finished once")
    check(count("RemoveObject", "apcamr") == 1, "camera pod removed")
    -- AI cargo drives out; the player flies off on their own
    local stops = {}
    for _ = 1, 30 * 120 do
        step(Drop, M, 1 / 30, function()
            objects[3].pos = V(objects[3].pos.x, 20, objects[3].pos.z + 0.5)
        end)
        if M.cr04drop.phase == "done" then break end
    end
    for _, c in ipairs(calls) do if c[1] == "Stop" and c[3] == 0 then stops[c[2]] = true end end
    check(stops["avrecy-1_recycler"] and stops["avmuf0_factory"] and stops["avfigh0_wingman"],
        "every AI cargo unit is handed back to its AI")
    check(dist2(objects[1].pos, V(1933, 0, 100685)) < 5, "recycler parks on its stock spot")
    check(dist2(objects[2].pos, V(1899, 0, 100681)) < 5, "factory parks on its stock spot")
    check(objects[1].pos.y < 40, "recycler is back on the ground")
    check(M.cr04drop.phase == "done", "ships lift off and the opening finishes")
    check(count("BuildObject", "avdropx") == 2, "both ships swapped to the ramp-closing model")
    check(count("RemoveObject", "avdropc") == 2 and count("RemoveObject", "avdropx") == 2,
        "both lift-off ships removed after climbing away")
    for _, o in pairs(objects) do check(not o.odf:find("^avdrop"), "no ship left behind") end
    check(Drop.Update(M) == false, "done stays done")
end

-- 2. Skip: a cancelled camera lands both ships at once and releases after the ramps.
do
    local Drop = reset()
    local M = {}
    Drop.Update(M)
    for _ = 1, 30 * 3 do step(Drop, M, 1 / 30) end
    camera.cancel = true
    step(Drop, M, 1 / 30)
    check(count("BuildObject", "avdropo") == 2, "skip touches both ships down")
    local released
    for _ = 1, 30 * 5 do
        if not step(Drop, M, 1 / 30) then released = now; break end
    end
    check(released and released < 3 + 2.6 + 0.2, "skip still waits only for the ramps")
    check(not locked() and camera.finish == 1, "skip unlocks and finishes the camera")
end

-- 3. A save taken mid-opening: everything stands down on load.
do
    local Drop = reset()
    local M = {}
    Drop.Update(M)
    for _ = 1, 30 * 8 do step(Drop, M, 1 / 30) end
    masks = {}   -- EXU masks are not saved
    Drop.OnLoad(M)
    check(Drop.Update(M) == false, "a loaded opening does not hold the mission")
    for _, o in pairs(objects) do check(not o.odf:find("^avdrop"), "no ship survives the load") end
    check(M.cr04drop.phase == "done" and not locked(), "loaded opening is finished and unlocked")
end

-- 4. No EXU control mask: the landing still plays.
do
    local Drop = reset({ noExu = true })
    local M = {}
    check(Drop.Update(M) == true, "landing plays without the mask")
    local found
    for _, line in ipairs(log) do if line:find("control lock unavailable") then found = true end end
    check(found, "missing mask is logged")
end

-- 5. Ship art missing: fail closed to the stock opening.
do
    local Drop = reset({ noShips = true })
    local M = {}
    check(Drop.Update(M) == false, "no ships, no hold")
    check(M.cr04drop.phase == "done" and not locked() and camera.ready == 0, "stock opening untouched")
end

print(string.format("CR04Drop: %d checks passed", checks))
