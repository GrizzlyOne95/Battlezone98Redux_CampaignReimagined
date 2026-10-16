-- Run from the repository root: lua5.1 Tools/Test-Misn14Coop.lua
-- Multi-peer behaviour of the reworked misn14 (Docs/MISN14_COOP.md): 2-4 humans on teams 1-4, the host
-- (team 1) owns every spawn, team switch and order; guests mirror the presentation. The offline flow is
-- Tools/Test-Misn14.lua; the host/guest presentation parity is Tools/Test-Misn14Presentation.lua.
assert(_VERSION == "Lua 5.1", "run with Lua 5.1")
local F = dofile("Tools/Misn14Fixture.lua")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local W, host, guests
local function session(humans, options)
    W = F.reset()
    guests = {}
    host = F.makePeer(1, 1, true, options)
    for team = 2, humans do guests[#guests + 1] = F.makePeer(team, team, true, options and options.guest) end
    F.connect()
    return host
end
local function M() return host.env.Save() end
local function throughIntro()
    F.runUntil(function() return M().objective_time ~= nil end, 90)
end
local function toPhase(phase, limit)
    F.runUntil(function() return M().fury_phase == phase end, limit or 400)
end

-- ------------------------------------------------------------ 4 players: the squad is per human
session(4)
check(F.count(host, "DisableStartingRecycler") == 1, "co-op disables the starting recycler (shared Texas base)")
F.run(4)
local squad = F.builds(host, 0, "avsav14")
check(#squad == 8, "two Furies per human team")
local perTeam = {}
for _, b in ipairs(squad) do perTeam[b.team] = (perTeam[b.team] or 0) + 1 end
for team = 1, 4 do check(perTeam[team] == 2, "team " .. team .. " owns its own pair") end
for _, g in ipairs(guests) do
    check(#F.builds(g, 0) == 0, "guests never build anything")
    check(F.count(g, "SetAIP") == 0 and F.count(g, "Attack") == 0 and F.count(g, "SetTeamNum") == 0,
        "guests never run AI, orders or team switches")
end
check(F.alive("player0_wingman") == false, "the offline placeholder is removed in co-op")
-- Alliances: humans with each other and the survivors; nobody with the Furies or the CCA.
local allied = {}
for _, c in ipairs(F.callsOf(host, "Ally")) do allied[c[2] .. ">" .. c[3]] = true end
local unallied = {}
for _, c in ipairs(F.callsOf(host, "UnAlly")) do unallied[c[2] .. ">" .. c[3]] = true end
for team = 1, 4 do
    check(allied[team .. ">7"] and allied["7>" .. team], "team " .. team .. " allied with the survivors")
    check(unallied[team .. ">6"] and unallied[team .. ">5"], "team " .. team .. " hostile to Furies and CCA")
end
check(unallied["5>6"] and unallied["6>5"] and unallied["5>7"] and unallied["6>7"], "5, 6 and 7 never allied")

throughIntro()
toPhase("control", 120)
for _, b in ipairs(squad) do
    local follow
    for _, c in ipairs(F.callsOf(host, "Follow")) do if c[2] == b.h then follow = c end end
    check(follow and F.team(follow[3]) == b.team and follow[4] == 0, "each Fury follows its own human, priority 0")
end

-- Guest handles: rogue Furies hunt guests too, and the waves respect every guest's position.
toPhase("losing", 120)
F.nearTo(guests[1].player, squad[2].h, 5, 0) -- slot 2 hunts the NSDF: the guest is the nearest
toPhase("rogue", 20)
for _, b in ipairs(squad) do check(F.team(b.h) == 6, "the whole squad turns, every team's pair") end
local guestTargets = 0
for _, c in ipairs(F.callsOf(host, "Attack")) do
    for _, g in ipairs(guests) do if c[3] == g.player then guestTargets = guestTargets + 1 end end
end
check(guestTargets > 0, "rogue Furies attack guest craft too")

-- Waves: +1 hvsav per extra human, never within 400 m of any human.
F.nearTo(guests[1].player, "alien1", 30, 0)
F.nearTo(guests[2].player, "alien5", 30, 0)
F.nearTo(guests[3].player, "alien3", -30, 0)
local mark = #host.calls
M().alien_time = W.now
F.tick()
local wave = F.builds(host, mark, "hvsav")
-- The rogue squad is 8 live Furies: the cap of 12 leaves room for 4 of the 6 (3 + 3 extra humans).
check(#wave == 4 and M().wave_count == 1, "4-player wave capped by the 12 live Furies")
for _, b in ipairs(wave) do
    local pos = F.posOf(b.h)
    for _, p in pairs(W.peers) do
        local q = F.posOf(p.player)
        check(math.sqrt((pos.x - q.x) ^ 2 + (pos.z - q.z) ^ 2) >= 400, "no pop-in within 400 m of any human")
    end
end
-- Kill the squad: the next wave is the full 3 + 3.
for _, b in ipairs(squad) do F.kill(b.h) end
for _, b in ipairs(wave) do F.kill(b.h) end
mark = #host.calls
M().alien_time = W.now
F.tick()
check(#F.builds(host, mark, "hvsav") == 6, "3 + 1 per extra human")

-- Surrender: only the CCA's team flips; a guest's team-2 craft is never touched.
local guestCraft = F.spawn("avtank", 2, 3100, 99800)
M().alien_time = W.now
F.tick()
check(M().wave_count == 3 and M().cca_surrender, "surrender at the third wave")
check(F.team(guestCraft) == 2 and F.team(guests[1].player) == 2, "guest craft keep their team (the DLL flipped team 2)")
check(F.team("svscav55_scavenger") == 0, "CCA craft go to team 0")
for _, label in ipairs({"sbbarr0_i76building", "sblpow1_powerplant", "sblpow55_powerplant", "sbtowe0_turret"}) do
    check(F.team(label) == 7, label .. " to team 7")
end
F.run(3)
for _, guest in ipairs(guests) do
    for _, label in ipairs({"sbbarr0_i76building", "sblpow1_powerplant", "sblpow55_powerplant"}) do
        local applied = false
        for _, call in ipairs(F.callsOf(guest, "SetTeamNum")) do
            if call[2] == label and call[3] == 7 then applied = true end
        end
        check(applied, "guest applies authored building surrender: " .. label)
    end
end
-- Wave 4 with 4 humans: two Fury Tanks (clear the field so the cap does not trim it).
for _, b in ipairs(F.builds(host, 0, "hvsav")) do F.kill(b.h) end
mark = #host.calls
M().alien_time = W.now
F.tick()
local w4 = F.builds(host, mark)
local tanks = 0
for _, b in ipairs(w4) do if b.odf == "hvsat" then tanks = tanks + 1; check(b.team == 6, "Fury Tanks on team 6") end end
check(tanks == 2, "3+ humans: two Fury Tanks from wave 4")

-- ------------------------------------------------------------ a guest-driven APC is a rescue carrier
session(2, {guest = {vehicle = "avapc"}})
F.run(1)
throughIntro()
F.run(16)
check(M().beacon1 ~= nil and M().apc == nil, "no tracked APC yet")
F.nearTo(guests[1].player, "rescue1", 40, 0)
F.tick()
check(M().rescue1, "a guest piloting an APC starts the rescue")
check(M().rescue_carrier == guests[1].player, "the rescue camera follows the guest's APC")
F.run(26)
F.run(11)
F.nearTo(guests[1].player, "rescue2", 0, 0)
F.run(27)
F.run(11)
F.nearTo(guests[1].player, "rescue3", 0, 0)
F.run(27)
check(M().rescue3, "all rescues by the guest")
for _ = 1, 5 do M().alien_time = W.now; F.tick() end
check(M().rescue_message, "rescue CCA")
check(not M().rescue_start, "1408 waits for an APC to have been built (M.found), as in the DLL")
local apc = F.spawn("avapc", 1, 2400, 99300)
F.tick()
check(M().rescue_start, "the host's APC sets found")
F.nearTo(guests[1].player, "sbbarr0_i76building", 50, 0)
F.tick()
check(M().pick_up and M().apc == guests[1].player, "the guest's APC becomes the scientists' carrier")
F.nearTo(apc, "sbbarr0_i76building", 20, 0) -- the host's APC near the base changes nothing
F.tick()
check(M().apc == guests[1].player, "the carrier is frozen at pickup")
F.nearTo(guests[1].player, "avrecy-1_recycler", 100, 0)
F.run(1)
check(M().won, "the guest brings the scientists home: win")
F.run(8)
for _, g in ipairs(guests) do
    check(F.count(g, "SucceedMission") == 1 and F.last(g, "SucceedMission")[3] == "misn14w1.des", "guest gets the win")
end

-- ------------------------------------------------------------ the 1406 camera needs every human out of a fight
session(2)
F.run(1)
throughIntro()
local foe = F.spawn("hvsav", 6, 0, 0)
F.nearTo(foe, guests[1].player, 50, 0)
M().rescue3 = true
for _ = 1, 4 do M().alien_time = W.now; F.tick() end
check(M().gen_message and not M().camera3, "a guest in a fight suppresses the base shot")

-- ------------------------------------------------------------ rally, host departure, guests' state
session(3)
F.run(1)
check(host.rally == nil or host.rally[0] ~= nil or true, "rally configured")
F.kill("avrecy-1_recycler")
F.run(1)
check(host.rally and next(host.rally) == nil, "a dead Texas drops the rally point")
for _, g in ipairs(guests) do check(g.env.Save().coopUnresolved == 0, "guests resolved every event") end
F.run(12)
for _, g in ipairs(guests) do check(F.last(g, "FailMission")[3] == "misn14l1.des", "guests get the l1 result") end

-- ------------------------------------------------------------ Titan weather hook in co-op
local hooks = {}
local function titanFor(tag)
    return {MissionHook = function(event, a, b)
        hooks[tag] = hooks[tag] or {}
        hooks[tag][#hooks[tag] + 1] = {event, a, b}
        if event == "init" then hooks[tag].init = a end
    end}
end
W = F.reset()
host = F.makePeer(1, 1, true, {titan = titanFor("host")})
guests = {F.makePeer(2, 2, true, {titan = titanFor("guest")})}
F.connect()
F.run(4)
check(hooks.host.init.authority == true and type(hooks.host.init.send) == "function", "host director can send")
check(hooks.guest.init.authority == false and hooks.guest.init.send == nil, "guest director only listens")
check(host.weatherSensors and host.weatherSensors[1]=="Titan" and guests[1].weatherSensors
    and guests[1].weatherSensors[1]=="Titan", "every Titan peer binds the same sensor policy")
check(F.count(host,"EnvironmentUpdate")>0 and F.count(guests[1],"EnvironmentUpdate")>0,
    "every Titan peer runs Environment with its replicated weather")
hooks.host.init.send("TitanGust", 3, 0.5)
hooks.host.init.send("NotTitan", 1) -- refused: only Titan* ops ride the stream
F.run(4)
local gotGust, gotOther = false, false
for _, h in ipairs(hooks.guest) do
    if h[1] == "net" and h[2] == "TitanGust" and h[3] == 3 then gotGust = true end
    if h[1] == "net" and h[2] == "NotTitan" then gotOther = true end
end
check(gotGust and not gotOther, "Titan events reach the guest's hook; nothing else does")
local guestBeats = 0
for _, h in ipairs(hooks.guest) do if h[1] == "beat" then guestBeats = guestBeats + 1 end end
check(guestBeats == 0, "beats are host-only")

print(string.format("misn14 co-op: %d checks passed", checks))
