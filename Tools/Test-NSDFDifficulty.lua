-- Single-player difficulty for the NSDF missions: Scripts/CRDifficulty.lua (misn06..misn14 wrap the natives with it),
-- plus the misn17/misn18 runtimes driven through their real fixtures with the real Scripts/DiffUtils.lua.
-- Run from the repository root:
--   lua5.1 Tools/Test-NSDFDifficulty.lua
assert(_VERSION == "Lua 5.1")
package.path = "Scripts/?.lua;" .. package.path
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

-- ------------------------------------------------------------------ the helper in isolation
local difficulty, network = 2, false
local function load(withDiffUtils)
    package.loaded.CRDifficulty = nil
    package.loaded.CRCoop = { IsNetworkGame = function() return network end }
    package.loaded.DiffUtils = nil
    package.preload.DiffUtils = nil
    if withDiffUtils then
        local RES = { 1.5, 1.25, 1.0, 0.75, 0.5 }
        local ENEMY = { 0.5, 0.75, 1.0, 1.5, 2.0 }
        package.loaded.DiffUtils = {
            Get = function() return { res = RES[difficulty + 1], enemy = ENEMY[difficulty + 1] } end,
            ScaleRes = function(v) return math.floor(v * RES[difficulty + 1]) end,
            ScaleEnemy = function(v) return math.ceil(v * ENEMY[difficulty + 1]) end,
        }
    else
        package.preload.DiffUtils = function() error("no DiffUtils on this host") end
    end
    return require("CRDifficulty")
end

-- Scrap and pilots.
local scrap = {}
local function native(team, amount) scrap[#scrap + 1] = { team, amount } end
local function last() return scrap[#scrap] end
local D = load(true)
local CAP = 100
local SetScrap = D.Resource(native, function() return CAP end, { [5] = true })
local AddScrap = D.Resource(native, nil, { [5] = true }, true)

difficulty, network = 2, false
SetScrap(1, 80); check(last()[2] == 80, "Medium: player scrap as written")
SetScrap(5, 40); check(last()[2] == 40, "Medium: enemy scrap as written")
difficulty = 4
SetScrap(1, 80); check(last()[2] == 40, "Very Hard: player scrap halved")
SetScrap(1, 100); check(last()[2] == 100, "a fill to capacity stays a fill")
SetScrap(1, 150); check(last()[2] == 150, "above capacity also stays as written")
SetScrap(5, 40); check(last()[2] == 80, "Very Hard: enemy scrap doubled")
SetScrap(5, 0); check(last()[2] == 0, "a zero enemy scrap stays zero")
AddScrap(1, 30); check(last()[2] == 15, "Very Hard: player top-up halved")
AddScrap(5, 60); check(last()[2] == 120, "Very Hard: enemy top-up doubled")
AddScrap(5, -20); check(last()[2] == -20, "a cost passes through")
AddScrap(1, -20); check(last()[2] == -20, "a player cost passes through")
SetScrap(7, 55); check(last()[1] == 7 and last()[2] == 55, "other teams are untouched")
difficulty = 0
SetScrap(1, 80); check(last()[2] == 100, "Very Easy: player scrap grows but is clamped to capacity")
SetScrap(1, 40); check(last()[2] == 60, "Very Easy: 40 -> 60")
SetScrap(5, 40); check(last()[2] == 40, "easier settings never lower an enemy top-up")
AddScrap(5, 60); check(last()[2] == 60, "easier settings never lower an enemy AddScrap")
difficulty = 4; network = true
SetScrap(1, 80); check(last()[2] == 80, "network game: player scrap unchanged")
SetScrap(5, 40); check(last()[2] == 40, "network game: enemy scrap unchanged")
AddScrap(1, 30); check(last()[2] == 30, "network game: top-up unchanged")
network = false
local bare = load(false)
local bareSet = bare.Resource(native, function() return CAP end, { [5] = true })
bareSet(1, 80); check(last()[2] == 80, "no DiffUtils: player scrap unchanged")
bareSet(5, 40); check(last()[2] == 40, "no DiffUtils: enemy scrap unchanged")
check(bare.Extras() == 0 and not bare.Active(), "no DiffUtils: no extras")

-- Extra hostile units.
D = load(true)
local built, serial = {}, 0
local function nativeBuild(odf, team, where)
    serial = serial + 1
    built[#built + 1] = { h = serial, odf = odf, team = team, where = where }
    return serial
end
local Build = D.Build(nativeBuild, { [5] = true })
local function count(odf, team)
    local n = 0
    for _, b in ipairs(built) do if b.odf == odf and b.team == team then n = n + 1 end end
    return n
end
local function reset() built, serial = {}, 0 end

difficulty = 4
reset(); for _ = 1, 10 do Build("svfigh", 5, "path1") end
check(count("svfigh", 5) == 20, "Very Hard: one extra per unit, got " .. count("svfigh", 5))
check(built[2].where == "path1" and built[2].team == 5, "an extra is built at the same place for the same team")
reset(); Build("svhaul", 5, "p"); Build("svturr", 5, "p"); Build("sspilo", 5, "p"); Build("svscav", 5, "p")
check(#built == 4, "haulers, turrets, pilots and scavengers are never extended")
reset(); Build("svfigh", 7, "p"); Build("avfigh", 1, "p")
check(#built == 2, "friendly units are never extended")
difficulty = 3
local some, none = false, false
for seed = 1, 40 do
    math.randomseed(seed); reset()
    for _ = 1, 10 do Build("svtank", 5, "p") end
    local n = count("svtank", 5)
    check(n >= 10 and n <= 20, "Hard: at most one extra per unit")
    if n > 10 then some = true end
    if n < 20 then none = true end
end
check(some and none, "Hard: each unit has a chance of an extra, not all or nothing")
math.randomseed(7); reset(); for _ = 1, 400 do Build("svfigh", 5, "p") end
check(count("svfigh", 5) > 560 and count("svfigh", 5) < 640, "Hard: about 0.5 extra per unit, got " .. count("svfigh", 5))
for _, d in ipairs({ 0, 1, 2 }) do
    difficulty = d; reset(); for _ = 1, 10 do Build("svfigh", 5, "p") end
    check(count("svfigh", 5) == 10, "difficulty " .. d .. ": units are never added or removed")
end
difficulty = 4; network = true; reset(); for _ = 1, 10 do Build("svfigh", 5, "p") end
check(count("svfigh", 5) == 10, "network game: no extras")
network = false
bare = load(false)
reset(); local BareBuild = bare.Build(nativeBuild, { [5] = true }); for _ = 1, 10 do BareBuild("svfigh", 5, "p") end
check(#built == 10, "no DiffUtils: no extras")

-- Orders reach the extras.
D = load(true); difficulty = 4; reset()
local orders, dead = {}, {}
_G.IsAlive = function(h) return not dead[h] end
local Attack, Goto = D.Mirror(function(h, ...) orders[#orders + 1] = { "Attack", h, ... } end,
    function(h, ...) orders[#orders + 1] = { "Goto", h, ... } end)
Build = D.Build(nativeBuild, { [5] = true })
local unit = Build("svfigh", 5, "p")
Attack(unit, "target", 1)
check(#orders == 2 and orders[1][2] ~= orders[2][2] and orders[2][2] == unit, "the extra gets the order, the unit keeps it")
check(orders[1][3] == "target" and orders[1][4] == 1, "extras receive the same arguments")
dead[orders[1][2]] = true; orders = {}
Goto(unit, "path"); check(#orders == 1 and orders[1][2] == unit, "a dead extra is not ordered")
orders = {}; Goto("stranger", "path"); check(#orders == 1, "an unextended unit is ordered once")
_G.IsAlive = nil

-- Fallback leadership: each extra is told to Follow its primary at build time.
do
    D = load(true); difficulty = 4; reset()
    local follows = {}
    _G.Follow = function(h, leader) follows[#follows + 1] = { h, leader } end
    local B = D.Build(nativeBuild, { [5] = true })
    local u = B("svfigh", 5, "p")
    check(#follows == 1 and follows[1][1] ~= u and follows[1][2] == u, "an extra follows its primary on build")
    follows = {}; B("svhaul", 5, "p")
    check(#follows == 0, "non-combat units get no Follow")
    _G.Follow = nil
    B("svfigh", 5, "p") -- no global Follow: must not error

    -- Lifecycle: RemoveObject / SetTeamNum / SetPerceivedTeam reach the extras.
    local log = {}
    local function rec(name) return function(h, ...) log[#log + 1] = { name, h, ... } end end
    local Remove = D.Remove(rec("Remove"))
    local SetTeamNum, SetPerceivedTeam = D.Mirror(rec("SetTeamNum"), rec("SetPerceivedTeam"))
    _G.IsAlive = function() return true end
    local primary = B("svtank", 5, "p")
    SetTeamNum(primary, 1); check(#log == 2 and log[1][2] ~= primary and log[2][2] == primary and log[1][3] == 1, "SetTeamNum reaches the extra")
    log = {}; SetPerceivedTeam(primary, 2); check(#log == 2 and log[1][3] == 2, "SetPerceivedTeam reaches the extra")
    log = {}; Remove(primary); check(#log == 2 and log[1][2] ~= primary and log[2][2] == primary, "RemoveObject removes the extra too")
    log = {}; SetTeamNum(primary, 1); check(#log == 1, "RemoveObject drops the extras list")
    log = {}; Remove("stranger"); check(#log == 1, "RemoveObject on an unextended unit is a plain call")

    -- A rebuilt non-combat unit under a reused handle clears the stale list.
    local reuse = 0
    local function reusing(odf, team, where) built[#built + 1] = { odf = odf }; reuse = reuse + 1; return (reuse <= 2) and (reuse == 1 and 500 or 501) or 500 end
    reset(); log = {}
    local B2 = D.Build(reusing, { [5] = true })
    local first = B2("svfigh", 5, "p")   -- primary 500, extra 501
    local SetTeam2 = D.Mirror(rec("SetTeamNum"))
    SetTeam2(first, 1); check(#log == 2, "stale test setup: extra registered")
    B2("svhaul", 5, "p")                  -- handle 500 reused by a hauler
    log = {}; SetTeam2(500, 1); check(#log == 1, "a non-combat rebuild clears the stale extras entry")
    _G.IsAlive = nil
end

-- misn12 is a stealth mission at the local limit: it takes no extras.
do
    local f = assert(io.open("Scripts/misn12cr.lua", "rb")); local src = f:read("*a"); f:close()
    check(not src:find("CRDifficulty", 1, true), "misn12 builds no extras")
end

-- ------------------------------------------------------------------ misn18 and misn17, real runtimes
package.loaded.CRDifficulty, package.loaded.DiffUtils, package.preload.DiffUtils = nil, nil, nil
package.loaded.CRCoop = nil
local F18 = dofile("Tools/Misn18Fixture.lua")
local function setup18(n, options)
    local w = F18.reset(); w.capacity = 200
    local p = {}
    for i = 1, n do p[i] = F18.makePeer(i, i, n > 1, options) end
    F18.connect(); F18.run(5)
    return w, p, p[1].env.Save()
end
local function wave1(difficultyIndex, n)
    local w, p = setup18(n or 1, { difficulty = difficultyIndex })
    F18.nearTo(p[1].player, "spawn1a"); F18.run(8)
    return F18.builds(p[1]), p, w
end
local function startScrap(p) return F18.last(p[1], "SetScrap")[3] end

local base, p = wave1(nil)
check(#base == 2, "misn18 without DiffUtils: the two wave craft")
check(startScrap(p) == 80, "misn18 without DiffUtils: starting scrap as written")
local medium; medium, p = wave1(2)
check(#medium == 2 and startScrap(p) == 80, "misn18 Medium: unchanged")
local vh; vh, p = wave1(4)
check(#vh == 4, "misn18 Very Hard: one extra per Fury, got " .. #vh)
check(startScrap(p) == 40, "misn18 Very Hard: starting scrap halved")
for _, b in ipairs(vh) do check(b.team == 6, "extras are Furies") end
local toT1, toT2 = 0, 0
for _, c in ipairs(F18.callsOf(p[1], "Goto")) do
    if c[3] == "transport1" then toT1 = toT1 + 1 elseif c[3] == "transport2" then toT2 = toT2 + 1 end
end
check(toT1 == 2 and toT2 == 2, "misn18 extras take the route of the unit they mirror (" .. toT1 .. "/" .. toT2 .. ")")
local easy; easy, p = wave1(0)
check(#easy == 2 and startScrap(p) == 120, "misn18 Very Easy: no unit removed, scrap 80 -> 120")
local sawExtra, sawNone = false, false
for seed = 1, 12 do
    math.randomseed(seed)
    local hard = wave1(3)
    check(#hard >= 2 and #hard <= 4, "misn18 Hard: at most one extra per Fury")
    if #hard > 2 then sawExtra = true end
    if #hard < 4 then sawNone = true end
end
check(sawExtra and sawNone, "misn18 Hard: a per-unit chance")
local netVh = wave1(4, 2)
check(#netVh == 3, "misn18 co-op ignores the difficulty: 2 craft + floor(2/2) extra, got " .. #netVh)
do
    local w, p2 = setup18(2, { difficulty = 4 })
    check(F18.last(p2[1], "SetScrap")[3] == 90, "misn18 co-op scrap: 80 + 10 per guest, not scaled")
end
-- Capacity: a scaled amount is clamped to it, a fill (amount >= capacity) is left as written.
do
    local w3 = F18.reset(); w3.capacity = 100
    local q = F18.makePeer(1, 1, false, { difficulty = 0 }); F18.connect(); F18.run(5)
    check(F18.last(q, "SetScrap")[3] == 100, "misn18 Very Easy: 80 -> 120 is clamped to capacity 100")
    w3 = F18.reset(); w3.capacity = 60
    q = F18.makePeer(1, 1, false, { difficulty = 4 }); F18.connect(); F18.run(5)
    check(F18.last(q, "SetScrap")[3] == 80, "misn18 Very Hard: a fill to capacity stays a fill")
end

local F17 = dofile("Tools/Misn17Fixture.lua")
local function tower(difficultyIndex)
    local w = F17.reset(); w.capacity = 200
    local peer = F17.makePeer(1, 1, false, { difficulty = difficultyIndex })
    F17.connect(); F17.run(5)
    local m = peer.env.Save()
    local mark = #peer.calls
    F17.nearTo(peer.player, m.tower1); F17.run(6)
    local furies = 0
    for _, b in ipairs(F17.builds(peer, mark)) do if b.team == 6 then furies = furies + 1 end end
    return furies, peer
end
local written, peer17 = tower(nil)
check(written >= 2, "misn17 without DiffUtils: the scripted Furies at the tower, got " .. written)
check(F17.last(peer17, "SetScrap")[3] == 40, "misn17 without DiffUtils: starting scrap as written")
local count17
count17, peer17 = tower(2)
check(count17 == written and F17.last(peer17, "SetScrap")[3] == 40, "misn17 Medium: unchanged")
count17, peer17 = tower(4)
check(count17 == 2 * written, "misn17 Very Hard: one extra per Fury, got " .. count17 .. " for " .. written)
check(F17.last(peer17, "SetScrap")[3] == 20, "misn17 Very Hard: starting scrap halved")
check(F17.count(peer17, "Attack") + F17.count(peer17, "Defend2") >= 2 * written, "misn17 extras are ordered like the unit they mirror")
count17, peer17 = tower(1)
check(count17 == written and F17.last(peer17, "SetScrap")[3] == 50, "misn17 Easy: no unit removed, scrap 40 -> 50")

print(string.format("NSDF difficulty: %d checks passed (Lua 5.1)", checks))
