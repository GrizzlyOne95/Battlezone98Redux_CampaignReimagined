-- Execute the complete mission with separate Lua 5.1 environments and the real
-- CRCoop registry. Engine/network mocks verify script decisions, not Redux
-- native map loading, physics, pathfinding, Lua wire serialization, or EXU hooks.
-- Peer replicas and the BZRNet envelope are separate: missing object handles
-- cannot become valid merely because a mission message reached a client.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local transport, reliableSend = nil, false
local births = {}
local function copy(object)
    local result = {}; for k, v in pairs(object) do result[k] = v end; return result
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
local labels = { "fake_player", "avland0_wingman", "sscr_171_scrap", "abcomm1_i76building",
    "avrecy-1_recycler", "apscrap-1_camerapod", "sscr_176_scrap", "apbase-1_camerapod", "asuser0_person" }
local distances = {}
local function reset()
    now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
    distances, births = {}, {}
    transport = PeerTransport.New(function(packet)
        if peers[packet.to] then
            peers[packet.to].env.Receive(packet.from, packet.kind, unpack(packet.args))
        end
    end)
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
    p.view = (not network or team == 1) and objects or {}
    for _, other in pairs(peers) do
        for h, object in pairs(objects) do other.view[h] = copy(object) end
    end
    local view = p.view
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
    e.GetHandle = function(label) return view[label] and label end
    e.IsValid = function(h) return view[h] ~= nil and view[h].alive end
    e.IsAlive = e.IsValid
    e.IsCraft = function(h) return e.IsValid(h) and not tostring(h):find("solar") end
    e.IsLocal = function(h) return view[h] and (view[h].team == team or (team == 1 and view[h].team >= 5)) end
    e.IsPerson = function(h) return view[h] and view[h].odf == "aspilo" end
    e.IsAudioMessageDone = function() return p.audioDone == true end
    e.GetLastEnemyShot = function() return p.shot or 0 end
    e.GetOdf = function(h) return view[h] and view[h].odf end
    e.SetTeamNum = function(h, t) record("SetTeamNum", h, t); view[h].team = t end
    e.IsOdf = function(h, odf) return view[h] and view[h].odf == odf end
    e.GetTeamNum = function(h) return view[h] and view[h].team or 0 end
    e.GetHealth = function(h) return view[h].health / view[h].maxHealth end
    e.GetMaxHealth = function(h) return view[h].maxHealth end
    e.SetMaxHealth = function(h, value) record("SetMaxHealth", h, value); view[h].maxHealth = value end
    e.SetCurHealth = function(h, value) record("SetCurHealth", h, value); view[h].health = value end
    e.IsDeployed = function(h) return view[h] and view[h].deployed end
    e.GetDistance = function(a, b)
        if tostring(a):find("player") and b == "launch_pad" then
            for _, human in pairs(peers) do
                if human.player == a then return human.nearLaunch and 20 or 1000 end
            end
        end
        if tostring(a):find("built") and b == "launch_pad" then return 20 end
        return distances[tostring(a) .. ":" .. tostring(b)] or 1000
    end
    e.GetPosition = function(h) return { x = 0, y = 0, z = 0 } end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function() return { x = 0, y = 0, z = 0 } end
    e.CountUnitsNearObject = function(target, distance, objectTeam, odf)
        local n = 0
        for h, object in pairs(view) do
            if object.alive and object.team == objectTeam and object.odf == odf and
                e.GetDistance(h, target) < distance then n = n + 1 end
        end
        return n
    end
    local function iterator()
        local key
        return function()
            key = next(view, key)
            while key and not view[key].alive do key = next(view, key) end
            return key
        end
    end
    e.AllCraft, e.AllObjects = iterator, iterator
    e.BuildObject = function(odf, objectTeam, pos)
        nextObject = nextObject + 1
        local h = "built" .. nextObject
        view[h] = { alive = true, team = objectTeam, odf = odf, health = 1000, maxHealth = 1000 }
        births[h] = now + 0.8
        record("BuildObject", h, odf, objectTeam)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h) record("RemoveObject", h); if view[h] then view[h].alive = false end end
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
                transport:Send(id, target, kind, args, reliableSend)
            end
        end
    end
    for _, name in ipairs({ "Attack", "Goto", "Retreat", "Follow", "Defend", "Defend2", "Patrol",
        "AddHealth", "Damage", "SetCommand", "SetCritical", "SetPathLoop", "SetVelocity",
        "SetPosition", "SetLabel", "SetIndependence", "SetAIP", "MakeExplosion", "SetWeaponMask", "SetScrap", "SetPilot", "SetObjectiveName", "SetObjectiveOn",
        "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective", "UpdateObjective",
        "CameraPath", "StartSound", "DisplayMessage", "Ally", "UnAlly", "FailMission", "SucceedMission" }) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetUserTarget" then
                check(e.IsValid((...)), "presentation used a not-yet-replicated handle")
            end
            record(n, ...)
        end
    end
    e.AiCommand = { UNDEPLOY = 21 }
    local function noop() end
    local aiTeam = { SetConfig = noop }
    local ai = { ResetObjectCacheTracking = noop, TrackWorldObject = noop, RefreshObjectCache = noop,
        AddObject = function(h)
            check(e.IsLocal(h) and not p.coop.IsHumanCraft(h), "aiCore registered remote/human craft")
            record("aiAdd", h)
        end, Factions = { NSDF = 1, CCA = 2 }, Bootstrap = noop,
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
        TerrainClutter = { BuildLayer = function() record("clutter") end },
        DiffUtils = { SetupTeams = function() return aiTeam, aiTeam end,
            Get = function() return { res = 1, index = p.difficulty } end, ScaleEnemy = function(n) return n end, ScaleRes = function(n) return n end,
            ScaleTimer = function(n) return n end },
        PersistentConfig = { Settings = {}, Initialize = noop, UpdateInputs = noop,
            UpdateHeadlights = noop }, AutoSave = { Update = function() record("autosave") end },
    }
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile("Scripts/misn02b.lua")), e)()
    p.env, p.coop = e, modules.CRCoop
    p.env.Start()
    p.state = p.env.Save()
    return p
end
local function replicate()
    for _, peer in pairs(peers) do
        if peer.view ~= objects then
            for h, object in pairs(objects) do
                if not births[h] or now >= births[h] then peer.view[h] = copy(object) end
            end
        end
    end
end
local function tick(seconds, reverse, drop)
    now = now + seconds
    replicate()
    for _, p in pairs(peers) do p.env.Update() end
    transport:Step(now, reverse, drop)
end
local function settle()
    for i = 1, 30 do tick(0.1) end
end
local function registerAll()
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
end

-- Four peers: only the leader simulates; ordered HUD/audio survives loss.
for _, mode in ipairs({ false, true }) do
reliableSend = mode
reset()
local host = makePeer(10, 1, true)
local clients = { makePeer(20, 2, true), makePeer(30, 3, true), makePeer(40, 4, true) }
registerAll()
for i = 1, 30 do tick(0.1, not mode or i < 8, function(packet) return i < 8 and (packet.kind == "E" or packet.kind == "A") end) end
settle()
check(host.state.start_done and host.state.camera1, "leader opening did not run")
for _, c in ipairs(clients) do
    check(not c.state.start_done and count(c, "BuildObject") == 0 and count(c, "aiUpdate") == 0, "client ran simulation")
    check(count(c, "Play") == 1 and c.difficulty == 3, "opening/difficulty lost or duplicated")
    check(last(c, "SetScrap")[2] == c.team and count(c, "SetScrap") == 1, "resources not owner-local")
    check(count(c, "CameraPath") > 0 and count(c, "clutter") == 1, "client presentation missing")
    check(count(c, "DisableStartingRecycler") == 1 and last(c, "SetLives")[2] == 999, "native co-op hooks absent")
    check(count(c, "autosave") == 0, "network attempted autosave")
end
check(not host.pilotOptions.shouldManageHandle(clients[1].player), "pilot mode claimed human")
clients[1].skip = true; host.skip = true; tick(0.1); settle()
check(host.state.camera1 and count(clients[1], "CameraFinish") > 0, "local skip advanced shared intro")
host.audioDone = true; tick(0.1); settle()
check(not host.state.camera3 and host.state.initialObjectiveCompleted, "shared intro/vehicle gate stuck")
for _, c in ipairs(clients) do check(count(c, "Play") == 2 and count(c, "UpdateObjective") == 1, "post-intro HUD/audio missing") end

-- Build the first scavenger, activate the staged enemy, retreat and rescue.
local scav = host.env.BuildObject("avscav", 1, "start")
distances["sscr_171_scrap:" .. scav] = 50
host.audioDone = false; tick(0.1); settle()
check(host.state.patrol1 and host.state.found2, "staged fighter did not activate")
check(objects[host.state.bscout].team == 6, "enemy occupies a human team")
distances[scav .. ":sscr_176_scrap"] = 100
host.shot = 1; tick(0.1); settle()
check(host.state.message2, "retreat did not trigger")
distances["abcomm1_i76building:" .. scav] = 100
tick(0.1); settle()
check(host.state.message3 and host.state.scav2, "rescue did not spawn scavenger")
for _, c in ipairs(clients) do check(last(c, "SetObjectiveOn")[2] == host.state.scav2, "rescued marker not replicated") end

-- A leader death follows native respawn instead of losing the convoy.
objects[host.player].alive = false
host.player = "respawn10"
objects[host.player] = { alive = true, team = 1, odf = "aspilo", health = 1000, maxHealth = 1000 }
settle(); check(not host.state.mission_lost, "respawn lost the mission")
check(host.coop.IsHumanCraft(host.player), "respawn handle not refreshed")
-- The returned convoy wins, preserving the authored debrief on every peer.
distances["abcomm1_i76building:" .. host.state.scav2] = 100
host.audioDone = true; tick(0.1)
for i = 1, 70 do tick(0.1, not mode or i < 4, function(packet) return i < 4 and packet.kind == "E" end) end
check(count(host, "SucceedMission") == 1, "leader success missing/duplicated")
for _, c in ipairs(clients) do check(count(c, "SucceedMission") == 1 and last(c, "SucceedMission")[3] == "misn02w1.des", "peer success debrief missing") end

check(host.view ~= clients[1].view, "peers share native world tables")
check(transport.delivered > 0, "peer transport unused")
if reliableSend then check(transport.rejected > 0 and transport.retries > 0, "reliable ordering/loss not exercised") end
end
reliableSend = false

-- Loss and terminal latch: base destruction can't become rescue/victory.
reset(); local host = makePeer(10, 1, true); local client = makePeer(20, 2, true)
registerAll(); settle(); host.audioDone = true
objects["avrecy-1_recycler"].alive = false
tick(0.1); settle(); settle()
check(count(host, "FailMission") == 1 and count(client, "FailMission") == 1, "replicated loss missing")
check(last(client, "FailMission")[3] == "misn02l1.des" and count(client, "SucceedMission") == 0, "loss became win")

-- Offline retains positioning, intro skips, save/load and player-death failure.
reset(); local solo = makePeer(10, 1, false)
tick(0.1)
check(solo.state.camera1 and count(solo, "SetPosition") == 1 and count(solo, "autosave") == 1, "offline startup changed")
check(count(solo, "DisableStartingRecycler") == 0 and #packets == 0, "offline used network")
solo.skip = true; tick(0.1)
check(not solo.state.camera3 and solo.state.intro_skipped, "offline skip changed")
local saved = solo.env.Save(); solo.env.Load(saved, {}, {}); now = now + 3; solo.env.Update()
check(solo.state.loading_done and count(solo, "clutter") == 2, "offline load did not rehydrate")
solo.env.BuildObject("avscav", 1, "start"); objects[solo.player].alive = false
solo.audioDone = true; tick(0.1)
check(solo.state.mission_lost and last(solo, "FailMission")[3] == "misn02l1.des", "offline player death changed")

-- Guest departure releases readiness; leader migration ends the mission.
reset(); host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle(); host.env.DeletePlayer(20, "Guest", 2); peers[20] = nil
check(host.coop.IsSessionReady(), "departed guest blocked readiness")
reset(); host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle(); client.env.DeletePlayer(10, "Host", 1); client.hosting = true; client.env.Update()
check(not client.coop.IsAuthority() and count(client, "FailMission") == 1, "host migration inherited simulation")

-- Late join halts progression rather than running an unreconciled world.
reset(); host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle(); local builds = count(host, "BuildObject")
local late = makePeer(30, 3, true)
for _, p in pairs(peers) do p.env.CreatePlayer(30, "Late", 3) end
late.env.CreatePlayer(10, "Host", 1); late.env.CreatePlayer(20, "Guest", 2)
settle(); check(count(host, "BuildObject") == builds and count(host, "DisplayMessage") == 1, "late join progressed")
print("misn02b co-op: " .. checks .. " complete-script Lua 5.1 checks passed")
