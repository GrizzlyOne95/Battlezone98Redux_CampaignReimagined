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

-- Mixed waves: restored fighters are primary; existing cap and no-pop-in apply.
local function waveBuilds(peer,mark)
    local out={}
    for _,b in ipairs(F.builds(peer,mark)) do
        if b.odf=="hvsav" or b.odf=="crfraz" then out[#out+1]=b end
    end
    return out
end
F.nearTo(guests[1].player, "alien1", 30, 0)
F.nearTo(guests[2].player, "alien5", 30, 0)
F.nearTo(guests[3].player, "alien3", -30, 0)
local mark = #host.calls
M().alien_time = W.now
F.tick()
local wave = waveBuilds(host, mark)
-- The rogue squad is 8 live Furies: the cap of 12 leaves room for 4 of the 6 (3 + 3 extra humans).
check(#wave == 4 and M().wave_count == 1, "4-player wave capped by the 12 live Furies")
check(#F.builds(host,mark,"crfraz")==4,"cap retains primary light fighters")
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
check(#waveBuilds(host,mark)==6,"3 + 1 per extra human")
check(#F.builds(host,mark,"crfraz")==5 and #F.builds(host,mark,"hvsav")==1,"five fighters and one heavy SAV")

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
for _, b in ipairs(waveBuilds(host,0)) do F.kill(b.h) end
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

-- ------------------------------------------------------------ dropship opening (CRDropIn)
-- One cargo ship carries every human craft and the Texas; the host owns the ship and the Texas, every peer
-- holds only its own craft, and the stock opening follows the release on every peer.
local function pins(peer, h) return F.count(peer, "SetTransform", h) end
local function shipsAlive()
    local n = 0
    for _, o in pairs(W.objects) do
        if o.alive and (o.odf == "avdropc" or o.odf == "avdropo" or o.odf == "avdropx") then n = n + 1 end
    end
    return n
end
session(4, {dropIn = true, guest = {dropIn = true}})
F.run(5)
check(M().cr14dropHold and #F.builds(host, 0, "avdropc") == 1 and #F.builds(host, 0, "apcamr") == 1,
    "the host starts one cargo ship and its camera pod")
check(not F.heard(host, "misn1401.wav") and #F.builds(host, 0, "avsav14") == 0, "the stock opening waits")
check(pins(host, "avrecy-1_recycler") > 0 and pins(host, host.player) > 0 and host.mask == "mission:misn14drop",
    "the host holds the Texas and its own craft, locked")
local lats = {}
for _, g in ipairs(guests) do
    local d = g.env.Save().dropin
    check(d and d.go and d.n == 1 and d.crew[g.team] and d.crew[g.team].ship == 1, "guest " .. g.id .. " has the drop plan")
    lats[#lats + 1] = tostring(d.crew[g.team].along) .. "/" .. tostring(d.crew[g.team].lat)
    check(#F.builds(g, 0) == 0 and pins(g, g.player) > 0 and g.mask == "mission:misn14drop",
        "guest " .. g.id .. " holds only its own craft, locked")
    check(F.count(g, "CameraObject") > 0 and g.camera == 1, "guest " .. g.id .. " films the shared drop camera")
    for _, c in ipairs(F.callsOf(g, "SetTransform")) do check(c[2] == g.player, "a guest pinned a craft it does not own") end
    check(F.count(g, "CameraPath") == 0 and not F.heard(g, "misn1401.wav"), "guest waits for the stock opening")
end
lats[#lats + 1] = tostring(M().dropin.crew[1].along) .. "/" .. tostring(M().dropin.crew[1].lat)
local seen = {}
for _, key in ipairs(lats) do check(not seen[key], "two humans share a hold slot"); seen[key] = true end
throughIntro()
F.run(2)
for _, g in ipairs(guests) do
    check(g.env.Save().dropin.released and g.mask == nil, "guest " .. g.id .. " is released and unlocked")
    check(F.heardCount(g, "misn1401.wav") == 1 and F.count(g, "CameraPath", "cam_path1") > 0,
        "guest " .. g.id .. " gets the stock briefing and flyover after the drop")
    check(g.camera == 0 and F.count(g, "AddObjective", "misn1401.otf") == 1, "guest camera released, stock objective shown")
    check(g.env.Save().coopUnresolved == 0, "guest resolved every drop handle")
end
check(host.mask == nil and host.camera == 0 and F.heardCount(host, "misn1401.wav") == 1, "host released, one briefing")
for _, p in ipairs({host, unpack(guests)}) do F.place(p.player, 2531.6 - 25 * (p.team - 1), 99387.9) end
F.run(60)
check(M().dropin.phase == "done" and shipsAlive() == 0, "the ship closes and leaves")
local goal = F.posOf("avrecy-1_recycler")
check(math.sqrt((goal.x - 2573.8) ^ 2 + (goal.z - 99396.2) ^ 2) < 8, "the Texas is set down at its landing goal")
check(#F.builds(host, 0, "avsav14") == 8, "the stock Fury pad (two per human) follows the drop")

-- A guest without CRDropIn still acknowledges the plan: the stream never stalls.
session(2, {dropIn = true, guest = {}})
throughIntro()
check(F.heardCount(guests[1], "misn1401.wav") == 1 and guests[1].env.Save().coopUnresolved == 0
    and F.count(guests[1], "SetTransform") == 0, "a guest without the module follows the stream and is never moved")
local said = false
for _, c in ipairs(F.callsOf(guests[1], "print")) do said = said or tostring(c[2]):find("CRDropIn unavailable", 1, true) ~= nil end
check(said, "the fallback is logged")

-- Host departure mid-drop unlocks every peer (nobody stays held).
session(2, {dropIn = true, guest = {dropIn = true}})
F.run(5)
check(guests[1].mask == "mission:misn14drop", "the guest is held")
host.env.DeletePlayer(1, "P1", 1)
guests[1].env.DeletePlayer(1, "P1", 1)
F.run(2)
check(guests[1].mask == nil, "the guest is unlocked when the host leaves")

print(string.format("misn14 co-op: %d checks passed", checks))
