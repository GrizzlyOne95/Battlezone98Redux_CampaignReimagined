-- Independent Lua peers, real CRCoop registry, lossy presentation simulator, the real Scripts/CRCCARuntime.lua
-- and Scripts/bd10cr.lua. Engine AI, rendering and combat remain mocks. Run from the repository root:
--   lua5.1 Tools/Test-Bdmisn10Coop.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/Bdmisn10Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

local function extrasFor(n) return math.min(math.floor(n / 2), 2) end
local DEFENCE_UNITS = { 6, 6, 6, 8 } -- the body's four defence groups
local PATROL_UNITS = 5

local function setup(n, options)
    options = options or {}
    local w = F.reset()
    w.audioBusy = options.busy == true
    local p = {}
    for i = 1, n do p[i] = F.makePeer(i, i, n > 1, options) end
    F.connect(); F.run(1)
    return w, p, p[1].env.Save()
end
local function builtAt(peer, where, odf)
    local out = {}
    for _, b in ipairs(F.builds(peer, 0, odf)) do
        if b.where == where then out[#out + 1] = b end
    end
    return out
end
local function guestsPassive(p)
    for i = 2, #p do
        for _, name in ipairs({"BuildObject", "SetScrap", "Hunt", "Goto", "Follow", "SetIndependence"}) do
            check(F.count(p[i], name) == 0, "guest " .. i .. " never mutates gameplay: " .. name)
        end
    end
end
local function noEnemyTeamTwo(peer)
    for _, b in ipairs(F.builds(peer)) do check(b.team ~= 2, "no unit is built on the authored enemy team 2") end
end
local function finishIntro(w) w.cameraDone["camera_start"] = true; F.run(4) end
-- Every Chinese craft the script built dies (the ambushers).
local function reap()
    for h, o in pairs(F.world().objects) do if o.alive and h:match("^built") and o.team == 5 then o.alive = false end end
end
-- The leader's human walks to 380 m of a spot (inside the 400 m trigger, outside the 350 m concealment ring).
local function approach(peer, spot) F.nearTo(peer.player, spot, 0, 380) end
local function killTargets()
    for i = 1, 6 do F.kill("destroy_" .. i) end
end

-- ------------------------------------------------------------------ offline == faithful
local function summary(peer)
    local out = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "BuildObject" then
            out[#out + 1] = "B:" .. c[3] .. ":" .. (c[4] == 2 and 5 or c[4]) .. ":" .. tostring(c[5])
        elseif c[1] == "SucceedMission" or c[1] == "FailMission" then
            out[#out + 1] = c[1] .. ":" .. tostring(c[3])
        elseif c[1] == "Hunt" then
            out[#out + 1] = "H"
        elseif c[1] == "Goto" or c[1] == "Follow" or c[1] == "SetIndependence" then
            out[#out + 1] = c[1]
        end
    end
    local lines = {}
    for _, c in ipairs(peer.calls) do
        if c[1] == "AudioMessage" or c[1] == "Play" then lines[#lines + 1] = c[2] end
    end
    return table.concat(out, ",") .. "|" .. table.concat(lines, ",")
end
local function fullRun(options)
    local w = F.reset()
    local peer = F.makePeer(1, 1, false, options)
    F.connect(); F.run(1)
    w.cameraDone["camera_start"] = true
    -- spring every ambush in turn from 380 m, then clear the targets
    for _, spot in ipairs({ "defend_a", "defend_b", "defend_c", "defend_d", "patrol_a", "patrol_b", "patrol_c", "patrol_d" }) do
        approach(peer, spot); F.run(3); reap()
    end
    F.place(peer.player, 1204, 101218)
    F.run(3)
    killTargets()
    F.run(60)
    return summary(peer), peer
end
do
    local faithful = fullRun({ faithful = true, script = "Scripts/bdmisn10.lua" })
    faithful = faithful:gsub("apcamr", "bpcamr") -- intentional CR rename: the nav beacon matches the player faction
    local offline, peer = fullRun({})
    check(faithful == offline and faithful:find("SucceedMission:bd10win.des", 1, true),
        "offline completes like the faithful port:\n" .. faithful .. "\n" .. offline)
    check(F.count(peer, "SucceedMission") == 1 and F.count(peer, "FailMission") == 0, "one victory, no failure")
    noEnemyTeamTwo(peer)
    check(F.count(peer, "SetAIControl", 5) == 1 and F.count(peer, "SetAIControl", 2) == 0, "AI control only for enemy team 5")
    check(F.index(peer, "SetAIControl") <= peer.chunkCalls, "SetAIControl runs at chunk root, before Start")
    -- 8 ambushes, 46 hunters, then the six captured tanks, the APC and the recycler
    local hunters = 0
    for _, b in ipairs(F.builds(peer)) do if b.team == 5 then hunters = hunters + 1 end end
    check(hunters == 46 and F.count(peer, "Hunt") == 46, "46 ambushers, each ordered to hunt")
end

-- ------------------------------------------------------------------ teams, scrap, pilots, the opening film
do
    local w, p, m = setup(4, {})
    F.run(3) -- the guests receive the stream
    check(m.startDone and m.coopMissionStarted, "the leader starts the shared mission")
    check(F.count(p[1], "SetScrap", 1) == 1 and F.callsOf(p[1], "SetScrap")[1][3] == 100 + 10 * 3, "starting scrap: 100 plus 10 per guest")
    check(F.count(p[1], "SetScrap", 5) == 1 and F.callsOf(p[1], "SetScrap")[2][3] == 0, "the enemy's scrap is team 5, not team 2")
    check(F.count(p[1], "SetScrap", 2) == 0, "no scrap is set on a guest's team 2")
    for team = 1, 4 do check(F.count(p[1], "SetPilot", team) == 1 and F.callsOf(p[1], "SetPilot")[1][3] == 10, "10 pilots for human team " .. team) end
    for i = 1, 4 do
        check(F.count(p[i], "DisableStartingRecycler") == 1, "extra starting recyclers disabled on peer " .. i)
        check(F.heardCount(p[i], "bd10001.wav") == 1, "briefing once on peer " .. i)
        check(p[i].camera == 1, "the opening film is shared: peer " .. i)
        check(F.last(p[i], "CameraPath")[2] == "camera_start" and F.last(p[i], "CameraPath")[5] == "destroy_4", "opening shot on peer " .. i)
        local o = F.callsOf(p[i], "AddObjective")
        check(o[1] and o[1][2] == "bd10001.otf", "objective on peer " .. i)
    end
    check(not m.cameraComplete[1], "the opening runs until its shot arrives")
    finishIntro(w)
    check(m.cameraComplete[1], "the opening ends when the path is done and the line has played")
    for i = 1, 4 do check(p[i].camera == 0, "opening cameras balanced on peer " .. i) end
    guestsPassive(p)
    check(p[1].rally ~= nil and p[1].rally[0] == "backup", "respawns at the Black Dog drop zone")
end
do -- a host skip releases only the host's camera and the runtime stops driving the shot: the opening ends for all
    local w, p, m = setup(3, {})
    w.cancel = true; F.run(2)
    w.cancel = false; F.run(4)
    check(m.cameraComplete[1], "a host skip ends the shared opening instead of stalling it")
    for i = 1, 3 do check(p[i].camera == 0, "no peer is left in the film after a host skip: " .. i) end
end
do -- a cancel that was already raised when the shot began is not a skip of that shot
    local w = F.reset()
    w.cancel = true
    local p1 = F.makePeer(1, 1, true, {})
    local p2 = F.makePeer(2, 2, true, {})
    F.connect(); F.run(4)
    check(not p1.env.Save().cameraComplete[1], "a stale cancel does not skip the opening")
end
do -- offline: skippable
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "offline opening opens")
    w.cancel = true; F.run(1)
    check(m.cameraComplete[1] and p[1].camera == 0, "offline the film can be skipped")
end
do -- a failed AudioMessage (nil) never stalls the opening
    local w = F.reset()
    local p1 = F.makePeer(1, 1, false, {})
    p1.env.AudioMessage = nil
    F.connect(); F.run(1)
    w.cameraDone["camera_start"] = true
    F.run(6)
    check(p1.env.Save().cameraComplete[1], "an opening without audio still ends")
end

-- ------------------------------------------------------------------ ambushes
for _, n in ipairs({ 1, 2, 4 }) do
    local w, p, m = setup(n, {})
    finishIntro(w)
    local extras = extrasFor(n)
    -- the 400 m trigger watches every human team, not only team 1
    local trigger = p[n]
    approach(trigger, "defend_d")
    F.run(4)
    local builds = builtAt(p[1], "defend_d")
    check(#builds == DEFENCE_UNITS[4] + extras, n .. " humans: the defend_d group plus " .. extras .. " extras")
    check(m.defencesSpawned[4] and not m.defencesSpawned[1], "only the sprung ambush is marked")
    for _, b in ipairs(builds) do
        check(b.team == 5, "ambushers are the co-op enemy")
        for _, q in ipairs(p) do check(q.env.GetDistance(q.player, b.h) >= 350, "no ambusher is built within 350 m of any human") end
    end
    check(F.count(p[1], "Hunt") == #builds, "every ambusher, extras included, is ordered to hunt")
    noEnemyTeamTwo(p[1])
    guestsPassive(p)
    -- a sprung ambush does not repeat
    F.run(10)
    check(#builtAt(p[1], "defend_d") == #builds, "an ambush springs once")
    -- a patrol group has five fighters and a tank
    approach(trigger, "patrol_b")
    F.run(4)
    check(#builtAt(p[1], "patrol_b") == PATROL_UNITS + extras, n .. " humans: the patrol group plus extras")
end
do -- below the trigger: nothing; beyond 400 m: nothing
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.nearTo(p[1].player, "patrol_a", 420, 0)
    F.nearTo(p[2].player, "patrol_c", 600, 0)
    F.run(4)
    check(#builtAt(p[1], "patrol_a") == 0 and #builtAt(p[1], "patrol_c") == 0, "no ambush outside 400 m")
end
do -- a human inside the concealment ring holds the ambush back until the spot is clear
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.nearTo(p[1].player, "patrol_c", 0, 380) -- triggers
    F.nearTo(p[2].player, "patrol_c", 0, 200) -- watching the spot
    F.run(4)
    check(m.patrolsSpawned[3] and #builtAt(p[1], "patrol_c") == 0, "nothing pops in within 350 m of a human")
    F.place(p[2].player, 2500, 99000)
    F.run(4)
    check(#builtAt(p[1], "patrol_c") == PATROL_UNITS + 1, "the held ambush arrives once the spot is clear")
    -- a save/load while it waits neither loses nor repeats it
end
do -- live cap bounds the extras, never the primaries
    local w, p, m = setup(4, {})
    finishIntro(w)
    for _, spot in ipairs({ "defend_a", "defend_b", "defend_c", "defend_d", "patrol_a", "patrol_b", "patrol_c", "patrol_d" }) do
        approach(p[4], spot); F.run(3)
    end
    local total = 0
    for _, b in ipairs(F.builds(p[1])) do if b.team == 5 then total = total + 1 end end
    check(total >= 46 and total <= 46 + 8 * 2, "all 46 primaries arrive, extras are bounded: " .. total)
end

-- ------------------------------------------------------------------ the objectives and the finale
do
    local w, p, m = setup(3, {})
    finishIntro(w)
    -- the restored Factory 1..6 objectives and the target markers
    for i = 1, 3 do
        local seen = {}
        for _, c in ipairs(F.callsOf(p[i], "AddObjective")) do seen[c[2]] = c[3] end
        check(seen["bd10001.otf"] == "white", "the briefing objective stays white on peer " .. i)
        for n = 2, 7 do check(seen["bd1000" .. n .. ".otf"] == "white", "Factory " .. (n - 1) .. " is listed on peer " .. i) end
        check(F.count(p[i], "SetObjectiveOn") == 6, "the six targets are marked on peer " .. i)
    end
    F.kill("destroy_2")
    F.run(2)
    local last = {}
    for _, c in ipairs(F.callsOf(p[2], "AddObjective")) do last[c[2]] = c[3] end
    check(last["bd10003.otf"] == "green" and last["bd10002.otf"] == "white", "a destroyed target turns its objective green")
    F.kill("destroy_1"); F.kill("destroy_3"); F.kill("destroy_4"); F.kill("destroy_5"); F.kill("destroy_6")
    F.run(1)
    check(m.objective1Complete, "all six targets down completes the objective")
    check(#F.builds(p[1], 0, "bpcamr") == 0, "the nav beacon waits ten seconds")
    F.run(11)
    check(#F.builds(p[1], 0, "bpcamr") == 1 and F.builds(p[1], 0, "bpcamr")[1].team == 1, "the nav beacon appears on the Black Dog side")
    check(F.heardCount(p[2], "bd10002.wav") == 1, "the drop zone warning plays for every peer")
    F.run(5)
    check(#F.builds(p[1], 0, "bvapc") == 1 and #F.builds(p[1], 0, "cbport") == 1, "the APC and the portal arrive")
    check(F.builds(p[1], 0, "cbport")[1].team == 0, "the portal is neutral")
    for i = 1, 3 do check(p[i].camera == 1, "the APC film is shared on peer " .. i) end
    check(F.count(p[1], "Goto") >= 1, "the APC is sent along its path")
    F.run(9)
    check(#F.builds(p[1], 0, "bvrecy") == 1 and #F.builds(p[1], 0, "cvtnka") == 6, "the captured recycler and its six tanks")
    check(F.count(p[1], "SetIndependence") == 6 and F.count(p[1], "Follow") == 6, "the tanks follow the recycler at independence zero")
    for _, b in ipairs(F.builds(p[1], 0, "cvtnka")) do check(b.team == 1, "the escort is built on the Black Dog side as in the DLL") end
    check(F.heardCount(p[3], "bd10003.wav") == 1, "the closing line plays for every peer")
    F.run(20)
    check(m.crFinale, "the finale latches the win flag")
    for i = 1, 3 do
        check(F.count(p[i], "SucceedMission") == 1 and F.last(p[i], "SucceedMission")[3] == "bd10win.des", "one victory on peer " .. i)
        check(F.count(p[i], "FailMission") == 0, "no failure on peer " .. i)
    end
    local lastOk = {}
    for _, c in ipairs(F.callsOf(p[1], "AddObjective")) do lastOk[c[2]] = c[3] end
    check(lastOk["bd10001.otf"] == "green", "the briefing objective turns green at the end of the hunt")
end
do -- failure after the finale began is ignored
    local w, p, m = setup(2, {})
    finishIntro(w)
    killTargets()
    F.run(60)
    check(m.crFinale and F.count(p[1], "SucceedMission") == 1, "the mission is won")
end

-- ------------------------------------------------------------------ save / load
do
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.kill("destroy_1")
    F.run(2)
    local objectives, marks = F.count(p[1], "AddObjective"), F.count(p[1], "SetObjectiveOn")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    local last = {}
    for _, c in ipairs(F.callsOf(p[1], "AddObjective")) do last[c[2]] = c[3] end
    check(F.count(p[1], "AddObjective") >= objectives + 7, "a load republishes the whole objective list")
    check(last["bd10002.otf"] == "green" and last["bd10003.otf"] == "white", "the republished list follows the state")
    check(F.count(p[1], "SetObjectiveOn") == marks + 5, "a load marks the five living targets again")
    check(F.heardCount(p[1], "bd10001.wav") == 1, "a load does not replay the briefing")
end
do -- a load during a film reopens the camera
    local w, p, m = setup(1, {})
    check(p[1].camera == 1, "the opening is running")
    local readies = F.count(p[1], "CameraReady")
    p[1].env.Load(p[1].env.Save())
    F.run(2)
    check(p[1].camera == 1 and F.count(p[1], "CameraReady") == readies + 1, "the running shot reopens after a load")
    w.cameraDone["camera_start"] = true
    F.run(5)
    check(m.cameraComplete[1] and p[1].camera == 0, "the body ends the shot as usual")
end
do -- a load while an ambush waits neither loses nor repeats it
    local w, p, m = setup(2, {})
    finishIntro(w)
    F.nearTo(p[1].player, "patrol_c", 0, 380)
    F.nearTo(p[2].player, "patrol_c", 0, 200)
    F.run(3)
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    F.place(p[2].player, 2500, 99000)
    F.run(5)
    check(#builtAt(p[1], "patrol_c") == PATROL_UNITS + 1, "the held ambush survives a load, once")
end

-- ------------------------------------------------------------------ leader leaves
do
    local w, p, m = setup(3, {})
    finishIntro(w)
    p[2].env.DeletePlayer(1); p[3].env.DeletePlayer(1)
    F.run(3)
    for i = 2, 3 do check(F.count(p[i], "FailMission") == 1, "the mission fails for guest " .. i .. " when the leader leaves") end
    check(F.count(p[1], "FailMission") == 0, "the leader itself keeps playing")
end

-- ------------------------------------------------------------------ weather: absent, present, broken
local function elysium(record, mode, sites)
    return function(peer)
        local V = { Seed = 4242, Initialized = false }
        function V.Init(o)
            peer.weatherInit = o; V.Initialized = true
            record("ElysiumInit", o.authority, o.send ~= nil, o.seed, o.startLevel, o.targetLevel)
            if mode == "initfail" then error("boom") end
        end
        function V.Update() if mode == "updatefail" then error("update boom") end end
        function V.AnnounceState() record("ElysiumAnnounce") end
        function V.ApplyNetEvent(op, ...) record("ElysiumEvent", op, ...) end
        function V.SetTargetLevel(n) record("ElysiumLevel", n) end
        function V.TriggerStrike(t) record("ElysiumStrike", t.x, t.y, t.z) end
        function V.OnObjectCreated(h) record("ElysiumCreated", h) end
        function V.Save() return { saved = true } end
        function V.Load(s) record("ElysiumLoad", s and s.saved) end
        function V.Shutdown() record("ElysiumShutdown") end
        return V
    end
end
do
    local w, p, m = setup(3, {})
    check(F.count(p[1], "EnvironmentInit") == 0 and m.startDone, "no weather module: the mission runs and touches no Environment")
end
do
    local sites = dofile("Scripts/CRElysiumSitesBD10.lua")
    check(sites.mission == "bdmisn10" and #sites.vents == 7, "the generated sites carry the seven geysers")
    local weather = { module = function(peer, record) return elysium(record, nil, sites)(peer) end, sites = sites }
    local w, p, m = setup(3, { weather = weather })
    check(F.count(p[1], "ElysiumInit", true) == 1 and F.last(p[1], "ElysiumInit")[3] == true, "the leader owns the weather and sends through the stream")
    check(F.last(p[1], "ElysiumInit")[5] == 1 and F.last(p[1], "ElysiumInit")[6] == 2, "the storm starts as haze")
    check(F.count(p[2], "ElysiumInit", false) == 1, "guests render only (not the authority)")
    check(p[1].env.Save().crcca.weatherSeed == 4242, "the weather seed is saved with the mission")
    finishIntro(w)
    check(F.count(p[1], "ElysiumStrike") == 0, "no lightning before the first event")
    -- the first ambush: level 3 and a strike on its spot
    approach(p[3], "patrol_b"); F.run(4)
    check(F.count(p[1], "ElysiumLevel", 3) == 1 and F.count(p[1], "ElysiumStrike") == 1, "the first ambush: rising storm and a strike")
    local strike = F.last(p[1], "ElysiumStrike")
    check(math.abs(strike[2] - 1976.7) < 0.1 and math.abs(strike[4] - 100677) < 0.1, "the strike lands on the ambush spot")
    -- three ambushes more reach the storm
    for _, spot in ipairs({ "patrol_a", "patrol_c", "defend_a" }) do approach(p[3], spot); F.run(4) end
    check(F.count(p[1], "ElysiumLevel", 4) == 1, "four ambushes: the storm")
    check(F.count(p[1], "ElysiumStrike") == 4, "one strike per ambush: " .. F.count(p[1], "ElysiumStrike"))
    -- each destroyed building draws a strike on its ruins
    F.kill("destroy_1"); F.run(1)
    check(F.count(p[1], "ElysiumStrike") == 5, "a destroyed target draws a strike")
    F.kill("destroy_2"); F.kill("destroy_3"); F.kill("destroy_4"); F.kill("destroy_5"); F.kill("destroy_6")
    F.run(1)
    check(F.count(p[1], "ElysiumStrike") == 10, "every target draws exactly one strike")
    F.run(30)
    check(F.count(p[1], "ElysiumLevel", 5) == 1, "the Chinese at the drop zone: the severe storm")
    check(F.count(p[1], "ElysiumStrike") == 12, "the APC and the captured recycler each draw a strike over the drop zone")
    check(F.count(p[1], "ElysiumCreated") > 0, "new objects are offered to the weather")
    for _, q in ipairs(p) do q.env.Load(q.env.Save()) end
    F.connect(); F.run(3)
    check(F.count(p[1], "ElysiumShutdown") >= 1 and F.count(p[1], "ElysiumLoad", true) == 1, "load restores the leader's weather state")
    check(F.count(p[1], "ElysiumStrike") == 12, "a load repeats no strike")
    F.run(30)
    check(F.count(p[1], "ElysiumLevel", 4) >= 1 and m.crFinale, "the victory eases the storm for the debrief")
end
do -- sites module missing: no weather, never an error
    local sites = dofile("Scripts/CRElysiumSitesBD10.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, nil, sites)(peer) end } })
    check(F.count(p[1], "ElysiumInit") == 0 and m.startDone, "module without sites: disabled")
end
for _, mode in ipairs({ "initfail", "updatefail" }) do
    local sites = dofile("Scripts/CRElysiumSitesBD10.lua")
    local w, p, m = setup(2, { weather = { module = function(peer, record) return elysium(record, mode, sites)(peer) end, sites = sites } })
    finishIntro(w)
    approach(p[2], "defend_c"); F.run(4)
    check(#builtAt(p[1], "defend_c") == DEFENCE_UNITS[3] + 1, "a failing weather director (" .. mode .. ") never stops the mission")
end

print("bdmisn10 co-op: " .. checks .. " checks passed")
