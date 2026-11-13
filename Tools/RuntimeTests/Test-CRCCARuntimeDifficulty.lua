-- Offline difficulty in Scripts/CRCCARuntime.lua, driven through the real Scripts/bd01cr.lua and
-- Scripts/DiffUtils.lua: harder settings add scaled enemies and enemy scrap, easier ones add player scrap,
-- and a network game ignores the setting. Run from the repository root:
--   lua5.1 Tools/RuntimeTests/Test-CRCCARuntimeDifficulty.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/CoopCampaignTests/Bdmisn01Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local DIRECT = { spawn_attack_ambush = true, spawn_attack_wave1 = true }
local function setup(n, difficulty)
    local w = F.reset()
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, { difficulty = difficulty }) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
-- Recycler deploys, Nav Alpha's ambushers appear, one dies, wave 1 arrives and the attack shot ends.
local function reachWave1a(w, m)
    w.cameraDone["camera_start_arc"] = true; F.run(1)
    w.objects["recycler"].deployed = true; F.run(23)
    F.kill(m.badGuy1_ambush); F.run(6)
    w.cameraDone["camera_attack_view"] = true; F.run(3)
end
local function scaled(peer)
    local n = 0
    for _, b in ipairs(F.builds(peer, 0)) do
        if (b.odf == "cvfigh" or b.odf == "cvltnk") and not DIRECT[b.where] then n = n + 1 end
    end
    return n
end
local function startingScrap(peer)
    for _, c in ipairs(F.callsOf(peer, "SetScrap")) do
        if c[2] == 1 then return c[3] end
    end
end

-- Medium, and no DiffUtils at all, build the mission as written.
local w, p, m = setup(1, nil); reachWave1a(w, m)
local written = scaled(p[1])
check(written > 0, "wave 1a builds scaled enemies")
check(startingScrap(p[1]) == 12, "no DiffUtils: starting scrap as written")
w, p, m = setup(1, 2); reachWave1a(w, m)
check(scaled(p[1]) == written and startingScrap(p[1]) == 12, "Medium: unchanged")

-- Very Hard doubles every scaled unit (one extra each) and halves the player's scrap.
w, p, m = setup(1, 4); reachWave1a(w, m)
check(scaled(p[1]) == 2 * written, "Very Hard: one extra per scaled unit")
check(startingScrap(p[1]) == 6, "Very Hard: player scrap halved")

-- Hard gives each scaled unit a 50% chance of an extra: over seeded runs some add one, some don't, none double.
local some, none = false, false
for seed = 1, 20 do
    math.randomseed(seed)
    w, p, m = setup(1, 3); reachWave1a(w, m)
    local hard = scaled(p[1])
    check(hard >= written and hard <= 2 * written, "Hard: at most one extra per scaled unit")
    if hard > written then some = true end
    if hard < 2 * written then none = true end
end
check(some and none, "Hard: extras are a per-unit chance, not all or nothing")
check(startingScrap(p[1]) == 9, "Hard: player scrap x0.75")

-- Scrap edge cases through the runtime directly (fixture capacity 30).
local function scrapAfter(difficulty, team, amount)
    local _, q = setup(1, difficulty)
    -- A second, bare runtime in the same peer: the mission keeps its own instance local.
    local r = q[1].runtime.Create(function() return {} end, { id = "difficulty", leaderTeam = 1, enemyTeam = 5,
        mapEnemyTeam = 2 })
    r.SetScrap(team, amount)
    local c = F.last(q[1], "SetScrap")
    return c[2], c[3]
end
local t, v = scrapAfter(4, 2, 40)
check(t == 5 and v == 80, "Very Hard: enemy scrap doubled, on the co-op enemy team")
t, v = scrapAfter(0, 2, 40)
check(v == 40, "Very Easy: an enemy top-up is never lowered")
t, v = scrapAfter(4, 1, 30)
check(v == 30, "a fill to capacity stays a fill")
t, v = scrapAfter(0, 1, 25)
check(v == 30, "easier settings never overflow capacity")

-- Easier settings never remove units; the player gets more scrap.
w, p, m = setup(1, 0); reachWave1a(w, m)
check(scaled(p[1]) == written and startingScrap(p[1]) == 18, "Very Easy: same enemies, scrap x1.5")

-- Co-op locks difficulty: Very Hard in a network game changes nothing.
w, p, m = setup(2, nil); reachWave1a(w, m)
local coopScrap, coopCount = startingScrap(p[1]), scaled(p[1])
w, p, m = setup(2, 4); reachWave1a(w, m)
check(startingScrap(p[1]) == coopScrap, "network game: scrap ignores difficulty")
check(scaled(p[1]) == coopCount, "network game: spawns ignore difficulty")

print("CRCCARuntimeDifficulty: " .. checks .. " checks passed")
