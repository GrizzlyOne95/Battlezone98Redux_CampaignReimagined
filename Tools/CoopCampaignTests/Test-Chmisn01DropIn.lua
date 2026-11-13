-- ch01 Recycler dropship delivery: the real Scripts/ch01cr.lua with the real Scripts/CRDropIn.lua (CRA cvdrop) over the
-- multi-peer fixture. Engine physics, floor collision and SDF animation are mocks: this proves script decisions only
-- (the drop starts at the comm tower's death, the body keeps running, the stored handle deploys and starts wave 1,
-- fallbacks, co-op ownership, save/load). Run from the repository root:
--   lua5.1 Tools/CoopCampaignTests/Test-Chmisn01DropIn.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Chmisn01Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function run(seconds) F.run(seconds, 0.5) end
local function aliveOdf(w, pattern)
    local n = 0
    for _, o in pairs(w.objects) do if o.alive and o.odf:find(pattern) then n = n + 1 end end
    return n
end
local function builds(peer, odf) return F.builds(peer, 0, odf) end
local function setup(n, options)
    local w = F.reset()
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); run(1)
    return w, p, p[1].env.Save()
end
-- Opening line, "CCA Base" nav, hangar inspected, armoury delivered.
local function reachComm(p)
    run(7)
    p[#p].info.sbhanga = true; run(1); p[#p].info.sbhanga = false
    run(18)
end
-- Then the comm array falls.
local function fall(p) reachComm(p); F.kill("target_2"); run(1) end
local PATH = F.PATHS.recycler

-- ---------------------------------------------------------------- offline
do
    local w, p, m = setup(1, { dropIn = true })
    local h = p[1]
    reachComm(p)
    check(aliveOdf(w, "^cvdrop") == 0 and aliveOdf(w, "^cvrecyd") == 0, "nothing is delivered before the comm array falls")
    F.kill("target_2"); run(1)
    check(m.objective2Complete and F.heardCount(h, "ch01005.wav") == 1, "the stock branch runs: audio, objective")
    check(aliveOdf(w, "^cvdropc") == 1, "one flying cvdrop")
    check(m.recycler ~= nil and w.objects[m.recycler].odf == "cvrecyd", "the body stored the delivered Recycler")
    check(w.objects[m.recycler].pos.y > 100, "the Recycler rides the descending ship")
    check(F.count(h, "CameraReady") == 0 and h.camera == 0, "no drop camera in a mid-mission delivery")
    check(F.count(h, "AddScrap") >= 2, "the scrap bonus is paid at once")
    check(m.wave1Time > 999000, "wave 1 waits for the Recycler to deploy")
    local first = m.recycler
    check(m.dropin.go and not m.dropin.released, "the ship is still flying; the mission is not held")
    run(25)
    check(m.dropin.released, "the ramp opened and the Recycler was released")
    check(aliveOdf(w, "^cvdropo") == 1 and w.objects[first].pos.y < 50, "the landed ship put the Recycler on the ground")
    F.place(first, PATH[1] + 300, PATH[3] + 300) -- the mock does not drive: the Recycler is off the ramp
    F.runUntil(function() return m.dropin.phase == "done" end, 120)
    check(aliveOdf(w, "^cvdrop") == 0, "the ship leaves")
    check(m.recycler == first and F.alive(first), "the same Recycler is still the stored handle")
    w.objects[first].deployed = true; run(1)
    check(m.recyclerDeployed and m.wave1Time > w.now and m.wave1Time < w.now + 61,
        "wave 1 is timed from the delivered Recycler's deployment")
    run(62)
    check(#builds(h, "svfigh") >= 4, "wave 1 arrives")
end

-- ---------------------------------------------------------------- the stock Recycler without the module
do
    local w, p, m = setup(1, {})
    fall(p)
    check(aliveOdf(w, "^cvdrop") == 0 and m.dropin == nil, "no CRDropIn: no ship")
    check(F.alive(m.recycler) and near(w.objects[m.recycler].pos.x, PATH[1], 1) and w.objects[m.recycler].pos.y < 50,
        "no CRDropIn: the Recycler stands on its path as stock")
end

-- ---------------------------------------------------------------- a failing start falls back to the stock Recycler
do
    local w, p, m = setup(1, { dropIn = true })
    p[1].modules.CRDropIn.Begin = function() error("boom") end
    fall(p)
    check(aliveOdf(w, "^cvdrop") == 0 and m.dropin.phase == "done", "a failing start builds no ship")
    check(F.alive(m.recycler) and w.objects[m.recycler].pos.y < 50, "the Recycler stays on its path")
    w.objects[m.recycler].deployed = true; run(1)
    check(m.recyclerDeployed, "the stock Recycler still starts wave 1")
    local w2, p2, m2 = setup(1, { dropIn = true })
    p2[1].modules.CRDropIn.Begin = function() return false end
    fall(p2)
    check(aliveOdf(w2, "^cvdrop") == 0 and w2.objects[m2.recycler].pos.y < 50, "a refused start leaves the Recycler on its path")
end

-- ---------------------------------------------------------------- co-op: host + a guest
do
    local w, p, m = setup(2, { dropIn = true })
    local host, guest = p[1], p[2]
    fall(p)
    check(#builds(host, "cvdropc") == 1 and F.count(guest, "BuildObject") == 0, "only the host builds the ship")
    local s = F.state(guest).dropin
    check(s and s.go and s.n == 1 and s.ships[1].prof == "cvdrop" and next(s.crew or {}) == nil, "the guest has the plan: one cvdrop, no crew")
    check(F.count(host, "CameraReady") == 0 and F.count(guest, "CameraReady") == 0, "no peer takes a camera")
    check(F.count(guest, "SetTransform") == 0, "the guest moves nothing (it carries no craft)")
    run(25)
    check(F.state(guest).dropin.released and F.state(host).dropin.released, "both peers released")
    for _, name in ipairs({ "BuildObject", "SetScrap", "RemoveObject", "Goto", "Stop" }) do
        check(F.count(guest, name) == 0, "guest never mutates gameplay: " .. name)
    end
    F.place(m.recycler, PATH[1] + 300, PATH[3] + 300)
    F.runUntil(function() return F.state(host).dropin.phase == "done" end, 120)
    check(aliveOdf(w, "^cvdrop") == 0, "the ship leaves in co-op")
    w.objects[m.recycler].deployed = true; run(1)
    check(m.recyclerDeployed, "co-op: the Recycler deploys")
end

-- ---------------------------------------------------------------- co-op: the host leaves mid-drop
do
    local w, p = setup(2, { dropIn = true })
    fall(p)
    check(F.state(p[2]).dropin and F.state(p[2]).dropin.go and not F.state(p[2]).dropin.released, "the guest follows the drop")
    p[2].env.DeletePlayer(1); run(1)
    check(F.state(p[2]).dropin.phase == "done", "a departed host takes the drop down")
end

-- ---------------------------------------------------------------- save and load
do
    local w, p, m = setup(1, { dropIn = true })
    local h = p[1]
    reachComm(p); F.kill("target_2"); run(4)
    check(aliveOdf(w, "^cvdrop") == 1 and m.dropin.go and not m.dropin.released, "mid-drop save point")
    h.env.Load(m); run(1)
    check(m.dropin.phase == "done" and aliveOdf(w, "^cvdrop") == 0, "a load mid-drop ends the drop")
    check(near(w.objects[m.recycler].pos.x, PATH[1], 5) and w.objects[m.recycler].pos.y < 20, "the Recycler is set down on its spot")
    w.objects[m.recycler].deployed = true; run(1)
    check(m.recyclerDeployed and m.wave1Time < 999000, "the loaded game still starts wave 1 on deployment")
    -- an old save: the Recycler already exists, there is no drop state, nothing is delivered again
    local w2, q, mq = setup(1, { dropIn = true })
    fall(q)
    run(25)
    F.place(mq.recycler, PATH[1] + 300, PATH[3] + 300)
    F.runUntil(function() return mq.dropin.phase == "done" end, 120)
    local old = q[1].env.Save()
    old.dropin = nil
    local before = #builds(q[1], "cvdropc")
    q[1].env.Load(old); run(3)
    check(#builds(q[1], "cvdropc") == before and aliveOdf(w2, "^cvdrop") == 0 and old.dropin == nil, "an old save never starts a drop")
end

print(string.format("chmisn01 dropship delivery: %d checks passed", checks))
