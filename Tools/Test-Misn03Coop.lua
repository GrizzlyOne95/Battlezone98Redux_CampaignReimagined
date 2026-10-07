-- Execute the complete mission with separate Lua 5.1 environments and the real
-- CRCoop registry. Engine/network mocks verify script decisions, not Redux
-- native replication, native map loading, pathfinding, or EXU's binary hooks.
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
local labels = { "avrec3-1_recycler", "scav1", "scav2", "svfigh1", "svfigh2",
    "enemyturret_1", "enemyturret_2", "enemyturret_3", "enemyturret_4", "geyser1",
    "solar1", "solar2", "solar3", "solar4", "launch_pad", "build1", "build3",
    "build4", "build5", "hanger", "cam_geyser", "shot_geyser", "box1",
    "crate1", "crate2", "crate3", "guy1", "guy2", "sucker" }
local function reset()
    now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
    for _, label in ipairs(labels) do
        objects[label] = { alive = true, team = label:find("^sv") and 5 or 1,
            odf = label, health = 1000, maxHealth = 1000, deployed = false }
    end
end
local function count(peer, name)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == name then n = n + 1 end end
    return n
end
local function last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
local function makePeer(id, team, network)
    local p = { id = id, team = team, net = network, hosting = team == 1,
        calls = {}, difficulty = team == 1 and 3 or 0, player = "player" .. id }
    peers[id] = p
    objects[p.player] = { alive = true, team = team, odf = "avtank", health = 1000, maxHealth = 1000 }
    local function record(name, ...)
        p.calls[#p.calls + 1] = { name, ... }
    end
    local e = setmetatable({}, { __index = _G })
    e._G = e
    e.print = function() end
    e.IsNetGame = function() return p.net end
    e.IsHosting = function() return p.hosting end
    e.GetTime = function() return now end
    e.GetPlayerHandle = function(remote)
        check(remote == nil, "remote GetPlayerHandle(team) must never be used")
        return p.player
    end
    e.GetHandle = function(label) return objects[label] and label end
    e.IsValid = function(h) return objects[h] ~= nil and objects[h].alive end
    e.IsAlive = e.IsValid
    e.IsCraft = function(h) return e.IsValid(h) and not tostring(h):find("solar") end
    e.IsLocal = function(h) return objects[h] and (objects[h].team == team or (team == 1 and objects[h].team == 5)) end
    e.IsOdf = function(h, odf) return objects[h] and objects[h].odf == odf end
    e.GetTeamNum = function(h) return objects[h] and objects[h].team or 0 end
    e.GetHealth = function(h) return objects[h].health / objects[h].maxHealth end
    e.GetMaxHealth = function(h) return objects[h].maxHealth end
    e.SetMaxHealth = function(h, value) record("SetMaxHealth", h, value); objects[h].maxHealth = value end
    e.SetCurHealth = function(h, value) record("SetCurHealth", h, value); objects[h].health = value end
    e.IsDeployed = function(h) return objects[h] and objects[h].deployed end
    e.GetDistance = function(a, b)
        if tostring(a):find("player") and b == "launch_pad" then
            for _, human in pairs(peers) do
                if human.player == a then return human.nearLaunch and 20 or 1000 end
            end
        end
        if tostring(a):find("built") and b == "launch_pad" then return 20 end
        return 1000
    end
    e.GetPosition = function(h) return { x = 0, y = 0, z = 0 } end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function() return { x = 0, y = 0, z = 0 } end
    e.CountUnitsNearObject = function(target, distance, objectTeam, odf)
        local n = 0
        for h, object in pairs(objects) do
            if object.alive and object.team == objectTeam and object.odf == odf and
                e.GetDistance(h, target) < distance then n = n + 1 end
        end
        return n
    end
    local function iterator()
        local key
        return function()
            key = next(objects, key)
            while key and not objects[key].alive do key = next(objects, key) end
            return key
        end
    end
    e.AllCraft, e.AllObjects = iterator, iterator
    e.BuildObject = function(odf, objectTeam, pos)
        nextObject = nextObject + 1
        local h = "built" .. nextObject
        objects[h] = { alive = true, team = objectTeam, odf = odf, health = 1000, maxHealth = 1000 }
        record("BuildObject", h, odf, objectTeam)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h) record("RemoveObject", h); if objects[h] then objects[h].alive = false end end
    e.CameraCancelled = function() return p.skip == true end
    e.CameraReady = function() record("CameraReady"); p.skip = false end
    e.CameraFinish = function() record("CameraFinish") end
    e.Send = function(to, kind, ...)
        local args = { ... }
        -- Conservative payload estimate: doubles plus per-field type tags;
        -- strings include terminators. Actual handle encoding is smaller.
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        check(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target, peer in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then
                packets[#packets + 1] = { from = id, to = target, kind = kind, args = args }
            end
        end
    end
    for _, name in ipairs({ "Attack", "Goto", "Retreat", "Follow", "Defend", "Defend2", "Patrol",
        "AddHealth", "Damage", "SetCommand", "SetCritical", "SetPathLoop", "SetVelocity",
        "SetWeaponMask", "SetScrap", "SetPilot", "SetObjectiveName", "SetObjectiveOn",
        "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective", "UpdateObjective",
        "CameraPath", "StartSound", "DisplayMessage", "Ally", "UnAlly", "FailMission", "SucceedMission" }) do
        local n = name
        e[n] = function(...) record(n, ...) end
    end
    e.AiCommand = { UNDEPLOY = 21 }
    local function noop() end
    local aiTeam = { SetConfig = noop }
    local ai = { Factions = { NSDF = 1, CCA = 2 }, Bootstrap = noop,
        AddSpecialObject = function(h) record("AddSpecialObject", h) end,
        Update = function() record("aiUpdate") end, Save = function() return {} end, Load = noop }
    local pilot = { Initialize = function(options) p.pilotOptions = options end,
        AddObject = function(h) record("PilotAdd", h) end, Save = function() return {} end,
        Update = function() record("pilotUpdate") end }
    local subtitles = { Play = function(file) record("Play", file); return file end,
        Queue = function(file) record("Queue", file) end, Stop = function() record("Stop") end,
        Update = function() record("subtitlesUpdate") end, Initialize = noop }
    local modules = {
        RequireFix = { Initialize = noop }, exu = {
            GetMyNetID = function() return id end, GetDifficulty = function() return p.difficulty end,
            SetDifficulty = function(d) p.difficulty = d end,
            DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(lives) record("SetLives", lives) end,
        }, aiCore = ai, PlayerPilotMode = pilot, ScriptSubtitles = subtitles,
        DiffUtils = { SetupTeams = function() return aiTeam, aiTeam end,
            Get = function() return { res = 1 } end, ScaleRes = function(n) return n end,
            ScaleTimer = function(n) return n end },
        PersistentConfig = { Settings = {}, Initialize = noop, UpdateInputs = noop,
            UpdateHeadlights = noop }, AutoSave = { Update = function() record("autosave") end },
    }
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile("Scripts/misn03.lua")), e)()
    p.env, p.coop = e, modules.CRCoop
    p.env.Start()
    p.state = p.env.Save()
    return p
end
local function deliver(reverse, drop)
    local batch = packets
    packets = {}
    if reverse then
        local reversed = {}; for i = #batch, 1, -1 do reversed[#reversed + 1] = batch[i] end
        batch = reversed
    end
    for _, packet in ipairs(batch) do
        if not (drop and drop(packet)) then
            peers[packet.to].env.Receive(packet.from, packet.kind, unpack(packet.args))
        end
    end
end
local function tick(seconds, reverse, drop)
    now = now + seconds
    for _, p in pairs(peers) do p.env.Update() end
    deliver(reverse, drop)
end
local function settle()
    for i = 1, 30 do tick(0.1) end
end
local function registerAll()
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
end

-- Four humans, distinct difficulty preferences: leader settings win. Opening
-- runs once even when the first event/ACK packets are lost or reordered.
reset()
local host = makePeer(10, 1, true)
local clients = { makePeer(20, 2, true), makePeer(30, 3, true), makePeer(40, 4, true) }
registerAll()
for i = 1, 20 do tick(0.1, true, function(packet) return i < 8 and (packet.kind == "E" or packet.kind == "A") end) end
settle()
check(host.state.first_wave_done, "host did not run the opening")
for _, client in ipairs(clients) do
    check(not client.state.first_wave_done and not client.state.start_done, "client executed campaign logic")
    check(count(client, "BuildObject") == 0 and count(client, "Attack") == 0, "client created/ordered mission AI")
    check(count(client, "Play") == 1, "opening dialogue was lost/duplicated")
    check(client.difficulty == 3, "host difficulty was not applied to client")
    check(last(client, "SetScrap")[2] == client.team, "client mutated another team's resources")
    check(count(client, "aiUpdate") == 0 and count(client, "pilotUpdate") == 0, "client ran shared mission AI")
    check(count(client, "SetMaxHealth") == 2, "custom defense health maximums were not delivered")
    check(count(client, "DisableStartingRecycler") == 1 and last(client, "SetLives")[2] == 999,
        "native co-op startup/respawn hooks missing")
end
check(not host.pilotOptions.shouldManageHandle(clients[1].player), "Pilot Mode may claim remote human")
local oldAudio = count(clients[1], "Play")
clients[1].env.Receive(30, "E", 999, "Play", now + 5, "fake.wav")
check(count(clients[1], "Play") == oldAudio, "non-leader injected presentation")

-- Complete actual evacuation camera and authoritative spawn/order blocks.
host.state.support_time, host.state.apc_spawn_time = now - 1, now - 1
tick(0.1); settle()
check(host.state.help_spawn and host.state.camera_ready, "evacuation did not start")
clients[1].skip = true
tick(0.1); settle()
check(count(clients[1], "CameraFinish") > 0, "client skip did not release camera")
check(not host.state.movie_over, "client skip ended everyone's movie")
host.skip = true
tick(0.1)
check(not host.state.movie_over, "host skip bypassed shared film timer")
host.state.movie_time = now - 1
tick(0.1); settle()
check(host.state.movie_over and host.state.remove_props, "evacuation film did not complete")
local transports = 0
for _, call in ipairs(host.calls) do
    if call[1] == "BuildObject" and call[3] == "avapc2" then transports = transports + 1 end
end
check(transports == 2, "authoritative transport spawn duplicated")
for _, client in ipairs(clients) do
    check(count(client, "BuildObject") == 0 and count(client, "RemoveObject") > 0, "prop cleanup did not reach client")
    check(last(client, "SetObjectiveOn") ~= nil and count(client, "Play") >= 3, "evacuation HUD/audio missing")
end
host.state.pull_out_time, host.state.turret_move_time = now - 1, now - 1
host.nearLaunch = true
tick(0.1); settle()
check(host.state.third_objective and not host.state.final_objective, "one human at pad completed everyone's mission")
for _, client in ipairs(clients) do client.nearLaunch = true end
tick(0.1); settle()
check(host.state.final_objective and host.state.startfinishingmovie, "all-player launch gate failed")
host.state.coopOutroDeadline = now - 1
tick(0.1); settle()
for i = 1, 40 do tick(0.1, true, function(packet) return i < 3 and packet.kind == "E" end) end
check(count(host, "SucceedMission") == 1, "host did not settle one successful result")
for _, client in ipairs(clients) do
    check(count(client, "SucceedMission") == 1 and count(client, "FailMission") == 0, "client result missing/duplicated")
    check(last(client, "SucceedMission")[3] == "misn03w1.des", "co-op victory debrief changed")
end

-- Offline: same mission Update, immediate stock result semantics and autosave.
reset()
local offline = makePeer(10, 1, false)
tick(0.1)
check(offline.state.first_wave_done and count(offline, "autosave") == 1, "offline startup/autosave changed")
check(count(offline, "DisableStartingRecycler") == 0 and #packets == 0, "offline used network startup/transport")
objects.solar1.alive = false
tick(0.1)
check(last(offline, "FailMission")[3] == "misn03f1.des", "offline tower failure debrief changed")
local saved = offline.env.Save()
offline.env.Load(saved, {}, {})
now = now + 3
offline.env.Update()
check(offline.state.loading_done, "offline save/load did not rehydrate")

-- Replicated loss is also an ordered event and cannot turn into success.
reset()
host = makePeer(10, 1, true)
local client = makePeer(20, 2, true)
registerAll(); settle()
objects.solar1.alive = false
tick(0.1); settle()
check(count(host, "FailMission") == 1 and count(client, "FailMission") == 1, "failure result did not reach both peers")
check(last(client, "FailMission")[3] == "misn03f1.des" and count(client, "SucceedMission") == 0,
    "loss debrief/terminal latch changed")

-- Missing/destroyed marker handles hold delivery briefly, then release the
-- stream. They must not deadlock cleanup and terminal results forever.
local expectedAck = last(client, "SucceedMission")
check(expectedAck == nil, "failure client acquired a success result")
local previousClear = count(client, "ClearObjectives")
local nextSeq
-- The stream's latest acknowledgement is observable in the outbound transport.
client.env.Receive(10, "E", 0, "ClearObjectives", now + 5)
nextSeq = packets[#packets].args[1] + 1
client.env.Receive(10, "E", nextSeq, "SetObjectiveOn", now + 5, "not-yet-replicated")
client.env.Receive(10, "E", nextSeq + 1, "ClearObjectives", now + 5)
check(count(client, "ClearObjectives") == previousClear, "sequence gap did not defer following event")
now = now + 6
client.env.Receive(10, "E", nextSeq, "SetObjectiveOn", now - 1, "not-yet-replicated")
client.env.Receive(10, "E", nextSeq + 1, "ClearObjectives", now - 1)
client.env.Receive(10, "E", nextSeq + 1, "ClearObjectives", now - 1)
check(count(client, "ClearObjectives") == previousClear + 1, "expired marker/duplicate handling failed")

-- A deleted human no longer holds the all-player proximity/readiness gate.
reset()
host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle()
host.env.DeletePlayer(20, "P20", 2)
peers[20] = nil; host.nearLaunch = true
check(host.coop.AllPlayersNear("launch_pad", 100), "departed guest still blocked launch")

-- Respawn/vehicle changes are refreshed by each owner and exchanged. Late
-- join is fail-closed and a migrated host never inherits campaign simulation.
reset()
host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle()
objects[client.player].alive = false
client.player = "player20respawn"
objects[client.player] = { alive = true, team = 2, odf = "aspilo", health = 1000, maxHealth = 1000 }
settle()
check(host.coop.IsHumanCraft(client.player) and host.coop.HasAllPlayerHandles(), "remote respawn handle was not refreshed")
local late = makePeer(30, 3, true)
for _, p in pairs(peers) do
    p.env.CreatePlayer(30, "Late", 3)
    if p == late then
        p.env.CreatePlayer(10, "Host", 1); p.env.CreatePlayer(20, "Client", 2)
    end
end
settle()
local builds = count(host, "BuildObject")
host.state.support_time = now - 1
settle()
check(count(host, "BuildObject") == builds and count(host, "DisplayMessage") > 0, "late join ran unreconciled mission state")
client.env.DeletePlayer(10, "Host", 1)
client.hosting = true
client.env.Update()
check(not client.coop.IsAuthority() and count(client, "FailMission") == 1, "host migration inherited authority or left mission running")
print("misn03 co-op: " .. checks .. " complete-script Lua 5.1 checks passed")
